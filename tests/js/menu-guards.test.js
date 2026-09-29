// Logic contract for the menu's guard batch (MenuModel.guardScript): one bash
// script answers every `when:` and `checked:`, reading each shared reader
// once. The script is run for real against stub commands.
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const { execFileSync } = require("node:child_process")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { test } = require("node:test")
const { loadPragma } = require("./lib/load-pragma.js")

const serialTest = (name, body) => test(name, { concurrency: false }, body)

const menu = loadPragma("plugins/araneadev.menu/MenuModel.js")

/**
 * Runs a guard script with stub commands first on PATH.
 * @param {string} script - the bash script
 * @param {Object<string, string>} stubs - command name to its bash body
 * @returns {{lines: Array<string>, calls: Array<string>}} the script's output lines and the stub calls
 */
function runGuards(script, stubs) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "aranea-guards-"))
  try {
    for (const [name, body] of Object.entries(stubs)) {
      const file = path.join(dir, name)
      fs.writeFileSync(file, `#!/usr/bin/env bash\necho ${name} >>"${dir}/calls"\n${body}\n`)
      fs.chmodSync(file, 0o755)
    }
    let out
    try {
      out = execFileSync("bash", ["-c", script], {
        env: { PATH: `${dir}:/usr/bin:/bin`, HOME: dir, TMPDIR: dir },
        encoding: "utf8"
      })
    } catch (error) {
      console.error(error.stderr || error.stdout || error)
      throw error
    }
    const callsFile = path.join(dir, "calls")
    const calls = fs.existsSync(callsFile)
      ? fs.readFileSync(callsFile, "utf8").trim().split("\n")
      : []
    return { lines: out.trim().split("\n"), calls }
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
}

const browserRows = {
  "defaults.firefox": { checked: "[[ $(omarchy-default-browser) == firefox ]]" },
  "defaults.chromium": { checked: "[[ $(omarchy-default-browser) == chromium ]]" },
  "install.vim": { when: "omarchy-pkg-missing vim" },
  "install.git": { when: "omarchy-cmd-missing definitely-not-a-command-xyz" },
  "plain.row": { label: "no guards" }
}

serialTest("guardScript is empty when no item has a guard", () => {
  assert.equal(menu.guardScript({ a: { label: "A" } }), "")
  assert.equal(menu.guardScript(null), "")
})

serialTest("the guard batch answers every when: and checked: as id:tag:result", () => {
  const { lines } = runGuards(menu.guardScript(browserRows), {
    "omarchy-default-browser": "echo firefox",
    pacman: "[[ $1 == -Qq ]] && echo vim; exit 0"
  })
  assert.deepEqual(lines.sort(), [
    "defaults.chromium:c:0",
    "defaults.firefox:c:1",
    "install.git:w:1",
    "install.vim:w:0"
  ])
})

serialTest("a reader shared by several rows runs once", () => {
  const { calls } = runGuards(menu.guardScript(browserRows), {
    "omarchy-default-browser": "echo firefox",
    pacman: "exit 0"
  })
  assert.equal(calls.filter((c) => c === "omarchy-default-browser").length, 1)
})

serialTest("package checks see provided names and fall back to pacman for versions", () => {
  const rows = {
    provided: { when: "omarchy-pkg-present vim" },
    versioned: { when: "omarchy-pkg-present 'bash>=1'" },
    none: { when: "omarchy-pkg-missing" }
  }
  const { lines } = runGuards(menu.guardScript(rows), {
    pacman: [
      'case "$1" in',
      "  -Qq) echo gvim ;;",
      "  -Qi) printf 'Name            : gvim\\nProvides        : vim=9.1\\n  xxd\\n' ;;",
      '  -Q) [[ $2 == "bash>=1" ]] ;;',
      "esac"
    ].join("\n")
  })
  assert.deepEqual(lines.sort(), ["none:w:0", "provided:w:1", "versioned:w:1"])
})

serialTest("only the plain $(reader) form is substituted", () => {
  const script = menu.guardScript({
    a: { when: "command -v omarchy-default-editor && [[ $(omarchy-default-editor) ]]" }
  })
  assert.ok(script.includes("command -v omarchy-default-editor && [[ ${__omarchy_read_"))
  assert.ok(script.includes("=$(omarchy-default-editor 2>/dev/null) || :"))
  assert.ok(!script.includes("omarchy-dns 2>/dev/null"), "unused readers are not captured")
})
