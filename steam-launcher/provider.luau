--!nonstrict
-- Steam Launcher — Noctalia v5 launcher provider.
-- Ported from the v4 QML plugin (git tag v1.0, noctalia-plugins/steam-launcher/).
-- Browses installed Steam games (scans ~/.steam/steam/steamapps/appmanifest_*.acf,
-- filters runtimes/Proton/redistributables, resolves cover art from librarycache)
-- and launches them via `steam steam://rungameid/<appid>`.
--
-- Single launcher_provider entry: onQuery triggers a scan (cached 30s),
-- fuzzy-filters the results, and publishes them via launcher.setResults.
-- onActivate extracts the appid and runs `steam steam://rungameid/<appid>`
-- detached. No service/widget/panel — a launcher runs on demand.
--
-- The scan used to be one `sh -c` pipeline that shell-quoted both directory
-- settings. It is now a `find -exec` argv exec (plugin_api 24): the shell never
-- sees the paths, so a directory name containing a quote or space cannot alter
-- the command. The awk program arrives as a single argv element, so it needs no
-- shell escaping either — only the in-awk string literals below.
local M = {}

local RESULT_LIMIT = 50
local REFRESH_TTL_MS = 30000 -- 30s, matching v4's refreshTtl

-- ── Pure logic (testable via __STEAM_TEST export) ──────────────────

-- Parse one `appid|name|iconPath` line → {appid, name, icon, isImage} or nil.
-- Tail parts (icon path) are rejoined with | in the unlikely case a path
-- contains a pipe — paranoia from v4, librarycache paths don't.
function M.parseLine(line)
  if line == nil or line:match("^%s*$") then return nil end
  local parts = {}
  for p in (line .. "|"):gmatch("([^|]*)|") do table.insert(parts, p) end
  if #parts < 3 then return nil end
  local appid, name = parts[1], parts[2]
  local icon = table.concat({ table.unpack(parts, 3) }, "|")
  if appid == "" or name == "" then return nil end
  return { appid = appid, name = name, icon = icon, isImage = icon ~= "" }
end

-- Parse the full scan stdout → array of {appid, name, icon, isImage}.
function M.parseScanOutput(stdout)
  local games = {}
  for line in tostring(stdout or ""):gmatch("[^\r\n]+") do
    local e = M.parseLine(line)
    if e then table.insert(games, e) end
  end
  return games
end

-- Extract the Steam appid from an appmanifest filename. Non-matching names
-- (appmanifest_foo.acf, appmanifest_1a.acf) return nil so the caller can skip
-- the entry rather than emit a bogus appid.
function M.appidFromManifestPath(path)
  return tostring(path or ""):match("appmanifest_(%d+)%.acf$")
end

-- The awk program run against every appmanifest, emitting `appid|name|iconPath`
-- per game. Runs via `find … -exec awk '<program>' {} +`, i.e. once per batch of
-- arguments. Ported from v4 Main.qml refresh(), preserving its filters and icon
-- rule:
--   1. appid from the filename
--   2. name from the `name` key
--   3. skip *runtime*|*proton*|*redistributabl* (case-insensitive)
--   4. first non-library_*.jpg under librarycache/<appid>/
--   5. emit appid|name|iconPath
--
-- Every rule is per-record and state resets on FNR==1, deliberately: with `{} +`
-- batching one awk process reads the whole batch, so END fires *once for the
-- batch* and would emit only the last file's game. (The earlier `-exec … {} \;`
-- form fired END per file, which is why the END-based port worked before.) FNR==1
-- resets per file; the emit therefore lives in the name rule, guarded by
-- `emitted` so a second name= line cannot produce a duplicate row.
--
-- Two awk constructs are traps here, each of which silently kills the whole
-- scan: `next` is a parse error inside an END action, and a POSIX class written
-- as `[[:space:]]+` inside sub()'s replacement-adjacent regex is fine but the
-- self-closing `[[:space:]]+` + `"` sequence is what the match rule must use
-- verbatim. Keep the regexes below as they are and re-run the e2e test.
function M.buildAwkProgram()
  return table.concat({
    "FNR==1 {",
      'id=""; name=""; haveid=0; emitted=0;',
      "if (split(FILENAME, parts, \"/\") > 0) {",
        "base=parts[length(parts)];",
        "if (match(base, /^appmanifest_[0-9]+\\.acf$/)) {",
          -- "appmanifest_" is 12 chars, so the digits start at 13. The prefix is
          -- fixed-length; the trailing ".acf" (4) is dropped from the length.
          "id=substr(base, 13, length(base) - 16); haveid=1;",
        "}",
      "}",
    "}",
    'haveid && !emitted && /^[[:space:]]*"name"[[:space:]]+"/ {',
      "n=$0;",
      'sub(/^[[:space:]]*"name"[[:space:]]+"/, "", n);',
      'sub(/"[[:space:]]*$/, "", n);',
      "lower=tolower(n);",
      "if (!(lower ~ /runtime/ || lower ~ /proton/ || lower ~ /redistributabl/)) {",
        'icon="";',
        'cmd="find \\"" CACHE "/" id "/\\" -maxdepth 1 -type f -name \\"*.jpg\\" ! -name \\"library_*\\" 2>/dev/null | head -1";',
        "cmd | getline icon;",
        "close(cmd);",
        'printf "%s|%s|%s\\n", id, n, icon;',
      "}",
      "emitted=1;",
    "}",
  }, " ")
