--!nonstrict
-- Static bar entry: a glyph that toggles the panel. All data lives in the
-- service.

local PANEL_ID = "aalbayaty/app-cheatsheet:cheatsheet"

local function render()
  barWidget.setGlyph(noctalia.getConfig("glyph") or "apps")
  barWidget.setTooltip(noctalia.tr("widget_tooltip"))
end

function onClick()
  noctalia.togglePanel(PANEL_ID)
end

function onIpc(event, _payload)
  if event == "toggle" then noctalia.togglePanel(PANEL_ID) end
end

function onConfigChanged()
  render()
end

if noctalia ~= nil then render() end
