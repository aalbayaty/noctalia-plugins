# Mawaqit — v4 (QML) → v5 (Luau) Port Design

**Date:** 2026-07-16
**Target repo:** `github.com/aalbayaty/noctalia-plugins` (plugin lives at repo-root `mawaqit/`)
**Plugin identity:** `id = "aalbayaty/mawaqit"`, `author = "aalbayaty"`, `min_noctalia = "5.0.0"`
**Source:** Noctalia v4 plugin `mawaqit` v1.3.7 (from `noctalia-dev/legacy-v4-plugins`)
**Scope decision:** Full feature parity **minus azan audio playback** (notifications only).
**Repo model:** Multi-plugin monorepo — `mawaqit/` is the first plugin; the shared root
scaffolding (§4) makes porting further plugins turnkey.

---

## 1. Purpose

"Mawaqit" (مواقيت, "appointed times") is a Muslim prayer-times companion for the Noctalia
desktop shell. It shows the five daily prayers (Fajr, Dhuhr, Asr, Maghrib, Isha) plus Sunrise
and, during Ramadan, Imsak; a live countdown to the next prayer; desktop notifications at each
prayer time; the Hijri (Islamic lunar) date; and a navigable Hijri month calendar with Islamic
events and a daily hadith/dhikr.

Despite the name, **all data comes from the Aladhan API (`api.aladhan.com`)**, not mawaqit.net.

## 2. Scope

**In scope (full parity):**
- Prayer-times fetch (7-day prefetch + single-day fallback), 18 calculation methods incl. Custom
  (id 99) with Fajr/Isha angles, Asr school (Shafi/Hanafi), per-prayer minute offsets ("tune").
- Bar widget: next-prayer name + live countdown or static time; horizontal & vertical layouts;
  "prayer now" grace window; elapsed count-up mode; hide-prayer-name; dynamic icon; theme colors.
- Popup panel: header, Gregorian + Hijri date, two tabs (Prayer Times / Calendar), countdown
  card, prayer list with next-prayer highlighting, upcoming-event hint banner.
- Desktop notifications at each prayer time (emoji title + Arabic body).
- Hijri calendar: 7-column grid, prev/next navigation, back-to-today, configurable week start,
  Friday highlight, today circle, past-day dimming, Gregorian day overlays, Islamic-event dots +
  tooltips, data-source indicator (API-synced vs arithmetic), last-synced label.
- Islamic events map (fixed + rule-based: Ayyam al-Bid, Laylat al-Qadr nights, Eids, etc.),
  Ramadan support (Imsak row, Iftar/Imsak highlighting, last-10-nights banner), Jumu'ah handling.
- Daily rotating hadith/dhikr (30-item Arabic pool with sources).
- Hijri day offset (−1/0/+1) for local moon-sighting; DecoType Arabic calligraphic font with
  English fallbacks.
- Persistent cache (weekly timings + per-month calendar) surviving restarts.
- Translations: en, fr, tr (+ ar where useful).

**Out of scope (dropped from v4):**
- **Azan audio playback** — v5 has no audio API; would require shelling out to an external
  player declared as a dependency. Removed entirely: no bundled mp3s, no `playAzan`/`azanFile`
  settings, no volume/stop UI in the bar, no azan preview in settings. Notifications remain.

## 3. Target platform constraints (v5)

The v5 plugin runtime differs fundamentally from v4 QML. Key constraints that shape this design
(verified against `noctalia.d.luau`, the `example/` plugin, and `validate-plugins.py`):

- **Language:** Luau (`--!nonstrict` at top of every file). Type annotations are a runtime no-op.
- **Entries are isolated script instances** — no shared Lua memory. They communicate via
  `noctalia.state` (in-memory pub/sub, `set`/`get`/`watch`) which is **lost on restart**.
- **Declarative UI only**, from a fixed `ui.*` vocabulary: `column, row, box, label, glyph,
  image, separator, spacer, progress, button, graph, input, select, slider, toggle, scroll`.
  **No tab component, no canvas, no custom QML.** The host diffs & patches the tree, so
  re-rendering the whole tree on every state change is cheap and idiomatic.
