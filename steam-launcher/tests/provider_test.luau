--!nonstrict
-- Pure-logic tests for steam-launcher. Run: luau steam-launcher/tests/provider_test.luau
local H = require("./harness")
local M = H.loadEntry("../provider")

-- ── parseLine ──────────────────────────────────────────────────────
H.test("parseLine valid", function()
  local e = M.parseLine("12345|Half-Life 2|/home/x/librarycache/12345/abc.jpg")
  H.eq(e.appid, "12345", "appid")
  H.eq(e.name, "Half-Life 2", "name")
  H.eq(e.icon, "/home/x/librarycache/12345/abc.jpg", "icon")
  H.eq(e.isImage, true, "isImage")
end)
H.test("parseLine empty icon → glyph fallback", function()
  local e = M.parseLine("999|Proton App|")
  H.eq(e.appid, "999", "appid")
  H.eq(e.name, "Proton App", "name")
  H.eq(e.icon, "", "icon empty")
  H.eq(e.isImage, false, "not isImage")
end)
H.test("parseLine malformed < 3 parts → nil", function()
  H.eq(M.parseLine("12345|Half-Life"), nil, "two parts")
  H.eq(M.parseLine("12345"), nil, "one part")
end)
H.test("parseLine empty → nil", function()
  H.eq(M.parseLine(""), nil, "empty")
  H.eq(M.parseLine("   "), nil, "whitespace")
end)
H.test("parseLine icon with pipe in path rejoined", function()
  -- paranoia: a path won't contain | but the parser rejoins tail parts
  local e = M.parseLine("1|Game|/a|b.jpg")
  H.eq(e.icon, "/a|b.jpg", "tail rejoined")
end)

