--!nonstrict
local H = { calls = {}, _watchers = {}, _state = {}, _tests = 0 }

local function uiCtor(name)
  return function(props, children)
    return { type = name, props = props or {}, children = children or {} }
  end
end
H.ui = {}
for _, n in ipairs({ "column","row","box","label","glyph","image","separator","spacer",
  "progress","button","graph","input","select","slider","toggle","scroll" }) do
  H.ui[n] = uiCtor(n)
end

H.state = {
  get = function(k) return H._state[k] end,
  set = function(k, v)
    H._state[k] = v
    if k == "command" then H.calls.command = v end
    for _, cb in ipairs(H._watchers[k] or {}) do cb(v) end
  end,
  watch = function(k, cb)
    H._watchers[k] = H._watchers[k] or {}
    table.insert(H._watchers[k], cb)
  end,
}

H.noctalia = {
  state = H.state,
  log = function() end,
  togglePanel = function(id) H.calls.togglePanel = id end,
  notify = function(t, b) H.calls.notify = H.calls.notify or {}; table.insert(H.calls.notify, { t, b }) end,
  notifyError = function(t, b) H.calls.notifyError = { t, b } end,
  setUpdateInterval = function(ms) H.calls.interval = ms end,
  http = function(req, cb) H.calls.http = req; if H._httpReply then cb(H._httpReply) end; return true end,
  getConfig = function(k) return H._config and H._config[k] end,
  pluginDir = function() return "/tmp/mawaqit-plugindir" end,
  pluginDataDir = function() return "/tmp/mawaqit-datadir" end,
  readFile = function(p) local v = H._fs and H._fs[p]; if v then return v, nil else return nil, "not found" end end,
  writeFile = function(p, c) H._fs = H._fs or {}; H._fs[p] = c; return true, nil end,
  fileExists = function(p) return H._fs ~= nil and H._fs[p] ~= nil end,
  formatTime = function(pat, unix) return "T" end,
  json = {
    decode = function(s) local ok, v = pcall(function() return H._decode(s) end); if ok then return v, nil else return nil, "decode" end end,
    encode = function(v) return "{}", nil end,
  },
  string = {
    trim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end,
    urlEncode = function(s) return (s:gsub("[^%w]", function(c) return string.format("%%%02X", string.byte(c)) end)) end,
    urlDecode = function(s) return s end,
  },
}
H.barWidget = {
  render = function(tree) H.calls.render = tree end,
  isVertical = function() return H._vertical == true end,
  setTooltip = function(t) H.calls.tooltip = t end,
  setText = function(t) H.calls.text = t end,
  setGlyph = function(g) H.calls.glyph = g end,
}
H.panel = {
  render = function(tree) H.calls.render = tree end,
  close = function() H.calls.close = true end,
  setWantsSecondTicks = function(b) H.calls.secondTicks = b end,
}

-- Configure fixtures before H.loadEntry: H.setConfig(t), H.setHttpReply(resp), H.setDecode(fn), H.setVertical(b)
function H.setConfig(t) H._config = t end
function H.setHttpReply(r) H._httpReply = r end
function H.setDecode(fn) H._decode = fn end
function H.setVertical(b) H._vertical = b end

function H.installGlobals()
  -- for tests that reference H.ui/H.state directly (harness self-test)
end

-- Load an entry module and inject the mock globals into its environment.
function H.loadEntry(relpath)
  local M = require(relpath) -- entry returns M because `noctalia == nil` at require time
  local env
  for _, v in pairs(M) do
    if type(v) == "function" then env = getfenv(v); break end
  end
  assert(env, "entry exported no function to locate its env")
  env.noctalia = H.noctalia
  env.ui = H.ui
  env.barWidget = H.barWidget
  env.panel = H.panel
  env.__MAWAQIT_TEST = true
  env._G = env
  H.env = env
  return M
end

function H.find(node, pred)
  if type(node) ~= "table" then return nil end
  if node.type and pred(node) then return node end
  for _, c in ipairs(node.children or {}) do
    local r = H.find(c, pred)
    if r then return r end
  end
  return nil
end
function H.findAll(node, pred, acc)
  acc = acc or {}
  if type(node) == "table" then
    if node.type and pred(node) then table.insert(acc, node) end
    for _, c in ipairs(node.children or {}) do H.findAll(c, pred, acc) end
  end
  return acc
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
