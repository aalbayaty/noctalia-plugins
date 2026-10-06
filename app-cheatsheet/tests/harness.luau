--!nonstrict
-- Mock-global test harness for app-cheatsheet. Same approach as the other
-- plugins' harnesses: stub the host globals, record calls, and inject them
-- into the entry's environment.
local H = { calls = {}, files = {}, _json = {}, _tests = 0 }

local function node(kind)
  return function(props, children) return { type = kind, props = props or {}, children = children or {} } end
end

H.ui = {}
for _, kind in ipairs({ "column", "row", "box", "label", "glyph", "image", "separator", "scroll", "button" }) do
  H.ui[kind] = node(kind)
end

H.panel = {
  render = function(tree) H.calls.rendered = tree; H.calls.renderCount = (H.calls.renderCount or 0) + 1 end,
  close = function() H.calls.closed = (H.calls.closed or 0) + 1 end,
}

H.noctalia = {
  log = function() end,
  notifyError = function(t, b) H.calls.notifyError = { t, b } end,
  tr = function(key, subst)
    if subst and subst.count ~= nil then return key .. ":" .. tostring(subst.count) end
    return key
  end,
  getConfig = function(k) return H._config and H._config[k] end,
  getenv = function(k) return H._env and H._env[k] end,
  fileInfo = function(path)
    if H._dirs and H._dirs[path] ~= nil then return { size = 0, mtime = 0, isDir = true } end
    return nil, "missing"
  end,
  commandExists = function(name) return H._cmdExists == nil or H._cmdExists[name] == true end,
  appIconPath = function(name, _size)
    H.calls.iconLookups = (H.calls.iconLookups or 0) + 1
    -- Stands in for the host killing a callback that ran out of CPU budget.
    if H._iconKill == name then
      H._iconKill = nil
      error("exceeded its CPU budget")
    end
    return H._icons and H._icons[name] or nil
  end,
  fileExists = function(path) return H._missing == nil or not H._missing[path] end,
  pluginDataDir = function() return "/data/app-cheatsheet" end,
  readFile = function(path)
    if H.files[path] == nil then return nil, "missing" end
    return H.files[path]
  end,
  writeFile = function(path, contents)
    H.files[path] = contents
    return true
  end,
  -- Opaque round-trip: encode hands back a token for a deep copy of the value.
  json = {
    encode = function(value)
      local function copy(v)
        if type(v) ~= "table" then return v end
        local out = {}
        for k, item in pairs(v) do out[k] = copy(item) end
        return out
      end
      H._jsonCount = (H._jsonCount or 0) + 1
      local token = "json#" .. H._jsonCount
      H._json[token] = copy(value)
      return token
    end,
    decode = function(text)
      if H._json[text] == nil then return nil, "invalid json" end
      return H._json[text]
    end,
  },
  focusedOutputName = function() return "DP-1" end,
  outputs = function() return { { name = "DP-1", width = 3440, height = 1440, scale = 1, focused = true } } end,
  togglePanel = function(id) H.calls.toggled = id end,
  -- argv exec; the scan's last argument is the directory, answered from _dirs.
  runAsync = function(cmd, cb, _ms)
    H.calls.runAsync = H.calls.runAsync or {}
    local copy = {}
    for i, v in ipairs(cmd) do copy[i] = v end
    table.insert(H.calls.runAsync, copy)
    if cb and not H._hang then
      local stdout = H._dirs and H._dirs[cmd[#cmd]] or ""
      cb({ exitCode = 0, stdout = stdout, stderr = "", timedOut = false, stdoutTruncated = false, stderrTruncated = false })
    end
    return true
  end,
  state = {
    _values = {},
    _watchers = {},
    _queue = {},
    _draining = false,
    -- Like the host, watchers run as their own events after the current
    -- callback returns, and one that dies does not take the others with it.
    set = function(key, value)
      local state = H.noctalia.state
      state._values[key] = value
      for _, fn in ipairs(state._watchers[key] or {}) do table.insert(state._queue, { fn, value }) end
      if state._draining then return end
      state._draining = true
      while #state._queue > 0 do
        local item = table.remove(state._queue, 1)
        local ok, err = pcall(item[1], item[2])
        if not ok then H.calls.killed = (H.calls.killed or 0) + 1 end
      end
      state._draining = false
    end,
    get = function(key) return H.noctalia.state._values[key] end,
    watch = function(key, fn)
      H.noctalia.state._watchers[key] = H.noctalia.state._watchers[key] or {}
      table.insert(H.noctalia.state._watchers[key], fn)
    end,
  },
}

function H.setConfig(t) H._config = t end
function H.setEnv(t) H._env = t end
function H.setDirs(t) H._dirs = t end
function H.setIcons(t) H._icons = t end
function H.setCmdExists(t) H._cmdExists = t end
function H.setMissing(t) H._missing = t end
function H.killIconLookup(name) H._iconKill = name end
function H.setHang(v) H._hang = v end
-- Forget everything in memory, as a shell restart would; files survive.
function H.restart()
  H.calls = {}
  H.noctalia.state._values = {}
  H.noctalia.state._watchers = {}
  H.noctalia.state._queue = {}
  H.noctalia.state._draining = false
end
function H.reset()
  H.restart()
  H.files = {}
  H._config, H._env, H._dirs, H._icons, H._cmdExists = nil, nil, nil, nil, nil
  H._missing, H._iconKill, H._hang = nil, nil, nil
end

function H.loadEntry(relpath)
  local M = require(relpath)
  local env
  for _, v in pairs(M) do
    if type(v) == "function" then env = getfenv(v); break end
  end
  assert(env, "entry exported no function to locate its env")
  env.noctalia = H.noctalia
  env.ui = H.ui
  env.panel = H.panel
  env.__APPCHEAT_TEST = true
  env._G = env
  H.env = env
  return M
end

-- Depth-first search of a ui tree.
function H.find(tree, pred, out)
  out = out or {}
  if type(tree) ~= "table" then return out end
  if pred(tree) then table.insert(out, tree) end
  for _, child in ipairs(tree.children or {}) do H.find(child, pred, out) end
  return out
end

function H.eq(a, b, msg)
  if a ~= b then error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2) end
end
function H.ok(cond, msg) if not cond then error("not ok: " .. (msg or ""), 2) end end
function H.test(name, fn)
  H._tests += 1
  local ok, err = pcall(fn)
  if ok then print("PASS: " .. name) else print("FAIL: " .. name .. ": " .. tostring(err)); error("test failed", 0) end
end
function H.finish() print(string.format("ALL PASS (%d tests)", H._tests)) end

return H
