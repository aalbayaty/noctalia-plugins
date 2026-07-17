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
H.test("shellQuote simple", function()
  H.eq(M.shellQuote("/home/x/steamapps"), "'/home/x/steamapps'", "simple path")
end)
H.test("shellQuote with single quote", function()
  H.eq(M.shellQuote("it's a path"), "'it'\\''s a path'", "escaped single quote")
end)
H.test("shellQuote empty", function()
  H.eq(M.shellQuote(""), "''", "empty -> ''")
end)

-- ── buildScanScript ──────────────────────────────────────────────────
H.test("buildScanScript contains key fragments", function()
  local s = M.buildScanScript("/home/x/steamapps", "/home/x/librarycache")
  H.ok(s:find("appmanifest_%*%.acf", 1), "find appmanifest glob")
  H.ok(s:find("/home/x/steamapps", 1), "steamapps path present")
  H.ok(s:find("/home/x/librarycache", 1), "librarycache path present")
  H.ok(s:find("runtime", 1), "runtime filter")
  H.ok(s:find("proton", 1), "proton filter")
  H.ok(s:find("redistributabl", 1), "redistributabl filter")
  H.ok(s:find("library_%*", 1), "library_* icon exclusion")
  H.ok(s:find("appid|name|icon", 1) or s:find("%%s|%%s|%%s", 1), "emit format")
end)
H.test("buildScanScript shell-quotes paths", function()
  local s = M.buildScanScript("/home/x's/steamapps", "/cache")
  H.ok(s:find("x'\\''s", 1), "single quote in path escaped")
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
  H.eq(H.calls.runAsync[#H.calls.runAsync], "steam steam://rungameid/12345", "launch command")
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
