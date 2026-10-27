-- Stamp the rendered snapshot, never the visitor's browser time. Phoenix is
-- UTC-7 year-round; using UTC formatting avoids host timezone dependencies.
function Span(el)
  if el.classes:includes("dashboard-rendered-at") then
    local now = os.time()
    local utc = os.date("!%Y-%m-%dT%H:%M:%SZ", now)
    local phoenix = os.date("!%b %d, %Y %I:%M %p", now - 7 * 60 * 60) .. " MST"
    return pandoc.RawInline("html", '<time datetime="' .. utc .. '">' .. phoenix .. '</time>')
  end
end
