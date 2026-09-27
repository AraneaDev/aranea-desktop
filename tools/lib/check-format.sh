#!/usr/bin/env bash
# format stage for tools/check: shfmt for shell, prettier for JS, JSON,
# Markdown and YAML, qmlformat for QML (settings from .qmlformat.ini). With
# --fix the files are rewritten; otherwise differences fail the stage.
check_root="${check_root:?tools/check sets check_root}"
fix="${fix:-0}"

# format stage entry point.
stage_format() {
  local status=0 files
  command -v shfmt >/dev/null || { echo "shfmt is required: tools/install-shfmt ~/.local/bin"; return 1; }
  [[ -x "$(node_bin)/prettier" ]] || { echo "prettier is required: npm ci"; return 1; }
  local qmlformat
  qmlformat="$(qt_tool qmlformat)" || { echo "qmlformat is required (qt6-declarative)"; return 1; }

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
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    formatted="$(cd "$check_root" && "$qmlformat" "$file")" || { echo "$file: qmlformat failed"; status=1; continue; }
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
