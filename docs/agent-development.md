# Agent development guide

This guide is for coding agents and automation that modify the Aranea
repository. It complements [Agent interface](agent-interface.md), which
documents the installed command-line protocol.

## Start with repository state

Before editing, inspect the current branch and worktree. Preserve unrelated
changes, use the current branch unless isolation is explicitly needed, and do
not reset or overwrite user work.

```bash
git status --short --branch
git diff --stat
```

Read [Architecture](architecture.md) and [Development](development.md) before
cross-cutting refactors. They define the source-of-truth and component
ownership boundaries.

## Choose the correct source of truth

| Change requested                     | Edit first                        | Regenerate or verify                         |
| ------------------------------------ | --------------------------------- | -------------------------------------------- |
| Palette, spacing, typography, motion | `design/tokens.toml`              | `scripts/generate-tokens --write`            |
| CSS, shell, or asset projection      | `design/templates/`               | `scripts/generate-tokens --check`            |
| Generated QML JS behavior            | Focused module beside the facade  | `node tools/js-facade-generator.mjs --write` |
| Repeated QML chrome                  | `plugins/araneadev.shared/`       | Register in `qmldir`, add QML checks         |
| Plugin-specific lifecycle            | Owning plugin entry point         | Plugin behavior tests                        |
| Installer or repair behavior         | `scripts/`, `hooks/`, or `tools/` | Shell contract and JSON tests                |

Never hand-edit generated projections or facade regions. If a generated diff
looks wrong, fix the input or generator and regenerate it.

## Extract and deduplicate safely

Use a shared component only when at least two consumers have the same stable
contract. Keep stateful behavior in the owning plugin. A good shared component
has explicit properties, signals for user actions, token-backed defaults, and
no dependency on root-only IDs.

For JavaScript, extract a pure domain with a narrow API, preserve the facade
exports, and add direct tests. Do not move QML lifecycle, IPC, or process
management into a pure module.

For paths, use `plugins/araneadev.shared/RuntimePaths.qml`. Do not reconstruct
`HOME`, `XDG_STATE_HOME`, or current-theme branding paths in individual
plugins.

## Test-driven change loop

1. Identify the contract that should remain stable.
2. Add or update the narrowest test that expresses it.
3. Make the smallest implementation change.
4. Run the focused test and inspect the diff.
5. Run the related suite and the repository gate before claiming completion.

Useful commands:

```bash
tests/run menu shared
tests/qml-types.test.sh
tests/qml-behaviour.test.sh shared
node --test tests/js/menu-guards.test.js
tools/check --only format,lint,docs,validate,qml,qmltest,test
tools/check
```

If a check fails, record the exact command, failure, and whether the failure
reproduces in isolation. Do not weaken a baseline or skip a test to make the
run green. Fix the cause or document a host dependency when the check is
genuinely unavailable.

## Isolated screenshot sessions

`scripts/capture-screenshots` captures the running shell and refuses tray
captures while real tray apps are registered. For a separately staged shell,
run the shell and its capture commands together under
`tools/with-capture-session <command> [args...]`. The helper creates a private
D-Bus bus, runtime directory and document data directory, shares only the
Wayland display socket, and removes the temporary runtime on exit. The caller
is responsible for staging shell configuration. Private capture processes
run in their own process group and are stopped before runtime cleanup.

Never run `dbus-run-session` against the live `XDG_RUNTIME_DIR`. A second
document portal unmounts an existing document filesystem at that path; the
accessibility bus also uses runtime sockets. Do not expose the live `doc`,
`at-spi`, `bus` or `systemd` paths inside the capture runtime. This helper is
session separation for captures, not a security sandbox. It does not stop or
restart the user's shell or change workspaces.

## Documentation and review handoff

Update the closest documentation when behavior, ownership, or a workflow
changes. Add architecture-level changes to `docs/architecture.md`; add
automation workflow changes here or to `docs/agent-interface.md` as
appropriate.

Before handoff, verify:

```bash
git diff --check
git status --short --branch
tools/check
```

Report what changed, what passed, what remains unavailable, and whether the
worktree contains uncommitted changes. Do not claim completion from a focused
test when the canonical gate is still failing.
