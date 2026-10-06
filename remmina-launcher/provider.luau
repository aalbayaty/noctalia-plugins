--!nonstrict
-- Remmina Launcher — Noctalia v5 launcher provider.
-- Ported from the v4 QML plugin (git tag v1.0, noctalia-plugins/remmina-launcher/).
-- Browses Remmina remote-desktop connections (scans ~/.local/share/remmina/*.remmina,
-- parses name+protocol from each INI-like file) and launches them via
-- `remmina -c <file>`.
--
-- Single launcher_provider entry: onQuery triggers a scan (cached 30s),
-- fuzzy-filters the results, and publishes them via launcher.setResults.
-- onActivate extracts the filepath and runs `remmina -c <file>` detached.
--
-- The scan used to be one `sh -c` pipeline that shell-quoted the directory
-- setting. It is now a `find -exec` argv exec (plugin_api 24): the shell never
-- sees the path or the filenames, so a connection file called `x'; rm -rf ~;'.remmina`
-- cannot alter the command. The awk program arrives as a single argv element, so
-- it needs no shell escaping either — only the in-awk string literals below.
local M = {}

local RESULT_LIMIT = 50
local REFRESH_TTL_MS = 30000 -- 30s, matching v4

-- ── Pure logic (testable via __REMMINA_TEST export) ────────────────

-- Parse a single .remmina file's contents → {name, protocol} or nil.
-- INI-like key=value; match leading "name=" / "protocol=" specifically
-- (other keys may contain '=' in values). Strip trailing \r for CRLF
-- files edited on Windows — ported from v4 Main.qml's onLoaded parser.
function M.parseRemminaFile(contents)
  if contents == nil or contents == "" then return nil end
  local name, protocol = nil, ""
  for line in tostring(contents):gmatch("[^\r\n]+") do
    line = line:gsub("\r$", "")
    if line:sub(1, 5) == "name=" and name == nil then
      name = line:sub(6)
    elseif line:sub(1, 9) == "protocol=" then
      protocol = line:sub(10)
    end
  end
  if not name or name == "" then return nil end
  return { name = name, protocol = protocol }
end

-- Parse one `name|protocol|filepath` line → {name, protocol, file} or nil.
function M.parseLine(line)
  if line == nil or line:match("^%s*$") then return nil end
  local parts = {}
  for p in (line .. "|"):gmatch("([^|]*)|") do table.insert(parts, p) end
  if #parts < 3 then return nil end
  local name, protocol, file = parts[1], parts[2], parts[3]
  if name == "" then return nil end
  return { name = name, protocol = protocol, file = file }
end

-- Parse the full scan stdout → array of {name, protocol, file}.
function M.parseScanOutput(stdout)
  local conns = {}
  for line in tostring(stdout or ""):gmatch("[^\r\n]+") do
    local e = M.parseLine(line)
    if e then table.insert(conns, e) end
  end
  return conns
end

-- The awk program run against every .remmina file, emitting
-- `name|protocol|filepath`. Runs via `find … -exec awk '<program>' {} +`, i.e.
-- once per batch of arguments.
--
-- Three awk traps shaped this program, each of which silently produced a wrong
-- or empty result before the e2e test caught it:
--
--   1. END fires *once per batch* under `{} +`, not per file, so an END-based
--      emit would return only the last connection. Hence `{} +` batching is
--      paired with per-record rules that reset on FNR==1.
--   2. `next` is a parse error inside an END action — avoid END entirely.
--   3. `sub()` on a field rewrites $0, and awk then re-evaluates the *changed*
--      record against the rules that follow. A trailing "emit anything left
--      over" rule therefore fires on the name rule's own output rather than on
--      a later line, which emitted the row before protocol= was ever read.
--      The emit consequently has no fallback rule: it is triggered solely by
--      the name rule, matching how Remmina always writes name= before the
--      protocol line.
--
-- The protocol is captured from the last `protocol=` line in the file, unlike
-- the retained M.parseRemminaFile which keeps the first. Remmina writes one
-- protocol per file, so this is unreachable in practice and the two parsers
-- agree on real input.
--
-- Files with no name= emit nothing (matching the old `END{ if(name!="") }`
-- guard). The `|` separator is still ambiguous for a name containing a pipe —
-- see M.parseLine, which always takes the trailing field as the path — so a
-- connection named with a pipe shifts its protocol into the path. Remmina does
-- not constrain those characters; noted rather than worked around, since a
-- delimiter change would need a matching parser change.
function M.buildAwkProgram()
  return table.concat({
    'FNR==1 { name=""; protocol=""; emitted=0; }',
    "/^[[:space:]]*name=/ {",
      'if (name == "") {',
        'n=$0; sub(/^[[:space:]]*name=/, "", n); gsub(/\\r$/, "", n); name=n;',
      "}",
    "}",
    "/^[[:space:]]*protocol=/ {",
      'if (!emitted && name != "") {',
        'p=$0; sub(/^[[:space:]]*protocol=/, "", p); gsub(/\\r$/, "", p); protocol=p;',
        'printf "%s|%s|%s\\n", name, protocol, FILENAME; emitted=1;',
      "}",
    "}",
  }, " ")
end

-- Build the scan argv. Direct exec (plugin_api 24) — no shell, so the directory
-- is not quoted or parsed; `find` receives it verbatim as an argv element.
function M.buildScanArgv(remminaDir)
  return {
    "find", remminaDir,
    "-maxdepth", "1",
    "-type", "f",
    "-name", "*.remmina",
    "-exec", "awk", M.buildAwkProgram(), "{}", "+",
  }
end

-- Format one connection as a LauncherResult row.
-- id = "remmina:<filepath>" (onActivate extracts the filepath from this).
-- subtitle shows the protocol uppercased to disambiguate identical names
-- across protocols; falls back to "Remmina" when protocol is empty.
function M.formatRow(conn)
  local subtitle = (conn.protocol and conn.protocol ~= "") and conn.protocol:upper() or "Remmina"
  return {
    id = "remmina:" .. conn.file,
    title = conn.name,
    subtitle = subtitle,
    glyph = "device-desktop",
    category = "Network",
    score = nil,
  }
end

-- Score one connection against the query words. Every word must match, in any
-- order: each is fuzzy-matched against the name, falling back to the protocol,
-- so "work rdp" finds "RDP Work" and "vnc mac" finds a VNC connection named
-- "RDP MAC". Returns the summed score (higher = better, as the host orders
-- launcher results), or nil when any word matches neither.
function M.scoreConnection(words, conn)
  local total = 0
  for _, word in ipairs(words) do
    local score = noctalia.fuzzyScore(word, conn.name)
    if score == nil and conn.protocol ~= nil and conn.protocol ~= "" then
      score = noctalia.fuzzyScore(word, conn.protocol)
    end
    if score == nil then return nil end
    total += score
  end
  return total
end

-- Filter + rank connections by query. Returns LauncherResult-shaped rows.
-- Empty/whitespace query = browse mode (all, capped at RESULT_LIMIT).
-- Otherwise match word by word (see M.scoreConnection), best first, capped.
function M.buildResults(conns, query)
  conns = conns or {}
  local words = {}
  for word in tostring(query or ""):gmatch("%S+") do table.insert(words, word) end
  local rows = {}
  if #words == 0 then
    for i = 1, math.min(#conns, RESULT_LIMIT) do
      table.insert(rows, M.formatRow(conns[i]))
    end
    return rows
  end
  local scored = {}
  for index, c in ipairs(conns) do
    local score = M.scoreConnection(words, c)
    if score ~= nil then table.insert(scored, { conn = c, score = score, index = index }) end
  end
  table.sort(scored, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.index < b.index
  end)
  for i = 1, math.min(#scored, RESULT_LIMIT) do
    local r = M.formatRow(scored[i].conn)
    r.score = scored[i].score
    table.insert(rows, r)
  end
  return rows
end

-- ── Runtime wiring (uses injected globals) ────────────────────────
-- Defined on M BEFORE the __REMMINA_TEST guard so tests can drive them via
-- M.onQuery / M.onActivate. In production the guard is skipped and the same
-- functions are also bound as globals for the host to call.

local function readCfg()
  return { remminaDir = noctalia.getConfig("remminaDir") or "~/.local/share/remmina" }
end

-- In-memory cache with 30s TTL.
local cache = { conns = nil, loadedAt = 0, loading = false }

function M._resetCache() cache = { conns = nil, loadedAt = 0, loading = false } end

local function nowMs() return os.time() * 1000 end

function M._refresh(cfg, onDone)
  if cache.loading then
    onDone(cache.conns)
    return
  end
  if cache.conns and (nowMs() - cache.loadedAt) < REFRESH_TTL_MS then
    onDone(cache.conns)
    return
  end
  cache.loading = true
  local argv = M.buildScanArgv(noctalia.expandPath(cfg.remminaDir))
  noctalia.runAsync(argv, function(res)
    cache.conns = M.parseScanOutput(res and res.stdout or "")
    cache.loadedAt = nowMs()
    cache.loading = false
    onDone(cache.conns)
  end)
end

function M.onQuery(query)
  local cfg = readCfg()
  M._refresh(cfg, function(conns)
    launcher.setResults(query, M.buildResults(conns, query))
  end)
end

function M.onActivate(id)
  if not id or id:sub(1, 8) ~= "remmina:" then return end
  local file = id:sub(9)
  if file == "" then return end
  if not noctalia.commandExists("remmina") then
    noctalia.notifyError("Remmina Launcher", "remmina command not found")
    return
  end
  noctalia.runAsync({ "remmina", "-c", file })
end

if _G.__REMMINA_TEST or noctalia == nil then return M end

-- Production: expose the same functions as globals for the host to call.
onQuery = M.onQuery
onActivate = M.onActivate
