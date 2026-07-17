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
local M = {}

local RESULT_LIMIT = 50
local REFRESH_TTL_MS = 30000 -- 30s, matching v4

-- ── Pure logic (testable via __REMMINA_TEST export) ────────────────

-- Shell-quote a string: wrap in single quotes, escape embedded single quotes.
function M.shellQuote(s)
  s = tostring(s or "")
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

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

-- Build the shell scan script. One `sh -c` pipeline emitting
-- `name|protocol|filepath` lines. Uses `find -exec awk` so awk runs once
-- per file (the ENDFILE block fires reliably per file). An earlier
-- `find -print0 | awk -v RS='\0'` form silently produced no output because
-- ENDFILE doesn't fire correctly with NUL-separated records.
function M.buildScanScript(remminaDir)
  local qDir = M.shellQuote(remminaDir)
  return "find " .. qDir .. " -maxdepth 1 -name '*.remmina' -type f -exec awk '" ..
    "FNR==1{name=\"\";protocol=\"\"} " ..
    "/^[[:space:]]*name=/{sub(/^[[:space:]]*name=/,\"\"); gsub(/\\r$/,\"\"); name=$0} " ..
    "/^[[:space:]]*protocol=/{sub(/^[[:space:]]*protocol=/,\"\"); gsub(/\\r$/,\"\"); protocol=$0} " ..
    "END{if(name!=\"\") printf \"%s|%s|%s\\n\", name, protocol, FILENAME}" ..
    "' {} \\; 2>/dev/null"
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

-- Filter + fuzzy-sort connections by query. Returns LauncherResult-shaped rows.
-- Empty/whitespace query = browse mode (all, capped at RESULT_LIMIT).
-- Otherwise fuzzy-match on name via noctalia.fuzzyScore, sort asc, cap.
function M.buildResults(conns, query)
  conns = conns or {}
  local q = noctalia.string.trim(query or "")
  local rows = {}
  if q == "" then
    for i = 1, math.min(#conns, RESULT_LIMIT) do
      table.insert(rows, M.formatRow(conns[i]))
    end
    return rows
  end
  local scored = {}
  for _, c in ipairs(conns) do
    local score = noctalia.fuzzyScore(q, c.name)
    if score ~= nil then table.insert(scored, { conn = c, score = score }) end
  end
  table.sort(scored, function(a, b) return a.score < b.score end)
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
  local script = M.buildScanScript(noctalia.expandPath(cfg.remminaDir))
  noctalia.runAsync(script, function(res)
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
  noctalia.runAsync("remmina -c " .. M.shellQuote(file), nil)
end

if _G.__REMMINA_TEST or noctalia == nil then return M end

-- Production: expose the same functions as globals for the host to call.
onQuery = M.onQuery
onActivate = M.onActivate
