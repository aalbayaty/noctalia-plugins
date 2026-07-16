--!nonstrict
local M = {}

-- Arabic calligraphic display font (loaded once in production via
-- noctalia.loadFont; nil in tests / before load, in which case ui labels
-- just fall back to the default font).
M.FONT = nil

-- ── Task 5.1: Header + date row ──────────────────────────────────────────────

function M.buildHeader()
  return ui.row({ gap = 8, align = "center" }, {
    ui.glyph({ name = "building-mosque", color = "primary" }),
    ui.label({ text = noctalia.tr("panel.title"), fontWeight = "bold" }),
    ui.spacer(),
    ui.button({ glyph = "refresh", onClick = "onRefresh" }),
    ui.button({ glyph = "x", onClick = "onClosePanel" }),
  })
end

function M.buildDateRow(hijri, gregorian)
  hijri = hijri or {}
  local hijriText = (hijri.displayAr ~= nil and hijri.displayAr ~= "") and hijri.displayAr or (hijri.display or "")
  return ui.row({ justify = "space_between", align = "center" }, {
    ui.label({ text = gregorian or "", color = "secondary" }),
    ui.label({ text = hijriText, fontFamily = M.FONT, color = "secondary" }),
  })
end

if _G.__MAWAQIT_TEST or noctalia == nil then return M end
