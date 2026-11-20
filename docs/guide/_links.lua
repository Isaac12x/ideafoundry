-- Rewrite relative *.md links between guide pages to *.html (site is served under a subpath).
function Link(el)
  if not el.target:match("^[%a]+:") and not el.target:match("^/") then
    el.target = el.target:gsub("%.md(#?)", ".html%1")
  end
  return el
end
