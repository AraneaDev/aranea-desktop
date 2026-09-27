#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
plugin="$repo_root/plugins/araneadev.polkit"
stock="/usr/share/omarchy/shell/plugins/polkit/PolkitModel.js"

node - "$repo_root" "$stock" <<'NODE'
const [root, stock] = process.argv.slice(2)
const fs = require('fs')
const p = require(`${root}/plugins/araneadev.polkit/PolkitLogic.js`)
const assert = (cond, msg) => { if (!cond) throw new Error(msg) }
const eq = (a, b, msg) => assert(JSON.stringify(a) === JSON.stringify(b), `${msg}: got ${JSON.stringify(a)}`)

// --- stock helpers keep their behaviour
const pam = 'auth sufficient pam_fprintd.so\nauth include system-auth'
assert(p.fingerprintConfiguredFromPamConfig(pam) === true, 'pam fprintd')
assert(p.fingerprintConfiguredFromPamConfig('#auth sufficient pam_fprintd.so\nauth include system-auth') === false, 'commented fprintd')
assert(p.fingerprintConfiguredFromPamConfig('auth [success=1] pam_exec.so quiet /usr/bin/lid\nauth sufficient pam_fprintd.so') === true, 'gate before fprintd')
assert(p.promptLooksFingerprint('Swipe your finger') && !p.promptLooksFingerprint('Password:'), 'fingerprint prompt')
eq(p.authorizationLabel("Authentication is needed to run `/usr/bin/true' as the super user"), "Authorize running '/usr/bin/true'", 'authorizationLabel')
if (fs.existsSync(stock)) {
  const s = require(stock)
  for (const m of ["Authentication is needed to run `/usr/bin/true' as the super user", 'Authentication is required to mount /dev/sdb1', '', 'x']) {
    eq(p.authorizationLabel(m), s.authorizationLabel(m), 'stock parity authorizationLabel ' + m)
    eq(p.promptLooksFingerprint(m), s.promptLooksFingerprint(m), 'stock parity fingerprint ' + m)
  }
  for (const raw of [pam, '', 'auth include system-auth']) eq(p.fingerprintConfiguredFromPamConfig(raw), s.fingerprintConfiguredFromPamConfig(raw), 'stock parity pam')
}

// --- request summary and command
const root1 = "Authentication is needed to run `/usr/bin/true' as the super user"
const user1 = "Authentication is required to run '/usr/bin/btop' as user Tim Schipper (tim)"
eq(p.summaryParts(root1), { prefix: "Run '", command: '/usr/bin/true', suffix: "' as root" }, 'super user parts')
eq(p.requestSummary(root1), "Run '/usr/bin/true' as root", 'super user summary')
eq(p.requestSummary(user1), "Run '/usr/bin/btop' as Tim Schipper (tim)", 'named user summary')
eq(p.requestSummary('Authentication is required to mount /dev/sdb1'), 'Authentication is required to mount /dev/sdb1', 'fallback summary')
eq(p.requestSummary(''), 'Authentication is needed', 'empty summary')
eq(p.requestSummary(undefined), 'Authentication is needed', 'undefined summary')
eq(p.commandFromMessage(root1), '/usr/bin/true', 'command')
eq(p.commandFromMessage(user1), '/usr/bin/btop', 'command named user')
eq(p.commandFromMessage('Authentication is required to mount /dev/sdb1'), '', 'no command')

// --- long commands (Review Focus 5)
eq(p.shortenMiddle('short', 64), 'short', 'short kept')
const long = '/usr/lib/' + 'a'.repeat(100) + '/bin/tool'
const cut = p.shortenMiddle(long, 64)
assert(cut.length === 64 && cut.includes('…') && cut.startsWith('/usr/lib/') && cut.endsWith('/bin/tool'), 'middle shortened: ' + cut)

// --- markup is escaped (Review Focus 2)
eq(p.escapeHtml('<b>&"x"</b>'), '&lt;b&gt;&amp;&quot;x&quot;&lt;/b&gt;', 'escapeHtml')
eq(p.requestMarkup(root1, '#3bff9e'), 'Run \'<font color="#3bff9e">/usr/bin/true</font>\' as root', 'markup')
const hostile = "Authentication is needed to run `/tmp/<b>x</b>&y' as the super user"
const hm = p.requestMarkup(hostile, '#3bff9e')
assert(!hm.includes('<b>') && hm.includes('&lt;b&gt;x&lt;/b&gt;&amp;y'), 'hostile command escaped: ' + hm)
const hm2 = p.requestMarkup('Install <i>pkg</i> & more', '#fff')
eq(hm2, 'Install &lt;i&gt;pkg&lt;/i&gt; &amp; more', 'hostile fallback escaped')
// final review m6: line breaks in a non-pkexec message become spaces
eq(p.requestMarkup('Line one\nline two\r\nthree', '#fff'), 'Line one line two three', 'newlines collapse')
assert(!p.requestMarkup(root1, '"><script>').includes('"><script>'), 'accent escaped')

