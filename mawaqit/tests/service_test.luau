--!nonstrict
local H = require("./harness")
H.setConfig({ city = "Cairo", country = "EG", method = "5", tune = true, tuneFajr = 3, use12hourFormat = true })
local M = H.loadEntry("../service")
H.test("readConfig maps + defaults", function()
  local c = M._readConfig()
  H.eq(c.city, "Cairo", "city"); H.eq(c.country, "EG", "country"); H.eq(c.method, "5", "method")
  H.eq(c.tune, true, "tune"); H.eq(c.tuneFajr, 3, "tuneFajr int"); H.eq(c.use12hourFormat, true, "12h")
  H.eq(c.school, "0", "default school"); H.eq(c.weekStartDay, 1, "default weekStart int")
end)
H.test("cache save then load valid", function()
  local cfg = M._readConfig()
  local entry = { timings = { Fajr = "02:50" }, gregorian = "16-07-2026", readable = "16 Jul 2026", hijri = { day = "1" } }
  M._saveCache(cfg, entry)
  local got = M._loadCache(cfg)
  H.eq(got.timings.Fajr, "02:50", "round-trip")
end)
H.test("cache invalidated on city change", function()
  local cfg = M._readConfig()
  M._saveCache(cfg, { timings = {}, gregorian = "x", readable = "x", hijri = {} })
  local other = M._readConfig(); other.city = "Paris"
  H.eq(M._loadCache(other), nil, "different city invalidates")
end)

H.test("fetch publishes state", function()
  H.setHttpReply({ ok = true, status = 200, body = "WEEKLYTOKEN" })
  H.setDecode(function(s) if s == "WEEKLYTOKEN" then return { code = 200, data = {
    { date = { gregorian = { date = "16-07-2026" }, readable = "16 Jul 2026",
      hijri = { day = "1", month = { number = 1, en = "Muharram", ar = "محرم", days = 30 }, year = "1448" } },
      timings = { Imsak="02:40", Fajr="02:50", Sunrise="05:03", Dhuhr="13:05", Asr="17:20", Maghrib="21:07", Isha="23:10" } } } } end return nil end)
  local cfg = M._readConfig()
  M._fetch(cfg, { todayISO = "2026-07-16", nowSec = 12*3600, dayOfYear = 197, gregWeekday = 4 })
  H.eq(H.state.get("status"), "ok", "status ok")
  H.truthy(H.state.get("prayers"), "prayers published")
  H.eq(H.state.get("gregorian"), "16 Jul 2026", "gregorian readable")
  H.truthy(H.state.get("hijri").displayAr, "hijri arabic display")
end)

