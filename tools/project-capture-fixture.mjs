// Prints the inert aranea.projects.capture payload (without the owner
// snapshot) for one Projects README surface. The data comes from the same
// fixture builders the offscreen renderers use, so the live desktop capture
// and the offscreen previews always show the same content.
//
// Usage: node tools/project-capture-fixture.mjs <surface>
import fs from "node:fs"
import path from "node:path"
import vm from "node:vm"
import { fileURLToPath } from "node:url"

const fixtures = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../tests/qml/fixtures")

/**
 * Loads the `sample` builder of a QML fixture script in an empty context.
 * @param {string} name - fixture script file name
 * @returns {Function} the script's sample function
 */
function builder(name) {
  const source = fs.readFileSync(path.join(fixtures, name), "utf8")
  return vm.runInNewContext(source + "\n;sample", {}, { filename: name })
}

/**
 * Builds the payload of one surface, mirroring the offscreen render states.
 * @param {string} surface - README surface name
 * @returns {object|null} payload, or null for an unknown surface
 */
function payload(surface) {
  const preview = builder("ProjectPreview.js")
  // Same fixture/state/count as scripts/capture-screenshots used offscreen.
  const states = {
    projects: ["project-details", undefined, "6"],
    "project-overview": ["project-details", "daily-task"],
    "project-problem": ["project-details", "problem"],
    "project-review": ["project-details", "review"],
    "project-switcher": ["projects-grouped", "switcher"]
  }
  let fixture
  let mode = ""
  if (surface === "project-actions") fixture = builder("ProjectActionsPreview.js")("passed")
  else if (states[surface]) fixture = preview(...states[surface])
  else if (surface === "project-preferences") {
    // Preferences of the sample, set to open a terminal and an agent but no editor.
    fixture = preview("project-details")
    fixture.projectSection = "preferences"
    fixture.projectTools.agents = [
      { id: "claude", label: "Claude Code", available: true, supported: true }
    ]
    for (const project of fixture.projectsState.projects)
      if (project.id === fixture.projectId) project.openRoles = ["terminal", "agent"]
  } else return null
  if (surface === "project-switcher") mode = "switcher"
  return {
    section: "projects",
    // The switcher lists every project; the others open the sample's details.
    projectId: mode === "switcher" ? "" : fixture.projectId,
    mode: mode,
    fixture: fixture
  }
}

const result = payload(process.argv[2] || "")
if (!result) {
  process.stderr.write("Usage: node tools/project-capture-fixture.mjs <surface>\n")
  process.exit(2)
}
process.stdout.write(JSON.stringify(result) + "\n")