// --- action ids
for (const id of ['org.freedesktop.policykit.exec', 'org.freedesktop.udisks2.filesystem-mount', 'a_b-c.d']) assert(p.validActionId(id), 'valid id ' + id)
for (const id of ['', 'a b', 'a;b', '$(id)', 'a/b', '-'.repeat(256), null, undefined]) assert(!p.validActionId(id), 'invalid id ' + id)

// --- pkaction output
const pkaction = [
  'org.freedesktop.policykit.exec:',
  '  description:       Run a program as another user',
  '  message:           Authentication is required to run a program as another user',
  '  vendor:            The polkit project',
  '  vendor_url:        http://www.freedesktop.org/wiki/Software/polkit/',
  '  icon:              ',
  '  implicit any:      auth_admin'
].join('\n')
eq(p.parseActionInfo(pkaction), { description: 'Run a program as another user', vendor: 'The polkit project' }, 'pkaction parsed')
eq(p.parseActionInfo(''), { description: '', vendor: '' }, 'empty pkaction')
eq(p.parseActionInfo('garbage\n\u0000\nno colon here'), { description: '', vendor: '' }, 'garbage pkaction')
eq(p.parseActionInfo('  vendor_url: http://x\n'), { description: '', vendor: '' }, 'vendor_url is not vendor')

// --- identities
eq(p.identityLabel({ displayName: 'tim', string: 'unix-user:tim' }), 'tim', 'displayName')
eq(p.identityLabel({ displayName: '', string: 'unix-user:tim' }), 'unix-user:tim', 'string fallback')
eq(p.identityLabel({}), '', 'empty identity')
eq(p.identityLabel(null), '', 'null identity')
const a = { displayName: 'tim' }, b = { displayName: 'root' }
eq(p.indexOfIdentity([a, b], b), 1, 'indexOf')
eq(p.indexOfIdentity([a, b], {}), -1, 'indexOf missing')
eq(p.indexOfIdentity(null, a), -1, 'indexOf null list')
eq(p.identityPosition([a], a), '', 'single identity')
eq(p.identityPosition([a, b], a), ' (1 of 2)', 'position')
eq(p.identityPosition([a, b], null), '', 'position unknown')
eq(p.nextIdentityIndex(2, 0), 1, 'next')
eq(p.nextIdentityIndex(2, 1), 0, 'wrap')
eq(p.nextIdentityIndex(2, -1), 0, 'unknown current')
eq(p.nextIdentityIndex(0, 0), -1, 'no identities')

// --- context line
eq(p.contextLine('Run a program as another user', 'tim', ''), 'Run a program as another user · as tim', 'both')
eq(p.contextLine('Run a program as another user', 'tim', ' (1 of 2)'), 'Run a program as another user · as tim (1 of 2)', 'with position')
eq(p.contextLine('', 'tim', ''), 'as tim', 'identity only')
eq(p.contextLine('Mount a filesystem', '', ''), 'Mount a filesystem', 'description only')
eq(p.contextLine('', '', ' (1 of 2)'), '', 'nothing')

// --- details
eq(p.detailRows('org.x', 'The polkit project', '/usr/bin/true', 'msg'),
  [{ key: 'ACTION', value: 'org.x' }, { key: 'VENDOR', value: 'The polkit project' }, { key: 'COMMAND', value: '/usr/bin/true' }, { key: 'MESSAGE', value: 'msg' }], 'all rows')
eq(p.detailRows('org.x', '', '', 'msg'), [{ key: 'ACTION', value: 'org.x' }, { key: 'MESSAGE', value: 'msg' }], 'empty rows hidden')

// --- placeholder
eq(p.promptPlaceholder('Password:'), 'Enter password', 'Password:')
eq(p.promptPlaceholder('password: '), 'Enter password', 'password: ')
eq(p.promptPlaceholder(''), 'Enter password', 'empty prompt')
eq(p.promptPlaceholder('Verification code:'), 'Verification code', 'custom prompt')
NODE

