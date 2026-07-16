--!nonstrict
local H = require("./harness")
local M = H.loadEntry("../service")

H.test("formatTime 24h passthrough", function() H.eq(M.formatTime("13:05", false), "13:05", "24h") end)
H.test("formatTime 12h pm", function() H.eq(M.formatTime("13:05", true), "1:05 PM", "pm") end)
H.test("formatTime 12h am + midnight", function()
  H.eq(M.formatTime("00:07", true), "12:07 AM", "midnight")
  H.eq(M.formatTime("12:00", true), "12:00 PM", "noon")
end)
H.test("toArabicNumerals", function() H.eq(M.toArabicNumerals("1447"), "١٤٤٧", "digits") end)
H.test("formatCountdownText", function()
  H.eq(M.formatCountdownText(3725), "1h 2m 5s", "h m s")
  H.eq(M.formatCountdownText(125), "2m 5s", "m s")
  H.eq(M.formatCountdownText(9), "9s", "s")
end)
H.test("cleanTime strips tz", function() H.eq(M.cleanTime("05:12 (BST)"), "05:12", "strip") end)
H.test("buildTuneParam off", function()
  H.eq(M.buildTuneParam({ tune = false }), "0,0,0,0,0,0,0,0,0", "zero")
end)
H.test("buildTuneParam on", function()
  H.eq(M.buildTuneParam({ tune = true, tuneFajr = 2, tuneDhuhr = -1, tuneAsr = 0, tuneMaghrib = 3, tuneIsha = 0 }),
       "0,2,0,-1,0,3,0,0,0", "order Imsak,Fajr,Sunrise,Dhuhr,Asr,Maghrib,Sunset,Isha,Midnight")
end)
H.test("buildWeeklyUrl", function()
  local u = M.buildWeeklyUrl({ city = "London", country = "UK", method = "3", school = "0", tune = false }, "16-07-2026")
  H.ok(u:find("timingsByCity/16%-07%-2026", 1), "date path")
  H.ok(u:find("city=London") ~= nil, "city")
  H.ok(u:find("country=UK") ~= nil, "country")
  H.ok(u:find("method=3") ~= nil, "method")
  H.ok(u:find("methodSettings=null,null,null") ~= nil, "methodSettings")
  H.ok(u:find("school=0") ~= nil, "school")
  H.ok(u:find("days=7") ~= nil, "days")
end)
H.test("buildWeeklyUrl custom angles", function()
  local u = M.buildWeeklyUrl({ city = "X", country = "Y", method = "99", school = "0", fajrAngle = "18", ishaAngle = "17", tune = false }, "16-07-2026")
  H.ok(u:find("methodSettings=18,null,17") ~= nil, "angles")
end)
local WEEKLY = { code = 200, data = {
  { date = { gregorian = { date = "16-07-2026" }, readable = "16 Jul 2026",
             hijri = { day = "01", month = { number = 1, en = "Muharram", ar = "محرم", days = 30 }, year = "1448" } },
    timings = { Imsak = "02:40 (BST)", Fajr = "02:50", Sunrise = "05:03", Dhuhr = "13:05",
                Asr = "17:20", Maghrib = "21:07", Isha = "23:10" } },
  { date = { gregorian = { date = "17-07-2026" }, readable = "17 Jul 2026",
             hijri = { day = "02", month = { number = 1, en = "Muharram", ar = "محرم", days = 30 }, year = "1448" } },
    timings = { Fajr = "02:52", Dhuhr = "13:05", Asr = "17:19", Maghrib = "21:06", Isha = "23:08", Imsak = "02:42", Sunrise = "05:04" } },
} }
H.test("normalizeWeekly picks today", function()
  local e = M.normalizeWeekly(WEEKLY, "2026-07-16")
  H.eq(e.timings.Fajr, "02:50", "fajr today")
  H.eq(e.timings.Imsak, "02:40", "imsak cleaned of tz")
  H.eq(e.gregorian, "16-07-2026", "greg")
  H.eq(e.readable, "16 Jul 2026", "readable")
  H.eq(tonumber(e.hijri.day), 1, "hijri day")
end)
H.test("normalizeWeekly fallback data[0]", function()
  local e = M.normalizeWeekly(WEEKLY, "2030-01-01")
  H.eq(e.gregorian, "16-07-2026", "fallback first")
end)
H.test("normalizeSingleDay", function()
  local e = M.normalizeSingleDay({ code = 200, data = {
    timings = { Fajr = "03:00 (UTC)", Dhuhr = "13:00", Asr = "17:00", Maghrib = "21:00", Isha = "23:00", Imsak = "02:50", Sunrise = "05:00" },
    date = { gregorian = { date = "16-07-2026" }, readable = "16 Jul 2026",
             hijri = { day = "01", month = { number = 1, en = "Muharram", ar = "محرم", days = 30 }, year = "1448" } } } })
  H.eq(e.timings.Fajr, "03:00", "cleaned")
  H.eq(e.gregorian, "16-07-2026", "greg")
end)
H.finish()
