-- render-yaml.lua
-- Reads YAML metadata and renders placeholder divs into HTML.
-- Generic: any div whose identifier matches a top-level metadata key holding
-- a list is replaced by a rendered list. Two special identifiers get their
-- own renderers:
--   ::: {#talks}   → talk entries (title + venue)
--   ::: {#courses} → course table
-- Every other matching identifier renders as a publication list supporting
-- the fields: id, title, coauthors, status, venue, pdf, abstract.

local function str(val)
  if not val then return "" end
  return pandoc.utils.stringify(val)
end

local function esc_html(s)
  if not s then return "" end
  s = s:gsub("&", "&amp;")
  s = s:gsub("<", "&lt;")
  s = s:gsub(">", "&gt;")
  return s
end

local function title_with_subtitle(val)
  local raw = str(val)
  local main, sub = raw:match("^(.-):%s*(.+)$")
  if main and sub then
    return '<span class="pub-title-main">' .. esc_html(main) .. ':</span> ' ..
           '<span class="pub-title-sub">' .. esc_html(sub) .. '</span>'
  end
  return esc_html(raw)
end

-- Render metadata value to inline HTML (strips <p> wrapper)
local function to_html(val)
  if not val then return "" end
  local t = pandoc.utils.type(val)
  if t == "string" then return val end
  local blocks
  if t == "Inlines" then
    blocks = {pandoc.Para(val)}
  elseif t == "Blocks" then
    blocks = val
  else
    return str(val)
  end
  local html = pandoc.write(pandoc.Pandoc(blocks), "html5")
  return (html:gsub("^<p>", ""):gsub("</p>\n?$", ""))
end

-- Render metadata value to block-level HTML (keeps <p> tags)
local function to_block(val)
  if not val then return "" end
  local t = pandoc.utils.type(val)
  if t == "string" then return "<p>" .. val .. "</p>" end
  local blocks
  if t == "Inlines" then
    blocks = {pandoc.Para(val)}
  elseif t == "Blocks" then
    blocks = val
  else
    return "<p>" .. str(val) .. "</p>"
  end
  return pandoc.write(pandoc.Pandoc(blocks), "html5")
end

local function render_papers(papers)
  local out = pandoc.Blocks{}
  for _, p in ipairs(papers) do
    local div_id = p.id and (' id="' .. str(p.id) .. '"') or ""
    local h = '<div class="pub-entry"' .. div_id .. '>\n'
    h = h .. '<span class="pub-title">' .. title_with_subtitle(p.title) .. '</span><br>\n'
    if p.coauthors then
      h = h .. '<span class="pub-authors">with ' .. to_html(p.coauthors) .. '</span><br>\n'
    end
    if p.venue then
      h = h .. '<span class="pub-venue">' .. to_html(p.venue) .. '</span>'
    elseif p.status then
      h = h .. '<span class="pub-status">' .. to_html(p.status) .. '</span>'
    end
    if p.pdf then
      h = h .. '&ensp;<a href="' .. str(p.pdf) .. '">PDF</a>'
    end
    h = h .. '\n'
    if p.abstract then
      h = h .. '<div class="pub-abstract">' .. to_block(p.abstract) .. '</div>\n'
    end
    h = h .. '</div>\n'
    out:insert(pandoc.RawBlock('html', h))
  end
  return out
end

local function render_talks(talks)
  local out = pandoc.Blocks{}
  for _, t in ipairs(talks) do
    local h = '<div class="talk-entry">\n'
    h = h .. '<span class="talk-title">' .. to_html(t.title) .. '</span>\n'
    if t.venue then
      h = h .. '<span class="talk-venue">' .. to_html(t.venue) .. '</span>\n'
    end
    h = h .. '</div>\n'
    out:insert(pandoc.RawBlock('html', h))
  end
  return out
end

local function render_courses(courses)
  local out = pandoc.Blocks{}
  local h = '<table>\n<thead>\n<tr>'
  h = h .. '<th>Course</th><th>Term</th><th>Instructor</th><th>School</th>'
  h = h .. '</tr>\n</thead>\n<tbody>\n'
  for _, c in ipairs(courses) do
    h = h .. '<tr>'
    h = h .. '<td>' .. str(c.course) .. '</td>'
    h = h .. '<td>' .. str(c.term) .. '</td>'
    h = h .. '<td>' .. str(c.instructor) .. '</td>'
    h = h .. '<td>' .. str(c.school) .. '</td>'
    h = h .. '</tr>\n'
  end
  h = h .. '</tbody>\n</table>\n'
  out:insert(pandoc.RawBlock('html', h))
  return out
end

function Pandoc(doc)
  local meta = doc.meta
  local new_blocks = pandoc.Blocks{}

  for _, block in ipairs(doc.blocks) do
    local replaced = false
    if block.t == "Div" and block.identifier ~= "" then
      local items = meta[block.identifier]
      if items and pandoc.utils.type(items) == "List" then
        if block.identifier == "courses" then
          new_blocks:extend(render_courses(items))
        elseif block.identifier == "talks" then
          new_blocks:extend(render_talks(items))
        else
          new_blocks:extend(render_papers(items))
        end
        replaced = true
      end
    end
    if not replaced then
      new_blocks:insert(block)
    end
  end

  return pandoc.Pandoc(new_blocks, meta)
end
