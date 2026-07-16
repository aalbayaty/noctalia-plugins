# noctalia-plugins

Personal Noctalia **v5** plugins (Luau). Each plugin is a top-level directory;
shared root files (`noctalia.d.luau`, `.luaurc`, `.vscode/`, `.github/`) give
editor support and CI for all of them.

## Plugins

| Plugin | Description |
| --- | --- |
| [`mawaqit/`](./mawaqit) | Muslim prayer times: live countdown, notifications, Hijri calendar with Islamic events. |

## How to add a plugin

1. Create a top-level `<plugin>/` directory.
2. Add `plugin.toml` with `id = "<author>/<plugin>"` (must equal author + dir name),
   `min_noctalia`, `tags`, `dependencies`, and at least one entry.
3. Add the entry `.luau` files, `translations/en.json` (every `label_key`/
   `description_key` in the manifest must exist here), and optional assets/thumbnail.
4. `python3 .github/workflows/validate-plugins.py` must pass.
5. `python3 .github/workflows/update-catalog.py` to refresh `catalog.toml` (or let CI do it).
6. Commit and push.

## Editor setup

Install [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp); the shipped
`.vscode/settings.json` points it at `noctalia.d.luau` for autocomplete + diagnostics.

## License

MIT
