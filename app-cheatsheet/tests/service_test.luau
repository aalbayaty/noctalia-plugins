--!nonstrict
-- Tests for the app-cheatsheet service. Run: luau app-cheatsheet/tests/service_test.luau
local H = require("./harness")
local M = H.loadEntry("../service")

local USER = "/home/test/.local/share/applications"
local SYS = "/sys/share/applications"

local function scanOf(dir, files)
  local lines = {}
  for _, file in ipairs(files) do
    for _, line in ipairs(file.lines) do table.insert(lines, dir .. "/" .. file.name .. ":" .. line) end
  end
  return table.concat(lines, "\n") .. "\n"
end

local function names(group)
  local out = {}
  for _, app in ipairs(group.apps) do table.insert(out, app.name) end
  return table.concat(out, ",")
end

local function groupNames(groups)
  local out = {}
  for _, group in ipairs(groups) do table.insert(out, group.name) end
  return table.concat(out, ",")
end

-- ── appDirs / desktopId ─────────────────────────────────────────────
H.test("appDirs: user dir first, XDG_DATA_DIRS order, de-duplicated", function()
  local dirs = M.appDirs("/home/test", nil, "/a/share:/b/share/:/a/share")
  H.eq(table.concat(dirs, " "), "/home/test/.local/share/applications /a/share/applications /b/share/applications", "dirs")
end)
H.test("appDirs: XDG_DATA_HOME wins, spec defaults when XDG_DATA_DIRS unset", function()
  local dirs = M.appDirs("/home/test", "/data", "")
  H.eq(table.concat(dirs, " "), "/data/applications /usr/local/share/applications /usr/share/applications", "dirs")
end)
H.test("desktopId: subdirectories become dashes", function()
  H.eq(M.desktopId(SYS .. "/firefox.desktop", SYS), "firefox", "plain")
  H.eq(M.desktopId(SYS .. "/kde/okular.desktop", SYS), "kde-okular", "nested")
  H.eq(M.desktopId("/elsewhere/x.desktop", SYS), nil, "outside dir")
end)

-- ── parseScan ───────────────────────────────────────────────────────
H.test("parseScan: reads only the [Desktop Entry] group", function()
  local entries = M.parseScan(scanOf(SYS, { { name = "firefox.desktop", lines = {
    "[Desktop Entry]", "Name=Firefox", "Type=Application", "Icon=firefox", "Categories=Network;WebBrowser;",
    "[Desktop Action new-window]", "Name=New Window",
  } } }), SYS, {})
  H.eq(entries.firefox.fields.Name, "Firefox", "name not overwritten by the action")
  H.eq(entries.firefox.fields.Categories, "Network;WebBrowser;", "categories")
  H.eq(entries.firefox.path, SYS .. "/firefox.desktop", "path")
end)
H.test("parseScan: strips CR and tolerates colons in values", function()
  local entries = M.parseScan(SYS .. "/a.desktop:[Desktop Entry]\r\n" .. SYS .. "/a.desktop:Name=A: the app\r\n", SYS, {})
  H.eq(entries.a.fields.Name, "A: the app", "name")
end)
H.test("parseScan: an earlier directory masks the same id later", function()
  local entries = {}
  M.parseScan(scanOf(USER, { { name = "steam.desktop", lines = { "[Desktop Entry]", "Name=Mine", "Type=Application", "NoDisplay=true" } } }), USER, entries)
  M.parseScan(scanOf(SYS, { { name = "steam.desktop", lines = { "[Desktop Entry]", "Name=Steam", "Type=Application" } } }), SYS, entries)
  H.eq(entries.steam.fields.Name, "Mine", "user entry kept")
  H.eq(entries.steam.fields.NoDisplay, "true", "still hidden")
end)

-- ── isVisible ───────────────────────────────────────────────────────
H.test("isVisible: filters non-GUI and hidden entries", function()
  H.ok(M.isVisible({ Type = "Application", Name = "A" }, "niri"), "plain app")
  H.ok(not M.isVisible({ Type = "Link", Name = "A" }, "niri"), "not an application")
  H.ok(not M.isVisible({ Type = "Application" }, "niri"), "no name")
  H.ok(not M.isVisible({ Type = "Application", Name = "A", NoDisplay = "true" }, "niri"), "NoDisplay")
  H.ok(not M.isVisible({ Type = "Application", Name = "A", Hidden = "true" }, "niri"), "Hidden")
  H.ok(not M.isVisible({ Type = "Application", Name = "A", Terminal = "true" }, "niri"), "Terminal")
end)
H.test("isVisible: OnlyShowIn / NotShowIn against XDG_CURRENT_DESKTOP", function()
  H.ok(not M.isVisible({ Type = "Application", Name = "A", OnlyShowIn = "GNOME;KDE;" }, "niri"), "only elsewhere")
  H.ok(M.isVisible({ Type = "Application", Name = "A", OnlyShowIn = "GNOME;niri;" }, "niri"), "only here")
  H.ok(not M.isVisible({ Type = "Application", Name = "A", NotShowIn = "niri;" }, "foo:niri"), "not here")
  H.ok(M.isVisible({ Type = "Application", Name = "A", NotShowIn = "KDE;" }, nil), "no desktop set")
end)

