# Mawaqit (مواقيت)

Muslim prayer-times companion for the Noctalia desktop shell: the five daily prayers
(Fajr, Dhuhr, Asr, Maghrib, Isha) plus Sunrise and, during Ramadan, Imsak; a live
countdown to the next prayer; desktop notifications at each prayer time; the Hijri
(Islamic lunar) date; and a navigable Hijri month calendar with Islamic events and a
daily rotating hadith/dhikr.

> Prayer times are fetched live from the **Aladhan API** (`api.aladhan.com`) — despite
> the name, this plugin does not talk to mawaqit.net.

## Features

- **Bar widget** — next-prayer name with a live countdown or the static time; works in
  both horizontal and vertical bar layouts; "prayer now" grace window; optional
  elapsed count-up mode after a prayer starts; option to hide the prayer name and show
  only the time; dynamic icon that follows the next/last prayer; themeable text/icon/
  active colors.
- **Popup panel** — header with refresh/close, Gregorian + Hijri date row (Arabic
  calligraphic date via the bundled DecoType font, with an English fallback), two tabs:
  - **Prayer Times** — countdown card, full prayer list with next-prayer highlighting,
    upcoming-event hint banner (Jumu'ah, Ramadan, Eid, etc.).
  - **Calendar** — 7-column Hijri month grid with prev/next navigation, back-to-today,
    configurable first day of week, Friday highlighting, today marker, past-day
    dimming, Gregorian day overlays, Islamic-event dots with tooltips, a data-source
    indicator (API-synced vs. estimated), and a daily hadith/dhikr.
- **Desktop notifications** at each prayer time (title + Arabic body), toggleable.
- **Islamic events** — fixed and rule-based (Ayyam al-Bid, Laylat al-Qadr nights,
  Eids, Ashura, Mawlid, Isra wal Mi'raj, Day of Arafah, etc.), Ramadan support (Imsak
  row, last-ten-nights banner), Jumu'ah handling that's recomputed every tick (no
  stale-Friday bug across midnight).
- **18 calculation methods** (incl. a fully Custom method with editable Fajr/Isha
  angles), selectable Asr school (Shafi/Maliki/Hanbali vs. Hanafi), and per-prayer
  minute offsets ("tune") for local fine-tuning.
- **Hijri day offset** (−1/0/+1) to align the displayed Hijri date with local moon
  sighting.
- Persistent local cache (weekly timings + per-month calendar) so the widget paints
  instantly on restart and survives brief network/API hiccups.
- Translations: English, French, Turkish, Arabic.

## Not included in this port

- **Azan audio playback was removed in v5 (no audio API).** Noctalia's v5 plugin
  runtime has no way to play audio (and no mechanism to shell out to an external
  player as a declared dependency), so the bundled azan mp3s, the `playAzan`/
  `azanFile` settings, the bar's stop/volume icons, and the settings-screen azan
  preview from the v4 plugin are all gone. Prayer **notifications** (title + body)
  still fire at each prayer time.
- There is no in-panel settings shortcut (v5 has no API to open the plugin settings
  screen from a panel) — configure the plugin from **Settings → Plugins** instead.

## Settings

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `city` | string | `London` | City name used for the Aladhan lookup. |
| `country` | string | `UK` | Country name or ISO code. |
| `method` | select | `3` (Muslim World League) | Calculation authority; 18 options incl. `99` = Custom. |
| `fajrAngle` | string | `""` | Custom Fajr solar angle; only shown when `method = Custom`. |
| `ishaAngle` | string | `""` | Custom Isha solar angle; only shown when `method = Custom`. |
| `school` | select | `0` | Asr shadow factor: `0` Shafi/Maliki/Hanbali, `1` Hanafi. |
| `hijriDayOffset` | select | `0` | Shift the displayed Hijri date: `-1` / `0` / `+1` day. |
| `weekStartDay` | select | `1` | Calendar week start: `6` Saturday, `0` Sunday, `1` Monday. |
| `tune` | bool | `false` | Enables the per-prayer minute offsets below. |
| `tuneFajr` … `tuneIsha` | int | `0` | Per-prayer minute offset (Fajr/Dhuhr/Asr/Maghrib/Isha); shown only when `tune = true`. |
| `showCountdown` | bool | `true` | Bar shows a live countdown instead of the static time. |
| `showElapsed` | bool | `false` | Count up (≤ 1 hour) after a prayer starts, instead of counting down to the next one. |
| `hidePrayerName` | bool | `false` | Bar shows only the time/countdown, without the prayer name. |
| `use12hourFormat` | bool | `false` | Use AM/PM instead of 24-hour time. |
| `widgetIcon` | glyph | `building-mosque` | Bar icon glyph. |
| `dynamicIcon` | bool | `false` | Bar icon follows the next/last prayer instead of the fixed icon. |
| `textColor` | select | `none` | Bar text color role (`none`/`primary`/`secondary`/`tertiary`/`error`). |
| `iconColor` | select | `none` | Bar icon color role. |
| `activeColor` | select | `primary` | Bar color used while the state is Now/Elapsed. |
| `showNotifications` | bool | `true` | Send a desktop notification at each prayer time. |
| `notifyMinutesBefore` | int | `15` | Send a reminder this many minutes before each prayer (0 = off). Shown only when `showNotifications` is on. |

## Data source

All prayer times and the Hijri calendar come from the free, keyless
[Aladhan API](https://aladhan.com/prayer-times-api) (`api.aladhan.com`) — a 7-day
weekly timings endpoint (with single-day fallback), and the `hToGCalendar`
Hijri→Gregorian calendar endpoint for the calendar tab.

## License

MIT
