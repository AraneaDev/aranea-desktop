// Logic contract for the polkit modules (moved from tests/polkit.test.sh).
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const path = require("node:path")
const { test } = require("node:test")

test("polkit logic", () => {
  const root = path.join(__dirname, "..", "..")
  const stock = "/usr/share/omarchy/shell/plugins/polkit/PolkitModel.js"
  const fs = require("fs")
  const p = require(`${root}/plugins/araneadev.polkit/PolkitLogic.js`)
  const assert = (cond, msg) => {
    if (!cond) throw new Error(msg)
  }
  const eq = (a, b, msg) =>
    assert(JSON.stringify(a) === JSON.stringify(b), `${msg}: got ${JSON.stringify(a)}`)

  // --- stock helpers keep their behaviour
  const pam = "auth sufficient pam_fprintd.so\nauth include system-auth"
  assert(p.fingerprintConfiguredFromPamConfig(pam) === true, "pam fprintd")
  assert(
    p.fingerprintConfiguredFromPamConfig(
      "#auth sufficient pam_fprintd.so\nauth include system-auth"
    ) === false,
    "commented fprintd"
  )
  assert(
    p.fingerprintConfiguredFromPamConfig(
      "auth [success=1] pam_exec.so quiet /usr/bin/lid\nauth sufficient pam_fprintd.so"
    ) === true,
    "gate before fprintd"
  )
  assert(
    p.promptLooksFingerprint("Swipe your finger") && !p.promptLooksFingerprint("Password:"),
    "fingerprint prompt"
  )
  eq(
    p.authorizationLabel("Authentication is needed to run `/usr/bin/true' as the super user"),
    "Authorize running '/usr/bin/true'",
    "authorizationLabel"
  )
  if (fs.existsSync(stock)) {
    const s = require(stock)
    for (const m of [
      "Authentication is needed to run `/usr/bin/true' as the super user",
      "Authentication is required to mount /dev/sdb1",
      "",
      "x"
    ]) {
      eq(p.authorizationLabel(m), s.authorizationLabel(m), "stock parity authorizationLabel " + m)
      eq(p.promptLooksFingerprint(m), s.promptLooksFingerprint(m), "stock parity fingerprint " + m)
    }
    for (const raw of [pam, "", "auth include system-auth"])
      eq(
        p.fingerprintConfiguredFromPamConfig(raw),
        s.fingerprintConfiguredFromPamConfig(raw),
        "stock parity pam"
      )
  } else {
    console.log("SKIP: stock Omarchy sources not present; parity checks not run")
  }

  // --- request summary and command
  const root1 = "Authentication is needed to run `/usr/bin/true' as the super user"
  const user1 = "Authentication is required to run '/usr/bin/btop' as user Tim Schipper (tim)"
  eq(
    p.summaryParts(root1),
    { prefix: "Run '", command: "/usr/bin/true", suffix: "'", target: "root" },
    "super user parts"
  )
  eq(p.requestSummary(root1), "Run '/usr/bin/true' as root", "super user summary")
  eq(p.requestSummary(user1), "Run '/usr/bin/btop' as Tim Schipper (tim)", "named user summary")
  eq(
    p.requestSummary("Authentication is required to mount /dev/sdb1"),
    "Authentication is required to mount /dev/sdb1",
    "fallback summary"
  )
  eq(p.requestSummary(""), "Authentication is needed", "empty summary")
  eq(p.requestSummary(undefined), "Authentication is needed", "undefined summary")
  eq(p.commandFromMessage(root1), "/usr/bin/true", "command")
  eq(p.commandFromMessage(user1), "/usr/bin/btop", "command named user")
  eq(p.commandFromMessage("Authentication is required to mount /dev/sdb1"), "", "no command")

  // --- long commands (Review Focus 5)
  eq(p.shortenMiddle("short", 64), "short", "short kept")
  const long = "/usr/lib/" + "a".repeat(100) + "/bin/tool"
  const cut = p.shortenMiddle(long, 64)
  assert(
    cut.length === 64 &&
      cut.includes("…") &&
      cut.startsWith("/usr/lib/") &&
      cut.endsWith("/bin/tool"),
    "middle shortened: " + cut
  )

  // --- markup is escaped (Review Focus 2)
  eq(p.escapeHtml('<b>&"x"</b>'), "&lt;b&gt;&amp;&quot;x&quot;&lt;/b&gt;", "escapeHtml")
  eq(
    p.requestMarkup(root1, "#3bff9e"),
    "Run '<font color=\"#3bff9e\">/usr/bin/true</font>'",
    "markup"
  )
  const hostile = "Authentication is needed to run `/tmp/<b>x</b>&y' as the super user"
  const hm = p.requestMarkup(hostile, "#3bff9e")
  assert(
    !hm.includes("<b>") && hm.includes("&lt;b&gt;x&lt;/b&gt;&amp;y"),
    "hostile command escaped: " + hm
  )
  const hm2 = p.requestMarkup("Install <i>pkg</i> & more", "#fff")
  eq(hm2, "Install &lt;i&gt;pkg&lt;/i&gt; &amp; more", "hostile fallback escaped")
  // final review m6: line breaks in a non-pkexec message become spaces
  eq(
    p.requestMarkup("Line one\nline two\r\nthree", "#fff"),
    "Line one line two three",
    "newlines collapse"
  )
  assert(!p.requestMarkup(root1, '"><script>').includes('"><script>'), "accent escaped")

  // --- action ids
  for (const id of [
    "org.freedesktop.policykit.exec",
    "org.freedesktop.udisks2.filesystem-mount",
    "a_b-c.d"
  ])
    assert(p.validActionId(id), "valid id " + id)
  for (const id of ["", "a b", "a;b", "$(id)", "a/b", "-".repeat(256), null, undefined])
    assert(!p.validActionId(id), "invalid id " + id)

  // --- pkaction output
  const pkaction = [
    "org.freedesktop.policykit.exec:",
    "  description:       Run a program as another user",
    "  message:           Authentication is required to run a program as another user",
    "  vendor:            The polkit project",
    "  vendor_url:        http://www.freedesktop.org/wiki/Software/polkit/",
    "  icon:              ",
    "  implicit any:      auth_admin"
  ].join("\n")
  eq(
    p.parseActionInfo(pkaction),
    { description: "Run a program as another user", vendor: "The polkit project" },
    "pkaction parsed"
  )
  eq(p.parseActionInfo(""), { description: "", vendor: "" }, "empty pkaction")
  eq(
    p.parseActionInfo("garbage\n\u0000\nno colon here"),
    { description: "", vendor: "" },
    "garbage pkaction"
  )
  eq(
    p.parseActionInfo("  vendor_url: http://x\n"),
    { description: "", vendor: "" },
    "vendor_url is not vendor"
  )

  // --- identities
  eq(p.identityLabel({ displayName: "tim", string: "unix-user:tim" }), "tim", "displayName")
  eq(
    p.identityLabel({ displayName: "", string: "unix-user:tim" }),
    "unix-user:tim",
    "string fallback"
  )
  eq(p.identityLabel({}), "", "empty identity")
  eq(p.identityLabel(null), "", "null identity")
  const a = { displayName: "tim" },
    b = { displayName: "root" }
  eq(p.indexOfIdentity([a, b], b), 1, "indexOf")
  eq(p.indexOfIdentity([a, b], {}), -1, "indexOf missing")
  eq(p.indexOfIdentity(null, a), -1, "indexOf null list")
  eq(p.identityPosition([a], a), "", "single identity")
  eq(p.identityPosition([a, b], a), " (1 of 2)", "position")
  eq(p.identityPosition([a, b], null), "", "position unknown")
  eq(p.nextIdentityIndex(2, 0), 1, "next")
  eq(p.nextIdentityIndex(2, 1), 0, "wrap")
  eq(p.nextIdentityIndex(2, -1), 0, "unknown current")
  eq(p.nextIdentityIndex(0, 0), -1, "no identities")

  // --- context line
  eq(
    p.contextLine("Run a program as another user", "tim", ""),
    "Run a program as another user · as tim",
    "both"
  )
  eq(
    p.contextLine("Run a program as another user", "tim", " (1 of 2)"),
    "Run a program as another user · as tim (1 of 2)",
    "with position"
  )
  eq(p.contextLine("", "tim", ""), "as tim", "identity only")
  eq(p.contextLine("Mount a filesystem", "", ""), "Mount a filesystem", "description only")
  eq(p.contextLine("", "", " (1 of 2)"), "", "nothing")

  // --- details
  eq(
    p.detailRows("org.x", "The polkit project", "/usr/bin/true", "msg"),
    [
      { key: "ACTION", value: "org.x" },
      { key: "VENDOR", value: "The polkit project" },
      { key: "COMMAND", value: "/usr/bin/true" },
      { key: "MESSAGE", value: "msg" }
    ],
    "all rows"
  )
  eq(
    p.detailRows("org.x", "", "", "msg"),
    [
      { key: "ACTION", value: "org.x" },
      { key: "MESSAGE", value: "msg" }
    ],
    "empty rows hidden"
  )

  // --- placeholder
  eq(p.promptPlaceholder("Password:"), "Enter password", "Password:")
  eq(p.promptPlaceholder("password: "), "Enter password", "password: ")
  eq(p.promptPlaceholder(""), "Enter password", "empty prompt")
  eq(p.promptPlaceholder("Verification code:"), "Verification code", "custom prompt")
})