# --- plugin shape: a clone of the stock agent
jq -e '.id == "araneadev.polkit" and .omarchy.clonedFrom == "omarchy.polkit" and .keepLoaded == true
  and .kinds == ["service"] and .entryPoints.service == "PolkitAgent.qml"' "$plugin/manifest.json" >/dev/null
grep -Fq 'import "PolkitLogic.js" as PolkitLogic' "$plugin/PolkitAgent.qml"
if grep -Fq 'PolkitModel' "$plugin/PolkitAgent.qml"; then
  echo "use PolkitLogic, not PolkitModel" >&2
  exit 1
fi
# The stock behaviour that must survive the restyle.
grep -Fq 'path: "/org/omarchy/PolkitAgent"' "$plugin/PolkitAgent.qml"
grep -Fq 'WlrLayershell.namespace: "omarchy-polkit"' "$plugin/PolkitAgent.qml"
grep -Fq 'path: "/etc/pam.d/polkit-1"' "$plugin/PolkitAgent.qml"
grep -Fq 'omarchy-hw-laptop-closed' "$plugin/PolkitAgent.qml"
grep -Fq 'id: shakeAnimation' "$plugin/PolkitAgent.qml"
grep -Fq 'flow.cancelAuthenticationRequest()' "$plugin/PolkitAgent.qml"
if grep -E 'console\.(log|warn).*passwordInput' "$plugin/PolkitAgent.qml"; then
  echo "never log the password" >&2
  exit 1
fi

# --- Aranea card
agent="$plugin/PolkitAgent.qml"
grep -Fq 'AUTHENTICATION REQUIRED' "$agent"
grep -Fq 'SYSTEM // PRIVILEGED' "$agent"
grep -Fq 'aranea-glyph.svg' "$agent"
grep -Fq 'PolkitLogic.requestMarkup(root.currentMessage' "$agent"
grep -Fq 'textFormat: Text.StyledText' "$agent"
grep -Fq 'PolkitLogic.contextLine(' "$agent"
grep -Fq 'PolkitLogic.detailRows(' "$agent"
grep -Fq 'ENTER AUTHORIZE · TAB DETAILS · ESC CANCEL' "$agent"
grep -Fq 'Math.max(Color.polkit.scrim.a, 0.72)' "$agent"
grep -Fq 'aranea/motion' "$agent"
# Review Focus 5: the card never exceeds the screen
grep -Fq 'Math.max(Style.space(120), Math.min(Style.space(380), panel.width - Style.gapsOut * 2))' "$agent"
# Action lookup: argv only, validated id, one request's result only (Review Focus 1)
grep -Fq '["timeout", "2", "pkaction", "--action-id", id, "--verbose"]' "$agent"
grep -Fq 'PolkitLogic.validActionId(id)' "$agent"
grep -Fq 'root.lookupQueued' "$agent"
grep -Fq 'String(flow.cookie || "") === root.lookupCookie' "$agent"
if grep -Eq '"(sh|bash)", "-c".*pkaction' "$agent"; then
  echo "pkaction must not run through a shell" >&2
  exit 1
fi
# Details start collapsed for every request
grep -Fq 'detailsOpen = false' "$agent"
# Review Focus 4: every focus holder routes keys through one handler
[[ "$(grep -c 'root.handleKey(event)' "$agent")" -ge 3 ]]
grep -Fq 'Qt.Key_Backtab' "$agent"
grep -Fq 'flow.selectedIdentity = flow.identities[' "$agent"
# The old pill above the card is gone (the request lives in the card now)
if grep -Fq 'justificationText' "$agent"; then
  echo "stock justification pill should be gone" >&2
  exit 1
fi

# --- final review fixes
# m1: a pkaction result rebuilds the details; keep keys working afterwards
grep -Fq 'if (root.detailsOpen) Qt.callLater(root.refocus)' "$agent"
# m2: content never spills past the card on very short screens
grep -Fq 'clip: true  // content never spills past the card' "$agent"
# m4: doctor reports whether a polkit prompt is enabled
grep -Fq 'ARANEA_DOCTOR_POLKIT_STATUS' "$repo_root/scripts/aranea-doctor"
# README tells a hand-disabler to restart the shell
grep -Fq 'omarchy plugin disable araneadev.polkit' "$repo_root/README.md"

echo "polkit contract passed"
