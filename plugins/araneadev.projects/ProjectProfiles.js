/**
 * Filter the actual supported tool probe without mutating it.
 * @param {{[key:string]:*}} tools - installed observations
 * @param {string} group - probe role collection
 * @returns {Array<{[key:string]:*}>} supported installed adapters
 */
function choices(tools, group) {
  /** @type {Array<{[key:string]:*}>} */
  var options = (tools || {})[group] || []
  return options.filter(function (tool) {
    return tool.available === true && tool.supported === true
  })
}
/**
 * Prefer an available desktop default for unspecified choices.
 * @param {{[key:string]:*}} tools - installed observations
 * @param {string} group - probe role collection
 * @param {string} key - default adapter field
 * @returns {?string} available adapter ID or null
 */
function preferred(tools, group, key) {
  var options = choices(tools, group)
  var id = ((tools || {}).defaults || {})[key]
  return options.some(function (tool) {
    return tool.id === id
  })
    ? id
    : options.length
      ? options[0].id
      : null
}
/**
 * Resolve null migrated defaults without changing the saved record; explicit missing IDs fail.
 * @param {{[key:string]:*}} profile - saved profile or local draft
 * @param {{[key:string]:*}} tools - installed observations
 * @returns {{ok:boolean,roles:string[],tools:{[key:string]:?string},error:string}} validity, unchanged roles, resolved adapters and recovery error
 */
function resolve(profile, tools) {
  /** @type {string[]} */
  var roles = (profile && profile.roles) || []
  var saved = (profile && profile.tools) || {}
  /** @type {{[key:string]:?string}} */
  var resolved = { editorId: null, terminalId: null, agentId: null }
  var error =
    roles.length &&
    roles.every(function (role) {
      return ["editor", "terminal", "agent"].indexOf(role) >= 0
    })
      ? ""
      : "Choose at least one tool role."
  /**
   * Select one required adapter or retain its first actionable failure.
   * @param {string} group - probe role collection
   * @param {string} key - adapter field
   * @param {string} label - human role description
   * @returns {void}
   */
  function select(group, key, label) {
    var id = saved[key] || preferred(tools, group, key)
    if (
      !choices(tools, group).some(function (tool) {
        return tool.id === id
      })
    ) {
      if (!error) error = "Choose an installed supported " + label + "."
    } else resolved[key] = id
  }
  if (roles.indexOf("editor") >= 0) select("editors", "editorId", "editor")
  if (roles.indexOf("agent") >= 0) select("agents", "agentId", "agent provider")
  if (roles.indexOf("terminal") >= 0 || roles.indexOf("agent") >= 0 || resolved.editorId === "nvim")
    select("terminals", "terminalId", "terminal for Terminal, Neovim or Agent")
  return { ok: !error, roles: roles.slice(), tools: resolved, error: error }
}
/**
 * Offer usable combinations from the actual probe; caller owns explicit persistence.
 * @param {{[key:string]:*}} tools - installed observations
 * @returns {Array<{[key:string]:*}>} unsaved usable profile drafts
 */
function presets(tools) {
  /** @type {Array<{[key:string]:*}>} */
  var result = [],
    editors = choices(tools, "editors")
  var terminal = preferred(tools, "terminals", "terminalId")
  var agent = preferred(tools, "agents", "agentId")
  /**
   * Append a usable draft for one supported combination.
   * @param {string} name - visible preset name
   * @param {string[]} roles - requested roles
   * @param {?string} editor - selected editor
   * @param {?string} provider - selected agent provider
   * @returns {void}
   */
  function add(name, roles, editor, provider) {
    var draft = {
      name: name,
      roles: roles,
      tools: {
        editorId: editor,
        terminalId: roles.indexOf("terminal") >= 0 || editor === "nvim" ? terminal : null,
        agentId: provider
      }
    }
    if (resolve(draft, tools).ok) result.push(draft)
  }
  if (
    editors.some(function (tool) {
      return tool.id === "code"
    })
  )
    add("VS Code", ["editor"], "code", null)
  if (terminal && agent) add("Terminal + Agent", ["terminal", "agent"], null, agent)
  if (
    terminal &&
    editors.some(function (tool) {
      return tool.id === "nvim"
    })
  )
    add("Neovim", ["editor"], "nvim", null)
  if (terminal) add("Terminal", ["terminal"], null, null)
  return result
}
/**
 * Return only the actual saved choice, never an inferred first profile.
 * @param {{[key:string]:*}} project - saved project
 * @returns {?{[key:string]:*}} remembered existing profile or null
 */
