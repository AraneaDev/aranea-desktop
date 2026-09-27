#!/usr/bin/env bash
# docs stage for tools/check: ESLint's jsdoc rules and TypeScript (checkJs)
# for JS, tools/check-docs for shell and QML. See CONTRIBUTING.md.
check_root="${check_root:?tools/check sets check_root}"
repo_root="${repo_root:?tools/check sets repo_root}"

# docs stage entry point.
stage_docs() {
  local status=0 files
  [[ -x "$(node_bin)/tsc" ]] || {
    echo "typescript is required: npm ci"
    return 1
  }
  mapfile -t files < <(shell_files)
  local qml
  mapfile -t qml < <(check_files '\.qml$')
  if ((${#files[@]} + ${#qml[@]})); then
    "$repo_root/tools/check-docs" --root "$check_root" "${files[@]}" "${qml[@]}" || status=1
  fi
  # ESLint with the jsdoc rules switched on (eslint.config.js).
  mapfile -t files < <(check_files '\.js$')
  if ((${#files[@]})); then
    (cd "$check_root" && ARANEA_ESLINT_DOCS=1 "$(node_bin)/eslint" --no-warn-ignored -c "$repo_root/eslint.config.js" -- "${files[@]}") || status=1
  fi
  (cd "$check_root" && "$(node_bin)/tsc" -p tsconfig.json) || status=1
  return "$status"
}
