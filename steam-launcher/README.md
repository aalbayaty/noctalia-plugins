# Steam Launcher

Browse and launch installed Steam games from the Noctalia launcher.

Type `/steam` in the launcher to list every installed game; type after the prefix
to fuzzy-filter by name. With `include_in_global_search = true`, matching games
also appear in the bare launcher search (≥2 chars). Press Enter on a game to
launch it via `steam steam://rungameid/<appid>`.

## How it works

On the first query, a single `sh` pipeline scans the Steam library:

1. Finds `appmanifest_*.acf` in the configured steamapps directory.
2. Extracts the appid (from the filename) and name (from the `"name"` key) of each.
3. Filters out Steam-internal build environments (names matching `*runtime*`,
   `*proton*`, or `*redistributabl*`, case-insensitive).
4. Resolves cover art: the first `.jpg` in `librarycache/<appid>/` that is **not**
   named `library_*` (those are tall storefront artwork; the hash-named jpgs are
   the 32×32 game tiles).
5. Emits `appid|name|iconPath` lines, parsed into the in-memory game list.

Results are cached for 30 seconds, so repeated queries within a browse session
don't re-scan. The cache is in-memory only (no durable file) — a launcher runs on
demand, so there's no "instant paint on restart" concern.

## Settings

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `steamappsDir` | string | `~/.steam/steam/steamapps` | Steam library folder containing `appmanifest_*.acf`. |
| `librarycacheDir` | string | `~/.steam/steam/appcache/librarycache` | Per-app cover-art cache folder. |

## Icon rendering caveat

Each result row sets **both** `icon` (the absolute jpg path, when cover art was
found) and `glyph` (`device-gamepad-2`, always). The v5 launcher row renderer's
handling of absolute file paths in `LauncherResult.icon` is **unverified** at the
time of this port — the v4 QML plugin used a `getImageUrl` → `file://` path which
has no direct v5 equivalent. If the cover art doesn't render on the shell, the
glyph fallback shows instead. Verify on a live v5 shell after install; if
`icon` is ignored, drop the `row.icon` line in `formatRow` and rely on the glyph
alone.

## Data source

All game data is read from the local Steam install on disk — no network calls,
no API keys. The plugin only lists games that are already installed in the
configured `steamappsDir`.

## License

MIT
