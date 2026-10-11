/** @typedef {{argv:Array<string>,cwd:string,expectedAppId:?string,evidenceMode:string}} LaunchSpec */

/**
 * Builds only installed-help-verified argv contracts. Availability is checked by
 * the probe/runtime, never by this pure adapter. Terminal identities use a valid
 * dotted GTK application ID so the same token works with every terminal.
 * Nvim requires the optional fifth selected terminal ID; no default is inferred.
 * @param {string} role - editor, terminal or agent
 * @param {string} toolId - supported fixed adapter ID (claude/codex for agent)
 * @param {string} path - exact absolute checkout directory
 * @param {string} token - unique dotted launch application ID
 * @param {string} [terminalId] - selected terminal adapter for nvim and agent
 * @returns {?LaunchSpec} safe launch specification, or null
 */
function launchSpec(role, toolId, path, token, terminalId) {
  if (typeof path !== "string" || path.charAt(0) !== "/") return null
  for (var i = 0; i < path.length; i++)
    if (path.charCodeAt(i) < 32 || path.charCodeAt(i) === 127) return null
  if (role === "editor" && toolId === "code")
    return {
      argv: ["code", "--new-window", path],
      cwd: path,
      expectedAppId: null,
      evidenceMode: "process-only"
    }
  if (
    typeof token !== "string" ||
    !/^[A-Za-z_][A-Za-z0-9_-]*(\.[A-Za-z_][A-Za-z0-9_-]*)+$/.test(token)
  )
    return null
  if (role === "editor" && toolId === "nvim") {
    var terminal = launchSpec("terminal", terminalId, path, token)
    if (!terminal) return null
    var execute = executeSeparator(terminalId)
    terminal.argv = terminal.argv.concat(execute, ["nvim", "--", path])
    return terminal
  }
  if (role === "agent") {
    if (toolId !== "claude" && toolId !== "codex") return null
    var host = launchSpec("terminal", terminalId, path, token)
    if (!host) return null
    host.argv = host.argv.concat(
      executeSeparator(terminalId),
      toolId === "claude" ? ["claude"] : ["codex", "--cd", path]
    )
    return host
  }
  if (role !== "terminal") return null
  /** @type {Array<string>} */
  var argv
  switch (toolId) {
    case "alacritty":
      argv = ["alacritty", "--class", token, "--working-directory", path]
      break
    case "kitty":
      argv = ["kitty", "--class", token, "--directory", path]
      break
    case "foot":
      argv = ["foot", "--app-id", token, "--working-directory", path]
      break
    case "ghostty":
      argv = [
        "ghostty",
        "--class=" + token,
        "--gtk-single-instance=false",
        "--working-directory=" + path
      ]
      break
    default:
      return null
  }
  return { argv: argv, cwd: path, expectedAppId: token, evidenceMode: "process-app-id" }
}

/**
 * Terminal argument that precedes an executed program, or none.
 * @param {string} terminalId - supported terminal adapter
 * @returns {Array<string>} execute separator
 */
function executeSeparator(terminalId) {
  return terminalId === "alacritty" ? ["--command"] : terminalId === "ghostty" ? ["-e"] : []
}

if (typeof module !== "undefined") module.exports = { launchSpec }
