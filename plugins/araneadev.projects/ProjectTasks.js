/**
 * Where a task checkout for a branch lives, next to the primary checkout.
 * @param {{checkouts:Array<{path:string,primary:boolean}>}} project - registered project
 * @param {string} branch - requested branch name
 * @returns {string} absolute folder, or '' when it cannot be derived
 */
function taskFolder(project, branch) {
  var name = String(branch || "").trim()
  var list = (project && project.checkouts) || []
  var primary = list.filter(function (checkout) {
    return checkout.primary === true
  })[0]
  if (!primary || !primary.path || name === "") return ""
  var path = String(primary.path).replace(/\/+$/, "")
  var cut = path.lastIndexOf("/")
  var dir = cut > 0 ? path.slice(0, cut) : ""
  var base = path.slice(cut + 1)
  return dir + "/" + base + "-worktrees/" + name.replace(/\//g, "-")
}
/**
 * Only the obvious branch-name problems; Git has the final say.
 * @param {string} name - requested branch name
 * @returns {string} problem text or ''
 */
function branchProblem(name) {
  var text = String(name || "")
  if (text.trim() === "") return "Enter a branch name."
  if (/\s/.test(text)) return "Branch names cannot contain spaces."
  return ""
}
/**
 * Explain what removing a task checkout would do, from the helper's check facts.
 * @param {{dirty:boolean,untracked:boolean,busy:boolean,unpushed:number,ignored:number,missing:boolean}} facts - removal check
 * @returns {{allowed:boolean,confirmLabel:string,lines:Array<string>}} dialog content after the view's own first line
 */
function removeSummary(facts) {
  // `facts || {}` narrows to `{}`, which has none of the fact fields.
  var f = /** @type {any} */ (facts || {})
  var lines = []
  var allowed = true
  if (f.dirty || f.untracked) {
    allowed = false
    lines.push(
      "This checkout has uncommitted or untracked changes. Commit, stash or delete them first."
    )
  }
  if (f.busy) {
    allowed = false
    lines.push("An action is still running in this checkout. Stop it first.")
  }
  var unpushed = Number(f.unpushed) || 0
  if (unpushed > 0)
    lines.push(
      unpushed + (unpushed === 1 ? " commit isn't" : " commits aren't") + " on any remote."
    )
  var ignored = Number(f.ignored) || 0
  if (ignored > 0)
    lines.push(
      ignored +
        (ignored === 1 ? " ignored item" : " ignored items") +
        " (such as build output or .env) will be deleted with the folder."
    )
  if (f.missing === true)
    lines.push("The folder is already gone. Remove only forgets this checkout.")
  return {
    allowed: allowed,
    confirmLabel: allowed && unpushed > 0 ? "Remove anyway" : "Remove",
    lines: lines
  }
}
if (typeof module !== "undefined")
  module.exports = {
    taskFolder: taskFolder,
    branchProblem: branchProblem,
    removeSummary: removeSummary
  }
