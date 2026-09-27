#!/usr/bin/env bash
# format stage for tools/check: shfmt for shell, prettier for JS, JSON,
# Markdown and YAML, qmlformat for QML (settings from .qmlformat.ini). With
# --fix the files are rewritten; otherwise differences fail the stage.
check_root="${check_root:?tools/check sets check_root}"
fix="${fix:-0}"

# format stage entry point.
stage_format() {
  local status=0 files
  command -v shfmt >/dev/null || {
    echo "shfmt is required: tools/install-shfmt ~/.local/bin"
    return 1
  }
  [[ -x "$(node_bin)/prettier" ]] || {
    echo "prettier is required: npm ci"
    return 1
  }
  # QML formatting depends on the qmlformat version (its output and the
  # .qmlformat.ini options changed across Qt releases), so it runs only with
  # Qt 6.11 or newer; older or missing qmlformat skips the QML part with a
  # note (a failure where everything is required, like the Arch CI job).
  local qmlformat qml_version
  qmlformat="$(qt_tool qmlformat)" || qmlformat=""
  qml_version="$([[ -n "$qmlformat" ]] && "$qmlformat" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n1)"
  if [[ -z "$qmlformat" ]] || ! printf '%s\n6.11\n' "${qml_version:-0.0}" | sort -V -C -r; then
    echo "QML formatting skipped: needs qmlformat 6.11+ (found ${qml_version:-none})"
    note_stage "QML skipped: qmlformat ${qml_version:-missing}"
    [[ "${ARANEA_CHECK_REQUIRE_ALL:-0}" == 1 ]] && status=1
    qmlformat=""
  fi

  mapfile -t files < <(shell_files)
  if ((${#files[@]})); then
    if ((fix)); then
      (cd "$check_root" && shfmt -w -i 2 -ci -- "${files[@]}") || status=1
    else
      (cd "$check_root" && shfmt -d -i 2 -ci -- "${files[@]}") || status=1
    fi
  fi

  mapfile -t files < <(check_files '\.js$' '\.json$' '\.md$' '\.ya?ml$')
  if ((${#files[@]})); then
    if ((fix)); then
      (cd "$check_root" && "$(node_bin)/prettier" --write --ignore-unknown --log-level warn -- "${files[@]}") || status=1
    else
      (cd "$check_root" && "$(node_bin)/prettier" --check --ignore-unknown --log-level warn -- "${files[@]}") || status=1
    fi
  fi

  local file formatted
  [[ -n "$qmlformat" ]] || return "$status"
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    formatted="$(cd "$check_root" && "$qmlformat" "$file")" || {
      echo "$file: qmlformat failed"
      status=1
      continue
    }
    if [[ "$formatted" != "$(<"$check_root/$file")" ]]; then
      if ((fix)); then
        printf '%s\n' "$formatted" >"$check_root/$file"
      else
        echo "$file: not formatted (run tools/check --fix)"
        status=1
      fi
    fi
  done < <(check_files '\.qml$')
  return "$status"
}
