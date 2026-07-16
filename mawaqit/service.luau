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

if _G.__MAWAQIT_TEST or noctalia == nil then return M end
