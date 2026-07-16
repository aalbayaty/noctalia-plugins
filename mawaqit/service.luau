--!nonstrict
local M = {}

local ARABIC_DIGITS = { ["0"]="٠",["1"]="١",["2"]="٢",["3"]="٣",["4"]="٤",["5"]="٥",["6"]="٦",["7"]="٧",["8"]="٨",["9"]="٩" }
function M.toArabicNumerals(s)
  return (tostring(s):gsub("%d", function(d) return ARABIC_DIGITS[d] end))
end

function M.formatTime(hhmm, use12h)
  local h, m = hhmm:match("^(%d+):(%d+)")
  if not h then return hhmm end
  h, m = tonumber(h), tonumber(m)
  if not use12h then return string.format("%02d:%02d", h, m) end
  local suffix = h < 12 and "AM" or "PM"
  local h12 = h % 12
  if h12 == 0 then h12 = 12 end
  return string.format("%d:%02d %s", h12, m, suffix)
end

function M.formatCountdownText(seconds)
  seconds = math.max(0, math.floor(seconds))
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  if h > 0 then return string.format("%dh %dm %ds", h, m, s) end
  if m > 0 then return string.format("%dm %ds", m, s) end
  return string.format("%ds", s)
end

local API_BASE = "https://api.aladhan.com/v1"

function M.cleanTime(raw)
  return (tostring(raw):gsub("%s*%(.*%)", ""))
end

function M.buildTuneParam(cfg)
  if not cfg.tune then return "0,0,0,0,0,0,0,0,0" end
  -- Aladhan order: Imsak,Fajr,Sunrise,Dhuhr,Asr,Maghrib,Sunset,Isha,Midnight
  return string.format("0,%d,0,%d,%d,%d,0,%d,0",
    cfg.tuneFajr or 0, cfg.tuneDhuhr or 0, cfg.tuneAsr or 0, cfg.tuneMaghrib or 0, cfg.tuneIsha or 0)
end

local function methodSettings(cfg)
  local fajr = (cfg.method == "99" and cfg.fajrAngle ~= nil and cfg.fajrAngle ~= "") and cfg.fajrAngle or "null"
  local isha = (cfg.method == "99" and cfg.ishaAngle ~= nil and cfg.ishaAngle ~= "") and cfg.ishaAngle or "null"
  return fajr .. ",null," .. isha
end

local function commonQuery(cfg)
  local enc = noctalia.string.urlEncode
  return string.format("city=%s&country=%s&method=%s&methodSettings=%s&school=%s&tune=%s",
    enc(cfg.city or ""), enc(cfg.country or ""), cfg.method or "3", methodSettings(cfg),
    cfg.school or "0", M.buildTuneParam(cfg))
end

function M.buildWeeklyUrl(cfg, ddmmyyyy)
  return string.format("%s/timingsByCity/%s?%s&days=7", API_BASE, ddmmyyyy, commonQuery(cfg))
end
function M.buildSingleDayUrl(cfg)
  return string.format("%s/timingsByCity?%s", API_BASE, commonQuery(cfg))
end

local function ddmmyyyyToISO(d)
  local dd, mm, yy = d:match("^(%d%d)%-(%d%d)%-(%d%d%d%d)")
  if not dd then return nil end
  return string.format("%s-%s-%s", yy, mm, dd)
end

local function normalizeEntry(rawDate, rawTimings)
  local timings = {}
  for k, v in pairs(rawTimings) do timings[k] = M.cleanTime(v) end
  return {
    timings = timings,
    hijri = rawDate.hijri,
    gregorian = rawDate.gregorian and rawDate.gregorian.date or "",
    readable = rawDate.readable or "",
  }
end

function M.normalizeWeekly(decoded, todayISO)
  if type(decoded) ~= "table" or decoded.code ~= 200 or type(decoded.data) ~= "table" then return nil end
  local chosen
  for _, item in ipairs(decoded.data) do
    local iso = item.date and item.date.gregorian and ddmmyyyyToISO(item.date.gregorian.date)
    if iso == todayISO then chosen = item; break end
  end
  chosen = chosen or decoded.data[1]
  if not chosen then return nil end
  return normalizeEntry(chosen.date, chosen.timings)
end

function M.normalizeSingleDay(decoded)
  if type(decoded) ~= "table" or decoded.code ~= 200 or type(decoded.data) ~= "table" then return nil end
  return normalizeEntry(decoded.data.date, decoded.data.timings)
end

-- ── Constants / small maps (Task 2.7, landed early for Task 2.4 use) ────────

M.PRAYER_ORDER = { "Imsak", "Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha" }
M.PRAYER_KEYS = { "Fajr", "Dhuhr", "Asr", "Maghrib", "Isha" }
M.NOTIFY_KEYS = { "Imsak", "Fajr", "Dhuhr", "Asr", "Maghrib", "Isha" }
M.PRAYER_GLYPHS = { Imsak = "moon", Fajr = "sun-moon", Sunrise = "sunrise", Dhuhr = "sun-high",
  Asr = "sun-low", Maghrib = "sunset", Isha = "moon-stars" }

function M.prayerGlyph(key, isJumuah)
  if key == "Dhuhr" and isJumuah then return "building-mosque" end
  return M.PRAYER_GLYPHS[key] or "building-mosque"
end

function M.colorRole(v)
  if v == nil or v == "none" then return "" end
  return v
