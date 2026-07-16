--!nonstrict
local H = require("./harness")
local M = H.loadEntry("../panel")

H.test("header buttons", function()
  local h = M.buildHeader()
  local btns = H.findAll(h, function(n) return n.type == "button" end)
  H.ok(#btns >= 2, "refresh + close")
  local names = {} for _, b in ipairs(btns) do names[b.props.onClick or ""] = true end
  H.ok(names["onRefresh"], "refresh cb"); H.ok(names["onClosePanel"], "close cb")
end)
H.test("date row prefers arabic hijri", function()
  local r = M.buildDateRow({ display = "1 Muharram 1448 AH", displayAr = "١ محرم ١٤٤٨" }, "16 Jul 2026")
  local found = H.find(r, function(n) return n.type == "label" and n.props.text == "١ محرم ١٤٤٨" end)
  H.truthy(found, "arabic hijri shown")
end)

H.finish()
