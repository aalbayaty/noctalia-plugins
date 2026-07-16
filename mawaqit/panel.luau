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

-- ── Task 5.4: Panel assembly + interactions ──────────────────────────────────

-- Placeholder for tab 1 (Calendar) — the real calendar grid lands in Phase 6.
local function buildCalendarPlaceholder()
  return ui.box({ fill = "surface_variant", radius = 8 }, { ui.label({ text = noctalia.tr("panel.tab.calendar") }) })
end

-- state: { status, error, prayers, countdown, hijri, gregorian, event, hadith, isRamadan }
function M.buildTree(state, activeTab)
  state = state or {}
  local children = {
    M.buildHeader(),
    M.buildDateRow(state.hijri, state.gregorian),
    M.buildTabs(activeTab),
    M.buildHint(state.event),
  }
  if activeTab == 1 then
    table.insert(children, buildCalendarPlaceholder())
  else
    table.insert(children, M.buildStatus(state.status, state.error))
    table.insert(children, M.buildCountdownCard(state.countdown, state.isRamadan))
    table.insert(children, M.buildPrayerList(state.prayers))
  end
  return ui.column({ gap = 12 }, children)
end

-- Local UI-only state: active tab (0 = prayers, 1 = calendar) and the
-- currently-viewed calendar month/year (seeded from `hijri` state on open;
-- 1/1400 is just a placeholder until the real hijri date arrives or the
-- calendar tab (Phase 6) picks its own).
local _activeTab = 0
local _viewMonth = 1
local _viewYear = 1400
local _subscribed = false

local function readState()
  return {
    status = noctalia.state.get("status"),
    error = noctalia.state.get("error"),
    prayers = noctalia.state.get("prayers"),
    countdown = noctalia.state.get("countdown"),
    hijri = noctalia.state.get("hijri"),
    gregorian = noctalia.state.get("gregorian"),
    event = noctalia.state.get("event"),
    hadith = noctalia.state.get("hadith"),
    isRamadan = noctalia.state.get("isRamadan"),
  }
end

function M._render()
  panel.render(M.buildTree(readState(), _activeTab))
end

local function subscribeOnce()
  if _subscribed then return end
  _subscribed = true
  noctalia.state.watch("countdown", M._render)
  noctalia.state.watch("prayers", M._render)
  noctalia.state.watch("calendar", M._render)
  noctalia.state.watch("hijri", M._render)
  noctalia.state.watch("event", M._render)
  noctalia.state.watch("hadith", M._render)
  noctalia.state.watch("status", M._render)
end

function onOpen(context)
  subscribeOnce()
  local hijri = noctalia.state.get("hijri")
  if hijri and hijri.month and hijri.month > 0 and hijri.year and hijri.year > 0 then
    _viewMonth = hijri.month
    _viewYear = hijri.year
  end
  M._render()
end

function onClose()
end

function onRefresh()
  noctalia.state.set("command", { action = "refresh", ts = os.time() })
  M._render()
end

function onClosePanel()
  panel.close()
end

function onTabPrayers()
  _activeTab = 0
  M._render()
end

function onTabCalendar()
  _activeTab = 1
  noctalia.state.set("command", { action = "calendar", ts = os.time(), month = _viewMonth, year = _viewYear })
  M._render()
end

-- Panels start on `onOpen` (host-driven), not at load time — no `M._start()` here.
if _G.__MAWAQIT_TEST or noctalia == nil then return M end
