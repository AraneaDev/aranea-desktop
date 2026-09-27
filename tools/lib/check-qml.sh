#!/usr/bin/env bash
# qml stage for tools/check: qmllint over every tracked QML file.
#
# Strict mode (Omarchy's shell Commons/Ui and Quickshell are present) compares
# the warnings with tools/baselines/qmllint.txt, which can only shrink: a new
# warning fails, and so does a baseline entry that no longer occurs (remove it
# with --update-baselines). Entries are "count<TAB>file:id:message", without
# line numbers, so moving code does not churn the baseline. Bare mode (CI
# without Omarchy) fails only on syntax errors. Syntax errors always fail.
check_root="${check_root:?tools/check sets check_root}"
repo_root="${repo_root:?tools/check sets repo_root}"
update_baselines="${update_baselines:-0}"
staged="${staged:-0}"

# Prints "count<TAB>file:id:message" for every warning in qmllint JSON (stdin).
# Machine-specific paths inside messages (the checked tree, the temporary
# import root) are replaced, so the baseline is the same everywhere.
qml_warning_counts() {
  jq -r '.files[]? | .filename as $file | .warnings[]? | "\($file):\(.id):\(.message)"' |
    sed -e "s#${check_root}/##g" -e "s#${qml_import_root:-/nonexistent-import-root}#<imports>#g" |
    LC_ALL=C sort | uniq -c | awk '{count = $1; sub(/^ *[0-9]+ /, ""); print count "\t" $0}'
}

# Compares CURRENT and BASELINE count files; prints "new warning: …" and
# "stale baseline entry: …" lines. Returns 1 when there is any.
qml_compare() {
  awk -F'\t' '
    FILENAME == ARGV[1] { base[$2] = $1; next }
    { cur[$2] = $1 }
    END {
      bad = 0
      for (k in cur) if (!(k in base) || cur[k] + 0 > base[k] + 0) { print "new warning: " cur[k] "\t" k; bad = 1 }
      for (k in base) if (!(k in cur) || cur[k] + 0 < base[k] + 0) { print "stale baseline entry: " base[k] "\t" k; bad = 1 }
      exit bad
    }' "$2" "$1"
}

# Prints the baseline shrunk to CURRENT: lower counts, fixed entries dropped,
# nothing added.
qml_shrunk_baseline() {
  awk -F'\t' '
    FILENAME == ARGV[1] { base[$2] = $1; next }
    ($2 in base) { n = ($1 + 0 < base[$2] + 0) ? $1 : base[$2]; print n "\t" $2 }' "$2" "$1" | LC_ALL=C sort -t$'\t' -k2
}

# qml stage entry point.
stage_qml() {
  local qmllint files
  qmllint="$(qt_tool qmllint)" || {
    echo "qmllint is required (qt6-declarative)"
    return 1
  }
  mapfile -t files < <(check_files '\.qml$')
  ((${#files[@]})) || return 0

  local shell_dir="${ARANEA_QML_SHELL_DIR:-/usr/share/omarchy/shell}" mode=bare import_root=""
  qml_import_root=""
  local args=(--ignore-settings --json -)
  if [[ -f "$shell_dir/Commons/qmldir" && -f "$shell_dir/Ui/qmldir" && -d /usr/lib/qt6/qml/Quickshell ]]; then
    mode=strict
    import_root="$(mktemp -d)"
    qml_import_root="$import_root"
    mkdir "$import_root/qs"
    ln -s "$shell_dir/Commons" "$import_root/qs/Commons"
    ln -s "$shell_dir/Ui" "$import_root/qs/Ui"
    args+=(-I "$import_root")
  else
    args+=(--bare)
  fi
  local json
  json="$(cd "$check_root" && "$qmllint" "${args[@]}" "${files[@]}" 2>/dev/null)"
  [[ -n "$import_root" ]] && rm -rf "$import_root"
  echo "qmllint: $mode mode, ${#files[@]} files"
  if ! jq -e '.files' >/dev/null 2>&1 <<<"$json"; then
    echo "qmllint produced no readable report"
    return 1
  fi

  local status=0 syntax
  syntax="$(jq -r '.files[] | .filename as $file | .warnings[] | select(.id == "syntax") | "\($file):\(.line): \(.message)"' <<<"$json")"
  if [[ -n "$syntax" ]]; then
    printf 'syntax error: %s\n' "$syntax"
    status=1
  fi
  if [[ "$mode" != strict ]]; then
    # Bare: only syntax is checked. Where everything is required (the Arch CI
    # job) that counts as a skip, which fails the run.
    note_stage "bare, syntax only"
    if ((status == 0)) && [[ "${ARANEA_CHECK_REQUIRE_ALL:-0}" == 1 ]]; then
      echo "strict QML needs Omarchy's Commons/Ui at $shell_dir and Quickshell"
      return 77
    fi
    return "$status"
  fi

  local baseline="$repo_root/tools/baselines/qmllint.txt" current relevant
  current="$(mktemp)"
  relevant="$(mktemp)"
  qml_warning_counts <<<"$json" >"$current"
  # Every entry counts in a full run (entries of deleted or renamed files
  # are stale); --staged lints a subset, so only those files' entries count.
  touch "$baseline"
  if ((staged)); then
    grep -F -f <(printf '\t%s:\n' "${files[@]}") "$baseline" >"$relevant" || true
  else
    cp "$baseline" "$relevant"
  fi
  if ((update_baselines)); then
    # With --staged, other files' entries are kept as they are; a full run
    # drops entries of files that no longer exist.
    local others=""
    if ((staged)); then
      others="$(grep -v -F -f <(printf '\t%s:\n' "${files[@]}") "$baseline" || true)"
    fi
    {
      [[ -n "$others" ]] && printf '%s\n' "$others"
      qml_shrunk_baseline "$current" "$relevant"
    } |
      LC_ALL=C sort -t$'\t' -k2 >"$baseline.new"
    mv "$baseline.new" "$baseline"
    if ((staged)); then
      grep -F -f <(printf '\t%s:\n' "${files[@]}") "$baseline" >"$relevant" || true
    else
      cp "$baseline" "$relevant"
    fi
  fi
  qml_compare "$current" "$relevant" || status=1
  rm -f "$current" "$relevant"
  return "$status"
}
