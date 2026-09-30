// The batch bash script that answers every `when:` and `checked:` guard.

/** @typedef {{id: string, label: string, kind?: string, parent?: string, when?: string, checked?: string}} MenuItem */
/** @typedef {{[key: string]: MenuItem}} ItemMap */
// Commands a `checked:` expression reads a value out of. Every sibling row
// asks the same one -- Defaults > Browser has seven rows all comparing
// against `omarchy-default-browser` -- so the batch runs it once and the rows
// read the captured answer.
//
// The capture has to be eager. These are read inside `$(...)`, and a value
// cached while one expression runs lives in that subshell only, so a lazy
// memo never survives to the expression after it.
var GUARD_READERS = [
  "omarchy-channel-current",
  "omarchy-default-agent",
  "omarchy-default-browser",
  "omarchy-default-editor",
  "omarchy-default-terminal",
  "omarchy-dns"
]

// Package and command presence account for most of what the guards ask, and
// asked one at a time they are almost all fork: the shipped menu spends over
// a second on them. Answer them inside the guard process instead. These
// shadow the real commands for the batch only, so they have to agree with
// them everywhere, including for no arguments at all (present is true of
// nothing, missing is not).
//
// `pacman -Q` resolves a name through what installed packages provide, not
// just what they are called -- with gvim installed it reports `vim` as
// present -- so the set has to carry provides too, or `install.editor.vim`
// comes back and offers to install what is already there. A version
// constraint (`bash>=1`) is not a name any set can answer, so it goes to
// pacman itself; no shipped guard writes one.
//
// `pacman -Qi` wraps a long list across continuation lines whenever COLUMNS
// is set in the environment, which a login shell may well have done, so the
// parser follows the indented lines rather than reading the first one and
// dropping half of what is installed.
/**
 * Returns the bash helpers that answer package and command checks in-process.
 * @returns {string} bash defining the package set and the omarchy-pkg-/cmd-present/missing shadows
 */
function guardHelpers() {
  return (
    "declare -A __omarchy_pkgs=()\n" +
    "mapfile -t __omarchy_pkg_names < <({ pacman -Qq; LC_ALL=C pacman -Qi" +
    ' | awk \'/^[A-Za-z]/ { provides = ($0 ~ /^Provides/); sub(/^[^:]*: /, "") }' +
    ' provides && $0 != "None" { n = split($0, p, " ");' +
    ' for (i = 1; i <= n; i++) { sub(/[<>=].*/, "", p[i]); print p[i] } }\'; } 2>/dev/null)\n' +
    'for __omarchy_pkg in "${__omarchy_pkg_names[@]}"; do __omarchy_pkgs[$__omarchy_pkg]=1; done\n' +
    "__omarchy_pkg_has() { [[ -n ${__omarchy_pkgs[$1]-} ]] && return 0; " +
    '[[ $1 == *[\\<\\>=]* ]] && { pacman -Q "$1" &>/dev/null; return; }; return 1; }\n' +
    'omarchy-pkg-present() { local p; for p in "$@"; do __omarchy_pkg_has "$p" || return 1; done; return 0; }\n' +
    'omarchy-pkg-missing() { local p; for p in "$@"; do __omarchy_pkg_has "$p" || return 0; done; return 1; }\n' +
    'omarchy-cmd-present() { local c; for c in "$@"; do command -v "$c" &>/dev/null || return 1; done; return 0; }\n' +
    'omarchy-cmd-missing() { local c; for c in "$@"; do command -v "$c" &>/dev/null || return 0; done; return 1; }\n'
  )
}

// Substitute the captured answer into the expression rather than shadowing
// the reader with a function. `$(reader)` and the variable holding what it
// printed are interchangeable -- both strip trailing newlines, both split the
// same way unquoted -- while a function would also catch `command -v reader`,
// `VAR=x reader`, and every other form, and answer those wrong. Anything but
// the plain substitution is left alone to run the real command.
/**
 * Returns the helpers plus eager captures of the readers the guards use.
 * @param {string} guards - the guard lines, already substituted
 * @returns {string} the helpers plus a capture line for each reader the guards use
 */
function guardPrelude(guards) {
  var prelude = guardHelpers()

  for (var i = 0; i < GUARD_READERS.length; i++) {
    // The guards arrive already substituted, so what marks a reader as wanted
    // is the slot standing in for it, not the call it replaced.
    if (guards.indexOf(guardReaderSlot(i)) < 0) continue
    // `|| :` so a reader that exits nonzero cannot take the batch down with
    // it under a login shell that turned on errexit.
    prelude += "__omarchy_read_" + i + "=$(" + GUARD_READERS[i] + " 2>/dev/null) || :\n"
  }

  return prelude
}

/**
 * Returns the bash variable that holds a reader's captured output.
 * @param {number} index - index into GUARD_READERS
 * @returns {string} the `${__omarchy_read_N}` expansion
 */
function guardReaderSlot(index) {
  return "${__omarchy_read_" + index + "}"
}

/**
 * Replaces each plain `$(reader)` in an expression with that reader's captured variable.
 * @param {string} expression - a `when:` or `checked:` bash expression
 * @returns {string} the substituted expression
 */
function substituteGuardReaders(expression) {
  for (var i = 0; i < GUARD_READERS.length; i++)
    expression = expression.split("$(" + GUARD_READERS[i] + ")").join(guardReaderSlot(i))

  return expression
}

/**
 * Wraps one guard expression in a bash `if` that prints `<id>:<tag>:<0|1>`.
 * @param {string} id - the item id
 * @param {string} tag - "w" for `when:`, "c" for `checked:`
 * @param {string} expression - the bash expression
 * @returns {string} one line of bash
 */
function guardLine(id, tag, expression) {
  return (
    "if { " +
    substituteGuardReaders(expression) +
    "; } >/dev/null 2>&1; then echo " +
    id +
    ":" +
    tag +
    ":1; else echo " +
    id +
    ":" +
    tag +
    ":0; fi\n"
  )
}

// One bash script for every `when:` and `checked:` in the menu, reporting
// `<id>:<w|c>:<0|1>` per line. Speed is the whole point: the menu opens on
// the last evaluation's answers, so however long this takes is how long a row
// can contradict the state it describes.
/**
 * Builds the batch bash script that evaluates every `when:` and `checked:` guard.
 * @param {ItemMap} items - items by id
 * @returns {string} the script, or "" when no item has a guard
 */
function guardScript(items) {
  var guards = ""
  var ids = Object.keys(items || {})

  for (var i = 0; i < ids.length; i++) {
    var entry = items[ids[i]]
    if (!entry) continue
    if (entry.when) guards += guardLine(ids[i], "w", entry.when)
    if (entry.checked) guards += guardLine(ids[i], "c", entry.checked)
  }

  return guards ? guardPrelude(guards) + guards : ""
}

if (typeof module !== "undefined")
  module.exports = {
    guardReaders: GUARD_READERS,
    guardHelpers: guardHelpers,
    guardPrelude: guardPrelude,
    guardReaderSlot: guardReaderSlot,
    substituteGuardReaders: substituteGuardReaders,
    guardLine: guardLine,
    guardScript: guardScript
  }