H.test("tick notifies at prayer minute + publishes countdown", function()
  H.calls.notify = nil
  local cfg = M._readConfig()
  -- seed current entry via a fetch first (reuses previous test's http mock)
  M._fetch(cfg, { todayISO = "2026-07-16", nowSec = 13*3600+5*60, dayOfYear = 197, gregWeekday = 4 })
  M._tick({ todayISO = "2026-07-16", nowSec = 13*3600+5*60, hhmm = "13:05", minute = 785, dayOfYear = 197, gregWeekday = 4 })
  H.truthy(H.state.get("countdown"), "countdown published")
  H.truthy(H.calls.notify, "notified at Dhuhr 13:05")
end)
H.test("command refresh re-fetches", function()
  H.calls.http = nil
  M._installCommandWatch()
  H.state.set("command", { action = "refresh", ts = 1 })
  H.truthy(H.calls.http, "refresh triggered a fetch")
end)

H.test("backoff bounds http retries on a failed-fetch day (no hammering)", function()
  H.setHttpReply({ ok = false, status = 0, body = "" })
  H.resetHttpCount()
  local cfg = M._readConfig()
  local baseNowCtx = { todayISO = "2026-07-17", nowSec = 10*3600, hhmm = "10:00", minute = 600, dayOfYear = 198, gregWeekday = 5 }
  M._fetch(cfg, baseNowCtx)
  for i = 1, 4 do
    M._tick({ todayISO = "2026-07-17", nowSec = 10*3600 + i, hhmm = "10:00", minute = 600, dayOfYear = 198, gregWeekday = 5 })
  end
  H.ok(H.httpCount() <= 2, "expected <=2 http calls (weekly+single fallback) within backoff window, got " .. tostring(H.httpCount()))
end)

H.test("tick does not re-notify the same prayer minute twice in a row", function()
  H.setHttpReply({ ok = true, status = 200, body = "WEEKLYTOKEN" })
  local cfg = M._readConfig()
  local nowCtx = { todayISO = "2026-07-18", nowSec = 13*3600+5*60, hhmm = "13:05", minute = 785, dayOfYear = 199, gregWeekday = 6 }
  M._fetch(cfg, nowCtx)
  M._lastNotifiedMinute = nil
  H.calls.notify = nil
  M._tick(nowCtx)
  M._tick(nowCtx)
  H.eq(#H.calls.notify, 1, "should notify exactly once across repeated ticks at the same minute")
end)

-- ── Pre-prayer reminder (notifyMinutesBefore) ───────────────────────────────
H.test("_shiftHHMM shifts a time by delta minutes with midnight wrap", function()
  H.eq(M._shiftHHMM("13:05", 0), "13:05", "no shift")
  H.eq(M._shiftHHMM("13:05", -15), "12:50", "shift back 15")
  H.eq(M._shiftHHMM("13:05", 15), "13:20", "shift forward 15")
  H.eq(M._shiftHHMM("00:10", -15), "23:55", "wrap back across midnight")
  H.eq(M._shiftHHMM("23:55", 15), "00:10", "wrap forward across midnight")
  H.eq(M._shiftHHMM("00:00", -1), "23:59", "wrap back from midnight")
end)

H.test("readConfig defaults notifyMinutesBefore to 15", function()
  local c = M._readConfig()
  H.eq(c.notifyMinutesBefore, 15, "default lead is 15 minutes")
end)

H.test("pre-notify fires 15 min before Dhuhr", function()
  H.setHttpReply({ ok = true, status = 200, body = "PRETOKEN" })
  H.setDecode(function(s) if s == "PRETOKEN" then return { code = 200, data = {
    { date = { gregorian = { date = "16-07-2026" }, readable = "16 Jul 2026",
      hijri = { day = "1", month = { number = 1, en = "Muharram", ar = "محرم", days = 30 }, year = "1448" } },
      timings = { Imsak="02:40", Fajr="02:50", Sunrise="05:03", Dhuhr="13:05", Asr="17:20", Maghrib="21:07", Isha="23:10" } } } } end return nil end)
  local cfg = M._readConfig()
  local nowCtx = { todayISO = "2026-07-16", nowSec = 12*3600+50*60, hhmm = "12:50", minute = 770, dayOfYear = 197, gregWeekday = 4 }
  M._fetch(cfg, nowCtx)
  M._lastNotifiedMinute = nil
  M._lastPreNotifiedMinute = nil
  H.calls.notify = nil
  M._tick(nowCtx)
  H.truthy(H.calls.notify, "pre-notified 15 min before Dhuhr at 12:50")
  H.eq(H.calls.notify[1][1], "🕌 Dhuhr in 15 min — 13:05", "title names Dhuhr + lead + prayer time")
  H.eq(H.calls.notify[1][2], "صلاة الظهر بعد ١٥ دقيقة", "body is Arabic 'Dhuhr prayer is in 15 minutes'")
end)

H.test("pre-notify does not fire when notifyMinutesBefore is 0", function()
  H.setConfig({ city = "Cairo", country = "EG", method = "5", tune = true, tuneFajr = 3, use12hourFormat = true, notifyMinutesBefore = 0 })
  H.setHttpReply({ ok = true, status = 200, body = "PRETOKEN0" })
  H.setDecode(function(s) if s == "PRETOKEN0" then return { code = 200, data = {
    { date = { gregorian = { date = "16-07-2026" }, readable = "16 Jul 2026",
      hijri = { day = "1", month = { number = 1, en = "Muharram", ar = "محرم", days = 30 }, year = "1448" } },
      timings = { Imsak="02:40", Fajr="02:50", Sunrise="05:03", Dhuhr="13:05", Asr="17:20", Maghrib="21:07", Isha="23:10" } } } } end return nil end)
  local cfg = M._readConfig()
  H.eq(cfg.notifyMinutesBefore, 0, "lead disabled")
  local nowCtx = { todayISO = "2026-07-16", nowSec = 12*3600+50*60, hhmm = "12:50", minute = 770, dayOfYear = 197, gregWeekday = 4 }
  M._fetch(cfg, nowCtx)
  M._lastNotifiedMinute = nil
  M._lastPreNotifiedMinute = nil
  H.calls.notify = nil
  M._tick(nowCtx)
  H.eq(H.calls.notify, nil, "no pre-notify when lead is 0")
  -- restore default config for subsequent tests
  H.setConfig({ city = "Cairo", country = "EG", method = "5", tune = true, tuneFajr = 3, use12hourFormat = true })
end)

H.test("pre-notify does not re-fire across repeated ticks at the same pre minute", function()
  H.setHttpReply({ ok = true, status = 200, body = "PRETOKEN2" })
  H.setDecode(function(s) if s == "PRETOKEN2" then return { code = 200, data = {
    { date = { gregorian = { date = "16-07-2026" }, readable = "16 Jul 2026",
      hijri = { day = "1", month = { number = 1, en = "Muharram", ar = "محرم", days = 30 }, year = "1448" } },
      timings = { Imsak="02:40", Fajr="02:50", Sunrise="05:03", Dhuhr="13:05", Asr="17:20", Maghrib="21:07", Isha="23:10" } } } } end return nil end)
  local cfg = M._readConfig()
  local nowCtx = { todayISO = "2026-07-16", nowSec = 12*3600+50*60, hhmm = "12:50", minute = 770, dayOfYear = 197, gregWeekday = 4 }
  M._fetch(cfg, nowCtx)
  M._lastNotifiedMinute = nil
  M._lastPreNotifiedMinute = nil
  H.calls.notify = nil
  M._tick(nowCtx)
  M._tick(nowCtx)
  H.eq(#H.calls.notify, 1, "pre-notify fires exactly once across repeated ticks at 12:50")
end)

H.test("pre-notify at 12:50 and at-prayer notify at 13:05 both fire for Dhuhr", function()
  H.setHttpReply({ ok = true, status = 200, body = "PRETOKEN3" })
  H.setDecode(function(s) if s == "PRETOKEN3" then return { code = 200, data = {
    { date = { gregorian = { date = "16-07-2026" }, readable = "16 Jul 2026",
      hijri = { day = "1", month = { number = 1, en = "Muharram", ar = "محرم", days = 30 }, year = "1448" } },
      timings = { Imsak="02:40", Fajr="02:50", Sunrise="05:03", Dhuhr="13:05", Asr="17:20", Maghrib="21:07", Isha="23:10" } } } } end return nil end)
  local cfg = M._readConfig()
  M._fetch(cfg, { todayISO = "2026-07-16", nowSec = 12*3600, dayOfYear = 197, gregWeekday = 4 })
  M._lastNotifiedMinute = nil
  M._lastPreNotifiedMinute = nil
  H.calls.notify = nil
  M._tick({ todayISO = "2026-07-16", nowSec = 12*3600+50*60, hhmm = "12:50", minute = 770, dayOfYear = 197, gregWeekday = 4 })
  M._tick({ todayISO = "2026-07-16", nowSec = 13*3600+5*60, hhmm = "13:05", minute = 785, dayOfYear = 197, gregWeekday = 4 })
  H.eq(#H.calls.notify, 2, "pre-notify + at-prayer notify both fire")
  H.eq(H.calls.notify[1][1], "🕌 Dhuhr in 15 min — 13:05", "first notify is the pre-reminder")
  H.eq(H.calls.notify[2][1], "🕌 Dhuhr — 13:05", "second notify is the at-prayer notify")
end)

H.test("pre-notify wraps across midnight for a 00:10 Fajr", function()
  H.setHttpReply({ ok = true, status = 200, body = "PRETOKEN4" })
  H.setDecode(function(s) if s == "PRETOKEN4" then return { code = 200, data = {
    { date = { gregorian = { date = "16-07-2026" }, readable = "16 Jul 2026",
      hijri = { day = "1", month = { number = 1, en = "Muharram", ar = "محرم", days = 30 }, year = "1448" } },
      timings = { Imsak="00:00", Fajr="00:10", Sunrise="05:30", Dhuhr="13:05", Asr="17:20", Maghrib="21:07", Isha="23:10" } } } } end return nil end)
  local cfg = M._readConfig()
  -- 23:55 is 15 min before Fajr (00:10 - 15 = 23:55, wrapping across midnight)
  local nowCtx = { todayISO = "2026-07-16", nowSec = 23*3600+55*60, hhmm = "23:55", minute = 1435, dayOfYear = 197, gregWeekday = 4 }
  M._fetch(cfg, nowCtx)
  M._lastNotifiedMinute = nil
  M._lastPreNotifiedMinute = nil
  H.calls.notify = nil
  M._tick(nowCtx)
  H.eq(#H.calls.notify, 1, "pre-notify fires for Fajr across midnight wrap")
  H.eq(H.calls.notify[1][1], "🕌 Fajr in 15 min — 00:10", "title names Fajr + 00:10 prayer time")
end)

H.test("pre-notify excludes Imsak even when its pre-minute matches", function()
  H.setHttpReply({ ok = true, status = 200, body = "PRETOKEN5" })
  H.setDecode(function(s) if s == "PRETOKEN5" then return { code = 200, data = {
    { date = { gregorian = { date = "16-07-2026" }, readable = "16 Jul 2026",
      hijri = { day = "1", month = { number = 1, en = "Muharram", ar = "محرم", days = 30 }, year = "1448" } },
      timings = { Imsak="02:40", Fajr="02:50", Sunrise="05:03", Dhuhr="13:05", Asr="17:20", Maghrib="21:07", Isha="23:10" } } } } end return nil end)
  local cfg = M._readConfig()
  -- 02:25 is 15 min before Imsak (02:40). If Imsak were in PRE_NOTIFY_KEYS, a pre-notify
  -- would fire here. It must not. No other prayer has a pre-minute at 02:25 (Fajr 02:50 → 02:35).
  local nowCtx = { todayISO = "2026-07-16", nowSec = 2*3600+25*60, hhmm = "02:25", minute = 145, dayOfYear = 197, gregWeekday = 4 }
  M._fetch(cfg, nowCtx)
  M._lastNotifiedMinute = nil
  M._lastPreNotifiedMinute = nil
  H.calls.notify = nil
  M._tick(nowCtx)
  H.eq(H.calls.notify, nil, "no pre-notify for Imsak (excluded from PRE_NOTIFY_KEYS)")
end)

-- ── Task 6.2: calendar command + fetch/cache ────────────────────────────────
H.test("calendar command builds synced state via http + writes a cache file", function()
  -- Seed today's hijri/gregorian context via a normal prayer fetch first
  -- (mirrors production: the command handler reads M._currentHijriCtx from
  -- already-published `hijri`/`gregorian` state).
  H.setHttpReply({ ok = true, status = 200, body = "WEEKLYTOKEN" })
  H.setDecode(function(s) if s == "WEEKLYTOKEN" then return { code = 200, data = {
    { date = { gregorian = { date = "16-07-2026" }, readable = "16 Jul 2026",
      hijri = { day = "1", month = { number = 1, en = "Muharram", ar = "محرم", days = 30 }, year = "1448" } },
      timings = { Fajr="02:50", Dhuhr="13:05", Asr="17:20", Maghrib="21:07", Isha="23:10" } } } } end return nil end)
  M._fetch(M._readConfig(), { todayISO = "2026-07-16", nowSec = 8*3600, dayOfYear = 197, gregWeekday = 4 })

  H.setHttpReply({ ok = true, status = 200, body = "CALTOKEN" })
  H.setDecode(function(s)
    if s == "CALTOKEN" then
      local data = {}
      for d = 1, 30 do
        data[d] = { gregorian = { day = tostring(15 + d), month = { en = "Jul" }, year = "2026" } }
      end
      return { code = 200, data = data }
    end
    return nil
  end)
  M._installCommandWatch()
  H.state.set("command", { action = "calendar", month = 1, year = 1448, ts = 2 })
  local cal = H.state.get("calendar")
  H.truthy(cal, "calendar state published")
  H.eq(cal.synced, true, "synced true once http completes")
  H.truthy(H._fs["/tmp/mawaqit-datadir/cal_1448_1.json"], "cache file written at cal_{y}_{m}.json")
end)

H.test("calendar command with a cache hit skips http and stays synced", function()
  H.resetHttpCount()
  H.state.set("command", { action = "calendar", month = 1, year = 1448, ts = 3 })
  H.eq(H.httpCount(), 0, "no new http call when the cache is already warm")
  H.eq(H.state.get("calendar").synced, true, "still synced from cache")
end)

H.test("calendarRefresh forces a re-fetch even with a warm cache", function()
  H.resetHttpCount()
  H.setHttpReply({ ok = true, status = 200, body = "CALTOKEN" })
  H.state.set("command", { action = "calendarRefresh", month = 1, year = 1448, ts = 4 })
  H.ok(H.httpCount() >= 1, "calendarRefresh always hits http, bypassing the TTL cache")
end)

H.test("hijriDisplayAr trims a padded Arabic month name", function()
  local cfg = M._readConfig()
  local entry = { timings = { Fajr = "05:00" },
    hijri = { day = "5", month = { number = 3, ar = "  ربيع الأول  ", en = "Rabi al-Awwal", days = 30 }, year = "1447" } }
  local bundle = M._processEntry(entry, cfg, { nowSec = 6*3600, gregWeekday = 2, dayOfYear = 10 })
  H.eq(bundle.hijri.displayAr, "٥ ربيع الأول ١٤٤٧", "trimmed Arabic month name in displayAr")
end)

H.finish()
