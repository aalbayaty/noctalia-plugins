--!nonstrict
-- Mock-global test harness for steam-launcher. Adapted from mawaqit's
-- tests/harness.luau: adds H.launcher (setResults/setQuery recorders) and
-- H.noctalia.runAsync/commandExists/fuzzyScore/expandPath, renames the
-- test-export flag to __STEAM_TEST.
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
    H.calls.runAsync = H.calls.runAsync or {}
    table.insert(H.calls.runAsync, cmd)
    if H._runAsyncResult and cb then cb(H._runAsyncResult) end
    return true
  end,
  commandExists = function(name) return H._cmdExists == nil or H._cmdExists[name] == true end,
  fuzzyScore = function(pattern, text)
    -- Simple substring score for tests: nil when no match, lower = better.
    -- Real noctalia.fuzzyScore is subsequence-based; this is enough to
    -- exercise the sort + filter paths.
    if pattern == nil or pattern == "" then return 0 end
    local p = tostring(pattern):lower()
    local t = tostring(text):lower()
    local start = t:find(p, 1, true)
    if not start then return nil end
    return start + #t - #p  -- earlier match + shorter leftover = lower score
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

-- Fixtures: H.setConfig(t), H.setRunAsyncResult(r), H.setCmdExists({steam=true})
function H.setConfig(t) H._config = t end
function H.setRunAsyncResult(r) H._runAsyncResult = r end
function H.setCmdExists(t) H._cmdExists = t end
function H.reset() H.calls = {}; H._runAsyncResult = nil; H._config = nil; H._cmdExists = nil end

-- Load the entry module and inject mock globals into its env. The entry
-- returns M because `noctalia == nil` at require time (the guard fires).
function H.loadEntry(relpath)
  local M = require(relpath)
  local env
  for _, v in pairs(M) do
    if type(v) == "function" then env = getfenv(v); break end
  end
  assert(env, "entry exported no function to locate its env")
  env.noctalia = H.noctalia
  env.launcher = H.launcher
  env.__STEAM_TEST = true
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
