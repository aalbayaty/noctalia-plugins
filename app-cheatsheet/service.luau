--!nonstrict
-- Data service for App Cheatsheet. Scans the XDG application directories,
-- keeps the visible GUI entries, groups them by category and publishes a
-- display-ready snapshot to noctalia.state for the panel. The snapshot is
-- also saved to the plugin data dir and republished from there on start.
--
-- The scan is a `grep` per directory rather than listDir + readFile: one
-- subprocess returns only the handful of keys we need from every .desktop
-- file, where reading ~100 files in Luau would not fit a callback's CPU
-- budget. One directory per run keeps each result under the stdout cap too
-- (all directories together are ~70 KB on a typical NixOS desktop).

local M = {}

local SNAPSHOT_KEY = "app-cheatsheet.snapshot"
local REFRESH_KEY = "app-cheatsheet.refresh"
local STEP_KEY = "app-cheatsheet.service-step"

local SCAN_PATTERN = "^(\\[|(Type|Name|Icon|Categories|NoDisplay|Hidden|Terminal|OnlyShowIn|NotShowIn)=)"
local FORCE_KEY = "app-cheatsheet.force-refresh"
local BUSY_KEY = "app-cheatsheet.busy"
local CACHE_FILE = "snapshot.json"
local CACHE_VERSION = 1

-- Icon-theme lookups are the expensive part (a batch of 30 exceeded the
-- ~25 ms callback budget), so they are sliced by time, not by count.
local ICON_SLICE_SECONDS = 0.004
local ICON_SIZE = 48
local SCAN_STALE_SECONDS = 10

M.OTHER = "Other"

-- Checked top to bottom; the first rule with a matching category wins, so the
-- specific sub-categories sit above the broad main ones (a browser is
-- "Network;WebBrowser", Steam is "Network;FileTransfer;Game").
M.RULES = {
  { name = "Browsers", match = { "WebBrowser" } },
  { name = "Communication", match = { "Chat", "InstantMessaging", "Email", "Telephony", "VideoConference", "IRCClient" } },
  { name = "Games", match = { "Game" } },
  { name = "Development", match = { "Development", "IDE", "TextEditor" } },
  { name = "Office", match = { "Office" } },
  { name = "Graphics", match = { "Graphics" } },
  { name = "Media", match = { "AudioVideo", "Audio", "Video", "Player", "Recorder" } },
  { name = "Remote & Network", match = { "RemoteAccess", "P2P", "FileTransfer", "Network" } },
  { name = "System & Settings", match = { "System", "Settings", "FileManager", "Monitor", "TerminalEmulator" } },
  { name = "Utilities", match = { "Utility" } },
}

local function trim(s)
  return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function splitList(value, separator)
  local items = {}
  for item in tostring(value or ""):gmatch("[^" .. separator .. "]+") do
    item = trim(item)
    if item ~= "" then table.insert(items, item) end
  end
  return items
end

-- Ordered, de-duplicated `<data dir>/applications` list: the user dir first,
-- then XDG_DATA_DIRS in order. Earlier directories take precedence.
function M.appDirs(home, dataHome, dataDirs)
  local bases = {}
  if dataHome ~= nil and dataHome ~= "" then
    table.insert(bases, dataHome)
  elseif home ~= nil and home ~= "" then
    table.insert(bases, home .. "/.local/share")
  end
  if dataDirs == nil or dataDirs == "" then dataDirs = "/usr/local/share:/usr/share" end
  for _, base in ipairs(splitList(dataDirs, ":")) do table.insert(bases, base) end

  local dirs, seen = {}, {}
  for _, base in ipairs(bases) do
    local dir = (base:gsub("/+$", "")) .. "/applications"
    if not seen[dir] then
      seen[dir] = true
      table.insert(dirs, dir)
    end
  end
  return dirs
end