-- ── categorize ──────────────────────────────────────────────────────
H.test("categorize: specific sub-categories beat broad ones", function()
  H.eq(M.categorize("Network;WebBrowser;"), "Browsers", "browser")
  H.eq(M.categorize("Network;Email;"), "Communication", "mail")
  H.eq(M.categorize("Network;FileTransfer;Game;"), "Games", "steam")
  H.eq(M.categorize("Network;RemoteAccess;"), "Remote & Network", "remote")
  H.eq(M.categorize("Utility;TextEditor;Development;"), "Development", "editor")
  H.eq(M.categorize("System;Utility;FileManager;"), "System & Settings", "file manager")
  H.eq(M.categorize("AudioVideo;Audio;Mixer;Settings;"), "Media", "mixer")
  H.eq(M.categorize("Utility;"), "Utilities", "utility")
  H.eq(M.categorize("X-Whatever;"), "Other", "unknown")
  H.eq(M.categorize(nil), "Other", "missing")
end)

-- ── settings parsing ────────────────────────────────────────────────
H.test("parseOverrides: list or separated string, trimmed, case-insensitive keys", function()
  local map = M.parseOverrides({ " Steam = Games ", "org.remmina.Remmina=Work; zed=Work", "broken", "=x", "y=" })
  H.eq(map["steam"], "Games", "list item")
  H.eq(map["org.remmina.remmina"], "Work", "id")
  H.eq(map["zed"], "Work", "semicolon-separated")
  H.eq(map["broken"], nil, "no equals")
  H.eq(map["y"], nil, "empty category")
  H.eq(M.parseOverrides("a=B\nc=D")["c"], "D", "plain string")
  H.eq(next(M.parseOverrides(nil)), nil, "nil")
end)

-- ── buildGroups ─────────────────────────────────────────────────────
local function entry(id, fields)
  fields.Type = fields.Type or "Application"
  return { id = id, path = SYS .. "/" .. id .. ".desktop", fields = fields }
end

local function sample()
  return {
    firefox = entry("firefox", { Name = "Firefox", Categories = "Network;WebBrowser;", Icon = "firefox" }),
    steam = entry("steam", { Name = "Steam", Categories = "Network;FileTransfer;Game;" }),
    ["org.remmina.Remmina"] = entry("org.remmina.Remmina", { Name = "Remmina", Categories = "Network;RemoteAccess;" }),
    zed = entry("zed", { Name = "Zed", Categories = "Utility;TextEditor;Development;" }),
    brave = entry("brave", { Name = "brave", Categories = "Network;WebBrowser;" }),
    odd = entry("odd", { Name = "Odd Tool" }),
    htop = entry("htop", { Name = "Htop", Categories = "System;", Terminal = "true" }),
  }
end

H.test("buildGroups: built-in order, Other last, apps sorted case-insensitively", function()
  local groups = M.buildGroups(sample(), "niri", {}, {})
  H.eq(groupNames(groups), "Browsers,Games,Development,Remote & Network,Other", "group order")
  H.eq(names(groups[1]), "brave,Firefox", "sorted apps")
  H.eq(groups[1].apps[2].icon, "firefox", "icon name carried")
end)
H.test("buildGroups: overrides by name or id, custom groups come first", function()
  local overrides = M.parseOverrides({ "Zed=Work", "org.remmina.remmina.desktop=Work", "odd tool=games", "steam=Archive" })
  local groups = M.buildGroups(sample(), "niri", overrides, {})
  H.eq(groupNames(groups), "Archive,Work,Browsers,Games", "custom first, alphabetical")
  H.eq(names(groups[2]), "Remmina,Zed", "custom group members")
  H.eq(names(groups[4]), "Odd Tool", "override into a built-in group, canonical name")
end)
H.test("buildGroups: hidden apps are dropped, empty groups vanish", function()
  local groups = M.buildGroups(sample(), "niri", {}, M.parseHidden({ "Steam", "odd" }))
  H.eq(groupNames(groups), "Browsers,Development,Remote & Network", "groups")
end)

-- ── end to end ──────────────────────────────────────────────────────
local function setup()
  H.reset()
  H.setEnv({ HOME = "/home/test", XDG_DATA_DIRS = "/sys/share:/missing/share", XDG_CURRENT_DESKTOP = "niri" })
  H.setDirs({
    [USER] = scanOf(USER, { { name = "steam.desktop", lines = { "[Desktop Entry]", "Name=Steam (user)", "Type=Application", "Categories=Game;" } } }),
    [SYS] = scanOf(SYS, {
      { name = "steam.desktop", lines = { "[Desktop Entry]", "Name=Steam", "Type=Application", "Categories=Game;" } },
      { name = "firefox.desktop", lines = { "[Desktop Entry]", "Name=Firefox", "Type=Application", "Icon=firefox", "Categories=Network;WebBrowser;" } },
      { name = "abs.desktop", lines = { "[Desktop Entry]", "Name=Abs", "Type=Application", "Icon=/icons/abs.png" } },
    }),
  })
  H.setIcons({ firefox = "/theme/firefox.svg" })
