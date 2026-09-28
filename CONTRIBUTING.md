# Contributing

## Getting set up

```bash
git clone https://github.com/AraneaDev/aranea-desktop.git
cd aranea-desktop
cp .githooks/pre-commit .githooks/pre-push .githooks/commit-msg .git/hooks/
```

Copy the hooks. Do not point `core.hooksPath` at `.githooks/`: a tracked hook
only exists in the working tree while a branch containing it is checked out,
so it would be missing on exactly the branches that predate it.

Install the JS tooling and the pinned binaries once:

```bash
npm ci
tools/install-shellcheck ~/.local/bin
tools/install-shfmt ~/.local/bin
tools/install-actionlint ~/.local/bin
```

`pre-commit` refuses a commit made directly on `master` and runs
`tools/check --staged --fast` over the staged content. `pre-push` refuses a
direct push to `master` and runs `tools/check --fast`. Neither is a control. Anyone can pass `--no-verify`,
and a fresh clone will not have them until they are copied there too.
Branch protection enforces the same rule server-side regardless.

## Checks

```bash
tools/check            # everything: format lint docs validate qml qmltest test smoke
tools/check --fix      # rewrite formatting (shfmt, prettier, qmlformat)
tools/check --fast     # skip the runtime smoke test and the slow bash tests
tools/check --only qml # one stage (or a comma-separated list); --skip works too
```

The stages:

- **format**: shfmt for shell, Prettier for JS/JSON/Markdown/YAML, qmlformat
  for QML (`.qmlformat.ini`). `tools/check --fix` writes the fixes.
- **lint**: ShellCheck (pinned 0.11.0), ESLint (`eslint.config.js`),
  markdownlint (`.markdownlint-cli2.jsonc`) and actionlint.
- **docs**: every piece of code is documented inline (see below), checked by
  ESLint's jsdoc rules, TypeScript (`tsconfig.json`, `checkJs`) and
  `tools/check-docs`.
- **validate**: every JSON, TOML, SVG, image and Lua file parses, relative
  Markdown links resolve, and no new em dashes (house style).
- **qml**: qmllint on every QML file. With Omarchy's shell and Quickshell
  installed it is strict and compared with `tools/baselines/qmllint.txt`;
  otherwise only syntax errors fail.
- **qmltest**: the behaviour tests in `tests/qml/`, run by
  `tests/qml-behaviour.test.sh` in an offscreen Quickshell (no Wayland, no
  windows). Plugins keep their state and logic in a non-visual entry file and
  load their window from a separate file, so these tests drive the real QML.
  Skipped without `quickshell` and Omarchy's shell.
- **test**: `tests/run` (every bash contract test, each in a sandbox that
  cannot touch your session) and the `node:test` suites in `tests/js/`,
  with per-module function coverage floors in `tools/baselines/coverage.txt`.
- **smoke**: loads every plugin at runtime in Quickshell inside an invisible
  headless sway, and fails on runtime errors. Needs `quickshell` and `sway`.

The baselines only improve: a new qmllint warning, a lower coverage number or
a new smoke error fails, and so does a baseline entry that no longer applies.
`tools/check --update-baselines` shrinks the qmllint and smoke lists and
raises coverage floors, but never loosens them; adding an entry is a manual
edit that shows up in review. Formatting-only commits are listed in
`.git-blame-ignore-revs` (`git config blame.ignoreRevsFile .git-blame-ignore-revs`);
merging rewrites commit hashes, so after merging a formatting commit, update
the list with the hashes it got on `master`.

### Inline documentation

Everything is documented where it lives, and the docs stage fails otherwise:

- **JS** (`plugins/**/*.js`): every top-level function has a JSDoc block with a
  description, `@param {Type} name - what` and `@returns {Type} what`.
  TypeScript checks those types against the code (without null checks,
  and not for `*` or the two `.pragma library` bridges), so wrong types are
  caught.
  Shared object shapes get a `@typedef`; `{}` locals that are used as maps
  get an inline `/** @type {{[key: string]: T}} */`.
- **Shell**: a header comment after the shebang saying what the file does
  (with a `Usage:` line for scripts you run under `scripts/` and `tools/`),
  and a `#` comment directly above every function.
- **QML**: a `//` header before the imports saying what the component is and
  where it is used, and a `//` comment directly above every root-level
  property, signal and function. Members whose name starts with `_` are
  private and exempt.

Comments say what the code does. `tools/check-docs FILE...` checks shell and
QML files on their own.

`tests/run` on its own runs every `tests/*.test.sh` (including the JS suites
through `tests/js.test.sh`); pass bare names to run a subset
(`tests/run ownership manifest`), and `-v` to see passing output.

CI (`.github/workflows/ci.yml`) runs `tools/check` on Ubuntu without the
Qt-dependent parts, and QML formatting, strict QML and the smoke test in an
Arch container with Quickshell, sway and Omarchy's shell at the tag in
`.omarchy-version`. A release is only tagged after
`tools/check` passed on the merged commit.

## Working on it

Work on a topic branch and open a pull request. `master` requires the checks
above to pass, a linear history (squash or rebase merges only, no merge
commits), and every review conversation resolved.

## Screenshots and the hero GIF

`screenshots/` and `screenshots/hero-showcase.gif` are real captures, not
mock-ups, produced by `scripts/capture-screenshots` against a live Aranea
session (see the "Artwork" section of the README for the exact invocation).
`tests/screenshot-coverage.test.sh` enforces that every surface
the capture script knows about has a checked-in screenshot, is referenced in
the README, and that the hero GIF's frame order and count match.
`tests/capture-batch.test.sh` runs the `--all` batch with every capture
replaced (`ARANEA_CAPTURE_SURFACE_COMMAND`): a failed surface keeps its old
PNG and fails the batch, and the notification inbox always comes back.

## Commit messages

Conventional commits, because `release-please` builds `CHANGELOG.md` and the
next version number in `theme-manifest.toml` from them.

```text
feat: add the icons integration
fix: stop the folder icon from clashing with the theme
docs: document the icons integration in the README
test: cover the icons integration's dry-run output
```

`feat` and `fix` appear in the changelog and move the version. `chore`,
`style`, `docs`, `test`, and `ci` are hidden from it. A `!` after the type, or
a `BREAKING CHANGE:` trailer, marks a break.

No em dashes, in code, comments, output strings or commit messages. A comma
or two short sentences instead.

Both rules are checked rather than trusted. `tools/check-commit-style.sh`
holds the one definition; the `commit-msg` hook runs it on what you type, and
CI (`.github/workflows/pr-title.yml`) runs it on every commit in a pull
request.

It also runs on the **pull request title**, which is the one that matters
most: this repository squash merges, so the title is the subject that reaches
`master` and the one `release-please` actually reads.

## Releases

Merging a conventional commit to `master` makes `release-please` open or
update a "release please" pull request with the next version and a
`CHANGELOG.md` entry. Merging that pull request tags the release and bumps
`version` in `theme-manifest.toml` to match.

That pull request is opened using the `RELEASE_PLEASE_TOKEN` secret (see
`.github/workflows/release-please.yml`), a personal access token that raises
the event as a real account, so GitHub starts `validate` and
`conventional-title` on it automatically, same as any other pull request.

Without that secret configured, the pull request is opened with the
workflow's own built-in token instead, and GitHub does not start checks for
events raised by that token. Close the pull request and reopen it once to
trigger `validate` and `conventional-title` before merging; branch
protection requires both to pass either way.
