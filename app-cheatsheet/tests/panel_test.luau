--!nonstrict
-- Tests for the app-cheatsheet panel. Run: luau app-cheatsheet/tests/panel_test.luau
local H = require("./harness")
local M = H.loadEntry("../panel")

local STRINGS = { title = "Applications", count = "3 apps", loading = "loading", empty = "empty" }

local function group(name, n)
  local apps = {}
  for i = 1, n do
    apps[i] = { id = name .. i, name = name .. " " .. i, path = "/apps/" .. name .. i .. ".desktop", iconPath = i == 1 and "/icons/x.png" or nil }
  end
  return { name = name, apps = apps }
end

local function labels(tree)
  local out = {}
  for _, node in ipairs(H.find(tree, function(n) return n.type == "label" end)) do table.insert(out, node.props.text) end
  return table.concat(out, "|")
end

H.test("columnCount: capped by the setting and by the output width", function()
  H.eq(M.columnCount(4, 3440), 4, "wide")
  H.eq(M.columnCount(6, 1080), 4, "portrait monitor")
  H.eq(M.columnCount(nil, 1920), 4, "default")
  H.eq(M.columnCount(3, 200), 1, "never zero")
end)

H.test("balancedColumns: fills the shortest column, keeps order within a column", function()
  local columns = M.balancedColumns({ group("A", 10), group("B", 2), group("C", 2), group("D", 1) }, 2)
  H.eq(#columns, 2, "count")
  H.eq(columns[1].groups[1].name, "A", "big group alone")
  H.eq(#columns[1].groups, 1, "column 1")
  H.eq(columns[2].groups[1].name .. columns[2].groups[2].name .. columns[2].groups[3].name, "BCD", "column 2 in order")
end)

H.test("buildTree: loading and empty states", function()
  H.ok(labels(M.buildTree(nil, 3, STRINGS, function() end)):find("loading", 1, true) ~= nil, "loading")
  H.ok(labels(M.buildTree({ groups = {}, count = 0 }, 3, STRINGS, function() end)):find("empty", 1, true) ~= nil, "empty")
end)

H.test("buildTree: headers, rows, icons and click wiring", function()
  local launched
  local tree = M.buildTree({ groups = { group("Games", 2), group("Work", 1) }, count = 3 }, 2, STRINGS, function(app) launched = app end)
  local text = labels(tree)
  H.ok(text:find("GAMES", 1, true) ~= nil and text:find("WORK", 1, true) ~= nil, "upper-cased headers")
  H.ok(text:find("3 apps", 1, true) ~= nil, "count shown")
  local rows = H.find(tree, function(n) return n.type == "row" and n.props.onClick ~= nil end)
  H.eq(#rows, 3, "one clickable row per app")
  H.eq(#H.find(tree, function(n) return n.type == "image" end), 2, "resolved icons use images")
  H.eq(#H.find(tree, function(n) return n.type == "glyph" and n.props.name == "app-window" end), 1, "fallback glyph")
  rows[2].props.onClick()
  H.eq(launched.id, "Games2", "click launches that row's app")
end)

H.test("open: renders the snapshot, requests a rescan, click launches via gio and closes", function()
  H.reset()
  H.setConfig({ columns = 3 })
  M._start()
  H.noctalia.state.set("app-cheatsheet.snapshot", { groups = { group("Games", 1) }, count = 1 })
  H.eq(H.calls.renderCount, nil, "no render while closed")
  M.onOpen({})
  H.eq(H.calls.renderCount, 1, "rendered on open")
  H.eq(H.noctalia.state.get("app-cheatsheet.refresh"), 1, "rescan requested")
  local rows = H.find(H.calls.rendered, function(n) return n.type == "row" and n.props.onClick ~= nil end)
  rows[1].props.onClick()
  H.eq(table.concat(H.calls.runAsync[1], " "), "gio launch /apps/Games1.desktop", "argv launch")
  H.eq(H.calls.closed, 1, "panel closed")
  H.noctalia.state.set("app-cheatsheet.snapshot", { groups = {}, count = 0 })
  H.eq(H.calls.renderCount, 2, "re-renders on a new snapshot while open")
end)

H.test("launch: missing gio reports an error and keeps the panel open", function()
  H.reset()
  H.setCmdExists({})
  M._start()
  H.noctalia.state.set("app-cheatsheet.snapshot", { groups = { group("Games", 1) }, count = 1 })
  M.onOpen({})
  H.find(H.calls.rendered, function(n) return n.type == "row" and n.props.onClick ~= nil end)[1].props.onClick()
  H.eq(H.calls.runAsync, nil, "nothing launched")
  H.eq(H.calls.closed, nil, "not closed")
  H.eq(H.calls.notifyError[2], "gio_missing", "error shown")
end)

H.finish()