- **Settings UI is 100% auto-generated** from the `plugin.toml` `[[setting]]` schema. No settings
  code. `noctalia.getConfig(key)` reads; **there is no `setConfig`** (plugins can't write settings).
- **HTTP is async/callback-only:** `noctalia.http(req, onResponse)`; ≤8 concurrent ops/plugin;
  `noctalia.json.decode/encode`; `noctalia.string.urlEncode`.
- **No audio API.** (Reason azan is dropped.)
- **Notifications:** `noctalia.notify(title, body?)` / `notifyError` — title+body only, **no
  urgency, icon, or actions**.
- **Timers:** `noctalia.setUpdateInterval(ms)` + global `update()`; `panel.setWantsSecondTicks`;
  no cron/setTimeout. Compute next-event timestamps from wall clock (`os.time()`).
- **Durable storage = files** via `noctalia.pluginDataDir()` + `writeFile`/`readFile`. Survives
  updates. (v4 stored cache inside the settings blob — that moves to files here.)
- **Fonts:** `noctalia.loadFont(path) -> family`, usable via `barWidget.setFont` or ui label
  `fontFamily`.
- **Assets** referenced by plugin-relative path; shell commands need absolute via `pluginDir()`.
- **No API to read the shell's global 12h/24h preference** → becomes a plugin setting.
- **No API to open the plugin settings screen** from a panel → the v4 in-panel settings button
  is dropped (users edit via Settings → Plugins).

## 4. Repository & plugin layout

The repo is a **multi-plugin monorepo** (like `noctalia-dev/official-plugins`): one top-level
directory per plugin, plus shared root scaffolding used by every plugin. The scaffolding is set up
once (Phase 0) and reused for every future port.

```
noctalia-plugins/                 (repo root)
├── README.md                     repo overview + "How to add a plugin" guide
├── noctalia.d.luau               v5 plugin API type defs (copied from official-plugins) — shared
│                                 editor autocomplete/diagnostics for ALL plugins
├── .luaurc                       Luau nonstrict config (shared)
├── .vscode/settings.json         points luau-lsp at noctalia.d.luau (shared)
├── .gitignore                    __pycache__, editor cruft
├── catalog.toml                  AUTO-GENERATED by CI (one [[plugin]] per dir) — never hand-edit
├── .github/
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── workflows/
│       ├── validate-plugins.yml / .py   adapted from official (see §13): enforces
│       │                                id == "<author>/<dirname>", schema, translation keys
│       └── update-catalog.yml    / .py   regenerates catalog.toml on push to main (author-agnostic)
├── docs/superpowers/specs/       design specs (this file)
├── mawaqit/                      ← FIRST plugin (this port)
│   └── … (plugin files below)
└── <future-plugin>/             ← each subsequent port is just another top-level dir
```

Each plugin directory is self-contained:

```
mawaqit/
├── plugin.toml            manifest: metadata, entries, full [[setting]] schema
├── service.luau           [[service]] "scheduler" — source of truth
├── widget.luau            [[widget]] "bar" — capsule, click → panel
├── panel.luau             [[panel]] "panel" — prayer list + Hijri calendar tabs
├── fonts/
│   └── DecoType.ttf       Arabic calligraphic display font
├── translations/
│   ├── en.json
│   ├── fr.json
│   ├── tr.json
│   └── ar.json            (optional; Arabic strings are inline-Arabic regardless of locale)
├── tests/                 luau unit tests (run with local `luau` CLI; NOT loaded by the shell)
│   ├── harness.luau       mock noctalia/ui/barWidget/panel globals + tiny assert runner
│   ├── logic_test.luau    prayer/countdown/hijri/events/hadith logic (service internals)
│   ├── widget_test.luau   widget render-from-state assertions
│   └── panel_test.luau    panel render-from-state assertions
├── thumbnail.webp         converted from v4 preview.png (16:9)
└── README.md
```

**No `require` at runtime.** Noctalia loads each entry into an isolated sandbox **without
`require`** (verified: mpvpaper's source comments "Noctalia plugin scripts run in an isolated
sandbox without `require`"). So there is no runtime-shared `lib/` directory. Instead
**`service.luau` is the sole owner of all non-trivial logic** (fetch, parse, countdown, Hijri
date, calendar, events, hadith, notifications) and publishes **pre-computed, display-ready**
values to `noctalia.state`; `widget.luau` and `panel.luau` are **thin renderers** that read state
and send commands back for interactions. Heavy logic therefore lives in exactly one file — nothing
is duplicated across entries. Testing strategy is in §5.4.

## 5. Component design

### 5.1 `service.luau` — `[[service]]` "scheduler" (sole logic owner)

Runs headless for the whole session (notifications/scheduling work even with no bar widget
placed). Owns ALL non-trivial logic and publishes display-ready values; the widget/panel never
compute prayer/Hijri/calendar data themselves.

- **On load:** read cache from `pluginDataDir()/prayer_cache.json` (instant paint), then
  revalidate over the network. `noctalia.setUpdateInterval(1000)`.
- **Prayer fetch** (async): build the Aladhan weekly URL (§6), `noctalia.http`, parse via
  `noctalia.json.decode`, extract today's entry (match `dd-MM-yyyy`→ISO against system date),
  compute cleaned `timings`, Hijri date fields, `isRamadan`, `isJumuah` (recomputed each tick —
  fixes v4's stale-Friday bug). On API/parse/transport error, fall back to the single-day
  endpoint; on failure schedule a backoff retry (`{5,10,15,30,60}` s). Cache validated against
  `city/country/method/school/fajrAngle/ishaAngle`; mismatch → refetch.
- **Calendar** (service-owned, so the Hijri/JDN/events logic exists in ONE file): the panel
  requests a month via the command channel; the service fetches `hToGCalendar/{m}/{y}` (cached to
  `pluginDataDir()/cal_{y}_{m}.json`, TTL 30 days, JDN estimation for un-synced months), builds a
  ready-to-render grid (per-cell: gregorian-day overlay, isToday, isPast, isFriday, event name
  en/ar), and publishes it to `state.calendar`.
- **Publish** to `noctalia.state` (all display-ready): `status` (loading/ok/error), `error`,
  `prayers` (ordered list of `{key,label,time,isNext,highlight}`), `hijri`
  (`{display, displayAr, day, month, year, monthNameEn, monthNameAr, days}`), `gregorian`,
  `isRamadan`, `isJumuah`, `event` (current/upcoming hint), `hadith` (`{text, source}`),
  `calendar`, and — once per second — `countdown`
  (`{next, label, secondsToNext, text, mode, color, glyph, elapsed}`) where `text`/`glyph`/`color`
  are already resolved for the bar so the widget only places them.
- **Tick (`update()`, 1 s):** on date rollover → refetch/reprocess; else recompute countdown /
  elapsed / "now" grace and, at each minute boundary, compare `HH:MM` against
  `{Imsak,Fajr,Dhuhr,Asr,Maghrib,Isha}` → `noctalia.notify` (dedup via last-notified minute).
  **No azan.** Imsak only participates during Ramadan.
- **Pre-prayer reminder (added v2.1.0):** a second, independent notify path fires
  `cfg.notifyMinutesBefore` minutes (int, default 15, range 0–30, 0 = off) before each of the
  five prayers — **excluding Imsak** (Imsak is itself a pre-Fajr marker). The lead minute is
  computed from wall-clock arithmetic via the pure helper `_shiftHHMM(prayerHHMM, -lead)`
  (wraps modulo 24 h, so a 00:10 Fajr with lead 15 fires at 23:55). Dedup uses a separate
  `_lastPreNotifiedMinute` slot so a pre-reminder and an at-prayer notify can both fire for the
  same prayer. Both slots are cleared in `onConfigChanged()`. Title: `🕌 Dhuhr in 15 min — 13:05`;
  body (Arabic, all locales): `صلاة الظهر بعد ١٥ دقيقة` ("Dhuhr prayer is in 15 minutes").
- **`onConfigChanged()`:** clear affected caches and refetch.
- **Command channel** (`noctalia.state.watch("command", …)`): the panel/widget publish
  `{action, ts, …}` — `refresh` (refetch prayers), `calendar` (`{month, year}` → build/publish
  that month), `calendarRefresh` (force network re-sync of a month).
- **`onExit(signal)`:** nothing to clean up (no child processes once azan is dropped).

### 5.2 `widget.luau` — `[[widget]]` "bar" (thin renderer)

`noctalia.state.watch("countdown"/"status", render)`; on click →
`noctalia.togglePanel("aalbayaty/mawaqit:panel")`. Renders via `barWidget.render()` (declarative,
for the icon+text composite and vertical layout) using `barWidget.isVertical()` to pick `ui.row`
vs `ui.column`. The display string, glyph, and color-state are read straight from the
service-published `countdown` (the v4 display ladder — loading→`"..."`, error→`"!"`, no-data→`"—"`,
elapsed→`"{label} +Xm"`, now→`"{label} · Now"`, countdown→`"{label} {Xh Ym}"`, else `"{label}
{HH:MM}"`, all 12h-aware and honoring `hidePrayerName`/`dynamicIcon` — is computed in the service).
The widget's only local logic is mapping the published color-state (`"normal"`/`"active"`) plus the
`textColor`/`iconColor`/`activeColor` settings to ui theme roles. Tooltip:
`"{label}: {time}\nTime remaining: {countdown}"`. **Removed:** azan volume/stop icons.

### 5.3 `panel.luau` — `[[panel]]` "panel" (thin renderer)

`[[panel]]` sized `width=360, height≈640, placement="floating", position="center"`. Declarative
`panel.render(tree)`; watches `countdown`/`prayers`/`calendar`/`hijri`/`event`/`hadith` state and
re-renders. Local UI-only state: `activeTab` (0 = prayers, 1 = calendar) and the currently-viewed
calendar `{month, year}`. All data is read from state — the panel computes nothing.

- **Header row:** `ui.glyph` widget icon + bold title + spacer + refresh `ui.button` (publishes
  `command={action="refresh"}` on tab 0, `command={action="calendarRefresh",…}` on tab 1) + close
  `ui.button` → `panel.close()`. (v4 settings button dropped — no API to open plugin settings.)
- **Date row:** `state.gregorian` (left) + `state.hijri.displayAr` (right, DecoType font,
  Arabic-Indic numerals; `state.hijri.display` English fallback).
- **Tabs:** two `ui.button`s (variant reflects `activeTab`); clicking sets `activeTab`, and
  entering the calendar tab publishes `command={action="calendar", month, year}`.
- **Hint banner:** tertiary@10% box, `state.event` ("Today/Tomorrow/in N days" + Arabic name).
- **Tab 0 — Prayer Times:** countdown card (`ui.box` fill = `countdown.color`@12%, big
  `countdown.text`, Arabic "now" line during grace); loading/error strip from `status`/`error`;
  prayer list = `ui.column` of `ui.row`s over `state.prayers` (glyph + label + time), each row's
  `isNext`/`highlight` driving fill/color; empty state.
- **Tab 1 — Calendar:** renders `state.calendar` (already a ready grid). Nav row (chevrons publish
  `command={action="calendar", month±1, year}`, month/year label, sync/estimate indicator),
  back-to-today link, weekday header (rotated by `weekStartDay`, Friday highlighted), 7-col grid of
  cells (`ui.box`/`ui.button`) using each cell's precomputed `isToday`/`isPast`/`isFriday`/`event`/
  `gday`; event cells show a dot + hover tooltip (Arabic event); below: today's event line,
  last-10-nights banner, `state.hadith` block, last-synced label.

### 5.4 Logic organization & testing

Because the sandbox has no `require`, the runtime logic lives directly inside `service.luau` as
sectioned `local` functions (URL builders; response normalizer; countdown/next-prayer/elapsed;
`toJDN`/`parseToJDN`/weekday/month-length estimation with the 12th-month leap table
`{2,5,7,10,13,16,18,21,24,26,29} mod 30`; events map with en+ar names and Ayyam al-Bid/Qadr rules;
upcoming-event look-ahead tiers; 30-item hadith pool; 12/24h + Arabic-Indic formatting; the
prayer→glyph map and color-key→role map).

**Testing without a shell.** The local toolchain is `luau` (run scripts) + `luau-analyze`
(typecheck/lint) + `python3 .github/workflows/validate-plugins.py` (manifest). Two techniques make
the logic and the renderers unit-testable off-shell:

1. **`__TEST` export.** Each entry ends with `if _G.__MAWAQIT_TEST then return { …internals… } end`.
   In production `__MAWAQIT_TEST` is nil, so the guard is skipped and the chunk finishes normally
   (the shell never sees a return); in tests the harness sets the flag, `load(src)()` returns the
   internal function table, and assertions run against pure functions (`computeCountdown`,
   `toJDN`, `eventsFor`, `formatTime`, …) with no network/time dependence (time and decoded-JSON
   tables are passed in as arguments).
2. **Mock-global harness** (`tests/harness.luau`): installs stub `noctalia`, `ui`, `barWidget`,
   `panel` globals that record calls and return `UiNode`-shaped tables (`{type, props, children}`)
   from `ui.*`, so `widget`/`panel` renders can be driven from a fake state and asserted on tree
   shape (glyph names, labels, fills) — no real shell required.

`luau-analyze` is a clean gate for pure code but flags the injected globals as "unknown" in the
entry files; the test/CI step runs it and filters out only the known-injected-global lines
(`noctalia`, `ui`, `barWidget`, `shortcut`, `launcher`, `desktopWidget`, `panel`), treating any
other diagnostic as a failure. Live UI/behavior verification happens on the user's v5 shell.

## 6. Aladhan API endpoints

1. **Weekly** — `https://api.aladhan.com/v1/timingsByCity/{dd-MM-yyyy}?city={city}&country={country}
   &method={method}&methodSettings={fajrAngle|null},null,{ishaAngle|null}&school={school}&days=7
   &tune={tuneParam}` where `tuneParam` = `0,{tuneFajr},0,{tuneDhuhr},{tuneAsr},{tuneMaghrib},0,
   {tuneIsha},0` when `tune` on else all-zero. Uses `json.data[]` (`date`, `timings`, `hijri`,
   `readable`); times cleaned by stripping ` (…)`.
2. **Single-day fallback** — `https://api.aladhan.com/v1/timingsByCity?city=…&country=…&method=…
   &methodSettings=…&school=…&tune=…` → `json.data.{timings,date.gregorian.date,date.hijri,
   date.readable}`.
3. **Hijri→Gregorian calendar** — `https://api.aladhan.com/v1/hToGCalendar/{month}/{year}` →
   `res.data[]` with `gregorian.{day,month.en,year}`.

No auth/keys. All GET. Async via `noctalia.http`; JSON via `noctalia.json.decode`; params
url-encoded via `noctalia.string.urlEncode`.

## 7. Settings schema (`plugin.toml` plugin-level `[[setting]]`)

Shared by all entries. All v4 settings except azan; proper defaults added for the three v4 keys
that lacked manifest defaults (`weekStartDay`, `fajrAngle`, `ishaAngle`).

| key | type | default | notes |
|---|---|---|---|
| `city` | string | `London` | Aladhan `city` |
| `country` | string | `UK` | Aladhan `country` |
| `method` | select | `3` | 18 options: 1,2,3,4,5,7,8,9,10,11,12,13,14,15,16,19,23,99 |
| `fajrAngle` | string | `""` | `visible_when method=99`; parsed float, empty→null |
| `ishaAngle` | string | `""` | `visible_when method=99` |
| `school` | select | `0` | 0 Shafi/Maliki/Hanbali, 1 Hanafi |
| `hijriDayOffset` | select | `0` | −1 / 0 / +1 |
| `weekStartDay` | select | `1` | 6 Sat / 0 Sun / 1 Mon |
| `tune` | bool | `false` | enables offsets |
| `tuneFajr…tuneIsha` | int | `0` | `visible_when tune=true`; min/max e.g. −30..30 |
| `showCountdown` | bool | `true` | |
| `showElapsed` | bool | `false` | count-up ≤1h after prayer |
| `hidePrayerName` | bool | `false` | |
| `showNotifications` | bool | `true` | |
| `widgetIcon` | glyph | `building-mosque` | |
| `dynamicIcon` | bool | `false` | |
| `textColor` | select | `none` | none/primary/secondary/tertiary/error |
| `iconColor` | select | `none` | |
| `activeColor` | select | `primary` | used during Now/Elapsed |
| `use12hourFormat` | bool | `false` | **new** — replaces v4's shell-global 12h flag |

Every `label_key`/`description_key`/option `label_key` must exist in `translations/en.json`
(CI-validated).

## 8. Persistence & state

- **Durable (files in `pluginDataDir()`):** `prayer_cache.json` (weekly timings + validation
  keys + savedAt), `cal_{y}_{m}.json` (per-month calendar, `{timestamp, data}`; TTL 30 days,
  prune >1 year). Replaces v4's practice of stuffing `_cache*`/`_cal_*` into the settings blob.
- **In-memory (`noctalia.state`, lost on restart, repopulated by service on load):** `status`,
  `error`, `prayers`, `hijri`, `gregorian`, `isRamadan`, `isJumuah`, `event`, `hadith`,
  `calendar`, `countdown`, `command` (all display-ready; see §5.1).

## 9. Translations

Port v4 `i18n/{en,fr,tr}.json` to `translations/{en,fr,tr}.json` as nested dot-path objects
(`noctalia.tr`/`trp`). **Remove azan keys** (`settings.azan*`, `widget.stopAzan`, `settings.azan1/2/3`).
Add `settings.use12hourFormat.{label,description}`. Also i18n-ify strings v4 hardcoded in English
(`"in N days"`, `"Syncing…"`, `"Sync:"`, weekday abbreviations, Hijri month names,
method/school/weekStartDay/hijriDayOffset option labels). Intentionally-Arabic strings (hadith,
event names, notification bodies, banners) stay Arabic in all locales. Complete the incomplete
Turkish file where feasible; otherwise host falls back to en.

## 10. Risks & mitigations

1. **Arabic/RTL shaping in `ui.*` is untested** (Hijri date, event names, hadith, DecoType). →
   Keep v4's English-fallback paths; build & eyeball the Arabic/calendar surfaces early on the
   user's v5 shell before completing the calendar tab.
2. **Glyph-name availability** — v4 icon names must exist in v5's glyph set. → Verify each against
   the picker; substitute the closest match where missing (the prayer→glyph map in `service.luau`
   is the single place to fix).
3. **No `require` in the sandbox (RESOLVED)** — confirmed via mpvpaper's source comments. Handled
   by making `service.luau` the sole logic owner (widget/panel are thin state-renderers), so no
   cross-entry code sharing is needed. Logic stays testable via the `__TEST` export + `luau`.
4. **Calendar complexity** — the v4 calendar is 911 lines of QML; the 7-col grid must be rebuilt
   from `ui.box`/`ui.row` and the service must pre-shape the grid. Ship prayer-times first,
   calendar second.
5. **Local verification is real but partial** — installed toolchain: `luau` (unit-run logic +
   mock-global renderer tests), `luau-analyze` (typecheck/lint, injected-globals filtered),
   `python3 validate-plugins.py` (manifest). These gate logic + manifest correctness locally; live
   UI/RTL/behavior verification happens on the user's v5 shell (they are standing one up).
6. **`isJumuah` staleness** — v4 snapshotted Friday-ness once; the service recomputes it each tick,
   fixing the midnight-rollover bug.

## 11. Delivery

- Multi-plugin monorepo (§4, §13); `mawaqit/` at repo root; `id="aalbayaty/mawaqit"`,
  `author="aalbayaty"`.
- Do **not** hand-edit `catalog.toml` (regenerated by `update-catalog.py` on push to main); the
  plan runs the generator once to seed it.
- Commit incrementally; push to `github.com/aalbayaty/noctalia-plugins` on the user's go-ahead.

## 12. Build phases (for the implementation plan)

0. **Repo scaffolding (multi-plugin monorepo, §13)** — root `README.md`, `noctalia.d.luau`,
   `.luaurc`, `.vscode/settings.json`, `.gitignore`, adapted `.github/workflows/` (validator +
   catalog generator), initial `catalog.toml`. One-time; reused by every future plugin.
1. **Scaffold + manifest + i18n + test harness** — `mawaqit/plugin.toml` (all settings),
   `translations/en.json`, `tests/harness.luau` (mock globals + assert runner). Passes
   `validate-plugins.py` and `luau tests/harness.luau`.
2. **Service logic (pure, TDD)** — URL builders, response normalizer, countdown/next/elapsed,
   Hijri `toJDN`/`parseToJDN`/month-length, events map, hadith pool, formatters — all as `local`s
   in `service.luau` exposed via the `__TEST` export and unit-tested with `luau tests/logic_test.luau`.
3. **Service runtime wiring** — load/cache/fetch/tick/notify/state-publish/command-channel using
   the tested logic. `luau-analyze` clean (filtered); verify on shell via IPC/logs.
4. **Bar widget** — declarative capsule from `countdown` state, H/V, colors, tooltip,
   click→panel; `tests/widget_test.luau` asserts tree shape via the mock harness.
5. **Panel — Prayer Times tab** — header, date row, tabs, countdown card, prayer list, hint
   banner, empty/error; `tests/panel_test.luau` for tree shape.
6. **Calendar tab + service calendar** — service-side grid build/publish + panel calendar render,
   navigation, overlays, indicators, hadith/events; **validate Arabic/RTL rendering on v5 shell here.**
7. **Polish + fr/tr/ar translations + README + thumbnail**, final `validate-plugins.py` +
   full `luau` test run, push.

## 13. Repository scaffolding (multi-plugin monorepo)

Set up once so every future plugin port is "drop a directory + `plugin.toml`".

**Shared editor/runtime config (copied verbatim from `noctalia-dev/official-plugins`):**
- `noctalia.d.luau` — the full v5 API type definitions; gives autocomplete + typo diagnostics to
  every plugin in the repo.
- `.luaurc` — `{ languageMode: "nonstrict", lint.FunctionUnused: false, lintErrors: false }`.
- `.vscode/settings.json` — points luau-lsp at `noctalia.d.luau`, ignores `**/*.d.luau`.
- `.gitignore` — at least `/.github/workflows/__pycache__`.

**CI (adapted from official; both scripts glob `*/plugin.toml`, so they scale to N plugins):**
- `validate-plugins.py` — copied, with **one change**: the official version hard-codes
  `expected_id = f"noctalia/{plugin_dir}"`. Replace it with a consistency check that works for any
  author in a personal repo: `expected_id = f"{manifest['author']}/{plugin_dir}"` (id must equal
  `<author>/<directory-name>`). Everything else (root fields, semver, entry schema, setting types,
  `visible_when`, translation-key existence against `translations/en.json`, panel placement/size)
  is kept as-is. Run locally with `python3 .github/workflows/validate-plugins.py`.
- `update-catalog.py` — copied **unchanged** (already author-agnostic; reads `id/name/version/
  author/min_noctalia/tags` + optional `license/icon/description/deprecated` from each
  `*/plugin.toml` and rewrites `catalog.toml`, preserving existing order). Run once to seed
  `catalog.toml`; the `update-catalog.yml` Action keeps it current on push to main.
- `validate-plugins.yml` / `update-catalog.yml` — the workflow wrappers; adapt branch/paths as
  needed. Validation runs on PRs; catalog regen runs on push to main.
- `PULL_REQUEST_TEMPLATE.md` + issue templates — optional, copy/trim from official.

**"How to add a plugin" (documented in the repo README):**
1. Create a top-level `<plugin>/` directory.
2. Add `plugin.toml` with `id = "<author>/<plugin>"` (must equal author + dir name),
   `min_noctalia`, `tags`, `dependencies`, and at least one entry.
3. Add the entry `.luau` files, `translations/en.json` (every `label_key`/`description_key`
   referenced by the manifest must exist here), and optional assets/thumbnail.
4. `python3 .github/workflows/validate-plugins.py` must pass.
5. `python3 .github/workflows/update-catalog.py` to refresh `catalog.toml` (or let CI do it).
6. Commit; push.

**Note:** if this repo is intended purely for one author's plugins, the validator's `expected_id`
can instead hard-code the owner (`f"aalbayaty/{plugin_dir}"`); the `author`-derived form above is
preferred because it also accepts co-maintainers' plugins without further edits.
