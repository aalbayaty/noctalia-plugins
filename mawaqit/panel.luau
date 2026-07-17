--!nonstrict
local M = {}

-- Arabic calligraphic display font (loaded once in production via
-- noctalia.loadFont; nil in tests / before load, in which case ui labels
-- just fall back to the default font).
M.FONT = nil

-- ── Task 5.1: Header + date row ──────────────────────────────────────────────

function M.buildHeader()
  local city = noctalia.getConfig("city") or ""
  return ui.row({ gap = 8, align = "center" }, {
    ui.glyph({ name = "building-mosque", color = "primary" }),
    ui.column({ gap = 0 }, {
      ui.label({ text = noctalia.tr("panel.title"), fontWeight = "bold" }),
      (city ~= "") and ui.label({ text = city, color = "secondary", fontSize = 12 }) or ui.spacer(),
    }),
    ui.spacer(),
    ui.button({ glyph = "refresh", onClick = "onRefresh" }),
    ui.button({ glyph = "x", onClick = "onClosePanel" }),
  })
end

function M.buildDateRow(hijri, gregorian, onClick)
  hijri = hijri or {}
  local hijriText = (hijri.displayAr ~= nil and hijri.displayAr ~= "") and hijri.displayAr or (hijri.display or "")
  if onClick then
    return ui.row({ justify = "space_between", align = "center" }, {
      ui.button({ text = gregorian or "", variant = "ghost", color = "secondary", fontSize = 18, onClick = onClick }),
      ui.button({ text = hijriText, variant = "ghost", color = "secondary", fontFamily = M.FONT, fontSize = 18, onClick = onClick }),
    })
  end
  return ui.row({ justify = "space_between", align = "center" }, {
    ui.label({ text = gregorian or "", color = "secondary", fontSize = 18 }),
    ui.label({ text = hijriText, fontFamily = M.FONT, color = "secondary", fontSize = 18 }),
  })
end

-- ── Task 5.2: Tabs + countdown card ──────────────────────────────────────────

-- Segmented tab bar: two equal-width halves inside one rounded container.
-- ui.button has no `radius` prop and Noctalia has no per-corner radius, so we
-- round only the OUTER sides by letting the container's `radius` clip its
-- children; the inner seam (gap = 0) stays flat. The active half's `primary`
-- fill lives on the clipped `ui.column` (not on the button's `variant`, whose
-- own fill would overflow the rounded corner and look square) — a transparent
-- `ghost` button inside is just the click target + label.
local function tabHalf(key, textKey, active, onClick)
  return ui.column({
    flexGrow = 1,
    fill = active and "primary" or "#00000000",
    align = "center",
    justify = "center",
  }, {
    ui.button({
      key = key,
      text = noctalia.tr(textKey),
      variant = active and "primary" or "ghost",
      flexGrow = 1,
      onClick = onClick,
    }),
  })
end