end

M.LABELS = { Imsak = "Imsak", Fajr = "Fajr", Sunrise = "Sunrise", Dhuhr = "Dhuhr", Asr = "Asr",
  Maghrib = "Maghrib", Isha = "Isha", Jumuah = "Jumu'ah" }

function M.labelFor(key, isJumuah)
  if key == "Dhuhr" and isJumuah then return M.LABELS.Jumuah end
  return M.LABELS[key] or key
end

-- ── Task 2.4: countdown + prayer rows ───────────────────────────────────────

-- Build the list of {key, seconds-since-midnight} entries in prayer order for
-- today, honoring Ramadan's leading Imsak slot. Sunrise never counts toward
-- the countdown (mirrors v4's `prayerKeys`), but Sunrise rows still render in
-- buildPrayerRows.
local function countdownKeys(isRamadan)
  if isRamadan then
    local keys = { "Imsak" }
    for _, k in ipairs(M.PRAYER_KEYS) do table.insert(keys, k) end
    return keys
  end
  return M.PRAYER_KEYS
end

local function secondsOf(hhmm)
  local h, m = tostring(hhmm):match("^(%d+):(%d+)")
  if not h then return nil end
  return tonumber(h) * 3600 + tonumber(m) * 60
end

-- Find the next-upcoming prayer (wrapping to tomorrow's first) and, if
-- applicable, the previous one (for elapsed-mode).
local function findNextAndPrev(timings, nowSec, isRamadan)
  local order = countdownKeys(isRamadan)
  local prayers = {}
  for _, key in ipairs(order) do
    local t = timings[key]
    local s = t and secondsOf(t)
    if s then table.insert(prayers, { name = key, time = s }) end
  end
  if #prayers == 0 then return nil end

  local nextIdx = nil
  for i, p in ipairs(prayers) do
    if p.time > nowSec then nextIdx = i; break end
  end

  local wrapped = false
  local nextEntry
  if nextIdx == nil then
    nextEntry = { name = prayers[1].name, time = prayers[1].time + 86400 }
    wrapped = true
  else
    nextEntry = prayers[nextIdx]
  end

  local prevIdx = wrapped and #prayers or (nextIdx - 1)
  local prevEntry = (prevIdx >= 1) and prayers[prevIdx] or nil

  return prayers, nextEntry, prevEntry
end

-- M.computeCountdown(timings, nowSec, cfg, ctx) → countdown state shape
-- { next, label, secondsToNext, text, mode, color, glyph, elapsed }
function M.computeCountdown(timings, nowSec, cfg, ctx)
  ctx = ctx or {}
  if not timings then
    return { next = nil, label = "", secondsToNext = -1, text = "", mode = "nodata", color = "primary", glyph = cfg.widgetIcon, elapsed = false }
  end

  local prayers, nextEntry, prevEntry = findNextAndPrev(timings, nowSec, ctx.isRamadan)
  if not prayers then
    return { next = nil, label = "", secondsToNext = -1, text = "", mode = "nodata", color = "primary", glyph = cfg.widgetIcon, elapsed = false }
  end

  local nextKey = nextEntry.name
  local diff = nextEntry.time - nowSec
  local secondsToNext = diff > 0 and diff or 0

  -- Elapsed-mode window: within [0, min(3600, secondsToNext)] seconds after prevEntry
  local elapsedFlag = false
  local mode = nil
  local displayKey = nextKey
  local elapsedSeconds = nil

  if cfg.showElapsed and prevEntry then
    local elapsed = nowSec - prevEntry.time
    local maxElapsed = math.min(3600, secondsToNext)
    if elapsed >= 0 and elapsed <= maxElapsed then
      elapsedFlag = true
      mode = "elapsed"
      displayKey = prevEntry.name
      elapsedSeconds = elapsed
    end
  end

  if not elapsedFlag then
    -- 5-minute grace period: "now" for any prayer whose time just passed
    for _, p in ipairs(prayers) do
      local ms = nowSec - p.time
      if ms >= 0 and ms < 300 then
        displayKey = p.name
        nextKey = p.name
        secondsToNext = 0
        mode = "now"
        break
      end
    end
  end

  if not mode then
    if cfg.showCountdown then mode = "countdown" else mode = "time" end
  end

  local color
  if ctx.isRamadan and nextKey == "Imsak" then
    color = "secondary"
  elseif ctx.isRamadan and nextKey == "Maghrib" then
    color = "tertiary"
  else
    color = "primary"
  end

  local label = M.labelFor(displayKey, ctx.isJumuah)
  local text
  if mode == "elapsed" then
    local elapsedText = M.formatCountdownText(elapsedSeconds)
    text = cfg.hidePrayerName and elapsedText or (label .. " +" .. elapsedText)
  elseif mode == "now" then
    text = cfg.hidePrayerName and "Now" or (label .. " — Now")
  elseif mode == "countdown" then
    local cdText = M.formatCountdownText(secondsToNext)
    text = cfg.hidePrayerName and cdText or (label .. " " .. cdText)
  else -- "time"
    local timeStr = M.formatTime(timings[nextKey] or "", cfg.use12hourFormat)
    text = cfg.hidePrayerName and timeStr or (label .. " " .. timeStr)
  end

  local glyph
  if cfg.dynamicIcon then
    glyph = M.prayerGlyph(displayKey, ctx.isJumuah)
  else
    glyph = cfg.widgetIcon
  end

  return {
    next = nextKey,
    label = label,
    secondsToNext = secondsToNext,
    text = text,
    mode = mode,
    color = color,
    glyph = glyph,
    elapsed = elapsedFlag,
  }
end

-- M.buildPrayerRows(timings, cfg, ctx, nextKey) → prayers array in
-- M.PRAYER_ORDER order (Imsak..Isha), each row:
-- { key, label, glyph, time, isNext, highlight } where highlight is one of
-- "next" | "imsak" | "maghrib" | nil.
function M.buildPrayerRows(timings, cfg, ctx, nextKey)
  ctx = ctx or {}
  local rows = {}
  for _, key in ipairs(M.PRAYER_ORDER) do
    local isNext = key == nextKey
    local isImsak = ctx.isRamadan and key == "Imsak"
    local isMaghrib = ctx.isRamadan and key == "Maghrib"
    local highlight = nil
    if isNext then highlight = "next"
    elseif isImsak then highlight = "imsak"
    elseif isMaghrib then highlight = "maghrib" end

    table.insert(rows, {
      key = key,
      label = M.labelFor(key, ctx.isJumuah),
      glyph = M.prayerGlyph(key, ctx.isJumuah),
      time = timings and timings[key] or nil,
      isNext = isNext,
      highlight = highlight,
    })
  end
  return rows
end

-- ── Task 2.5: Hijri / JDN math ──────────────────────────────────────────────

function M.toJDN(y, m, d)
  local a = math.floor((14 - m) / 12)
  local yy = y + 4800 - a
  local mm = m + 12 * a - 3
  return d + math.floor((153 * mm + 2) / 5) + 365 * yy + math.floor(yy / 4)
       - math.floor(yy / 100) + math.floor(yy / 400) - 32045
end

function M.jdnToGreg(jdn)
  local a = jdn + 32044
  local b = math.floor((4 * a + 3) / 146097)
  local c = a - math.floor((146097 * b) / 4)
  local d = math.floor((4 * c + 3) / 1461)
  local e = c - math.floor((1461 * d) / 4)
  local m = math.floor((5 * e + 2) / 153)
  local day = e - math.floor((153 * m + 2) / 5) + 1
  local month = m + 3 - 12 * math.floor(m / 10)
  local year = 100 * b + d - 4800 + math.floor(m / 10)
  return year, month, day
end

local MONTH_ABBR = { Jan=1, Feb=2, Mar=3, Apr=4, May=5, Jun=6, Jul=7, Aug=8, Sep=9, Oct=10, Nov=11, Dec=12 }
function M.parseReadableToJDN(readable)
  local d, mon, y = tostring(readable):match("(%d+)%s+(%a+)%s+(%d+)")
  if not d then return nil end
  local mm = MONTH_ABBR[mon]
  if not mm then return nil end
  return M.toJDN(tonumber(y), mm, tonumber(d))
end

function M.weekdayColumn(jdn, weekStartDay)
  local offset = (weekStartDay + 6) % 7
  return (jdn % 7 - offset + 7) % 7
end

local HIJRI_LEAP = { [2]=true,[5]=true,[7]=true,[10]=true,[13]=true,[16]=true,[18]=true,[21]=true,[24]=true,[26]=true,[29]=true }
function M.isHijriLeapYear(hyear)
  return HIJRI_LEAP[hyear % 30] == true
end
function M.estimateMonthLength(hmonth, hyear)
  if hmonth == 12 then return M.isHijriLeapYear(hyear) and 30 or 29 end
  return (hmonth % 2 ~= 0) and 30 or 29
end

-- ── Task 2.6: Islamic events, hadith pool, last-ten-nights ──────────────────
-- Data ported verbatim from /tmp/legacy-v4-plugins/mawaqit/Panel.qml
-- (islamicEvents/islamicEventsAr maps ~L144-163, hadithPool ~L72-105).

M.EVENTS = {
  ["1-1"]   = { en = "Islamic New Year", ar = "رأس السنة الهجرية" },
  ["1-10"]  = { en = "Ashura",           ar = "عاشوراء" },
  ["3-12"]  = { en = "Mawlid an-Nabi",   ar = "المولد النبوي" },
  ["7-27"]  = { en = "Isra wal Miraj",   ar = "الإسراء والمعراج" },
  ["9-1"]   = { en = "Start of Ramadan", ar = "بداية رمضان" },
  ["9-21"]  = { en = "Laylat al-Qadr",   ar = "ليلة القدر" },
  ["9-23"]  = { en = "Laylat al-Qadr",   ar = "ليلة القدر" },
  ["9-25"]  = { en = "Laylat al-Qadr",   ar = "ليلة القدر" },
  ["9-27"]  = { en = "Laylat al-Qadr",   ar = "ليلة القدر" },
  ["9-29"]  = { en = "Laylat al-Qadr",   ar = "ليلة القدر" },
  ["10-1"]  = { en = "Eid al-Fitr",      ar = "عيد الفطر" },
  ["12-9"]  = { en = "Day of Arafah",    ar = "يوم عرفة" },
  ["12-10"] = { en = "Eid al-Adha",      ar = "عيد الأضحى" },
}

function M.eventsFor(hmonth, hday)
  local key = hmonth .. "-" .. hday
  if M.EVENTS[key] then return M.EVENTS[key] end
  if (hday == 13 or hday == 14 or hday == 15) and hmonth ~= 9 and hmonth ~= 10 and hmonth ~= 12 then
    return { en = "Ayyam al-Bid", ar = "أيام البيض" }
  end
  if hday == 29 then
    return { en = "Laylat al-Shakk", ar = "ليلة الشك" }
  end
  return nil
end

function M.isLastTenNights(hmonth, hday, monthDays)
  return hmonth == 9 and hday >= 20 and not (hday == 29 and monthDays == 29)
end

M.HADITH = {
  { text = "إنما الأعمال بالنيات", source = "البخاري" },
  { text = "المسلم من سلم المسلمون من لسانه ويده", source = "البخاري" },
  { text = "لا يؤمن أحدكم حتى يحب لأخيه ما يحب لنفسه", source = "البخاري" },
  { text = "الطهور شطر الإيمان", source = "مسلم" },
  { text = "خيركم من تعلم القرآن وعلمه", source = "البخاري" },
  { text = "الدين النصيحة", source = "مسلم" },
  { text = "من كان يؤمن بالله واليوم الآخر فليقل خيراً أو ليصمت", source = "البخاري" },
  { text = "البر حسن الخلق", source = "مسلم" },
  { text = "إن الله رفيق يحب الرفق في الأمر كله", source = "البخاري" },
  { text = "الكلمة الطيبة صدقة", source = "البخاري" },
  { text = "خير الناس أنفعهم للناس", source = "الطبراني" },
  { text = "إن الله جميل يحب الجمال", source = "مسلم" },
  { text = "أحب الأعمال إلى الله أدومها وإن قل", source = "البخاري" },
  { text = "اتق الله حيثما كنت", source = "الترمذي" },
  { text = "إن من أحبكم إليّ وأقربكم مني مجلساً يوم القيامة أحاسنكم أخلاقاً", source = "الترمذي" },
  { text = "من صام رمضان إيماناً واحتساباً غُفر له ما تقدم من ذنبه", source = "البخاري" },
  { text = "أفضل الصيام بعد رمضان شهر الله المحرم", source = "مسلم" },
  { text = "ابتغوا ليلة القدر في الوتر من العشر الأواخر من رمضان", source = "البخاري" },
  { text = "تبسمك في وجه أخيك صدقة", source = "الترمذي" },
  { text = "الصلوات الخمس كفارة لما بينهن ما اجتنبت الكبائر", source = "مسلم" },
  -- Hisn al-Muslim
  { text = "أعوذُ بكلماتِ اللهِ التّامّاتِ مِن شرِّ ما خَلَق", source = "حصن المسلم" },
  { text = "بِسْمِ اللَّهِ الَّذِي لَا يَضُرُّ مَعَ اسْمِهِ شَيْءٌ فِي الْأَرْضِ وَلَا فِي السَّمَاءِ وَهُوَ السَّمِيعُ الْعَلِيمُ", source = "حصن المسلم" },
  { text = "سُبْحَانَ اللهِ وَبِحَمْدِهِ", source = "حصن المسلم" },
  { text = "حَسْبِيَ اللَّهُ لاَ إِلَهَ إِلاَّ هُوَ عَلَيهِ تَوَكَّلتُ وَهُوَ رَبُّ الْعَرْشِ الْعَظِيمِ", source = "حصن المسلم" },
  { text = "اللَّهُمَّ إِنِّي أَعُوذُ بِكَ مِنَ الْكُفْرِ وَالفَقْرِ وَأَعُوذُ بِكَ مِنْ عَذَابِ القَبْرِ لاَ إِلَهَ إِلاَّ أَنْتَ", source = "حصن المسلم" },
  { text = "الْحَمْدُ لِلَّهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا وَإِلَيْهِ النُّشُورُ", source = "حصن المسلم" },
  { text = "بِسْمِ اللهِ تَوَكَّلْتُ عَلَى اللهِ وَلاَ حَوْلَ وَلاَ قُوَّةَ إِلاَّ بِاللهِ", source = "حصن المسلم" },
  { text = "بِسْمِ اللهِ وَالصَّلاَةُ وَالسَّلاَمُ عَلَى رَسُولِ اللهِ اللَّهُمَّ افْتَحْ لِي أَبْوَابَ رَحْمَتِكَ", source = "حصن المسلم" },
  { text = "لاَ إِلَهَ إِلاَّ اللهُ العَظِيمُ الحَلِيمُ لاَ إِلَهَ إِلاَّ اللهُ رَبُّ العَرْشِ العَظِيمِ لاَ إِلَهَ إِلاَّ اللهُ رَبُّ السَّمَاوَاتِ وَرَبُّ الأَرْضِ وَرَبُّ العَرْشِ الكَرِيمِ", source = "حصن المسلم" },
  { text = "اللَّهُمَّ لاَ سَهْلَ إِلاَّ مَا جَعَلْتَهُ سَهْلاً وَأَنْتَ تَجْعَلُ الْحَزْنَ إِذَا شِئْتَ سَهْلاً", source = "حصن المسلم" },
}

-- v4's `dailyHadith` indexes 0-based: `hadithPool[dayOfYear % hadithPool.length]`
-- (dayOfYear itself is 0-based, from `new Date(y,0,0)`). Luau arrays are
-- 1-based, so the equivalent lookup is `(dayOfYear % #M.HADITH) + 1` — NOT
-- `((dayOfYear - 1) % #M.HADITH) + 1`, which shifts the whole pool by one day
-- relative to v4.
function M.hadithForDay(dayOfYear)
  return M.HADITH[(dayOfYear % #M.HADITH) + 1]
end

-- ── upcomingEvent look-ahead (ported from Panel.qml's getHintEvent/upcomingEvent) ──
-- gregWeekday follows JS Date#getDay() convention: 0=Sun .. 5=Fri .. 6=Sat.
-- hyear is optional; when omitted, month-12 length falls back to non-leap (29).

local ARABIC_GREETINGS = { ["9-1"] = "رمضان كريم", ["10-1"] = "عيدكم مبارك", ["12-10"] = "عيدكم مبارك" }
local HINT_TIER1 = { ["1-1"] = "Islamic New Year" }
local HINT_TIER2 = { ["1-10"] = "Ashura", ["3-12"] = "Mawlid an-Nabi", ["7-27"] = "Isra wal Miraj", ["12-9"] = "Day of Arafah" }
local HINT_TIER4 = {
  ["9-1"] = "Start of Ramadan", ["9-20"] = "Laylat al-Qadr", ["9-22"] = "Laylat al-Qadr",
  ["9-24"] = "Laylat al-Qadr", ["9-26"] = "Laylat al-Qadr", ["9-28"] = "Laylat al-Qadr",
  ["10-1"] = "Eid al-Fitr", ["12-10"] = "Eid al-Adha",
}
local HINT_NAMES_AR = {
  ["Islamic New Year"] = "رأس السنة الهجرية", ["Ashura"] = "عاشوراء", ["Mawlid an-Nabi"] = "المولد النبوي",
  ["Isra wal Miraj"] = "الإسراء والمعراج", ["Start of Ramadan"] = "بداية رمضان", ["Laylat al-Qadr"] = "ليلة القدر",
  ["Eid al-Fitr"] = "عيد الفطر", ["Day of Arafah"] = "يوم عرفة", ["Eid al-Adha"] = "عيد الأضحى",
  ["Ayyam al-Bid"] = "أيام البيض",
}

local function getHintEvent(m, d, daysAway)
  local key = m .. "-" .. d
  if ARABIC_GREETINGS[key] and daysAway == 0 then
    return { name = ARABIC_GREETINGS[key], daysAway = 0, tier = 0 }
  end
  if HINT_TIER1[key] and daysAway <= 7 then
    return { name = HINT_NAMES_AR[HINT_TIER1[key]] or HINT_TIER1[key], daysAway = daysAway, tier = 1 }
  end
  if HINT_TIER2[key] and daysAway <= 3 then
    return { name = HINT_NAMES_AR[HINT_TIER2[key]] or HINT_TIER2[key], daysAway = daysAway, tier = 2 }
  end
  if (d == 13 or d == 14 or d == 15) and m ~= 9 and m ~= 10 and m ~= 12 and daysAway <= 3 then
    return { name = "أيام البيض", daysAway = daysAway, tier = 3 }
  end
  if d == 29 and daysAway == 0 then
    return { name = "ليلة الشك", daysAway = 0, tier = 4 }
  end
  if HINT_TIER4[key] and daysAway == 0 then
    return { name = HINT_NAMES_AR[HINT_TIER4[key]] or HINT_TIER4[key], daysAway = 0, tier = 4 }
  end
  return nil
end

function M.upcomingEvent(hmonth, hday, gregWeekday, hyear)
  if not hmonth or not hday or hmonth == 0 or hday == 0 then return nil end
  local todayKey = hmonth .. "-" .. hday
  if gregWeekday == 5 and not ARABIC_GREETINGS[todayKey] then
    return { daysAhead = 0, nameAr = "جمعة مباركة" }
  end

  local best = nil
  local d, m = hday, hmonth
  local monthLen = M.estimateMonthLength(m, hyear or 0)
  for i = 0, 30 do
    local candidate = getHintEvent(m, d, i)
    if candidate then
      if not best or candidate.daysAway < best.daysAway
        or (candidate.daysAway == best.daysAway and candidate.tier < best.tier) then
        best = candidate
      end
    end
    if best and best.daysAway == 0 and best.tier <= 2 then break end
    d = d + 1
    if d > monthLen then
      d = 1
      m = m + 1
      if m > 12 then m = 1 end
      monthLen = M.estimateMonthLength(m, hyear or 0)
    end
  end

  if not best then return nil end
  return { daysAhead = best.daysAway, nameAr = best.name }
end

-- ── Task 2.7 (remainder): methods + month-name constants ───────────────────

-- Ported verbatim from /tmp/legacy-v4-plugins/mawaqit/Settings.qml `methods` combo (~L11-30).
M.METHODS = {
  ["1"] = "University of Islamic Sciences, Karachi",
  ["2"] = "Islamic Society of North America (ISNA)",
  ["3"] = "Muslim World League (MWL)",
  ["4"] = "Umm Al-Qura University, Makkah",
  ["5"] = "Egyptian General Authority of Survey",
  ["7"] = "Institute of Geophysics, Tehran",
  ["8"] = "Gulf Region",
  ["9"] = "Kuwait",
  ["10"] = "Qatar",
  ["11"] = "Majlis Ugama Islam Singapura",
  ["12"] = "Union Organization Islamic de France",
  ["13"] = "Diyanet İşleri Başkanlığı, Turkey",
  ["14"] = "Spiritual Administration of Muslims of Russia",
  ["15"] = "Moonsighting Committee Worldwide",
  ["16"] = "Dubai (Experimental)",
  ["19"] = "Algeria",
  ["23"] = "Ministry of Awqaf, Islamic Affairs and Holy Places, Jordan",
  ["99"] = "Custom Method",
}

-- Ported verbatim from /tmp/legacy-v4-plugins/mawaqit/Panel.qml `monthNamesEn` (~L584-585).
M.MONTH_NAMES_EN = { "Muharram", "Safar", "Rabi al-Awwal", "Rabi ath-Thani", "Jumada al-Ula",
  "Jumada al-Akhira", "Rajab", "Shaban", "Ramadan", "Shawwal", "Dhu al-Qadah", "Dhu al-Hijjah" }

-- NOTE: v4's Panel.qml has no static Arabic month-name array — the Arabic name
-- is always taken dynamically from the Aladhan API response (hijri.month.ar).
-- These are the standard canonical Hijri month names, in the same order as
-- M.MONTH_NAMES_EN, provided for offline/pure-logic use (e.g. calendar nav
-- when no API data is cached yet).
M.MONTH_NAMES_AR = { "محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى",
  "جمادى الآخرة", "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة" }

-- ── Task 3.1: Config reader ──────────────────────────────────────────────────

local function cfgStr(key, default) local v = noctalia.getConfig(key); if v == nil then return default end; return v end
local function cfgInt(key, default) local v = noctalia.getConfig(key); if v == nil then return default end; return tonumber(v) or default end
local function cfgBool(key, default) local v = noctalia.getConfig(key); if v == nil then return default end; return v == true end

function M._readConfig()
  return {
    city = cfgStr("city", "London"), country = cfgStr("country", "UK"),
    method = cfgStr("method", "3"), fajrAngle = cfgStr("fajrAngle", ""), ishaAngle = cfgStr("ishaAngle", ""),
    school = cfgStr("school", "0"),
    hijriDayOffset = cfgInt("hijriDayOffset", 0), weekStartDay = cfgInt("weekStartDay", 1),
    tune = cfgBool("tune", false),
    tuneFajr = cfgInt("tuneFajr", 0), tuneDhuhr = cfgInt("tuneDhuhr", 0), tuneAsr = cfgInt("tuneAsr", 0),
    tuneMaghrib = cfgInt("tuneMaghrib", 0), tuneIsha = cfgInt("tuneIsha", 0),
    showCountdown = cfgBool("showCountdown", true), showElapsed = cfgBool("showElapsed", false),
    hidePrayerName = cfgBool("hidePrayerName", false), use12hourFormat = cfgBool("use12hourFormat", false),
    widgetIcon = cfgStr("widgetIcon", "building-mosque"), dynamicIcon = cfgBool("dynamicIcon", false),
    textColor = cfgStr("textColor", "none"), iconColor = cfgStr("iconColor", "none"), activeColor = cfgStr("activeColor", "primary"),
    showNotifications = cfgBool("showNotifications", true),
  }
end

-- ── Task 3.2: Cache read/write + validation ──────────────────────────────────

function M._cachePath() return (noctalia.pluginDataDir()) .. "/prayer_cache.json" end

function M._saveCache(cfg, entry)
  local blob = { entry = entry, city = cfg.city, country = cfg.country, method = cfg.method,
    school = cfg.school, fajrAngle = cfg.fajrAngle, ishaAngle = cfg.ishaAngle }
  local enc = noctalia.json.encode(blob)
  if enc then noctalia.writeFile(M._cachePath(), enc) end
end

function M._loadCache(cfg)
  if not noctalia.fileExists(M._cachePath()) then return nil end
  local raw = noctalia.readFile(M._cachePath())
  if not raw then return nil end
  local blob = noctalia.json.decode(raw)
  if type(blob) ~= "table" or not blob.entry then return nil end
  if blob.city ~= cfg.city or blob.country ~= cfg.country or blob.method ~= cfg.method
     or blob.school ~= cfg.school or blob.fajrAngle ~= cfg.fajrAngle or blob.ishaAngle ~= cfg.ishaAngle then
    return nil
  end
  return blob.entry
end

-- ── Task 3.3: Fetch pipeline + state publishing ──────────────────────────────

local function isoToDDMMYYYY(iso)
  local y, m, d = tostring(iso):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not y then return iso end
  return string.format("%s-%s-%s", d, m, y)
end

M._PRAYER_NAMES_AR = { Fajr = "الفجر", Dhuhr = "الظهر", Asr = "العصر", Maghrib = "المغرب", Isha = "العشاء", Imsak = "الإمساك" }

-- Build the publishable state bundle for one Aladhan day entry
-- ({ timings, hijri, gregorian, readable }). Pure aside from reading noctalia.tr
-- for the (rare) upcoming-event banner text.
function M._processEntry(entry, cfg, nowCtx)
  local hijriRaw = entry.hijri or {}
  local hijriMonthTbl = hijriRaw.month
  local hijriDayRaw = tonumber(hijriRaw.day) or 0
  local hijriMonth = (type(hijriMonthTbl) == "table" and hijriMonthTbl.number) or 0
  local hijriYear = tonumber(hijriRaw.year) or 0
  local monthNameEn = (type(hijriMonthTbl) == "table" and hijriMonthTbl.en) or M.MONTH_NAMES_EN[hijriMonth] or ""
  local monthNameAr = (type(hijriMonthTbl) == "table" and hijriMonthTbl.ar) or M.MONTH_NAMES_AR[hijriMonth] or ""
  local monthDays = (type(hijriMonthTbl) == "table" and tonumber(hijriMonthTbl.days)) or 30
  local hijriDay = math.max(1, math.min(30, hijriDayRaw + (cfg.hijriDayOffset or 0)))

  local isRamadan = hijriMonth == 9
  local isJumuah = nowCtx.gregWeekday == 5
  local ctx = { isRamadan = isRamadan, isJumuah = isJumuah }

  local countdown = M.computeCountdown(entry.timings, nowCtx.nowSec, cfg, ctx)
  local prayers = M.buildPrayerRows(entry.timings, cfg, ctx, countdown.next)

  local event = nil
  local up = M.upcomingEvent(hijriMonth, hijriDay, nowCtx.gregWeekday, hijriYear)
  if up then
    local whenText
    if up.daysAhead == 0 then whenText = noctalia.tr("panel.today")
    elseif up.daysAhead == 1 then whenText = noctalia.tr("panel.tomorrow")
    else whenText = noctalia.trp("panel.inDays", up.daysAhead, { count = up.daysAhead }) end
    event = { whenText = whenText, nameAr = up.nameAr }
  end

  local hadith = M.hadithForDay(nowCtx.dayOfYear or 0)

  local hijriDisplay, hijriDisplayAr = "", ""
  if hijriDay > 0 and monthNameEn ~= "" and hijriYear > 0 then
    hijriDisplay = string.format("%d %s %d AH", hijriDay, monthNameEn, hijriYear)
  end
  if hijriDay > 0 and monthNameAr ~= "" and hijriYear > 0 then
    hijriDisplayAr = M.toArabicNumerals(hijriDay) .. " " .. noctalia.string.trim(monthNameAr) .. " " .. M.toArabicNumerals(hijriYear)
  end

  return {
    status = "ok", error = "",
    prayers = prayers,
    hijri = { display = hijriDisplay, displayAr = hijriDisplayAr, day = hijriDay, month = hijriMonth,
      year = hijriYear, monthNameEn = monthNameEn, monthNameAr = monthNameAr, days = monthDays },
    gregorian = (entry.readable ~= nil and entry.readable ~= "") and entry.readable or (entry.gregorian or ""),
    isRamadan = isRamadan, isJumuah = isJumuah,
    event = event, hadith = hadith, countdown = countdown,
  }
end

function M._publish(bundle)
  noctalia.state.set("status", bundle.status)
  noctalia.state.set("error", bundle.error)
  noctalia.state.set("prayers", bundle.prayers)
  noctalia.state.set("hijri", bundle.hijri)
  noctalia.state.set("gregorian", bundle.gregorian)
  noctalia.state.set("isRamadan", bundle.isRamadan)
  noctalia.state.set("isJumuah", bundle.isJumuah)
  noctalia.state.set("event", bundle.event)
  noctalia.state.set("hadith", bundle.hadith)
  noctalia.state.set("countdown", bundle.countdown)
end

-- Applies + publishes one fetched/cached entry and remembers it for M._tick.
function M._applyEntry(entry, cfg, nowCtx)
  local bundle = M._processEntry(entry, cfg, nowCtx)
  M._publish(bundle)
  M._currentEntry = entry
  M._currentIsRamadan = bundle.isRamadan
  M._status = bundle.status
  M._lastFetchDate = nowCtx.todayISO
  return bundle
end

M._retryCount = 0
M._retryDelays = { 5, 10, 15, 30, 60 }

function M._scheduleRetry(nowCtx)
  local idx = math.min(M._retryCount, #M._retryDelays - 1)
  local delay = M._retryDelays[idx + 1]
  M._retryCount = M._retryCount + 1
  M._nextRetryAt = (nowCtx and nowCtx.nowSec or 0) + delay
  return delay
end

-- Registers the shared "command" watcher exactly once. Installed from
-- M._start() (production boot); tests that don't call M._start() (which only
-- runs past the __MAWAQIT_TEST guard) invoke this directly instead of
-- piggybacking on M._fetch.
function M._installCommandWatch()
  if M._commandWatchInstalled then return end
  M._commandWatchInstalled = true
  noctalia.state.watch("command", function(cmd)
    if type(cmd) ~= "table" then return end
    if cmd.action == "refresh" then
      M._fetch(M._cfg or M._readConfig(), M._nowCtx())
    end
  end)
end

-- Async weekly fetch -> normalize -> process -> publish, with a single-day
-- fallback and a {5,10,15,30,60}s backoff schedule (ported from Main.qml's
-- fetchWeek/fetchSingleDay/scheduleRetry) recorded via M._scheduleRetry.
--
-- Reentrancy: M._fetchInFlight mirrors v4's `_xhr` guard — while a fetch
-- pipeline (weekly, and its possible single-day fallback) is outstanding, a
-- second call is a no-op. The flag is cleared at every terminal outcome:
-- weekly success, single-day fallback success, and both-failed.
--
-- Attempt tracking: M._lastAttemptDate is stamped at the START of every
-- attempt (success or failure) so M._tick's date-rollover check can tell "a
-- fetch was already attempted today" apart from "a fetch already SUCCEEDED
-- today" (M._lastFetchDate, set only in M._applyEntry). Without this, a
-- failed day never advances M._lastFetchDate and every 1s tick would re-enter
-- M._fetch, bypassing the backoff schedule entirely.
function M._fetch(cfg, nowCtx)
  if M._fetchInFlight then return end
  M._fetchInFlight = true
  M._lastAttemptDate = nowCtx.todayISO
  M._cfg = cfg
  noctalia.state.set("status", "loading")
  local ddmmyyyy = isoToDDMMYYYY(nowCtx.todayISO)
  local weeklyUrl = M.buildWeeklyUrl(cfg, ddmmyyyy)
  noctalia.http({ url = weeklyUrl }, function(resp)
    local entry = nil
    if resp and resp.ok and resp.status == 200 then
      local decoded = noctalia.json.decode(resp.body)
      entry = M.normalizeWeekly(decoded, nowCtx.todayISO)
    end
    if entry then
      M._retryCount = 0
      M._nextRetryAt = nil
      M._saveCache(cfg, entry)
      M._applyEntry(entry, cfg, nowCtx)
      M._fetchInFlight = false
      return
    end
    local singleUrl = M.buildSingleDayUrl(cfg)
    noctalia.http({ url = singleUrl }, function(resp2)
      local entry2 = nil
      if resp2 and resp2.ok and resp2.status == 200 then
        local decoded2 = noctalia.json.decode(resp2.body)
        entry2 = M.normalizeSingleDay(decoded2)
      end
      if entry2 then
        M._retryCount = 0
        M._nextRetryAt = nil
        M._saveCache(cfg, entry2)
        M._applyEntry(entry2, cfg, nowCtx)
      else
        M._scheduleRetry(nowCtx)
        M._status = "error"
        noctalia.state.set("status", "error")
        noctalia.state.set("error", noctalia.tr("error.generic"))
      end
      M._fetchInFlight = false
    end)
  end)
end

-- ── Task 3.4: Tick, notifications, command channel, lifecycle ───────────────

-- Minute-boundary notify dedup (via M._lastNotifiedMinute) + emoji title +
-- Arabic body, ported from Main.qml's checkPrayerTimes/onPrayerTime. No azan.
function M._maybeNotify(entry, cfg, ctx, hhmm)
  if not entry or not entry.timings or not hhmm then return end
  if hhmm == M._lastNotifiedMinute then return end
  for _, key in ipairs(M.NOTIFY_KEYS) do
    if entry.timings[key] == hhmm then
      M._lastNotifiedMinute = hhmm
      if cfg.showNotifications then
        if key == "Imsak" then
          noctalia.notify("🌙 Imsak — " .. hhmm, "حان وقت الإمساك")
        else
          local arName = M._PRAYER_NAMES_AR[key] or key
          noctalia.notify("🕌 " .. key .. " — " .. hhmm, "حان الآن موعد صلاة " .. arName)
        end
      end
    end
  end
end

-- Pure-driving tick helper: refetches on date rollover or when a due backoff
-- retry is pending, else republishes the live countdown and checks notifies.
function M._tick(nowCtx)
  local cfg = M._cfg or M._readConfig()
  if not M._lastAttemptDate or nowCtx.todayISO ~= M._lastAttemptDate then
    M._fetch(cfg, nowCtx)
    return
  end
  if M._status == "error" and M._nextRetryAt and nowCtx.nowSec >= M._nextRetryAt then
    M._fetch(cfg, nowCtx)
    return
  end
  if M._currentEntry then
    local ctx = { isRamadan = M._currentIsRamadan, isJumuah = nowCtx.gregWeekday == 5 }
    local countdown = M.computeCountdown(M._currentEntry.timings, nowCtx.nowSec, cfg, ctx)
    noctalia.state.set("countdown", countdown)
    if nowCtx.hhmm then
      M._maybeNotify(M._currentEntry, cfg, ctx, nowCtx.hhmm)
    end
  end
end

-- Builds the tick context from wall-clock time (os.time/os.date), for the
-- host-driven update()/onConfigChanged() globals below.
function M._nowCtx()
  local t = os.date("*t")
  local nowSec = t.hour * 3600 + t.min * 60 + t.sec
  return {
    todayISO = string.format("%04d-%02d-%02d", t.year, t.month, t.day),
    nowSec = nowSec,
    hhmm = string.format("%02d:%02d", t.hour, t.min),
    minute = math.floor(nowSec / 60),
    dayOfYear = t.yday or 0,
    gregWeekday = (t.wday or 1) - 1, -- os.date wday: 1=Sun..7=Sat -> JS-style 0=Sun..6=Sat
  }
end

function M._start()
  local cfg = M._readConfig()
  M._cfg = cfg
  noctalia.setUpdateInterval(1000)
  M._installCommandWatch()
  local ctx = M._nowCtx()
  local cached = M._loadCache(cfg)
  if cached then
    M._applyEntry(cached, cfg, ctx)
  end
  M._fetch(cfg, ctx)
end

function update()
  M._tick(M._nowCtx())
end

function onConfigChanged()
  M._fetch(M._readConfig(), M._nowCtx())
end

function onExit(signal)
end

if _G.__MAWAQIT_TEST or noctalia == nil then return M end
M._start()
