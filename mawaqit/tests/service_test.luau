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

H.test("hijriDisplayAr trims a padded Arabic month name", function()
  local cfg = M._readConfig()
  local entry = { timings = { Fajr = "05:00" },
    hijri = { day = "5", month = { number = 3, ar = "  ربيع الأول  ", en = "Rabi al-Awwal", days = 30 }, year = "1447" } }
  local bundle = M._processEntry(entry, cfg, { nowSec = 6*3600, gregWeekday = 2, dayOfYear = 10 })
  H.eq(bundle.hijri.displayAr, "٥ ربيع الأول ١٤٤٧", "trimmed Arabic month name in displayAr")
end)

H.finish()