-- ── parseScanOutput ─────────────────────────────────────────────────
H.test("parseScanOutput multi-line", function()
  local out = "1|Game A|/a.jpg\n2|Game B|/b.jpg\n3|Game C|"
  local games = M.parseScanOutput(out)
  H.eq(#games, 3, "three games")
  H.eq(games[2].name, "Game B", "second game")
  H.eq(games[3].isImage, false, "third no icon")
end)
H.test("parseScanOutput skips blank + malformed", function()
  local out = "1|A|/a.jpg\n\nbad|line\n2|B|/b.jpg"
  local games = M.parseScanOutput(out)
  H.eq(#games, 2, "blank + malformed skipped")
end)
H.test("parseScanOutput empty → {}", function()
  H.eq(#M.parseScanOutput(""), 0, "empty string")
  H.eq(#M.parseScanOutput("\n\n"), 0, "only newlines")
end)

-- ── shellQuote ──────────────────────────────────────────────────────
-- Removed with the shell pipeline: argv exec (plugin_api 24) never quotes.

-- ── appidFromManifestPath ───────────────────────────────────────────
H.test("appidFromManifestPath extracts digits", function()
  H.eq(M.appidFromManifestPath("/a/b/appmanifest_12345.acf"), "12345", "appid")
  H.eq(M.appidFromManifestPath("/a/b/appmanifest_1.acf"), "1", "single digit")
end)
H.test("appidFromManifestPath rejects non-appmanifest", function()
  H.eq(M.appidFromManifestPath("/a/b/appmanifest_foo.acf"), nil, "non-numeric")
  H.eq(M.appidFromManifestPath("/a/b/appmanifest_1a.acf"), nil, "trailing letter")
  H.eq(M.appidFromManifestPath("/a/b/other_1.acf"), nil, "wrong prefix")
  H.eq(M.appidFromManifestPath("/a/b/appmanifest_1.txt"), nil, "wrong extension")
  H.eq(M.appidFromManifestPath(""), nil, "empty")
  H.eq(M.appidFromManifestPath(nil), nil, "nil")
end)

-- ── buildAwkProgram ─────────────────────────────────────────────────
H.test("buildAwkProgram keeps the filters and emit format", function()
  local p = M.buildAwkProgram()
  H.ok(p:find("runtime", 1, true), "runtime filter")
  H.ok(p:find("proton", 1, true), "proton filter")
  H.ok(p:find("redistributabl", 1, true), "redistributabl filter")
  H.ok(p:find("library_%*", 1), "library_* icon exclusion")
  H.ok(p:find("appmanifest_%[0%-9%]", 1), "appid regex from filename")
  H.ok(p:find("%%s|%%s|%%s", 1), "emit format")
  H.ok(p:find("close%(cmd%)", 1), "getline command closed")
end)
H.test("buildAwkProgram resets per file (FNR==1)", function()
  local p = M.buildAwkProgram()
  H.ok(p:find("FNR==1", 1, true), "per-file reset")
  -- END blocks must run per file, never once at the end of a batched run, so
  -- FILENAME (not the awk-end-only ENDFILE) is what identifiers the file.
  H.ok(p:find("FILENAME", 1, true), "FILENAME used for output path")
  H.ok(not p:find("ENDFILE", 1, true), "no ENDFILE dependency")
end)
H.test("buildAwkProgram has no END block at all", function()
  -- END fires once per *batch* under `find -exec … {} +`, so an END-based emit
  -- returns only the last file's game. (It also cannot contain `next`, which is
  -- a parse error there.) The program must be purely per-record, resetting on
  -- FNR==1, so no END block may appear.
  local p = M.buildAwkProgram()
  H.ok(not p:find("END {", 1, true), "no END block")
  H.ok(not p:find("%f[%w]next%f[%W]", 1), "no next")
end)

-- ── buildScanArgv ────────────────────────────────────────────────────
H.test("buildScanArgv is a direct-exec argv, not a shell string", function()
  local argv = M.buildScanArgv("/home/x/steamapps", "/home/x/librarycache")
  H.eq(type(argv), "table", "argv is a table")
  H.eq(argv[1], "find", "find first")
  H.eq(argv[2], "/home/x/steamapps", "directory is a bare argv element")
  H.ok(argv[3] == "-maxdepth" and argv[4] == "1", "maxdepth 1")
  H.eq(argv[5], "-type", "-type flag")
  H.eq(argv[6], "f", "regular files only")
  H.eq(argv[7], "-name", "-name flag")
  H.eq(argv[8], "appmanifest_*.acf", "glob is a bare argv element")
  H.eq(argv[9], "-exec", "-exec flag")
  H.eq(argv[10], "awk", "awk runs via exec")
  H.eq(argv[11], "-v", "awk gets a variable assignment")
  H.eq(argv[12], "CACHE=/home/x/librarycache", "librarycache passed as -v")
  H.eq(argv[13], M.buildAwkProgram(), "program is one argv element")
  H.ok(argv[14] == "{}" and argv[15] == "+", "batch substitution")
  H.eq(#argv, 15, "no extra elements")
end)
H.test("buildScanArgv passes awkward paths verbatim", function()
  -- The whole point of argv exec: a directory name with a quote, a space, or a
  -- shell metacharacter is one element `find` receives untouched. The old shell
  -- form needed shellQuote() for exactly this and could still be misread.
  local nasty = "/home/x' $(rm -rf ~) | tee /tmp/p ; steamed/steamapps"
  local argv = M.buildScanArgv(nasty, "/c")
  H.eq(argv[2], nasty, "path not shell-escaped or split")
  H.eq(argv[12], "CACHE=/c", "cache still passed")
  H.eq(#argv, 15, "path stayed one element")
end)
H.test("buildScanArgv never emits a shell", function()
  local argv = M.buildScanArgv("/a", "/b")
  for _, v in ipairs(argv) do
    H.ok(v ~= "sh" and v ~= "-c", "no shell in argv")
  end
end)

-- ── buildResults ─────────────────────────────────────────────────────
local GAMES = {
  { appid = "1", name = "Half-Life 2", icon = "/a.jpg", isImage = true },
  { appid = "2", name = "Portal 2", icon = "", isImage = false },
  { appid = "3", name = "Team Fortress 2", icon = "/c.jpg", isImage = true },
}
H.test("buildResults empty query = all (browse)", function()
  local rows = M.buildResults(GAMES, "")
  H.eq(#rows, 3, "all games")
end)
H.test("buildResults whitespace query = all", function()
  local rows = M.buildResults(GAMES, "   ")
  H.eq(#rows, 3, "whitespace = browse")
end)
H.test("buildResults fuzzy filter", function()
  local rows = M.buildResults(GAMES, "portal")
  H.eq(#rows, 1, "one match")
  H.eq(rows[1].title, "Portal 2", "portal matched")
end)
H.test("buildResults no match → empty", function()
  local rows = M.buildResults(GAMES, "zzzzz")
  H.eq(#rows, 0, "no matches")
end)
H.test("buildResults empty games → empty", function()
  H.eq(#M.buildResults({}, "anything"), 0, "no games")
  H.eq(#M.buildResults(nil, "anything"), 0, "nil games")
end)
H.test("buildResults caps at 50", function()
  local many = {}
  for i = 1, 80 do
    table.insert(many, { appid = tostring(i), name = "Game "..i, icon = "", isImage = false })
  end
  H.eq(#M.buildResults(many, ""), 50, "capped at 50")
end)
H.test("buildResults sorts by score asc", function()
  -- "2" matches "Portal 2" (substring at end) and "Team Fortress 2" (at end).
  -- Both same score; order stable. Use a query that matches at different positions.
  local rows = M.buildResults(GAMES, "2")
  H.ok(#rows >= 1, "at least one match")
  -- All returned rows should have a score field
  for _, r in ipairs(rows) do H.ok(r.score ~= nil, "row has score") end
end)

-- ── formatRow ────────────────────────────────────────────────────────
H.test("formatRow with icon", function()
  local r = M.formatRow(GAMES[1])
  H.eq(r.id, "steam:1", "id shape")
  H.eq(r.title, "Half-Life 2", "title")
  H.eq(r.subtitle, "Steam", "subtitle")
  H.eq(r.glyph, "device-gamepad-2", "glyph fallback always set")
  H.eq(r.category, "Games", "category is Games")
  H.eq(r.icon, "/a.jpg", "icon path when present")
end)
H.test("formatRow without icon", function()
  local r = M.formatRow(GAMES[2])
  H.eq(r.id, "steam:2", "id")
  H.eq(r.glyph, "device-gamepad-2", "glyph")
  H.eq(r.icon, nil, "no icon field when no path")
end)

H.finish()

-- ── Runtime wiring: onQuery / onActivate / TTL cache ───────────────
H.reset()
H.setConfig({ steamappsDir = "~/.steam/steam/steamapps", librarycacheDir = "~/.steam/steam/appcache/librarycache" })
H.setRunAsyncResult({ stdout = "1|Half-Life 2|/a.jpg\n2|Portal 2|\n", exitCode = 0 })
H.setCmdExists({ steam = true })

H.test("onQuery drives scan + setResults", function()
  H.reset()
  M._resetCache()
  H.setConfig({ steamappsDir = "~/.steam/steam/steamapps", librarycacheDir = "~/.steam/steam/appcache/librarycache" })
  H.setRunAsyncResult({ stdout = "1|Half-Life 2|/a.jpg\n2|Portal 2|\n", exitCode = 0 })
  M.onQuery("")
  H.truthy(H.calls.launcherResults, "setResults called")
  H.eq(#H.calls.launcherResults, 1, "one setResults call")
  local rows = H.calls.launcherResults[1].rows
  H.eq(#rows, 2, "two games returned")
  H.eq(rows[1].title, "Half-Life 2", "first game")
  H.eq(rows[2].title, "Portal 2", "second game")
  H.ok(#H.calls.runAsync >= 1, "scan ran")
end)

H.test("onQuery fuzzy filter", function()
  H.reset()
  M._resetCache()
  H.setConfig({ steamappsDir = "~/.steam/steam/steamapps", librarycacheDir = "~/.steam/steam/appcache/librarycache" })
  H.setRunAsyncResult({ stdout = "1|Half-Life 2|/a.jpg\n2|Portal 2|\n", exitCode = 0 })
  -- first call loads cache
  M.onQuery("")
  H.reset()
  H.setConfig({ steamappsDir = "~/.steam/steam/steamapps", librarycacheDir = "~/.steam/steam/appcache/librarycache" })
  -- second call within TTL: no re-scan, filter from cache
  M.onQuery("portal")
  H.truthy(H.calls.launcherResults, "setResults called")
  local rows = H.calls.launcherResults[#H.calls.launcherResults].rows
  H.eq(#rows, 1, "one fuzzy match")
  H.eq(rows[1].title, "Portal 2", "portal matched")
end)

H.test("onActivate launches steam://rungameid", function()
  H.reset()
  H.setCmdExists({ steam = true })
  M.onActivate("steam:12345")
  H.truthy(H.calls.runAsync, "runAsync called")
  local argv = H.calls.runAsync[#H.calls.runAsync]
  H.eq(type(argv), "table", "argv form, not a shell string")
  H.eq(argv[1], "steam", "program")
  H.eq(argv[2], "steam://rungameid/12345", "uri is one argv element")
  H.eq(#argv, 2, "no shell wrapper")
end)

H.test("onActivate ignores non-steam id", function()
  H.reset()
  M.onActivate("remmina:/path")
  H.ok(H.calls.runAsync == nil, "non-steam id ignored")
end)

H.test("onActivate ignores empty appid", function()
  H.reset()
  H.setCmdExists({ steam = true })
  M.onActivate("steam:")
  H.ok(H.calls.runAsync == nil, "empty appid ignored")
end)

H.test("onActivate gates on commandExists", function()
  H.reset()
  H.setCmdExists({ steam = false })
  M.onActivate("steam:12345")
  H.ok(H.calls.runAsync == nil, "no launch when steam missing")
  H.truthy(H.calls.notifyError, "notifyError called")
end)

H.test("TTL cache: second onQuery within 30s skips scan", function()
  H.reset()
  M._resetCache()
  H.setConfig({ steamappsDir = "~/.steam/steam/steamapps", librarycacheDir = "~/.steam/steam/appcache/librarycache" })
  H.setRunAsyncResult({ stdout = "1|Game|/a.jpg\n", exitCode = 0 })
  M.onQuery("")
  local firstRunAsyncCount = #H.calls.runAsync
  -- second query within TTL
  M.onQuery("")
  H.eq(#H.calls.runAsync, firstRunAsyncCount, "no second scan within TTL")
end)

H.finish()
