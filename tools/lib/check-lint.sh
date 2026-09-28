#!/usr/bin/env bash
# lint stage for tools/check: ShellCheck (pinned 0.11.0), ESLint, markdownlint
# and actionlint. A missing tool fails the stage with its install command.
check_root="${check_root:?tools/check sets check_root}"
repo_root="${repo_root:?tools/check sets repo_root}"

# lint stage entry point.
stage_lint() {
  local status=0 files
  command -v shellcheck >/dev/null || {
    echo "shellcheck is required: sudo tools/install-shellcheck"
    return 1
  }
  [[ -x "$(node_bin)/eslint" ]] || {
    echo "eslint is required: npm ci"
    return 1
  }
  [[ -x "$(node_bin)/markdownlint-cli2" ]] || {
    echo "markdownlint-cli2 is required: npm ci"
    return 1
  }
  command -v actionlint >/dev/null || {
    echo "actionlint is required: tools/install-actionlint ~/.local/bin"
    return 1
  }

  mapfile -t files < <(shell_files)
  if ((${#files[@]})); then
    (cd "$check_root" && shellcheck -x -- "${files[@]}") || status=1
  fi
  mapfile -t files < <(check_files '\.js$' '\.mjs$')
  if ((${#files[@]})); then
    (cd "$check_root" && "$(node_bin)/eslint" --no-warn-ignored -c "$repo_root/eslint.config.js" -- "${files[@]}") || status=1
  fi
  mapfile -t files < <(check_files '\.md$')
  if ((${#files[@]})); then
    (cd "$check_root" && "$(node_bin)/markdownlint-cli2" --config "$repo_root/.markdownlint-cli2.jsonc" "${files[@]}") || status=1
  fi
  mapfile -t files < <(check_files '^\.github/workflows/.*\.ya?ml$')
  if ((${#files[@]})); then
    (cd "$check_root" && actionlint -- "${files[@]}") || status=1
  fi
  return "$status"
}
