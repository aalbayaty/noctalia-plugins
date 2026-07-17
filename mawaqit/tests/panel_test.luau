--!nonstrict
local H = require("./harness")
local M = H.loadEntry("../panel")

H.test("header buttons", function()
  local h = M.buildHeader()
  local btns = H.findAll(h, function(n) return n.type == "button" end)
  H.ok(#btns >= 2, "refresh + close")
  local names = {} for _, b in ipairs(btns) do names[b.props.onClick or ""] = true end
  H.ok(names["onRefresh"], "refresh cb"); H.ok(names["onClosePanel"], "close cb")
end)
H.test("date row prefers arabic hijri", function()
  local r = M.buildDateRow({ display = "1 Muharram 1448 AH", displayAr = "١ محرم ١٤٤٨" }, "16 Jul 2026")
  local found = H.find(r, function(n) return n.type == "label" and n.props.text == "١ محرم ١٤٤٨" end)
  H.truthy(found, "arabic hijri shown")
end)

H.test("tabs render two buttons with active variant", function()
  local t0 = M.buildTabs(0)
  local btns = H.findAll(t0, function(n) return n.type == "button" end)
  H.eq(#btns, 2, "two tab buttons")
  H.eq(btns[1].props.variant, "primary", "prayers active")
  H.eq(btns[2].props.variant, "ghost", "calendar inactive")
  H.eq(btns[1].props.onClick, "onTabPrayers", "prayers cb")
  H.eq(btns[2].props.onClick, "onTabCalendar", "calendar cb")
  local t1 = M.buildTabs(1)
  local btns1 = H.findAll(t1, function(n) return n.type == "button" end)
  H.eq(btns1[1].props.variant, "ghost", "prayers inactive when tab1")
  H.eq(btns1[2].props.variant, "primary", "calendar active when tab1")
end)
H.test("countdown card fill + big text", function()
  local cd = { text = "Fajr 10m", color = "primary", mode = "countdown", label = "Fajr", next = "Fajr" }
  local card = M.buildCountdownCard(cd, false)
  H.eq(card.type, "box", "card is a box")
  H.eq(card.props.fill, "primary/0.12", "fill from countdown color")
  local big = H.find(card, function(n) return n.type == "label" and n.props.text == "Fajr 10m" end)
  H.truthy(big, "big countdown text present")
  H.eq(big.props.fontSize, 28, "big font size")
end)
H.test("countdown card shows Arabic now line when mode is now", function()
  local cd = { text = "Fajr — Now", color = "primary", mode = "now", label = "Fajr", next = "Fajr" }
  local card = M.buildCountdownCard(cd, false)
  local nowLine = H.find(card, function(n) return n.type == "label" and n.props.text and n.props.text:find("حان الآن") ~= nil end)
  H.truthy(nowLine, "arabic now line present")
end)
H.test("countdown card omits Arabic now line otherwise", function()
  local cd = { text = "Fajr 10m", color = "primary", mode = "countdown", label = "Fajr", next = "Fajr" }
  local card = M.buildCountdownCard(cd, false)
  local nowLine = H.find(card, function(n) return n.type == "label" and n.props.text and n.props.text:find("حان الآن") ~= nil end)
  H.eq(nowLine, nil, "no arabic now line in countdown mode")
end)

H.test("prayer list one row per prayer", function()
  local prayers = {
    { key="Fajr", label="Fajr", time="02:50", isNext=true, highlight="next" },
    { key="Dhuhr", label="Dhuhr", time="13:05", isNext=false, highlight=nil },
  }
  local list = M.buildPrayerList(prayers)
  local rows = H.findAll(list, function(n) return n.type == "row" end)
  H.eq(#rows, 2, "one row per prayer")
end)
H.test("next-prayer row highlight fill", function()
  local prayers = { { key="Fajr", label="Fajr", time="02:50", isNext=true, highlight="next" } }
  local list = M.buildPrayerList(prayers)
  local row = H.find(list, function(n) return n.type == "row" end)
  H.eq(row.props.fill, "primary/0.15", "next row fill")
end)
H.test("imsak-in-ramadan row highlight fill", function()
  local prayers = { { key="Imsak", label="Imsak", time="02:40", isNext=false, highlight="imsak" } }
  local list = M.buildPrayerList(prayers)
  local row = H.find(list, function(n) return n.type == "row" end)
  H.eq(row.props.fill, "secondary/0.08", "imsak row fill")
end)
H.test("maghrib-in-ramadan row highlight fill", function()
  local prayers = { { key="Maghrib", label="Maghrib", time="21:07", isNext=false, highlight="maghrib" } }
  local list = M.buildPrayerList(prayers)
  local row = H.find(list, function(n) return n.type == "row" end)
  H.eq(row.props.fill, "tertiary/0.08", "maghrib row fill")
end)
H.test("plain row uses surface_variant fill", function()
  local prayers = { { key="Asr", label="Asr", time="17:20", isNext=false, highlight=nil } }
  local list = M.buildPrayerList(prayers)
  local row = H.find(list, function(n) return n.type == "row" end)
  H.eq(row.props.fill, "surface_variant", "plain row fill")
end)
H.test("prayer list renders the published Jumuah-aware glyph for Dhuhr on Friday", function()
  local prayers = {
    { key="Fajr", label="Fajr", time="02:50", isNext=false, highlight="none" },
    { key="Dhuhr", label="Jumu'ah", glyph="building-mosque", time="13:05", isNext=false, highlight="none" },
    { key="Asr", label="Asr", time="17:20", isNext=false, highlight="none" },
  }
  local list = M.buildPrayerList(prayers)
  local dhuhrRow = H.find(list, function(n)
    return n.type == "row" and H.find(n, function(c) return c.type == "label" and c.props.text == "Jumu'ah" end) ~= nil
  end)
  H.truthy(dhuhrRow, "dhuhr row found")
  local glyphNode = H.find(dhuhrRow, function(n) return n.type == "glyph" end)
  H.truthy(glyphNode, "glyph node present")
  H.eq(glyphNode.props.name, "building-mosque", "dhuhr uses published jumuah glyph, not the duplicated non-jumuah map")
end)
H.test("hint banner shows event text", function()
  local hint = M.buildHint({ whenText = "Today", nameAr = "جمعة مباركة" })
  local when = H.find(hint, function(n) return n.type == "label" and n.props.text == "Today" end)
  local ar = H.find(hint, function(n) return n.type == "label" and n.props.text == "جمعة مباركة" end)
  H.truthy(when, "whenText shown"); H.truthy(ar, "nameAr shown")
end)
H.test("hint banner is spacer when no event", function()
  local hint = M.buildHint(nil)
  H.eq(hint.type, "spacer", "spacer when nil")
end)
H.test("status strip shows busy on loading", function()
  local s = M.buildStatus("loading", "")
  local busy = H.find(s, function(n) return n.type == "label" or n.type == "progress" end)
  H.truthy(busy, "busy indicator present")
end)
H.test("status strip shows error text", function()
  local s = M.buildStatus("error", "Could not load prayer times")
  local err = H.find(s, function(n) return n.type == "label" and n.props.color == "error" end)
  H.truthy(err, "error label present")
  H.eq(err.props.text, "Could not load prayer times", "error text")
end)
H.test("status strip is empty on ok", function()
  local s = M.buildStatus("ok", "")
  H.eq(s.type, "spacer", "spacer on ok")
end)

-- ── Task 6.3: M.buildCalendarTab (calendar tab renderer) ────────────────────
local function makeCalendar(overrides)
  local cells = {}
  for d = 1, 30 do
    cells[d] = { hday = d, gday = tostring(d), isToday = false, isPast = false, isFriday = false, eventAr = nil }
  end
  cells[5].isToday = true
  cells[12].eventAr = "عاشوراء"
  local cal = {
    month = 1, year = 1448, monthNameEn = "Muharram", synced = true, syncedAt = "16 Jul, 08:00",
    gregRange = "Jul 2026", weekStartDay = 1, leadingBlanks = 6, cells = cells,
  }
  for k, v in pairs(overrides or {}) do cal[k] = v end
  return cal
end

H.test("buildCalGrid child count == full 7-col rows (leadingBlanks + #cells, padded)", function()
  local cal = makeCalendar()
  local grid = M.buildCalGrid(cal)
  local count = 0
  for _, row in ipairs(grid.children or {}) do count = count + #(row.children or {}) end
  local filledCount = cal.leadingBlanks + #cal.cells
  local expected = math.ceil(filledCount / 7) * 7
  H.eq(count, expected, "padded to a multiple of 7")
end)

H.test("buildCalGrid rows are all exactly 7 cells wide (rectangle, no ragged last row)", function()
  local cal = makeCalendar()
  local grid = M.buildCalGrid(cal)
  local rows = grid.children or {}
  H.ok(#rows > 0, "grid has rows")
  for i, row in ipairs(rows) do
    H.eq(#(row.children or {}), 7, "row " .. i .. " has exactly 7 children")
  end
end)

H.test("buildCalGrid today cell gets the primary circle fill", function()
  local cal = makeCalendar()
  local grid = M.buildCalGrid(cal)
  local today = H.find(grid, function(n) return n.type == "button" and n.props.fill == "primary" end)
  H.truthy(today, "today cell filled primary")
end)

H.test("buildCalGrid event cell contains a dot indicator node", function()
  local cal = makeCalendar()
  local grid = M.buildCalGrid(cal)
  local dot = H.find(grid, function(n) return n.type == "box" and n.props.dot == true end)
  H.truthy(dot, "event dot rendered as a nested box")
end)

H.test("buildCalNav chevrons carry onCalPrev/onCalNext", function()
  local cal = makeCalendar()
  local nav = M.buildCalNav(cal)
  local prev = H.find(nav, function(n) return n.type == "button" and n.props.glyph == "chevron-left" end)
  local nxt = H.find(nav, function(n) return n.type == "button" and n.props.glyph == "chevron-right" end)
  H.truthy(prev, "prev button present"); H.eq(prev.props.onClick, "onCalPrev", "prev cb")
  H.truthy(nxt, "next button present"); H.eq(nxt.props.onClick, "onCalNext", "next cb")
end)

H.test("buildCalNav shows sync glyph when synced, calculator when estimated", function()
  local synced = M.buildCalNav(makeCalendar({ synced = true }))
  local est = M.buildCalNav(makeCalendar({ synced = false }))
  H.truthy(H.find(synced, function(n) return n.type == "glyph" and n.props.name == "shield-check" end), "synced glyph")
  H.truthy(H.find(est, function(n) return n.type == "glyph" and n.props.name == "calculator" end), "estimate glyph")
end)

H.test("buildCalNav month label is primary during Ramadan, default otherwise", function()
  local ramadan = M.buildCalNav(makeCalendar({ month = 9, monthNameEn = "Ramadan" }))
  local ramadanLabel = H.find(ramadan, function(n) return n.type == "label" and n.props.text:find("Ramadan") ~= nil end)
  H.truthy(ramadanLabel, "ramadan month label present")
  H.eq(ramadanLabel.props.color, "primary", "ramadan month label is primary")

  local muharram = M.buildCalNav(makeCalendar({ month = 1, monthNameEn = "Muharram" }))
  local muharramLabel = H.find(muharram, function(n) return n.type == "label" and n.props.text:find("Muharram") ~= nil end)
  H.truthy(muharramLabel, "muharram month label present")
  H.eq(muharramLabel.props.color, nil, "non-ramadan month label keeps default color")
end)

H.test("buildCalendarTab date row is clickable and goes back to today", function()
  local tree = M.buildCalendarTab(makeCalendar(), { day = 5, month = 1, year = 1448, days = 30 }, "16 Jul 2026", nil)
  local todayBtn = H.find(tree, function(n) return n.type == "button" and n.props.onClick == "onCalToday" end)
  H.truthy(todayBtn, "date row in calendar tab is clickable for onCalToday")
end)

H.test("buildCalendarTab renders the hadith block", function()
  local cal = makeCalendar()
  local tree = M.buildCalendarTab(cal, { day = 5, month = 1, year = 1448, days = 30 }, "16 Jul 2026", { text = "hadith text", source = "البخاري" })
  H.truthy(H.find(tree, function(n) return n.type == "label" and n.props.text == "hadith text" end), "hadith text shown")
  H.truthy(H.find(tree, function(n) return n.type == "label" and n.props.text == "― البخاري" end), "hadith source shown")
end)

H.test("buildCalendarTab shows the last-10-nights banner and suppresses hadith during it", function()
  local cal = makeCalendar({ month = 9, monthNameEn = "Ramadan" })
  local hijri = { day = 22, month = 9, year = 1448, days = 30 }
  local tree = M.buildCalendarTab(cal, hijri, "16 Jul 2026", { text = "hadith text", source = "البخاري" })
  H.truthy(H.find(tree, function(n) return n.type == "label" and n.props.text and n.props.text:find("العشر الأواخر") ~= nil end),
    "last-10-nights banner shown")
  H.eq(H.find(tree, function(n) return n.type == "label" and n.props.text == "hadith text" end), nil,
    "hadith suppressed while last-10-nights banner shows")
end)

H.test("buildCalendarTab sync label reflects synced vs estimated state", function()
  local t1 = M.buildCalendarTab(makeCalendar({ synced = true }), { day = 5, month = 1, year = 1448, days = 30 }, "16 Jul 2026", nil)
  local t2 = M.buildCalendarTab(makeCalendar({ synced = false }), { day = 5, month = 1, year = 1448, days = 30 }, "16 Jul 2026", nil)
  H.truthy(H.find(t1, function(n) return n.type == "label" and n.props.text == "calendar.sync" end), "synced label key")
  H.truthy(H.find(t2, function(n) return n.type == "label" and n.props.text == "calendar.approximate" end), "estimate label key")
end)

H.test("panel interactions", function()
  H.state.set("status", "ok")
  H.state.set("prayers", { { key="Fajr", label="Fajr", time="02:50", isNext=true, highlight="next" } })
  H.state.set("countdown", { text = "Fajr 10m", color = "primary", mode = "countdown", label = "Fajr", next = "Fajr" })
  H.state.set("hijri", { display = "1 Muharram 1448 AH", displayAr = "١ محرم ١٤٤٨" })
  H.env.onOpen({})
  H.truthy(H.calls.render, "rendered on open")
  H.env.onRefresh()
  H.eq(H.calls.command.action, "refresh", "refresh command")
  H.env.onClosePanel()
  H.eq(H.calls.close, true, "closed")
  H.env.onTabCalendar()
  H.eq(H.calls.command.action, "calendar", "calendar command on tab switch")
end)

-- ── Task 6.4: wire tab 1 + calendar nav + fonts ─────────────────────────────
H.test("onTabCalendar renders the calendar tab tree with a grid", function()
  H.state.set("calendar", makeCalendar())
  H.env.onTabCalendar()
  local tree = H.calls.render
  -- Header alone contributes 2 buttons (refresh, close); a real calendar grid
  -- (nav chevrons + day cells + spacers) pushes this well past that.
  local cellsAndSpacers = H.findAll(tree, function(n)
    return n.type == "spacer" or n.type == "button" or n.type == "box"
  end)
  H.ok(#cellsAndSpacers > 2, "grid rendered with cells, not just the Phase-5 placeholder")
  H.truthy(H.find(tree, function(n) return n.type == "button" and n.props.glyph == "chevron-left" end), "calendar nav row present")
  H.env.onTabPrayers()
end)

H.test("onCalNext advances the viewed month and publishes a calendar command", function()
  H.state.set("hijri", { day = 1, month = 1, year = 1448, monthNameEn = "Muharram", monthNameAr = "محرم", days = 30 })
  H.env.onOpen({}) -- seeds _viewMonth/_viewYear from hijri (1, 1448)
  H.env.onCalNext()
  H.eq(H.calls.command.action, "calendar", "calendar command")
  H.eq(H.calls.command.month, 2, "month + 1")
  H.eq(H.calls.command.year, 1448, "same year (no wrap)")
end)

H.test("onCalPrev wraps Muharram (1) back to Dhu al-Hijjah (12) of the prior year", function()
  H.state.set("hijri", { day = 1, month = 1, year = 1448, days = 30 })
  H.env.onOpen({})
  H.env.onCalPrev()
  H.eq(H.calls.command.month, 12, "wraps to month 12")
  H.eq(H.calls.command.year, 1447, "year - 1 on wrap")
end)

H.test("onCalNext wraps Dhu al-Hijjah (12) forward to Muharram (1) of the next year", function()
  H.state.set("hijri", { day = 1, month = 12, year = 1448, days = 30 })
  H.env.onOpen({})
  H.env.onCalNext()
  H.eq(H.calls.command.month, 1, "wraps to month 1")
  H.eq(H.calls.command.year, 1449, "year + 1 on wrap")
end)

H.test("onCalToday resets the view to the current hijri month and publishes calendar", function()
  H.state.set("hijri", { day = 1, month = 3, year = 1448, days = 30 })
  H.env.onOpen({})
  H.env.onCalNext(); H.env.onCalNext() -- move away from the current month
  H.env.onCalToday()
  H.eq(H.calls.command.month, 3, "back to current month")
  H.eq(H.calls.command.year, 1448, "same year")
end)

H.test("onCalRefresh publishes calendarRefresh for the viewed month", function()
  H.state.set("hijri", { day = 1, month = 1, year = 1448, days = 30 })
  H.env.onOpen({})
  H.env.onCalRefresh()
  H.eq(H.calls.command.action, "calendarRefresh", "calendarRefresh action")
  H.eq(H.calls.command.month, 1, "viewed month")
end)

H.test("onRefresh routes to a calendar refresh when the calendar tab is active", function()
  H.env.onTabCalendar()
  H.env.onRefresh()
  H.eq(H.calls.command.action, "calendarRefresh", "refresh routes to calendar refresh on tab 1")
  H.env.onTabPrayers()
  H.env.onRefresh()
  H.eq(H.calls.command.action, "refresh", "refresh stays a prayer refresh on tab 0")
end)

H.finish()
