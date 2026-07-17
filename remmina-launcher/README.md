# Remmina Launcher

Browse and launch Remmina remote-desktop connections from the Noctalia launcher.

Type `/remmina` in the launcher to list every connection; type after the prefix
to fuzzy-filter by name. With `include_in_global_search = true`, matching
connections also appear in the bare launcher search (≥2 chars). Press Enter on a
connection to launch it via `remmina -c <file>`.

## How it works

On the first query, a single `find … | awk` pipeline scans the Remmina config
directory:

1. Finds `*.remmina` files (NUL-separated, so paths with spaces work).
2. For each file, `awk` extracts the first `name=` and `protocol=` lines
   (stripping trailing `\r` for CRLF files edited on Windows).
3. Emits `name|protocol|filepath` lines, parsed into the in-memory list.

Results are cached for 30 seconds, so repeated queries within a browse session
don't re-scan. The cache is in-memory only — a launcher runs on demand.

Each result's subtitle shows the protocol uppercased (RDP / VNC / SSH / SPICE / …)
to disambiguate identical connection names across protocols; connections with no
protocol fall back to a "Remmina" subtitle.

## Settings

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `remminaDir` | string | `~/.local/share/remmina` | Folder containing Remmina `*.remmina` connection files. |

## Data source

All connection data is read from the local Remmina config directory on disk —
no network calls. The plugin only lists connections that already exist as
`.remmina` files.

## License

MIT
