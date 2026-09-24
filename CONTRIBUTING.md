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

`pre-commit` refuses a commit made directly on `master` and runs `bash -n` and
ShellCheck over the staged content of any shell script. `pre-push` refuses a
direct push to `master`. Neither is a control. Anyone can pass `--no-verify`,
and a fresh clone will not have them until they are copied there too.
Branch protection enforces the same rule server-side regardless.

## Checks

```bash
for test in tests/*.test.sh; do bash "$test"; done
shellcheck -x scripts/*.sh hooks/* tests/*.test.sh
find integrations -type f -name '*.svg' -print0 | xargs -0 -n1 xmllint --noout
find backgrounds screenshots -type f \( -name '*.png' -o -name '*.jpg' \) -print0 | xargs -0 -n1 identify
```

CI (`.github/workflows/ci.yml`) runs all of the above on every push and pull
request to `master`, plus a syntax pass over every shell script and QML type
validation for the Quickshell plugins.

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

That pull request is opened with the workflow's own token, so GitHub does not
start checks on it automatically. Close it and reopen it once to trigger
`validate` and `conventional-title` before merging; branch protection requires
both to pass like any other pull request.
