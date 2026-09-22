#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/ownership.sh"

dry_run=0
assume_yes=0

usage() {
  cat <<'EOF'
Usage: scripts/uninstall.sh [--dry-run] [--yes]

Restores files previously managed by an Aranea integration.
EOF
}

while (($#)); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --yes) assume_yes=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

record="$(ownership_record)"
if [[ ! -f "$record" ]]; then
  printf '%s\n' 'No Aranea-managed files found.'
  exit 0
fi

if (( dry_run )); then
  printf '%s\n' 'would restore Aranea-managed files:'
  sed 's/^/  /' "$record"
  exit 0
fi

if (( ! assume_yes )) && [[ -t 0 ]]; then
  read -r -p 'Restore Aranea-managed files? [y/N] ' answer
  [[ "$answer" =~ ^[Yy]$ ]] || { printf '%s\n' 'Cancelled.'; exit 0; }
fi

restore_managed_files
printf '%s\n' 'Aranea-managed files restored.'