function remembered(project) {
  /** @type {Array<{[key:string]:*}>} */
  var saved = (project || {}).profiles || []
  return (
    saved.filter(function (profile) {
      return profile.id === project.lastProfileId
    })[0] || null
  )
}

/**
 * Whether a saved profile can start with the installed tools.
 * @param {{[key:string]:*}} profile - saved profile
 * @param {{[key:string]:*}} tools - installed observations
 * @returns {boolean} usable
 */
function usable(profile, tools) {
  return resolve(profile, tools).ok
}

/**
 * The profile Start working uses: remembered when usable, else the first usable saved one.
 * @param {{[key:string]:*}} project - saved project
 * @param {{[key:string]:*}} tools - supported installed observations
 * @returns {?{[key:string]:*}} profile to start, or null
 */
function primary(project, tools) {
  if (!project) return null
  var remembered_ = remembered(project)
  if (remembered_ && usable(remembered_, tools)) return remembered_
  /** @type {Array<{[key:string]:*}>} */
  var saved = project.profiles || []
  return (
    saved.find(function (profile) {
      return usable(profile, tools)
    }) || null
  )
}

/**
 * Explain a fallback from an unusable remembered profile.
 * @param {{[key:string]:*}} project - saved project
 * @param {{[key:string]:*}} tools - installed observations
 * @returns {string} note or empty
 */
function fallbackNote(project, tools) {
  var remembered_ = remembered(project)
  var chosen = primary(project, tools)
  if (!remembered_ || !chosen || usable(remembered_, tools) || chosen.id === remembered_.id)
    return ""
  return remembered_.name + " isn't available, using " + chosen.name + "."
}

/**
 * Why Start working cannot start anything, when profiles exist.
 * @param {{[key:string]:*}} project - saved project
 * @param {{[key:string]:*}} tools - installed observations
 * @returns {string} reason or empty
 */
function blockedReason(project, tools) {
  /** @type {Array<{[key:string]:*}>} */
  var saved = (project && project.profiles) || []
  if (!saved.length || primary(project, tools)) return ""
  if (!presets(tools).length)
    return "Install a supported editor or terminal (VS Code, Neovim, Kitty, Alacritty, Foot or Ghostty), then Refresh."
  return "None of this project's profiles can start: " + resolve(saved[0], tools).error
}

/**
 * Describe actual adapters with readable names and dependent terminals.
 * @param {{[key:string]:*}} profile - saved profile or local draft
 * @param {{[key:string]:*}} tools - installed observations
 * @returns {string} readable tool summary or recovery instruction
 */
function summary(profile, tools) {
  var resolved = resolve(profile, tools)
  if (!resolved.ok) return resolved.error
  /**
   * Find a supported adapter's human label.
   * @param {string} group - probe collection
   * @param {string} key - resolved adapter field
   * @returns {string} friendly label
   */
  function label(group, key) {
    var tool = choices(tools, group).filter(function (item) {
      return item.id === resolved.tools[key]
    })[0]
    return tool ? tool.label || tool.id : ""
  }
  var terminal = label("terminals", "terminalId") + " terminal"
  return resolved.roles
    .map(function (role) {
      if (role === "terminal") return terminal
      var name = role === "editor" ? label("editors", "editorId") : label("agents", "agentId")
      return resolved.roles.indexOf("terminal") < 0 &&
        (role === "agent" || resolved.tools.editorId === "nvim")
        ? name + " in " + terminal
        : name
    })
    .join(" + ")
}

if (typeof module !== "undefined")
  module.exports = {
    choices: choices,
    preferred: preferred,
    resolve: resolve,
    presets: presets,
    remembered: remembered,
    primary: primary,
    usable: usable,
    fallbackNote: fallbackNote,
    blockedReason: blockedReason,
    summary: summary
  }
