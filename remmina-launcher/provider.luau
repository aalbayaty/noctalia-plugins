--!nonstrict
-- Remmina Launcher — Noctalia v5 launcher provider.
-- Ported from the v4 QML plugin (git tag v1.0, noctalia-plugins/remmina-launcher/).
-- Browses Remmina remote-desktop connections (scans ~/.local/share/remmina/*.remmina,
-- parses name+protocol) and launches them via `remmina -c <file>`.
-- Implemented in later tasks.
local M = {}
function M._placeholder() end
if _G.__REMMINA_TEST or noctalia == nil then return M end
