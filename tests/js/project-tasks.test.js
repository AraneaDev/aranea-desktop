const { test } = require("node:test")
const assert = require("node:assert/strict")
const { loadPragma } = require("./lib/load-pragma.js")
const tasks = loadPragma("plugins/araneadev.projects/ProjectTasks.js")
const project = {
  checkouts: [
    { id: "c-1", path: "/home/u/Work/myapp", primary: true },
    { id: "c-2", path: "/home/u/Work/myapp-worktrees/feat-a", primary: false }
  ]
}
const plain = (v) => JSON.parse(JSON.stringify(v))
test("task folder sits next to the primary checkout", () => {
  assert.equal(tasks.taskFolder(project, "feat/login"), "/home/u/Work/myapp-worktrees/feat-login")
  assert.equal(tasks.taskFolder(project, ""), "")
  assert.equal(tasks.taskFolder({ checkouts: [] }, "x"), "")
})
test("branch problems are only the obvious ones", () => {
  assert.equal(tasks.branchProblem("  "), "Enter a branch name.")
  assert.equal(tasks.branchProblem("a b"), "Branch names cannot contain spaces.")
  assert.equal(tasks.branchProblem("feat/x"), "")
})
test("remove summary explains each blocker", () => {
  const clean = { dirty: false, untracked: false, busy: false, unpushed: 0 }
  assert.deepEqual(plain(tasks.removeSummary(clean)), { allowed: true, confirmLabel: "Remove", lines: [] })
  assert.equal(tasks.removeSummary({ ...clean, untracked: true }).allowed, false)
  assert.equal(tasks.removeSummary({ ...clean, busy: true }).allowed, false)
  const one = tasks.removeSummary({ ...clean, unpushed: 1 })
  assert.equal(one.confirmLabel, "Remove anyway")
  assert.deepEqual(plain(one.lines), ["1 commit isn't on any remote."])
  assert.deepEqual(plain(tasks.removeSummary({ ...clean, unpushed: 3 }).lines), ["3 commits aren't on any remote."])
})
test("remove summary mentions ignored items and a missing folder", () => {
  const clean = { dirty: false, untracked: false, busy: false, unpushed: 0, ignored: 0, missing: false }
  const one = tasks.removeSummary({ ...clean, ignored: 1 })
  assert.deepEqual(plain(one), { allowed: true, confirmLabel: "Remove", lines: ["1 ignored item (such as build output or .env) will be deleted with the folder."] })
  assert.deepEqual(plain(tasks.removeSummary({ ...clean, ignored: 4 }).lines), ["4 ignored items (such as build output or .env) will be deleted with the folder."])
  const gone = tasks.removeSummary({ ...clean, missing: true })
  assert.equal(gone.allowed, true)
  assert.deepEqual(plain(gone.lines), ["The folder is already gone. Remove only forgets this checkout."])
})
test("remove summary lines keep a fixed order", () => {
  const all = tasks.removeSummary({ dirty: true, untracked: false, busy: true, unpushed: 2, ignored: 3, missing: true })
  assert.equal(all.allowed, false)
  assert.deepEqual(plain(all.lines), [
    "This checkout has uncommitted or untracked changes. Commit, stash or delete them first.",
    "An action is still running in this checkout. Stop it first.",
    "2 commits aren't on any remote.",
    "3 ignored items (such as build output or .env) will be deleted with the folder.",
    "The folder is already gone. Remove only forgets this checkout."
  ])
})
