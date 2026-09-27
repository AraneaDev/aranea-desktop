#!/usr/bin/env bash
# Helpers shared by the tools/check stage libraries. Sourced by tools/check
# (which sets check_root, repo_root and check_files) before any stage.
check_root="${check_root:?tools/check sets check_root}"
repo_root="${repo_root:?tools/check sets repo_root}"

# Prints tracked shell files: a .sh name or a sh/bash shebang (not symlinks).
shell_files() {
  local file
  while IFS= read -r file; do
    [[ -n "$file" && -f "$check_root/$file" && ! -L "$check_root/$file" ]] || continue
    if [[ "$file" == *.sh ]] || head -n1 "$check_root/$file" 2>/dev/null | grep -Eq '^#!.*\b(ba)?sh\b'; then
      printf '%s\n' "$file"
    fi
  done < <(check_files)
}

# Prints the node_modules/.bin directory holding the JS tools.
node_bin() {
  printf '%s/.bin\n' "${ARANEA_CHECK_NODE_MODULES:-$repo_root/node_modules}"
}

# Prints the qmlformat/qmllint binary NAME from PATH or Qt's bin directory.
qt_tool() {
  command -v "$1" 2>/dev/null || { [[ -x "/usr/lib/qt6/bin/$1" ]] && printf '/usr/lib/qt6/bin/%s\n' "$1"; }
}
