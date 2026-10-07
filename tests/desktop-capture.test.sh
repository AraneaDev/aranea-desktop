#!/usr/bin/env bash
# Startup frames must be retried, and a permanently blank capture must
# preserve the previous desktop image instead of publishing it.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
bin="$ARANEA_TEST_SANDBOX/bin"
out="$ARANEA_TEST_SANDBOX/shots"
mkdir -p "$bin" "$out"
convert -size 160x90 xc:'#101010' "$ARANEA_TEST_SANDBOX/blank.png" 2>/dev/null
convert -size 160x90 gradient:black-white "$ARANEA_TEST_SANDBOX/ready.png" 2>/dev/null
cat >"$bin/grim" <<'STUB'
#!/usr/bin/env bash
count=$(cat "$ARANEA_TEST_SANDBOX/count" 2>/dev/null || echo 0)
count=$((count + 1))
echo "$count" > "$ARANEA_TEST_SANDBOX/count"
frame=blank
if [[ "${CAPTURE_ALWAYS_BLANK:-0}" != 1 && "$count" -gt 1 ]]; then frame=ready; fi
cp "$ARANEA_TEST_SANDBOX/$frame.png" "${@: -1}"
STUB
printf '#!/usr/bin/env bash\nexit 0\n' >"$bin/sleep"
chmod +x "$bin"/*
export PATH="$bin:$PATH"
capture="$repo_root/scripts/capture-screenshots"
"$capture" --surface desktop --output "$out" >/dev/null
cmp -s "$out/desktop.png" "$ARANEA_TEST_SANDBOX/ready.png"
[[ "$(cat "$ARANEA_TEST_SANDBOX/count")" -gt 1 ]]
printf previous >"$out/desktop.png"
rm "$ARANEA_TEST_SANDBOX/count"
if CAPTURE_ALWAYS_BLANK=1 "$capture" --surface desktop --output "$out" >/dev/null 2>&1; then
  echo 'permanently blank capture was accepted' >&2
  exit 1
fi
[[ "$(cat "$out/desktop.png")" == previous ]]
[[ "$(find "$out" -name '.desktop.*' | wc -l)" == 0 ]]
echo 'desktop capture retries startup frames and preserves the prior capture on failure'