function M.buildTabs(activeTab)
  return ui.row({ gap = 0, radius = 999, fill = "surface_variant/0.4" }, {
    tabHalf("tab_prayers", "panel.tab.prayers", activeTab == 0, "onTabPrayers"),
    tabHalf("tab_calendar", "panel.tab.calendar", activeTab == 1, "onTabCalendar"),
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
      table.insert(children, ui.label({ text = "حان الآن موعد صلاة " .. arName, color = color, fontFamily = M.FONT, fontSize = 16 }))
    end
  end

  table.insert(children, ui.label({ text = countdown.label or "", color = color }))
  table.insert(children, ui.label({ text = countdown.text or "", fontSize = 28, fontWeight = "bold", color = color }))

  return ui.box({ fill = color .. "/0.12", radius = 12 }, {
    ui.column({ gap = 4, align = "center" }, children),
  })
end

-- ── Task 5.3: Prayer list + hint banner + status/error ───────────────────────

local function rowFill(highlight)
  if highlight == "next" then return "primary/0.15" end
  if highlight == "imsak" then return "secondary/0.08" end
  if highlight == "maghrib" then return "tertiary/0.08" end
  return "surface_variant"
end

function M.buildPrayerList(prayers)
  local rows = {}
  for _, p in ipairs(prayers or {}) do
    table.insert(rows, ui.row({ fill = rowFill(p.highlight), gap = 6, align = "center" }, {
      ui.glyph({ name = p.glyph or "building-mosque" }),
      ui.label({ text = p.label, fontSize = 19 }),
      ui.spacer(),
      ui.label({ text = p.time or "—", fontSize = 19 }),
    }))
  end
  return ui.column({ gap = 4 }, rows)
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

-- ── Task 6.3: Calendar tab renderer ──────────────────────────────────────────
-- Ported from /tmp/legacy-v4-plugins/mawaqit/Panel.qml's calItem (nav row,
-- weekday header, day Grid delegate, today's-event Text, last-10-nights
-- Rectangle, daily-Hadith ColumnLayout, last-synced NText, ~L693-905).

-- Mirrors service.luau's M.isLastTenNights(hmonth, hday, monthDays) — panel.luau
-- can't `require` service.luau, so this tiny check is intentionally duplicated
-- (keep the two in sync by hand if the Ramadan last-10-nights rule changes).
local function calIsLastTenNights(hijri)
  if not hijri or hijri.month ~= 9 then return false end
  local hday = hijri.day or 0
  local monthDays = hijri.days or 30
  return hday >= 20 and not (hday == 29 and monthDays == 29)
end

local function isCurrentCalMonth(calendar, hijri)
  return hijri ~= nil and calendar.month == hijri.month and calendar.year == hijri.year
end

function M.buildCalNav(calendar)
  local label = (calendar.monthNameEn or "") .. "  " .. tostring(calendar.year or "")
  local isRamadan = calendar.month == 9
  return ui.row({ justify = "space_between", align = "center" }, {
    ui.button({ glyph = "chevron-left", onClick = "onCalPrev" }),
    ui.column({ gap = 1, align = "center" }, {
      ui.label({ text = label, fontWeight = "bold", textAlign = "center", color = isRamadan and "primary" or nil }),
      ui.row({ gap = 4, align = "center" }, {
        ui.glyph({ name = calendar.synced and "shield-check" or "calculator", color = calendar.synced and "primary" or "secondary" }),
        ui.label({ text = calendar.gregRange or "", color = "secondary" }),
      }),
    }),
    ui.button({ glyph = "chevron-right", onClick = "onCalNext" }),
  })
end

function M.buildCalBackToToday(calendar, hijri)
  if isCurrentCalMonth(calendar, hijri) then return ui.spacer() end
  return ui.row({ justify = "center" }, {
    ui.button({ text = "↩ " .. noctalia.tr("calendar.today"), variant = "ghost", onClick = "onCalToday" }),
  })
end

-- Weekday abbreviation keys, in the fixed Mo..Su order used to rotate by
-- weekStartDay (mirrors v4's `all = ["Mo","Tu","We","Th","Fr","Sa","Su"]`).
-- Index 5 is always "Fr" — the Jumu'ah column — regardless of rotation.
local WEEKDAY_KEYS = { "calendar.weekday.mo", "calendar.weekday.tu", "calendar.weekday.we",
  "calendar.weekday.th", "calendar.weekday.fr", "calendar.weekday.sa", "calendar.weekday.su" }

-- Shared calendar column width so the weekday header cells sit directly above
-- the day cells (both use this width + justify = "space_between").
local CAL_CELL_W = 44

function M.buildCalWeekdayHeader(weekStartDay)
  local offset = ((weekStartDay or 1) + 6) % 7
  local cells = {}
  for i = 0, 6 do
    local idx = (offset + i) % 7 + 1
    table.insert(cells, ui.column({ width = CAL_CELL_W, align = "center" }, {
      ui.label({ text = noctalia.tr(WEEKDAY_KEYS[idx]), fontSize = 15, fontWeight = "bold",
        color = (idx == 5) and "primary" or "secondary", textAlign = "center" }),
    }))
  end
  return ui.row({ justify = "space_between" }, cells)
end

-- One day cell: a ui.column with fill/radius (both supported on column/row,
-- which — unlike ui.box — also render their children) holding the day number
-- label and an optional event-dot + gregorian-overlay row.
-- ui.button does NOT support fill/radius/color/fontWeight (silently ignored),
-- and ui.box is a leaf visual that ignores children, so ui.column is the right
-- container for a filled, rounded cell that shows text.
local function calDayCell(cell)
  local textColor = nil
  if cell.isToday then textColor = "on_primary"
  elseif cell.isPast then textColor = "on_surface/0.3"
  elseif cell.isFriday then textColor = "primary"
  elseif cell.eventAr then textColor = "tertiary"
  end

  local dayLabel = ui.label({
    text = tostring(cell.hday),
    color = textColor,
    fontWeight = cell.isToday and "bold" or "normal",
    fontSize = 17,
    textAlign = "center",
  })

  local children = { dayLabel }
  if (cell.eventAr and not cell.isToday) or cell.gday then
    local extras = {}
    if cell.eventAr and not cell.isToday then
      table.insert(extras, ui.box({ fill = cell.isPast and "tertiary/0.3" or "tertiary", radius = 2, width = 4, height = 4 }))
    end
    if cell.gday then
      table.insert(extras, ui.label({ text = tostring(cell.gday), fontSize = 10,
        color = cell.isToday and "on_primary/0.6" or "secondary/0.6", textAlign = "center" }))
    end
    table.insert(children, ui.row({ gap = 2, align = "center", justify = "center" }, extras))
  end

  return ui.column({
    fill = cell.isToday and "primary" or "#00000000",
    radius = 999,
    width = CAL_CELL_W,
    height = 40,
    align = "center",
    justify = "center",
    gap = 1,
  }, children)
end

-- A blank placeholder that occupies the same 40×32 footprint as a day cell so
-- the 7-column grid stays aligned. Uses #00000000 (alpha 0) for true
-- transparency ("transparent" is not a valid palette role).
local function calBlankCell()
  return ui.column({ width = CAL_CELL_W, height = 40, fill = "#00000000" })
end

-- The 7-col day grid: `calendar.leadingBlanks` leading placeholder cells, then
-- calendar.cells day columns, then trailing placeholder padding out to a
-- full multiple of 7 — mirrors v4's `Math.ceil(filledCount/7)*7` padding
-- (Panel.qml:607-612) so every row has exactly 7 cells and columns stay
-- aligned with the weekday header above (a ragged last row would get spread
-- across the full width by `justify = "space_between"` and misalign).
function M.buildCalGrid(calendar)
  local flat = {}
  for _ = 1, (calendar.leadingBlanks or 0) do
    table.insert(flat, calBlankCell())
  end
  for _, cell in ipairs(calendar.cells or {}) do
    table.insert(flat, calDayCell(cell))
  end
  local needed = math.ceil(#flat / 7) * 7
  for _ = #flat + 1, needed do
    table.insert(flat, calBlankCell())
  end

  local rows, row = {}, {}
  for _, node in ipairs(flat) do
    table.insert(row, node)
    if #row == 7 then
      table.insert(rows, ui.row({ justify = "space_between" }, row))
      row = {}
    end
  end
  return ui.column({ gap = 2 }, rows)
end

-- Today's event line ("🌙 <eventAr>"), only for the currently-viewed month
-- being the real current Hijri month, and only when the last-10-nights
-- banner isn't already showing (mirrors v4's `!root.showLast10Nights` gate).
function M.buildCalTodayEvent(calendar, hijri, showLast10)
  if showLast10 or not isCurrentCalMonth(calendar, hijri) then return ui.spacer() end
  local cell = calendar.cells and hijri and calendar.cells[hijri.day]
  local eventAr = cell and cell.eventAr
  if not eventAr or eventAr == "" then return ui.spacer() end
  return ui.label({ text = "🌙 " .. eventAr, color = "tertiary", fontFamily = M.FONT, textAlign = "center" })
end

function M.buildCalLast10Banner(calendar, hijri, showLast10)
  if not (showLast10 and isCurrentCalMonth(calendar, hijri)) then return ui.spacer() end
  return ui.box({ fill = "primary/0.08", radius = 12 }, {
    ui.label({ text = "العشر الأواخر\nأفضل ليالي رمضان، فيها ليلة القدر خير من ألف شهر", color = "primary", fontFamily = M.FONT, textAlign = "center" }),
  })
end

function M.buildCalHadith(hadith, showLast10)
  if showLast10 or hadith == nil then return ui.spacer() end
  return ui.column({ gap = 2 }, {
    ui.separator({}),
    ui.label({ text = hadith.text or "", fontFamily = M.FONT, textAlign = "center" }),
    ui.label({ text = (hadith.source ~= nil and hadith.source ~= "") and ("― " .. hadith.source) or "", color = "secondary", textAlign = "center" }),
  })
end

-- M.buildCalendarTab(calendar, hijri, gregorian, hadith) — full calendar tab:
-- nav row, weekday header, 7-col grid, today's-event line, and the
-- last-10-nights banner.
function M.buildCalendarTab(calendar, hijri, gregorian, hadith)
  calendar = calendar or {}
  local showLast10 = calIsLastTenNights(hijri)
  return ui.column({ gap = 8 }, {
    M.buildCalNav(calendar),
    M.buildCalWeekdayHeader(calendar.weekStartDay),
    ui.separator({}),
    M.buildCalGrid(calendar),
    M.buildCalTodayEvent(calendar, hijri, showLast10),
    M.buildCalLast10Banner(calendar, hijri, showLast10),
  })
end

-- ── Task 5.4: Panel assembly + interactions ──────────────────────────────────

-- state: { status, error, prayers, countdown, hijri, gregorian, event, hadith,
--          isRamadan, calendar }
function M.buildTree(state, activeTab)
  state = state or {}
  local children = {
    M.buildHeader(),
    M.buildDateRow(state.hijri, state.gregorian),
    M.buildTabs(activeTab),
    M.buildHint(state.event),
  }
  if activeTab == 1 then
    table.insert(children, M.buildCalendarTab(state.calendar, state.hijri, state.gregorian, state.hadith))
  else
    table.insert(children, M.buildStatus(state.status, state.error))
    table.insert(children, M.buildCountdownCard(state.countdown, state.isRamadan))
    table.insert(children, M.buildPrayerList(state.prayers))
    table.insert(children, M.buildCalHadith(state.hadith, false))
  end
  return ui.column({ gap = 8 }, children)
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
    calendar = noctalia.state.get("calendar"),
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

-- Loads the Arabic calligraphic DecoType font once (Phase 7 ships the actual
-- fonts/DecoType.ttf asset; until then — and in tests, where noctalia.loadFont
-- isn't mocked at all — the pcall fails and M.FONT just stays nil, falling
-- back to the default font everywhere fontFamily = M.FONT is used).
local function ensureFontLoaded()
  if M.FONT ~= nil then return end
  local ok, family = pcall(noctalia.loadFont, "fonts/DecoType.ttf")
  if ok and family then M.FONT = family end
end

function onOpen(context)
  subscribeOnce()
  ensureFontLoaded()
  local hijri = noctalia.state.get("hijri")
  if hijri and hijri.month and hijri.month > 0 and hijri.year and hijri.year > 0 then
    _viewMonth = hijri.month
    _viewYear = hijri.year
  end
  M._render()
end

function onClose()
end

function onCalRefresh()
  noctalia.state.set("command", { action = "calendarRefresh", ts = os.time(), month = _viewMonth, year = _viewYear })
  M._render()
end

function onRefresh()
  if _activeTab == 1 then
    onCalRefresh()
    return
  end
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
  if _activeTab == 1 then
    onCalToday()
    return
  end
  _activeTab = 1
  noctalia.state.set("command", { action = "calendar", ts = os.time(), month = _viewMonth, year = _viewYear })
  M._render()
end

-- Hijri month wraps 1..12; a wrap also steps the year (per v4's
-- calItem.navigate(): forward wraps m>12 -> m=1,y++; backward wraps m<1 ->
-- m=12,y--).
local function wrapHijriMonth(month, year, delta)
  local m, y = month + delta, year
  if m > 12 then m = 1; y = y + 1 end
  if m < 1 then m = 12; y = y - 1 end
  return m, y
end

function onCalPrev()
  _viewMonth, _viewYear = wrapHijriMonth(_viewMonth, _viewYear, -1)
  noctalia.state.set("command", { action = "calendar", ts = os.time(), month = _viewMonth, year = _viewYear })
  M._render()
end

function onCalNext()
  _viewMonth, _viewYear = wrapHijriMonth(_viewMonth, _viewYear, 1)
  noctalia.state.set("command", { action = "calendar", ts = os.time(), month = _viewMonth, year = _viewYear })
  M._render()
end

function onCalToday()
  local hijri = noctalia.state.get("hijri")
  if hijri and hijri.month and hijri.month > 0 and hijri.year and hijri.year > 0 then
    _viewMonth = hijri.month
    _viewYear = hijri.year
  end
  noctalia.state.set("command", { action = "calendar", ts = os.time(), month = _viewMonth, year = _viewYear })
  M._render()
end

-- Panels start on `onOpen` (host-driven), not at load time — no `M._start()` here.
if _G.__MAWAQIT_TEST or noctalia == nil then return M end
