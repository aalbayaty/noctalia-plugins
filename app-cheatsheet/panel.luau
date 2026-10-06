--!nonstrict
-- Thin renderer for App Cheatsheet: draws the service's snapshot as balanced
-- columns of category blocks. Clicking a row launches the app and closes the
-- panel. No search by design; the Noctalia launcher already covers that.

local M = {}

local SNAPSHOT_KEY = "app-cheatsheet.snapshot"
local REFRESH_KEY = "app-cheatsheet.refresh"
local FORCE_KEY = "app-cheatsheet.force-refresh"
local BUSY_KEY = "app-cheatsheet.busy"
local FALLBACK_GLYPH = "app-window"

local snapshot = nil
local busy = false
local panelOpen = false

-- Columns the output can fit at ~260px each, capped by the setting.
function M.columnCount(configured, outputWidth)
  local wanted = math.clamp(tonumber(configured) or 4, 1, 6)
  local fits = math.max(1, math.floor((outputWidth or 1920) / 260))
  return math.min(wanted, fits)
end

-- Search budget for balancedColumns. The exact search is exponential in the
-- worst case and runs inside a render callback, so it stops after this many
-- steps and keeps the best layout found (never worse than the greedy seed).
local BALANCE_NODE_LIMIT = 20000

-- Split the groups into `count` columns of as equal height as possible: the
-- tallest column is made as short as it can be, then the shortest as tall as it
-- can be. A header counts as two rows.
--
-- Largest-first greedy placement gives the starting layout; a depth-first
-- search over the same order then looks for a better one, skipping branches
-- that cannot beat the best so far and columns of equal height (they are
-- interchangeable). Within a column the groups keep their service order
-- (custom groups first), and columns are ordered by their first group, so the
-- panel still reads Browsers-first from the top left.
function M.balancedColumns(groups, count)
  local items = {}
  local total = 0
  for order, group in ipairs(groups) do
    items[order] = { group = group, order = order, weight = #group.apps + 2 }
    total += items[order].weight
  end
  table.sort(items, function(a, b)
    if a.weight ~= b.weight then return a.weight > b.weight end
    return a.order < b.order
  end)

  local load, assign, best = {}, {}, {}
  for index = 1, count do load[index] = 0 end
  for index, item in ipairs(items) do
    local target = 1
    for column = 2, count do
      if load[column] < load[target] then target = column end
    end
    load[target] += item.weight
    best[index] = target
  end
  local bestMax, bestMin = math.max(table.unpack(load)), math.min(table.unpack(load))

  -- Nothing can beat every column sitting at the average (rounded either way).
  local idealSpread = total % count == 0 and 0 or 1
  local nodes, done = 0, bestMax - bestMin <= idealSpread
  for index = 1, count do load[index] = 0 end

  local function search(index)
    if done then return end
    nodes += 1
    if nodes > BALANCE_NODE_LIMIT then
      done = true
      return
    end
    if index > #items then
      local highest, lowest = math.max(table.unpack(load)), math.min(table.unpack(load))
      if highest < bestMax or (highest == bestMax and lowest > bestMin) then
        bestMax, bestMin = highest, lowest
        for i = 1, #items do best[i] = assign[i] end
        if highest - lowest <= idealSpread then done = true end
      end
      return
    end
    local weight = items[index].weight
    local tried = {}
    for column = 1, count do
      local current = load[column]
      if not tried[current] and current + weight <= bestMax then
        tried[current] = true
        load[column] = current + weight
        assign[index] = column
        search(index + 1)
        load[column] = current
        if done then return end
      end
    end
  end
  if not done then search(1) end

  local columns = {}
  for index = 1, count do columns[index] = { groups = {}, weight = 0 } end
  for index, item in ipairs(items) do
    local column = columns[best[index]]
    table.insert(column.groups, item)
    column.weight += item.weight
  end
  for _, column in ipairs(columns) do
    table.sort(column.groups, function(a, b) return a.order < b.order end)
    column.first = column.groups[1] ~= nil and column.groups[1].order or math.huge
    for index, item in ipairs(column.groups) do column.groups[index] = item.group end
  end
  table.sort(columns, function(a, b) return a.first < b.first end)
  return columns
end

local function appRow(app, onLaunch)
  local icon
  if app.iconPath ~= nil then
    icon = ui.image({ path = app.iconPath, width = 22, height = 22 })
  else
    icon = ui.glyph({ name = FALLBACK_GLYPH, size = 20, color = "on_surface_variant" })
  end
  return ui.row({
    key = "app-" .. app.id,
    gap = 8,
    align = "center",
    paddingV = 3,
    paddingH = 6,
    radius = 6,
    onClick = function() onLaunch(app) end,
  }, {
    icon,
    ui.label({ text = app.name, fontSize = 13, maxLines = 1, flexGrow = 1 }),
  })
end

local function groupNode(group, onLaunch)
  local children = {
    ui.label({ text = string.upper(group.name), color = "primary", fontSize = 14, fontWeight = "bold" }),
    ui.separator({ color = "outline", thickness = 1, spacing = 1 }),
  }
  for _, app in ipairs(group.apps) do table.insert(children, appRow(app, onLaunch)) end
  return ui.column({ key = "group-" .. group.name, gap = 1, paddingV = 3, align = "stretch" }, children)
end

local function message(glyph, text)
  return ui.column({ flexGrow = 1, align = "center", justify = "center", gap = 8 }, {
    ui.glyph({ name = glyph, size = 32, color = "on_surface_variant" }),
    ui.label({ text = text, color = "on_surface_variant" }),
  })
end

-- `data` is the service snapshot ({ groups, count }) or nil while loading.
-- `strings` = { title, count, loading, empty, refresh }.
-- `refresh` = { busy, onClick } for the header button, or nil to omit it.
function M.buildTree(data, columnCount, strings, onLaunch, refresh)
  local header = { ui.label({ text = strings.title, fontSize = 16, fontWeight = "bold", flexGrow = 1 }) }
  local refreshButton = nil
  if refresh ~= nil then
    refreshButton = ui.button({
      glyph = refresh.busy and "loader" or "refresh",
      width = 26,
      height = 26,
      glyphSize = 14,
      variant = "ghost",
      controlSize = "sm",
      tooltip = strings.refresh,
      onClick = refresh.onClick,
    })
  end
  local body
  if data == nil then
    body = message("loader", strings.loading)
  elseif #data.groups == 0 then
    body = message("apps-off", strings.empty)
  else
    table.insert(header, ui.label({ text = strings.count, color = "on_surface_variant", fontSize = 12 }))
    local columnNodes = {}
    for index, column in ipairs(M.balancedColumns(data.groups, columnCount)) do
      local nodes = {}
      for _, group in ipairs(column.groups) do table.insert(nodes, groupNode(group, onLaunch)) end
      table.insert(columnNodes, ui.column({ key = "column-" .. index, flexGrow = 1, gap = 8, align = "stretch" }, nodes))
    end
    body = ui.scroll({ flexGrow = 1, gap = 0 }, {
      ui.row({ key = "app-columns", gap = 22, align = "stretch" }, columnNodes),
    })
  end
  if refreshButton ~= nil then table.insert(header, refreshButton) end
  return ui.column({ key = "app-cheatsheet", flexGrow = 1, gap = 8, align = "stretch" }, {
    ui.row({ gap = 8, align = "center" }, header),
    body,
  })
end

-- ── Runtime ────────────────────────────────────────────────────────────────

local function outputWidth()
  local focused = noctalia.focusedOutputName()
  for _, output in ipairs(noctalia.outputs()) do
    if output.name == focused or output.focused then
      return output.width / math.max(output.scale or 1, 1)
    end
  end
  return 1920
end

local function launch(app)
  if not noctalia.commandExists("gio") then
    noctalia.notifyError(noctalia.tr("launch_failed"), noctalia.tr("gio_missing"))
    return
  end
  -- gio resolves the Exec line (field codes, Flatpak wrappers) itself.
  noctalia.runAsync({ "gio", "launch", app.path })
  panel.close()
end

local function requestRefresh()
  noctalia.state.set(FORCE_KEY, (tonumber(noctalia.state.get(FORCE_KEY)) or 0) + 1)
end

-- Building ~100 rows is the panel's only real cost, so the tree is reused
-- until something it depends on changes.
local cachedTree, cachedFor = nil, nil

local function render()
  local columns = M.columnCount(noctalia.getConfig("columns"), outputWidth())
  if cachedTree == nil or cachedFor.snapshot ~= snapshot or cachedFor.columns ~= columns or cachedFor.busy ~= busy then
    local strings = {
      title = noctalia.tr("title"),
      count = noctalia.tr("count", { count = snapshot ~= nil and snapshot.count or 0 }),
      loading = noctalia.tr("loading"),
      empty = noctalia.tr("empty"),
      refresh = noctalia.tr("refresh"),
    }
    cachedTree = M.buildTree(snapshot, columns, strings, launch, { busy = busy, onClick = requestRefresh })
    cachedFor = { snapshot = snapshot, columns = columns, busy = busy }
  end
  panel.render(cachedTree)
end

function onOpen(_context)
  panelOpen = true
  snapshot = noctalia.state.get(SNAPSHOT_KEY)
  busy = noctalia.state.get(BUSY_KEY) == true
  render()
  -- Ask the service for a light rescan so newly installed apps appear; known
  -- icons are reused and it only republishes when something changed.
  noctalia.state.set(REFRESH_KEY, (tonumber(noctalia.state.get(REFRESH_KEY)) or 0) + 1)
end

function onClose()
  panelOpen = false
end

function onConfigChanged()
  if panelOpen then render() end
end

function onIpc(event, _payload)
  if event == "toggle" then
    if panelOpen then panel.close() else noctalia.togglePanel("aalbayaty/app-cheatsheet:cheatsheet") end
  end
end

function M._start()
  noctalia.state.watch(SNAPSHOT_KEY, function(value)
    snapshot = value
    if panelOpen then render() end
  end)
  noctalia.state.watch(BUSY_KEY, function(value)
    busy = value == true
    if panelOpen then render() end
  end)
end

M.onOpen = function(context) onOpen(context) end

if _G.__APPCHEAT_TEST or noctalia == nil then return M end
M._start()
