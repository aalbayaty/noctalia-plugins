--!nonstrict
-- Pure-logic tests for remmina-launcher. Run: luau remmina-launcher/tests/provider_test.luau
local H = require("./harness")
local M = H.loadEntry("../provider")

-- ── parseRemminaFile ────────────────────────────────────────────────
H.test("parseRemminaFile extracts name + protocol", function()
  local contents = "[remmina]\nname=My Server\nprotocol=RDP\nserver=1.2.3.4\n"
  local e = M.parseRemminaFile(contents)
  H.eq(e.name, "My Server", "name")
  H.eq(e.protocol, "RDP", "protocol")
end)
H.test("parseRemminaFile strips trailing CR (CRLF)", function()
  local contents = "[remmina]\r\nname=MyHost\r\nprotocol=VNC\r\n"
  local e = M.parseRemminaFile(contents)
  H.eq(e.name, "MyHost", "name no CR")
  H.eq(e.protocol, "VNC", "protocol no CR")
end)
H.test("parseRemminaFile missing name → nil", function()
  local e = M.parseRemminaFile("[remmina]\nprotocol=RDP\n")
  H.eq(e, nil, "no name = nil")
end)
H.test("parseRemminaFile missing protocol → empty string", function()
  local e = M.parseRemminaFile("[remmina]\nname=Host\n")
  H.eq(e.name, "Host", "name")
  H.eq(e.protocol, "", "protocol empty")
end)
H.test("parseRemminaFile only matches leading key=", function()
  -- other keys may contain '=' in values; match only leading name=/protocol=
  local e = M.parseRemminaFile("name=Real\nother=name=fake\nprotocol=SSH\n")
  H.eq(e.name, "Real", "name not confused by other=name=fake")
  H.eq(e.protocol, "SSH", "protocol")
end)
H.test("parseRemminaFile empty/nil → nil", function()
  H.eq(M.parseRemminaFile(""), nil, "empty")
  H.eq(M.parseRemminaFile(nil), nil, "nil")
end)

-- ── parseLine ──────────────────────────────────────────────────────
H.test("parseLine valid", function()
  local e = M.parseLine("My Server|RDP|/home/x/.remmina/server.remmina")
  H.eq(e.name, "My Server", "name")
  H.eq(e.protocol, "RDP", "protocol")
  H.eq(e.file, "/home/x/.remmina/server.remmina", "file")
end)
H.test("parseLine empty protocol", function()
  local e = M.parseLine("Host||/path/to/host.remmina")
  H.eq(e.name, "Host", "name")
  H.eq(e.protocol, "", "protocol empty")
  H.eq(e.file, "/path/to/host.remmina", "file")
end)
H.test("parseLine malformed < 3 parts → nil", function()
  H.eq(M.parseLine("Name|RDP"), nil, "two parts")
  H.eq(M.parseLine("Name"), nil, "one part")
end)
H.test("parseLine empty → nil", function()
  H.eq(M.parseLine(""), nil, "empty")
  H.eq(M.parseLine("   "), nil, "whitespace")
end)
H.test("parseLine empty name → nil", function()
  H.eq(M.parseLine("|RDP|/path"), nil, "empty name rejected")
end)

