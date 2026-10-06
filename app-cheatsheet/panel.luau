--!nonstrict
-- Thin renderer for App Cheatsheet: draws the service's snapshot as balanced
-- columns of category blocks. Clicking a row launches the app and closes the
-- panel. No search by design; the Noctalia launcher already covers that.

local M = {}

local SNAPSHOT_KEY = "app-cheatsheet.snapshot"
local REFRESH_KEY = "app-cheatsheet.refresh"
local FALLBACK_GLYPH = "app-window"

local snapshot = nil
local panelOpen = false

-- Columns the output can fit at ~260px each, capped by the setting.
function M.columnCount(configured, outputWidth)
  local wanted = math.clamp(tonumber(configured) or 4, 1, 6)
  local fits = math.max(1, math.floor((outputWidth or 1920) / 260))
  return math.min(wanted, fits)
end

-- Greedy balance: each group goes to the currently shortest column, so the
-- groups keep their order reading down each column. A header counts as two rows.
function M.balancedColumns(groups, count)
  local columns = {}
  for index = 1, count do columns[index] = { groups = {}, weight = 0 } end
  for _, group in ipairs(groups) do
    local target = 1
    for index = 2, count do
      if columns[index].weight < columns[target].weight then target = index end
    end
    table.insert(columns[target].groups, group)
    columns[target].weight += #group.apps + 2
  end
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
-- `strings` = { title, count, loading, empty }.
function M.buildTree(data, columnCount, strings, onLaunch)
  local header = { ui.label({ text = strings.title, fontSize = 16, fontWeight = "bold", flexGrow = 1 }) }
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

local function render()
  local strings = {
    title = noctalia.tr("title"),
    count = noctalia.tr("count", { count = snapshot ~= nil and snapshot.count or 0 }),
    loading = noctalia.tr("loading"),
    empty = noctalia.tr("empty"),
  }
  panel.render(M.buildTree(snapshot, M.columnCount(noctalia.getConfig("columns"), outputWidth()), strings, launch))
end

function onOpen(_context)
  panelOpen = true
  snapshot = noctalia.state.get(SNAPSHOT_KEY)
  render()
  -- Ask the service to rescan so newly installed apps appear; it only
  -- republishes when something changed.
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
end

M.onOpen = function(context) onOpen(context) end

if _G.__APPCHEAT_TEST or noctalia == nil then return M end
M._start()
