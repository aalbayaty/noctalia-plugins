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

-- ── Task 5.2: Tabs + countdown card ──────────────────────────────────────────

function M.buildTabs(activeTab)
  return ui.row({ gap = 4 }, {
    ui.button({ text = noctalia.tr("panel.tab.prayers"), variant = (activeTab == 0) and "primary" or "ghost", onClick = "onTabPrayers" }),
    ui.button({ text = noctalia.tr("panel.tab.calendar"), variant = (activeTab == 1) and "primary" or "ghost", onClick = "onTabCalendar" }),
  })
end

-- Arabic prayer names for the "now" grace-window line, ported from
-- Panel.qml's `arNames` (~L462). Kept minimal/local — the service owns the
-- canonical `M._PRAYER_NAMES_AR` map; this file can't `require` it.
local COUNTDOWN_NAMES_AR = { Fajr = "الفجر", Dhuhr = "الظهر", Asr = "العصر", Maghrib = "المغرب", Isha = "العشاء", Imsak = "الإمساك" }

function M.buildCountdownCard(countdown, isRamadan)
  countdown = countdown or {}
  local color = countdown.color or "primary"
  local children = {}

  if countdown.mode == "now" and countdown.next then
    local arName = COUNTDOWN_NAMES_AR[countdown.next] or ""
    if arName ~= "" then
      table.insert(children, ui.label({ text = "حان الآن موعد صلاة " .. arName, color = color, fontFamily = M.FONT }))
    end
  end

  table.insert(children, ui.label({ text = countdown.label or "", color = color }))
  table.insert(children, ui.label({ text = countdown.text or "", fontSize = 28, fontWeight = "bold", color = color }))

  return ui.box({ fill = color .. "/0.12", radius = 12, align = "center" }, {
    ui.column({ gap = 4, align = "center" }, children),
  })
end

if _G.__MAWAQIT_TEST or noctalia == nil then return M end
