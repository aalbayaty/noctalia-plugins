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

-- ── Task 5.3: Prayer list + hint banner + status/error ───────────────────────

-- The panel can't `require` service.luau (sandbox has no `require`), so this
-- tiny prayer→glyph map is intentionally duplicated from service.luau's
-- `M.PRAYER_GLYPHS` — keep the two in sync by hand if prayer keys/icons change.
local PRAYER_GLYPHS = { Imsak = "moon", Fajr = "sun-moon", Sunrise = "sunrise", Dhuhr = "sun-high",
  Asr = "sun-low", Maghrib = "sunset", Isha = "moon-stars" }

function M.rowGlyph(key)
  return PRAYER_GLYPHS[key] or "building-mosque"
end

local function rowFill(highlight)
  if highlight == "next" then return "primary/0.15" end
  if highlight == "imsak" then return "secondary/0.08" end
  if highlight == "maghrib" then return "tertiary/0.08" end
  return "surface_variant"
end

function M.buildPrayerList(prayers)
  local rows = {}
  for _, p in ipairs(prayers or {}) do
    table.insert(rows, ui.row({ fill = rowFill(p.highlight), gap = 8, align = "center" }, {
      ui.glyph({ name = M.rowGlyph(p.key) }),
      ui.label({ text = p.label }),
      ui.spacer(),
      ui.label({ text = p.time or "—" }),
    }))
  end
  return ui.column({ gap = 6 }, rows)
end

function M.buildHint(event)
  if event == nil then return ui.spacer() end
  return ui.box({ fill = "tertiary/0.10", radius = 8 }, {
    ui.row({ justify = "space_between", align = "center" }, {
      ui.label({ text = event.whenText or "", color = "tertiary" }),
      ui.label({ text = event.nameAr or "", color = "tertiary", fontFamily = M.FONT }),
    }),
  })
end

function M.buildStatus(status, err)
  if status == "loading" then
    return ui.row({ align = "center", gap = 6 }, { ui.progress({ indeterminate = true }), ui.label({ text = noctalia.tr("calendar.syncing") }) })
  end
  if status == "error" then
    local text = (err ~= nil and err ~= "") and err or noctalia.tr("error.generic")
    return ui.label({ text = text, color = "error" })
  end
  return ui.spacer()
end

if _G.__MAWAQIT_TEST or noctalia == nil then return M end
