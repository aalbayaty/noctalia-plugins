--!nonstrict
-- Steam Launcher — Noctalia v5 launcher provider.
-- Ported from the v4 QML plugin (git tag v1.0, noctalia-plugins/steam-launcher/).
-- Implemented in later tasks.
local M = {}
if _G.__STEAM_TEST or noctalia == nil then return M end