-- Desktop file id per the spec: path below the applications dir, "/" → "-",
-- without the extension.
function M.desktopId(path, dir)
  local prefix = dir .. "/"
  if path:sub(1, #prefix) ~= prefix then return nil end
  local rel = path:sub(#prefix + 1):gsub("%.desktop$", "")
  return (rel:gsub("/", "-"))
end

-- Parse one directory's grep output ("<path>:<line>") into `entries`, keyed by
-- desktop id. An id already present came from a higher-priority directory and
-- is left alone, hidden or not: that is how a user-level entry masks a system one.
function M.parseScan(stdout, dir, entries)
  local seenHere = {}
  local currentPath, current, inMain = nil, nil, false
  for line in tostring(stdout or ""):gmatch("[^\n]+") do
    local path, text = line:match("^(.-%.desktop):(.*)$")
    if path ~= nil then
      if path ~= currentPath then
        currentPath, current, inMain = path, nil, false
        local id = M.desktopId(path, dir)
        if id ~= nil and entries[id] == nil then
          current = { id = id, path = path, fields = {} }
          entries[id] = current
          seenHere[id] = true
        end
      end
      if current ~= nil then
        text = text:gsub("\r$", "")
        local section = text:match("^%[(.-)%]")
        if section ~= nil then
          inMain = section == "Desktop Entry"
        elseif inMain then
          local key, value = text:match("^(%w+)=(.*)$")
          if key ~= nil and current.fields[key] == nil then current.fields[key] = trim(value) end
        end
      end
    end
  end
  return entries
end

local function intersects(listValue, set)
  for _, item in ipairs(splitList(listValue, ";")) do
    if set[item] then return true end
  end
  return false
end

-- `desktops` is XDG_CURRENT_DESKTOP (colon-separated).
function M.isVisible(fields, desktops)
  if fields.Type ~= "Application" then return false end
  if fields.Name == nil or fields.Name == "" then return false end
  if fields.NoDisplay == "true" or fields.Hidden == "true" or fields.Terminal == "true" then return false end
  local current = {}
  for _, name in ipairs(splitList(desktops, ":")) do current[name] = true end
  if fields.OnlyShowIn ~= nil and fields.OnlyShowIn ~= "" and not intersects(fields.OnlyShowIn, current) then
    return false
  end
  if fields.NotShowIn ~= nil and intersects(fields.NotShowIn, current) then return false end
  return true
end

function M.categorize(categories)
  local set = {}
  for _, item in ipairs(splitList(categories, ";")) do set[item] = true end
  for _, rule in ipairs(M.RULES) do
    for _, name in ipairs(rule.match) do
      if set[name] then return rule.name end
    end
  end
  return M.OTHER
end

-- Settings arrive as a string list; a single string with ";" or newline
-- separators is accepted too.
local function settingItems(value)
  if type(value) == "table" then
    local items = {}
    for _, item in ipairs(value) do
      for _, part in ipairs(splitList(item, ";\n")) do table.insert(items, part) end
    end
    return items
  end
  return splitList(value, ";\n")
end

-- "App=Category" entries → { [lowercased app key] = category }.
function M.parseOverrides(value)
  local map = {}
  for _, item in ipairs(settingItems(value)) do
    local key, category = item:match("^(.-)=(.*)$")
    if key ~= nil then
      key, category = trim(key):lower(), trim(category)
      if key ~= "" and category ~= "" then map[key] = category end
    end
  end
  return map
end

function M.parseHidden(value)
  local set = {}
  for _, item in ipairs(settingItems(value)) do set[item:lower()] = true end
  return set
end

-- An app is addressed by desktop id (with or without ".desktop") or by name.
local function lookup(map, app)
  local id = app.id:lower()
  local hit = map[id]
  if hit == nil then hit = map[id .. ".desktop"] end
  if hit == nil then hit = map[app.name:lower()] end
  return hit
end

-- entries → sorted groups: custom categories first (alphabetical), then the
-- built-in ones in RULES order, "Other" last. Empty groups are dropped.
function M.buildGroups(entries, desktops, overrides, hidden)
  local canonical, rank = {}, {}
  for index, rule in ipairs(M.RULES) do
    canonical[rule.name:lower()] = rule.name
    rank[rule.name] = index
  end
  canonical[M.OTHER:lower()] = M.OTHER
  rank[M.OTHER] = #M.RULES + 1

  local byName = {}
  for _, entry in pairs(entries) do
    if M.isVisible(entry.fields, desktops) then
      local app = { id = entry.id, name = entry.fields.Name, icon = entry.fields.Icon or "", path = entry.path }
      if not lookup(hidden, app) then
        local category = lookup(overrides, app)
        if category ~= nil then
          category = canonical[category:lower()] or category
        else
          category = M.categorize(entry.fields.Categories)
        end
        byName[category] = byName[category] or { name = category, apps = {} }
        table.insert(byName[category].apps, app)
      end
    end
  end

  local groups = {}
  for _, group in pairs(byName) do
    table.sort(group.apps, function(a, b)
      local left, right = a.name:lower(), b.name:lower()
      if left ~= right then return left < right end
      return a.id < b.id
    end)
    table.insert(groups, group)
  end
  table.sort(groups, function(a, b)
    local left, right = rank[a.name] or 0, rank[b.name] or 0
    if left ~= right then return left < right end
    return a.name:lower() < b.name:lower()
  end)
  return groups
end

-- Cheap identity of a snapshot, so an unchanged rescan does not republish and
-- make the open panel redraw.
function M.signature(groups)
  local parts = {}
  for _, group in ipairs(groups) do
    table.insert(parts, "#" .. group.name)
    for _, app in ipairs(group.apps) do
      table.insert(parts, app.id .. "|" .. app.name .. "|" .. tostring(app.iconPath or "") .. "|" .. app.path)
    end
  end
  return table.concat(parts, "\n")
end

-- Shape check for a snapshot read back from disk.
function M.validSnapshot(data)
  if type(data) ~= "table" or data.version ~= CACHE_VERSION or type(data.groups) ~= "table" then return false end
  for _, group in ipairs(data.groups) do
    if type(group.name) ~= "string" or type(group.apps) ~= "table" then return false end
    for _, app in ipairs(group.apps) do
      if type(app.id) ~= "string" or type(app.name) ~= "string" or type(app.path) ~= "string" or type(app.icon) ~= "string" then
        return false
      end
    end
  end
  return type(data.count) == "number"
end

-- ── Runtime ────────────────────────────────────────────────────────────────

-- Work that does not fit one callback's CPU budget is queued as a step: the
-- service pings itself through shared state and the watch callback runs one
-- queued step as its own event with a fresh budget.
local steps = {}
local stepCounter = 0

local function schedule(fn)
  table.insert(steps, fn)
  stepCounter += 1
  noctalia.state.set(STEP_KEY, stepCounter)
end

-- A callback that exceeds its budget is killed mid-flight, so nothing here may
-- rely on a later line of the same callback running. `job` identifies the
-- current scan: a scan that died leaves `scanning` set, and the next request
-- after SCAN_STALE_SECONDS abandons it by starting a new job (steps of the
-- old one see a different id and stop).
local job = 0
local scanning = false
local scanStarted = 0
local rescanQueued = false
local lastSignature = nil
local scan

-- iconCache[id .. "\0" .. icon] = path | false. Seeded from the disk cache so
-- a normal rescan does no theme lookups at all; `unverified` marks seeded
-- paths that still need one existence check (icon paths are often
-- /nix/store paths that a rebuild + GC removes).
local iconCache = {}
local unverified = {}

local function iconKey(app)
  return app.id .. "\0" .. app.icon
end

local function iconFor(app)
  if app.icon:sub(1, 1) == "/" then return app.icon end
  local cacheKey = iconKey(app)
  local cached = iconCache[cacheKey]
  if cached and unverified[cacheKey] then
    unverified[cacheKey] = nil
    if not noctalia.fileExists(cached) then cached = nil end
  end
  if cached == nil then
    cached = noctalia.appIconPath(app.id, ICON_SIZE)
    if cached == nil and app.icon ~= "" then cached = noctalia.appIconPath(app.icon, ICON_SIZE) end
    iconCache[cacheKey] = cached or false
  end
  return cached or nil
end

local function cachePath()
  local directory = noctalia.pluginDataDir()
  if directory == nil then return nil end
  return directory .. "/" .. CACHE_FILE
end

local function setBusy(busy)
  noctalia.state.set(BUSY_KEY, busy)
end

-- Publish the last saved snapshot straight away so the panel has content
-- before (and regardless of) the first scan finishing.
local function loadCache()
  local path = cachePath()
  if path == nil then return end
  local contents = noctalia.readFile(path)
  if contents == nil then return end
  local data = noctalia.json.decode(contents)
  if not M.validSnapshot(data) then return end
  for _, group in ipairs(data.groups) do
    for _, app in ipairs(group.apps) do
      if app.iconPath ~= nil and app.icon:sub(1, 1) ~= "/" then
        iconCache[iconKey(app)] = app.iconPath
        unverified[iconKey(app)] = true
      end
    end
  end
  lastSignature = M.signature(data.groups)
  noctalia.state.set(SNAPSHOT_KEY, { groups = data.groups, count = data.count })
end

local function finish(groups)
  local count = 0
  for _, group in ipairs(groups) do count += #group.apps end
  local signature = M.signature(groups)
  scanning = false
  if signature ~= lastSignature then
    lastSignature = signature
    noctalia.state.set(SNAPSHOT_KEY, { groups = groups, count = count })
    local path = cachePath()
    local encoded = noctalia.json.encode({ version = CACHE_VERSION, groups = groups, count = count })
    if path ~= nil and encoded ~= nil then noctalia.writeFile(path, encoded) end
  end
  setBusy(false)
  if rescanQueued then
    rescanQueued = false
    scan()
  end
end

local function resolveIcons(groups, myJob)
  local flat = {}
  for _, group in ipairs(groups) do
    for _, app in ipairs(group.apps) do table.insert(flat, app) end
  end
  local index = 1
  local function step()
    if myJob ~= job then return end
    if index > #flat then
      finish(groups)
      return
    end
    -- Queue the continuation first and advance before each lookup: a theme
    -- lookup can be slow enough to get this callback killed, and then the
    -- next step simply carries on with the following app.
    schedule(step)
    local deadline = os.clock() + ICON_SLICE_SECONDS
    repeat
      local app = flat[index]
      index += 1
      app.iconPath = iconFor(app)
    until index > #flat or os.clock() >= deadline
  end
  step()
end

local function group(entries, myJob)
  if myJob ~= job then return end
  local groups = M.buildGroups(
    entries,
    noctalia.getenv("XDG_CURRENT_DESKTOP"),
    M.parseOverrides(noctalia.getConfig("overrides")),
    M.parseHidden(noctalia.getConfig("hidden"))
  )
  schedule(function() resolveIcons(groups, myJob) end)
end

scan = function()
  if scanning and os.time() - scanStarted < SCAN_STALE_SECONDS then
    rescanQueued = true
    return
  end
  job += 1
  local myJob = job
  scanning = true
  scanStarted = os.time()
  rescanQueued = false
  setBusy(true)

  local dirs = {}
  for _, dir in ipairs(M.appDirs(noctalia.getenv("HOME"), noctalia.getenv("XDG_DATA_HOME"), noctalia.getenv("XDG_DATA_DIRS"))) do
    local info = noctalia.fileInfo(dir)
    if info ~= nil and info.isDir then table.insert(dirs, dir) end
  end

  local entries = {}
  local index = 0
  local function nextDir()
    if myJob ~= job then return end
    index += 1
    local dir = dirs[index]
    if dir == nil then
      schedule(function() group(entries, myJob) end)
      return
    end
    -- -R follows symlinks (Nix profile and Flatpak export dirs are all links).
    local started = noctalia.runAsync({ "grep", "-R", "-s", "-H", "-E", SCAN_PATTERN, "--include=*.desktop", dir }, function(result)
      if myJob ~= job then return end
      if result.stdoutTruncated then
        noctalia.log("app-cheatsheet: scan output truncated for " .. dir)
        noctalia.notifyError(noctalia.tr("scan_truncated"), noctalia.tr("scan_truncated_body", { dir = dir }))
      end
      M.parseScan(result.stdout, dir, entries)
      nextDir()
    end, 10000)
    if not started then
      noctalia.log("app-cheatsheet: could not start grep for " .. dir)
      nextDir()
    end
  end
  nextDir()
end

-- Full refresh: forget every resolved icon and republish even if unchanged.
local function forceRefresh()
  iconCache = {}
  unverified = {}
  lastSignature = nil
  scanStarted = 0 -- abandon a scan in flight; it would reuse nothing anyway
  scan()
end

function onConfigChanged()
  scan()
end

function onIpc(event, _payload)
  if event == "refresh" then forceRefresh() end
end

-- Test hook: drop all in-memory state, as a shell restart would.
function M._reset()
  steps, iconCache, unverified = {}, {}, {}
  scanning, rescanQueued, lastSignature, scanStarted = false, false, nil, 0
end

function M._start()
  noctalia.state.watch(STEP_KEY, function(_value)
    local fn = table.remove(steps, 1)
    if fn ~= nil then fn() end
  end)
  noctalia.state.watch(REFRESH_KEY, function(_value) scan() end)
  noctalia.state.watch(FORCE_KEY, function(_value) forceRefresh() end)
  loadCache()
  scan()
end

if _G.__APPCHEAT_TEST or noctalia == nil then return M end
M._start()
