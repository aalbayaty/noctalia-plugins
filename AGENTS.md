# AGENTS.md

Guidance for AI agents working in this repo. Read before editing.

## What this is

Multi-plugin monorepo for Noctalia **v5** desktop-shell plugins (Luau). Each plugin is one
top-level directory (`mawaqit/` is the only one so far). Shared root files — `noctalia.d.luau`,
`.luaurc`, `.vscode/`, `.github/` — serve every plugin. See `README.md` for the overview and
`docs/superpowers/specs/2026-07-16-mawaqit-v5-port-design.md` for the full plugin architecture.

## Commands

All commands run from the **repo root**.

| Task | Command |
| --- | --- |
| Run one test file | `luau mawaqit/tests/logic_test.luau` |
| Validate manifests (CI gate) | `python3 .github/workflows/validate-plugins.py` |
| Regenerate `catalog.toml` | `python3 .github/workflows/update-catalog.py` |
| Check translation parity | `python3 mawaqit/tests/i18n_parity.py` |
| Typecheck/lint one file | `luau-analyze mawaqit/service.luau` |

There is no test runner — each `*_test.luau` is a standalone script that prints `PASS:`/`FAIL:`
and exits non-zero on failure. Run each file individually (`luau` takes one file).

**`luau-analyze` caveat:** it reports `TypeError: Unknown global 'noctalia'` (and `ui`,
`barWidget`, `panel`, `shortcut`, `launcher`, `desktopWidget`) for every entry file. These
globals are host-injected at runtime and expected — filter them out. Any **other** diagnostic
is a real failure.

**`i18n_parity.py` caveat:** uses a CWD-relative path (`mawaqit/translations`); must run from
the repo root, not from inside `mawaqit/`.

## Architecture

- **No `require` at runtime.** The Noctalia shell loads each entry (`service.luau`,
  `widget.luau`, `panel.luau`) into an isolated sandbox without `require`. Entries cannot
  share Lua memory.
- **`service.luau` owns all logic** — fetch, parse, countdown, Hijri calendar, events,
  notifications. `widget.luau` and `panel.luau` are thin renderers that read pre-computed,
  display-ready values from `noctalia.state` and send commands back. Do not duplicate logic
  across entries.
- **Entries communicate via `noctalia.state`** (`set`/`get`/`watch`) — in-memory, lost on
  restart. Durable storage uses files (`pluginDataDir()` + `writeFile`/`readFile`).
- **`noctalia.d.luau` is editor-only.** It declares host-injected globals for luau-lsp
  autocomplete/diagnostics. Type annotations are a runtime no-op.

## Testing without a shell

Tests run under the local `luau` CLI, not the Noctalia shell. Two techniques make off-shell
testing work:

1. **Test export guard.** Each entry ends with
   `if _G.__MAWAQIT_TEST then return { …internals… } end`. In production the flag is nil (guard
   skipped, no return). In tests the harness sets the flag, `require` returns the internal
   function table, and assertions run against pure functions with no network/time dependence.
2. **Mock-global harness** (`tests/harness.luau`). Installs stub `noctalia`, `ui`,
   `barWidget`, `panel` globals that record calls and return `{type, props, children}` nodes
   from `ui.*`. `H.loadEntry("../service")` requires the entry, finds its env via `getfenv`
   on an exported function, and injects the mocks.

## Plugin manifest rules (`plugin.toml`)

Enforced by `validate-plugins.py` (the CI gate):

- `id` must equal `<author>/<dirname>` (e.g. `aalbayaty/mawaqit`).
- `version` and `min_noctalia` must be semver (`MAJOR.MINOR.PATCH`).
- `description` max 120 characters.
- Every `label_key` and `description_key` must exist as a key in `translations/en.json`.
- `select` settings require `options` with unique `value` strings; `default` must match one.
- `int` settings: `min` ≤ `default` ≤ `max`; `step` > 0.
- `visible_when` = `{ key, values }` — `values` is a non-empty list of strings.
- Entry `entry` paths must stay inside the plugin directory (no `..` or absolute paths).
- Entry types: `widget`, `panel`, `shortcut`, `desktop_widget`, `launcher_provider`,
  `service`. At least one required.

## Conventions

- `--!nonstrict` at the top of every `.luau` file.
- `catalog.toml` is auto-generated — never hand-edit, don't commit it (CI regenerates on push
  to `main` in the official repo; run `update-catalog.py` locally in forks).
- **Bump `version` in `plugin.toml` for every plugin change you want Noctalia to notice.**
  The shell uses the version to detect updates, so after editing code, settings, or assets,
  increment the semver patch (or appropriate level), regenerate `catalog.toml`, and commit both.
- Don't edit non-English translation files (`fr.json`, `tr.json`, `ar.json`) unless the PR is
  explicitly for translation work. Add new strings to `en.json` only; run `i18n_parity.py` to
  verify other locales catch up.
- Settings UI is 100% auto-generated from `plugin.toml` `[[setting]]` — no settings code, no
  `setConfig` (plugins read via `noctalia.getConfig`, can't write settings).
- Commit messages use conventional commits with plugin scope: `feat(mawaqit):`,
  `fix(mawaqit):`, `test(mawaqit):`, `i18n(mawaqit):`, `assets(mawaqit):`, `chore:`.
- Default branch is `main`; no develop/staging branches.