test("polkit spoofing (4a)", () => {
  const p = require(path.join(__dirname, "..", "..", "plugins/araneadev.polkit/PolkitLogic.js"))
  const eq = (a, b, msg) => {
    if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: got ${JSON.stringify(a)}`)
  }
  const spoof = "Authentication is needed to run `/tmp/x' as user tim (tim)' as the super user"
  eq(p.commandFromMessage(spoof), "/tmp/x' as user tim (tim)", "command keeps the fake tail")
  eq(p.targetLine(spoof), "as root", "real target wins")
  const reverse = "Authentication is needed to run `/tmp/x' as the super user' as user Bob (bob)"
  eq(p.targetLine(reverse), "as Bob (bob)", "named user at the end wins")
  eq(
    p.targetLine("Authentication is needed to run `/usr/bin/true' as the super user"),
    "as root",
    "root"
  )
  eq(p.targetLine("Authentication is required to mount /dev/sdb1"), "", "not pkexec")
  eq(
    p.targetLine("Authentication is needed to run `/usr/bin/true' as the admin"),
    "",
    "unknown tail"
  )
  eq(p.requestSummary(spoof), "Run '/tmp/x' as user tim (tim)' as root", "summary")
  // invisible or blank-looking characters are shown as escapes
  eq(p.visibleCommand("/bin/a⠀⠀b"), "/bin/a\\u2800\\u2800b", "braille blank")
  eq(p.visibleCommand("a​b‮c⁦d﻿e"), "a\\u200Bb\\u202Ec\\u2066d\\uFEFFe", "zero-width and bidi")
  eq(p.visibleCommand("a\u0007b\u0085c"), "a\\u0007b\\u0085c", "C0 and C1 controls")
  eq(p.visibleCommand("/usr/bin/true --flag"), "/usr/bin/true --flag", "normal text untouched")
  const padded = "Authentication is needed to run `/bin/sh" + "⠀".repeat(3) + "' as the super user"
  const m = p.requestMarkup(padded, "#fff")
  if (m.includes("⠀") || !m.includes("\\u2800")) throw new Error("markup hides padding: " + m)
  const rows = p.detailRows("org.x", "", p.commandFromMessage(padded), padded)
  if (rows.some((r) => r.value.includes("⠀"))) throw new Error("details hide padding")
})

test("polkit hint line (4a)", () => {
  const p = require(path.join(__dirname, "..", "..", "plugins/araneadev.polkit/PolkitLogic.js"))
  const eq = (a, b, msg) => {
    if (a !== b) throw new Error(`${msg}: got ${JSON.stringify(a)}`)
  }
  eq(p.hintLine(false, 1), "ENTER AUTHORIZE · TAB DETAILS · ESC CANCEL", "password, one identity")
  eq(p.hintLine(true, 0), "TAB DETAILS · ESC CANCEL", "fingerprint")
  eq(
    p.hintLine(false, 2),
    "ENTER AUTHORIZE · TAB DETAILS · ⇧TAB SWITCH IDENTITY · ESC CANCEL",
    "several identities"
  )
  eq(p.hintLine(true, 3), "TAB DETAILS · ⇧TAB SWITCH IDENTITY · ESC CANCEL", "fingerprint, several")
})

test("polkit final review fixes (4a)", () => {
  const p = require(path.join(__dirname, "..", "..", "plugins/araneadev.polkit/PolkitLogic.js"))
  const eq = (a, b, msg) => {
    if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: got ${JSON.stringify(a)}`)
  }
  // C1: a line or paragraph separator in the command still parses; the fallback is escaped too
  const sep = "Authentication is needed to run `/tmp/x' as user tim (tim)⠀⠀ ' as the super user"
  eq(p.targetLine(sep), "as root", "separator in command")
  eq(p.commandFromMessage(sep), "/tmp/x' as user tim (tim)⠀⠀ ", "command kept whole")
  const fallback = p.requestMarkup("Install⠀⠀ pkg‮", "#fff")
  if (/[⠀‮]/.test(fallback)) throw new Error("fallback hides characters: " + fallback)
  // I3: display names may contain an apostrophe
  eq(
    p.targetLine("Authentication is needed to run `/usr/bin/true' as user Tim O'Brien (tim)"),
    "as Tim O'Brien (tim)",
    "apostrophe in name"
  )
  eq(
    p.targetLine("Authentication is needed to run `/tmp/x' as the super user' as user Bob (bob)"),
    "as Bob (bob)",
    "spoof still loses"
  )
  // m2: more blank-looking characters, astral ones included
  eq(
    p.visibleCommand("a b؜c᠎d e　f️gﾠh"),
    "a\\u00A0b\\u061Cc\\u180Ed\\u2003e\\u3000f\\uFE0Fg\\uFFA0h",
    "BMP invisibles"
  )
  eq(p.visibleCommand("x\u{E0041}y"), "x\\u{E0041}y", "tag character")
  eq(p.visibleCommand("ü😀"), "ü😀", "visible astral kept")
})
