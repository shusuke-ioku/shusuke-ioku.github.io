-- render-yaml.lua
-- Reads YAML metadata and renders placeholder divs into HTML.
-- Usage: add placeholder divs in .qmd files:
--   ::: {#papers}    → renders papers list from `papers:` metadata
--   ::: {#other-pubs} → renders from `other_publications:` metadata
--   ::: {#talks}      → renders from `talks:` metadata
--   ::: {#courses}    → renders from `courses:` metadata

local function str(val)
  if not val then return "" end
  return pandoc.utils.stringify(val)
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
    h = h .. '<span class="pub-title"><strong>' .. to_html(p.title) .. '</strong></span><br>\n'
    if p.coauthors then
      h = h .. '<span class="pub-authors">with ' .. to_html(p.coauthors) .. '</span><br>\n'
    end
    h = h .. '<span class="pub-status">' .. to_html(p.status) .. '</span>'
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

local function render_other_pubs(pubs)
  local out = pandoc.Blocks{}
  for _, p in ipairs(pubs) do
    local h = '<div class="pub-entry">\n'
    h = h .. '<span class="pub-title"><strong>' .. to_html(p.title) .. '</strong></span><br>\n'
    if p.coauthors then
      h = h .. '<span class="pub-authors">with ' .. to_html(p.coauthors) .. '</span><br>\n'
    end
    if p.venue then
      h = h .. '<span class="pub-venue">' .. to_html(p.venue) .. '</span>\n'
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
    if block.t == "Div" then
      if block.identifier == "papers" and meta.papers then
        new_blocks:extend(render_papers(meta.papers))
        replaced = true
      elseif block.identifier == "other-pubs" and meta.other_publications then
        new_blocks:extend(render_other_pubs(meta.other_publications))
        replaced = true
      elseif block.identifier == "talks" and meta.talks then
        new_blocks:extend(render_talks(meta.talks))
        replaced = true
      elseif block.identifier == "courses" and meta.courses then
        new_blocks:extend(render_courses(meta.courses))
        replaced = true
      end
    end
    if not replaced then
      new_blocks:insert(block)
    end
  end

  return pandoc.Pandoc(new_blocks, meta)
end