end

-- Build the scan argv. Direct exec (plugin_api 24) — no shell, so neither path
-- is quoted or parsed; `find` receives them verbatim as argv elements, and the
-- awk program reads the librarycache root from `-v CACHE=…` rather than a shell
-- variable (the old `sh -c` form exported it). Without -v, CACHE expands to the
-- empty string and every icon lookup silently finds nothing.
function M.buildScanArgv(steamappsDir, librarycacheDir)
  return {
    "find", steamappsDir,
    "-maxdepth", "1",
    "-type", "f",
    "-name", "appmanifest_*.acf",
    "-exec", "awk", "-v", "CACHE=" .. librarycacheDir,
    M.buildAwkProgram(), "{}", "+",
  }
end

-- Format one game as a LauncherResult row.
-- id = "steam:<appid>" (onActivate extracts the appid from this).
-- icon is set to the absolute jpg path when available; glyph is always set
-- as a fallback (the shell uses whichever it supports — see README caveat).
function M.formatRow(game)
  local row = {
    id = "steam:" .. game.appid,
    title = game.name,
    subtitle = "Steam",
    glyph = "device-gamepad-2",
    category = "Games",
    score = nil,
  }
  if game.isImage and game.icon ~= "" then
    row.icon = game.icon
  end
  return row
end

-- Filter + fuzzy-sort games by query. Returns LauncherResult-shaped rows.
-- Empty/whitespace query = browse mode (all games, capped at RESULT_LIMIT).
-- Otherwise fuzzy-match on name via noctalia.fuzzyScore (nil = no match),
-- sort by score ascending (lower = better), cap at RESULT_LIMIT.
function M.buildResults(games, query)
  games = games or {}
  local q = noctalia.string.trim(query or "")
  local rows = {}
  if q == "" then
    for i = 1, math.min(#games, RESULT_LIMIT) do
      table.insert(rows, M.formatRow(games[i]))
    end
    return rows
  end
  local scored = {}
  for _, g in ipairs(games) do
    local score = noctalia.fuzzyScore(q, g.name)
    if score ~= nil then table.insert(scored, { game = g, score = score }) end
  end
  table.sort(scored, function(a, b) return a.score < b.score end)
  for i = 1, math.min(#scored, RESULT_LIMIT) do
    local r = M.formatRow(scored[i].game)
    r.score = scored[i].score
    table.insert(rows, r)
  end
  return rows
end

-- ── Runtime wiring (uses injected globals) ────────────────────────
-- Defined on M BEFORE the __STEAM_TEST guard so tests can drive them via
-- H.env.onQuery / H.env.onActivate (the guard returns M with these attached).
-- In production the guard is skipped and the same functions are also bound
-- as globals below for the host to call.

local function readCfg()
  return {
    steamappsDir = noctalia.getConfig("steamappsDir") or "~/.steam/steam/steamapps",
    librarycacheDir = noctalia.getConfig("librarycacheDir") or "~/.steam/steam/appcache/librarycache",
  }
end

-- In-memory cache with 30s TTL. A launcher provider stays loaded across
-- queries (the kaomoji plugin relies on the same pattern), so this
-- avoids re-scanning on every keystroke within a browse session.
local cache = { games = nil, loadedAt = 0, loading = false }

-- Test helper: clear the in-memory cache between tests.
function M._resetCache() cache = { games = nil, loadedAt = 0, loading = false } end

local function nowMs() return os.time() * 1000 end

function M._refresh(cfg, onDone)
  if cache.loading then
    onDone(cache.games)
    return
  end
  if cache.games and (nowMs() - cache.loadedAt) < REFRESH_TTL_MS then
    onDone(cache.games)
    return
  end
  cache.loading = true
  -- The awk program reads the librarycache root from its environment; passing it
  -- here keeps it out of the argv the shell would otherwise have to quote.
  local argv = M.buildScanArgv(
    noctalia.expandPath(cfg.steamappsDir),
    noctalia.expandPath(cfg.librarycacheDir)
  )
  noctalia.runAsync(argv, function(res)
    cache.games = M.parseScanOutput(res and res.stdout or "")
    cache.loadedAt = nowMs()
    cache.loading = false
    onDone(cache.games)
  end)
end

function M.onQuery(query)
  local cfg = readCfg()
  M._refresh(cfg, function(games)
    launcher.setResults(query, M.buildResults(games, query))
  end)
end

function M.onActivate(id)
  if not id or id:sub(1, 6) ~= "steam:" then return end
  local appid = id:sub(7)
  if appid == "" then return end
  if not noctalia.commandExists("steam") then
    noctalia.notifyError("Steam Launcher", "steam command not found")
    return
  end
  noctalia.runAsync({ "steam", "steam://rungameid/" .. appid })
end

if _G.__STEAM_TEST or noctalia == nil then return M end

-- Production: expose the same functions as globals for the host to call.
onQuery = M.onQuery
onActivate = M.onActivate
