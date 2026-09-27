#!/usr/bin/env bash
# validate stage for tools/check: every tracked file of a known type parses,
# relative Markdown links resolve, and no em dash appears outside the
# allowlist. Sourced by tools/check, which sets these and check_files.
check_root="${check_root:?tools/check sets check_root}"
repo_root="${repo_root:?tools/check sets repo_root}"

# Runs one validator over FILES (read from stdin), reporting each failure.
validate_each() {
  local label="$1"
  shift
  local file status=0
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if ! "$@" "$check_root/$file" >/dev/null 2>"$check_root/.validate-err"; then
      printf '%s: invalid %s: %s\n' "$file" "$label" "$(head -c 200 "$check_root/.validate-err")"
      status=1
    fi
  done
  rm -f "$check_root/.validate-err"
  return "$status"
}

# Parses a TOML file with Python's standard library.
toml_parse() {
  python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$1"
}

# Checks that every relative link in a Markdown file points at a file.
markdown_links() {
  local file="$1" dir target status=0
  dir="$(dirname "$file")"
  while IFS= read -r target; do
    target="${target%%#*}"
    [[ -z "$target" || "$target" == *://* || "$target" == mailto:* ]] && continue
    [[ -e "$dir/$target" ]] || {
      printf 'broken link %s\n' "$target" >&2
      status=1
    }
  done < <(grep -oE '\]\([^) ]+' "$file" | sed 's/^](//')
  return "$status"
}

# validate stage entry point.
stage_validate() {
  local status=0
  command -v jq >/dev/null || {
    echo "jq is required (install jq)"
    return 1
  }
  command -v python3 >/dev/null || {
    echo "python3 is required"
    return 1
  }
  check_files '\.json$' | validate_each JSON jq empty || status=1
  check_files '\.toml$' | validate_each TOML toml_parse || status=1
  if command -v xmllint >/dev/null; then
    check_files '\.svg$' | validate_each SVG xmllint --noout || status=1
  else
    echo "xmllint is required (install libxml2)"
    status=1
  fi
  if command -v identify >/dev/null; then
    check_files '\.png$' '\.jpe?g$' | validate_each image identify || status=1
  else
    echo "identify is required (install imagemagick)"
    status=1
  fi
  if command -v luac >/dev/null; then
    check_files '\.lua$' | validate_each Lua luac -p -o /dev/null || status=1
  fi
  check_files '\.md$' | validate_each 'Markdown links' markdown_links || status=1
  # House rule: no em dash outside the allowlist (one path per line).
  local allow="$repo_root/tools/baselines/em-dash-allow.txt" file
  local em_dash=$'\xe2\x80\x94'
  while IFS= read -r file; do
    [[ -n "$file" && -f "$check_root/$file" ]] || continue
    grep -Fqx -- "$file" "$allow" 2>/dev/null && continue
    if grep -Iq "$em_dash" "$check_root/$file" 2>/dev/null; then
      printf '%s: em dash (house style; see tools/baselines/em-dash-allow.txt)\n' "$file"
      status=1
    fi
  done < <(check_files)
  return "$status"
}