-- ── parseScanOutput ─────────────────────────────────────────────────
H.test("parseScanOutput multi-line", function()
  local out = "Server A|RDP|/a.remmina\nServer B|VNC|/b.remmina\n"
  local conns = M.parseScanOutput(out)
  H.eq(#conns, 2, "two connections")
  H.eq(conns[1].name, "Server A", "first")
  H.eq(conns[2].protocol, "VNC", "second protocol")
end)
H.test("parseScanOutput skips blank + malformed", function()
  local out = "A|RDP|/a.remmina\n\nbad|line\nB|SSH|/b.remmina"
  local conns = M.parseScanOutput(out)
  H.eq(#conns, 2, "blank + malformed skipped")
end)
H.test("parseScanOutput empty → {}", function()
  H.eq(#M.parseScanOutput(""), 0, "empty string")
  H.eq(#M.parseScanOutput("\n\n"), 0, "only newlines")
end)

-- ── shellQuote ──────────────────────────────────────────────────────
-- Removed with the shell pipeline: argv exec (plugin_api 24) never quotes.

-- ── buildAwkProgram ─────────────────────────────────────────────────
H.test("buildAwkProgram contains key fragments", function()
  local p = M.buildAwkProgram()
  H.ok(p:find("name=", 1, true), "extracts name=")
  H.ok(p:find("protocol=", 1, true), "extracts protocol=")
  H.ok(p:find("%%s|%%s|%%s", 1), "emit format")
  H.ok(p:find("FILENAME", 1, true), "FILENAME used for output path")
end)
H.test("buildAwkProgram resets per file (FNR==1)", function()
  local p = M.buildAwkProgram()
  -- 'find -exec … {} +' batches files into one awk process, so END runs once for
  -- the batch. FNR==1 resets per file; without it a file lacking name= would
  -- inherit the previous file's name and be emitted twice.
  H.ok(p:find("FNR==1", 1, true), "per-file reset")
  H.ok(not p:find("ENDFILE", 1, true), "no ENDFILE dependency")
  -- END fires once per batch under {}+, so an END-based emit returns only the
  -- last file's connection.
  H.ok(not p:find("END {", 1, true), "no END block")
end)
H.test("buildAwkProgram never uses next inside END", function()
  -- `next` is a parse error in an END action: awk rejects the entire program and
  -- the scan silently returns nothing.
  local p = M.buildAwkProgram()
  H.ok(not p:find("%f[%w]next%f[%W]", 1), "no next")
end)
H.test("buildAwkProgram does not sub() over $0", function()
  -- sub() on a field rewrites $0, and awk re-evaluates the *changed* record
  -- against later rules — a trailing emit rule then fires on the name rule's own
  -- output, before protocol= is read.
  local p = M.buildAwkProgram()
  H.ok(not p:find("sub%([^,]-%%,%s*\"\"%);%s*name%s*=%s*%$0", 1), "name not built via $0 sub")
  H.ok(p:find('n=%$0;', 1) or p:find("n=$0;", 1, true), "name goes through a temp var")
end)
H.test("buildAwkProgram strips CRLF", function()
  local p = M.buildAwkProgram()
  H.ok(p:find("gsub%(/\\\\r$/", 1) or p:find("\\r$", 1, true), "CR stripped")
end)
H.test("buildAwkProgram skips files with no name", function()
  local p = M.buildAwkProgram()
  H.ok(p:find('name != ""', 1, true), "nameless files do not emit")
end)

-- ── buildScanArgv ────────────────────────────────────────────────────
H.test("buildScanArgv is a direct-exec argv, not a shell string", function()
  local argv = M.buildScanArgv("/home/x/.remmina")
  H.eq(type(argv), "table", "argv is a table")
  H.eq(argv[1], "find", "find first")
  H.eq(argv[2], "/home/x/.remmina", "directory is a bare argv element")
  H.ok(argv[3] == "-maxdepth" and argv[4] == "1", "maxdepth 1")
  H.eq(argv[5], "-type", "-type flag")
  H.eq(argv[6], "f", "regular files only")
  H.eq(argv[7], "-name", "-name flag")
  H.eq(argv[8], "*.remmina", "glob is a bare argv element")
  H.eq(argv[9], "-exec", "-exec flag")
  H.eq(argv[10], "awk", "awk runs via exec")
  H.eq(argv[11], M.buildAwkProgram(), "program is one argv element")
  H.ok(argv[12] == "{}" and argv[13] == "+", "batch substitution")
  H.eq(#argv, 13, "no extra elements")
end)
H.test("buildScanArgv passes awkward paths verbatim", function()
  -- The whole point of argv exec: a directory name with a quote, a space, or a
  -- shell metacharacter is one element `find` receives untouched. The old shell
  -- form needed shellQuote() for exactly this and could still be misread.
  local nasty = "/home/x' $(rm -rf ~) | tee /tmp/p ; .remmina-archive"
  local argv = M.buildScanArgv(nasty)
  H.eq(argv[2], nasty, "path not shell-escaped or split")
  H.eq(#argv, 13, "path stayed one element")
end)
H.test("buildScanArgv never emits a shell", function()
  local argv = M.buildScanArgv("/a")
  for _, v in ipairs(argv) do
    H.ok(v ~= "sh" and v ~= "-c", "no shell in argv")
  end
end)

-- ── buildResults ─────────────────────────────────────────────────────
local CONNS = {
  { name = "Production Server", protocol = "RDP", file = "/a.remmina" },
  { name = "Dev Box", protocol = "SSH", file = "/b.remmina" },
  { name = "Test VNC", protocol = "VNC", file = "/c.remmina" },
}
H.test("buildResults empty query = all (browse)", function()
  local rows = M.buildResults(CONNS, "")
  H.eq(#rows, 3, "all connections")
end)
H.test("buildResults whitespace query = all", function()
  local rows = M.buildResults(CONNS, "   ")
  H.eq(#rows, 3, "whitespace = browse")
end)
H.test("buildResults fuzzy filter", function()
  local rows = M.buildResults(CONNS, "dev")
  H.eq(#rows, 1, "one match")
  H.eq(rows[1].title, "Dev Box", "dev matched")
end)
H.test("buildResults no match → empty", function()
  H.eq(#M.buildResults(CONNS, "zzzzz"), 0, "no matches")
end)
H.test("buildResults empty connections → empty", function()
  H.eq(#M.buildResults({}, "anything"), 0, "no connections")
  H.eq(#M.buildResults(nil, "anything"), 0, "nil connections")
end)
H.test("buildResults caps at 50", function()
  local many = {}
  for i = 1, 80 do
    table.insert(many, { name = "Conn "..i, protocol = "RDP", file = "/"..i..".remmina" })
  end
  H.eq(#M.buildResults(many, ""), 50, "capped at 50")
end)

-- ── formatRow ────────────────────────────────────────────────────────
H.test("formatRow with protocol", function()
  local r = M.formatRow(CONNS[1])
  H.eq(r.id, "remmina:/a.remmina", "id shape")
  H.eq(r.title, "Production Server", "title")
  H.eq(r.subtitle, "RDP", "subtitle protocol uppercased")
  H.eq(r.glyph, "device-desktop", "glyph")
  H.eq(r.category, "Network", "category is Network")
end)
H.test("formatRow empty protocol → Remmina subtitle", function()
  local r = M.formatRow({ name = "Host", protocol = "", file = "/x.remmina" })
  H.eq(r.subtitle, "Remmina", "fallback subtitle")
end)
H.test("formatRow lowercase protocol uppercased", function()
  local r = M.formatRow({ name = "H", protocol = "ssh", file = "/x.remmina" })
  H.eq(r.subtitle, "SSH", "uppercased")
end)

H.finish()

-- ── Runtime wiring: onQuery / onActivate / TTL cache ───────────────
H.test("onQuery drives scan + setResults", function()
  H.reset()
  M._resetCache()
  H.setConfig({ remminaDir = "~/.local/share/remmina" })
  H.setRunAsyncResult({ stdout = "Server A|RDP|/a.remmina\nServer B|SSH|/b.remmina\n", exitCode = 0 })
  M.onQuery("")
  H.truthy(H.calls.launcherResults, "setResults called")
  H.eq(#H.calls.launcherResults, 1, "one setResults call")
  local rows = H.calls.launcherResults[1].rows
  H.eq(#rows, 2, "two connections returned")
  H.eq(rows[1].title, "Server A", "first conn")
  H.eq(rows[2].subtitle, "SSH", "second protocol uppercased")
  H.ok(#H.calls.runAsync >= 1, "scan ran")
end)

H.test("onQuery fuzzy filter from cache", function()
  H.reset()
  M._resetCache()
  H.setConfig({ remminaDir = "~/.local/share/remmina" })
  H.setRunAsyncResult({ stdout = "Server A|RDP|/a.remmina\nServer B|SSH|/b.remmina\n", exitCode = 0 })
  M.onQuery("")
  H.reset()
  H.setConfig({ remminaDir = "~/.local/share/remmina" })
  M.onQuery("server b")
  H.truthy(H.calls.launcherResults, "setResults called")
  local rows = H.calls.launcherResults[#H.calls.launcherResults].rows
  H.eq(#rows, 1, "one fuzzy match")
  H.eq(rows[1].title, "Server B", "server b matched")
end)

H.test("onActivate launches remmina -c", function()
  H.reset()
  H.setCmdExists({ remmina = true })
  M.onActivate("remmina:/home/x/.remmina/server.remmina")
  H.truthy(H.calls.runAsync, "runAsync called")
  local argv = H.calls.runAsync[#H.calls.runAsync]
  H.eq(type(argv), "table", "argv form, not a shell string")
  H.eq(argv[1], "remmina", "program")
  H.eq(argv[2], "-c", "connect flag")
  H.eq(argv[3], "/home/x/.remmina/server.remmina", "file is one argv element")
  H.eq(#argv, 3, "no shell wrapper")
end)

H.test("onActivate ignores non-remmina id", function()
  H.reset()
  M.onActivate("steam:12345")
  H.ok(H.calls.runAsync == nil, "non-remmina id ignored")
end)

H.test("onActivate ignores empty filepath", function()
  H.reset()
  H.setCmdExists({ remmina = true })
  M.onActivate("remmina:")
  H.ok(H.calls.runAsync == nil, "empty filepath ignored")
end)

H.test("onActivate gates on commandExists", function()
  H.reset()
  H.setCmdExists({ remmina = false })
  M.onActivate("remmina:/path.remmina")
  H.ok(H.calls.runAsync == nil, "no launch when remmina missing")
  H.truthy(H.calls.notifyError, "notifyError called")
end)

H.test("TTL cache: second onQuery within 30s skips scan", function()
  H.reset()
  M._resetCache()
  H.setConfig({ remminaDir = "~/.local/share/remmina" })
  H.setRunAsyncResult({ stdout = "Conn|RDP|/a.remmina\n", exitCode = 0 })
  M.onQuery("")
  local firstRunAsyncCount = #H.calls.runAsync
  M.onQuery("")
  H.eq(#H.calls.runAsync, firstRunAsyncCount, "no second scan within TTL")
end)

H.finish()
