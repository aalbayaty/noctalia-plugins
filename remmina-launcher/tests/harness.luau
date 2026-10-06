--!nonstrict
-- Mock-global test harness for remmina-launcher. Adapted from steam-launcher's
-- tests/harness.luau: same mock surface, flag renamed to __REMMINA_TEST.
local H = { calls = {}, _tests = 0 }

H.noctalia = {
  log = function() end,
  notify = function(t, b) H.calls.notify = H.calls.notify or {}; table.insert(H.calls.notify, { t, b }) end,
  notifyError = function(t, b) H.calls.notifyError = { t, b } end,
  getConfig = function(k) return H._config and H._config[k] end,
  expandPath = function(p)
    if p == nil then return p end
    return (tostring(p):gsub("^~", "/home/test"))
  end,
  runAsync = function(cmd, cb, ms)
    -- Entries exec via argv arrays (plugin_api 24); keep a flat copy of every
    -- command (table or string) so tests can assert on either form.
    H.calls.runAsync = H.calls.runAsync or {}
    if type(cmd) == "table" then
      local copy = {}
      for i, v in ipairs(cmd) do copy[i] = v end
      table.insert(H.calls.runAsync, copy)
    else
      table.insert(H.calls.runAsync, cmd)
    end
    if H._runAsyncResult and cb then cb(H._runAsyncResult) end
    return true
  end,
  commandExists = function(name) return H._cmdExists == nil or H._cmdExists[name] == true end,
  -- Stand-in for the native matcher: case-insensitive substring, higher =
  -- better (earlier and tighter matches score more), nil when absent.
  fuzzyScore = function(pattern, text)
    if pattern == nil or pattern == "" then return 0 end
    local p = tostring(pattern):lower()
    local t = tostring(text):lower()
    local start = t:find(p, 1, true)
    if not start then return nil end
    return 1000 - (start + #t - #p)
  end,
  string = {
    trim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end,
  },
}

H.launcher = {
  setResults = function(query, rows)
    H.calls.launcherResults = H.calls.launcherResults or {}
    table.insert(H.calls.launcherResults, { query = query, rows = rows })
  end,
  setQuery = function(text) H.calls.launcherQuery = text end,
}

function H.setConfig(t) H._config = t end
function H.setRunAsyncResult(r) H._runAsyncResult = r end
function H.setCmdExists(t) H._cmdExists = t end
function H.reset() H.calls = {}; H._runAsyncResult = nil; H._config = nil; H._cmdExists = nil end

function H.loadEntry(relpath)
  local M = require(relpath)
  local env
  for _, v in pairs(M) do
    if type(v) == "function" then env = getfenv(v); break end
  end
  assert(env, "entry exported no function to locate its env")
  env.noctalia = H.noctalia
  env.launcher = H.launcher
  env.__REMMINA_TEST = true
  env._G = env
  H.env = env
  return M
end

function H.eq(a, b, msg)
  if a ~= b then error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2) end
end
function H.ok(cond, msg) if not cond then error("not ok: " .. (msg or ""), 2) end end
function H.truthy(v, msg) if v == nil or v == false then error("not truthy: " .. (msg or ""), 2) end end
function H.test(name, fn)
  H._tests += 1
  local ok, err = pcall(fn)
  if ok then print("PASS: " .. name) else print("FAIL: " .. name .. ": " .. tostring(err)); error("test failed", 0) end
end
function H.finish() print(string.format("ALL PASS (%d tests)", H._tests)) end

return H
