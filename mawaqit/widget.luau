--!nonstrict
local M = {}

local function role(v) if v == nil or v == "" or v == "none" then return "on_surface" end return v end

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

if _G.__MAWAQIT_TEST or noctalia == nil then return M end