end

H.test("scan: publishes a grouped snapshot with icons, one grep per existing dir", function()
  setup()
  M._reset()
  M._start()
  local snap = H.noctalia.state.get("app-cheatsheet.snapshot")
  H.ok(snap ~= nil, "snapshot published")
  H.eq(snap.count, 3, "count")
  H.eq(groupNames(snap.groups), "Browsers,Games,Other", "groups")
  H.eq(snap.groups[1].apps[1].iconPath, "/theme/firefox.svg", "theme icon")
  H.eq(snap.groups[2].apps[1].name, "Steam (user)", "user dir wins")
  H.eq(snap.groups[3].apps[1].iconPath, "/icons/abs.png", "absolute icon path used as is")
  H.eq(#H.calls.runAsync, 2, "missing dir skipped")
  H.eq(H.calls.runAsync[1][1], "grep", "argv exec")
  H.eq(H.calls.runAsync[1][#H.calls.runAsync[1]], USER, "user dir scanned first")
end)
H.test("scan: an unchanged rescan does not republish; a settings change does", function()
  setup()
  M._reset()
  M._start()
  local first = H.noctalia.state.get("app-cheatsheet.snapshot")
  H.noctalia.state.set("app-cheatsheet.refresh", 1)
  H.ok(H.noctalia.state.get("app-cheatsheet.snapshot") == first, "same table, not republished")
  H.setConfig({ overrides = { "Firefox=Work" } })
  H.env.onConfigChanged()
  local second = H.noctalia.state.get("app-cheatsheet.snapshot")
  H.ok(second ~= first, "republished")
  H.eq(groupNames(second.groups), "Work,Games,Other", "override applied")
end)

H.test("scan: reports busy while running and clears it", function()
  setup()
  M._reset()
  local seen = {}
  H.noctalia.state.watch("app-cheatsheet.busy", function(value) table.insert(seen, tostring(value)) end)
  M._start()
  H.eq(table.concat(seen, ","), "true,false", "busy transitions")
end)

H.test("scan: a killed icon lookup does not stall the scan", function()
  setup()
  M._reset()
  H.killIconLookup("firefox")
  M._start()
  H.eq(H.calls.killed, 1, "one callback died")
  local snap = H.noctalia.state.get("app-cheatsheet.snapshot")
  H.ok(snap ~= nil, "snapshot still published")
  H.eq(snap.count, 3, "all apps listed")
  H.eq(H.noctalia.state.get("app-cheatsheet.busy"), false, "not stuck busy")
end)

H.test("cache: snapshot is saved, republished on restart and its icons reused", function()
  setup()
  M._reset()
  M._start()
  H.ok(H.files["/data/app-cheatsheet/snapshot.json"] ~= nil, "cache written")
  -- Fresh module state, as after a shell restart; scans hang so only the cache can answer.
  M._reset()
  H.restart()
  H.setHang(true)
  M._start()
  local snap = H.noctalia.state.get("app-cheatsheet.snapshot")
  H.ok(snap ~= nil, "published from cache before any scan finished")
  H.eq(snap.groups[1].apps[1].iconPath, "/theme/firefox.svg", "icon from cache")
  H.setHang(false)
  H.env.onIpc("refresh")
  H.eq(H.noctalia.state.get("app-cheatsheet.busy"), false, "refresh abandons the hung scan and completes")
end)

H.test("cache: cached icons skip the theme lookup unless the file is gone", function()
  setup()
  M._reset()
  M._start()
  M._reset()
  H.restart()
  M._start()
  -- Only the app with no resolvable icon is retried; firefox comes from the cache.
  H.eq(H.calls.iconLookups, 1, "after a restart, cached icons are verified, not looked up")
  M._reset()
  H.restart()
  H.setMissing({ ["/theme/firefox.svg"] = true })
  H.setIcons({ firefox = "/theme2/firefox.svg" })
  M._start()
  H.eq(H.noctalia.state.get("app-cheatsheet.snapshot").groups[1].apps[1].iconPath, "/theme2/firefox.svg", "a vanished icon file is re-resolved")
end)

H.test("cache: a corrupt or foreign cache file is ignored", function()
  H.ok(not M.validSnapshot(nil), "nil")
  H.ok(not M.validSnapshot({ version = 99, groups = {}, count = 0 }), "other version")
  H.ok(not M.validSnapshot({ version = 1, groups = { { name = "A", apps = { { id = "x" } } } }, count = 1 }), "incomplete app")
  H.ok(M.validSnapshot({ version = 1, groups = { { name = "A", apps = { { id = "x", name = "X", path = "/x", icon = "" } } } }, count = 1 }), "valid")
end)

H.finish()
