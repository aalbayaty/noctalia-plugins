--!nonstrict
local M = {}

local function role(v)
  if v == nil or v == "" or v == "none" then return "on_surface" end
  return v
end

function M.colorRoleFor(cd, cfg, which)
  if cd.mode == "now" or cd.mode == "elapsed" then return role(cfg.activeColor) end
  return role(which == "glyph" and cfg.iconColor or cfg.textColor)
end

function M.buildTree(cd, cfg, isVertical)
  local glyph = ui.glyph({ name = cd.glyph, color = M.colorRoleFor(cd, cfg, "glyph") })
  local label = ui.label({ text = cd.text, color = M.colorRoleFor(cd, cfg, "text") })
  if isVertical then
    return ui.column({ gap = 2, align = "center" }, { glyph, label })
  end
  return ui.row({ gap = 6, align = "center" }, { glyph, label })
end

local function readCfg()
  return { textColor = noctalia.getConfig("textColor") or "none",
           iconColor = noctalia.getConfig("iconColor") or "none",
           activeColor = noctalia.getConfig("activeColor") or "primary" }
end

function M._start()
  local function render()
    local cd = noctalia.state.get("countdown") or { text = "…", glyph = "building-mosque", mode = "loading", color = "primary" }
    barWidget.render(M.buildTree(cd, readCfg(), barWidget.isVertical()))
    if cd.label and cd.next then barWidget.setTooltip(cd.label .. ": " .. (cd.time or "")) end
  end
  noctalia.state.watch("countdown", render)
  noctalia.state.watch("status", render)
  render()
end

function onClick()
  noctalia.togglePanel("aalbayaty/mawaqit:panel")
end

if _G.__MAWAQIT_TEST or noctalia == nil then return M end
M._start()
