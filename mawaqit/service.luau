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

if _G.__MAWAQIT_TEST or noctalia == nil then return M end
