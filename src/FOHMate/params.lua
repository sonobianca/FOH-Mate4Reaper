-- FOHMate/params.lua: Performance mode parameter rows.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- parameter rows
--
-- The rows of a rack's column are saved on the rack (its track), so a duplicated rack takes them
-- along. Each row is one parameter of one FX of that rack: the FX's GUID and the parameter's
-- index, plus the name the plug-in reported when the row was made (to notice a changed plug-in)
-- and a name of the user's own (nil = the reported one). A row whose FX or parameter is gone is
-- kept and drawn greyed out, never silently dropped.

PARAM_CACHE = {}   -- per rack: the saved text and the rows parsed from it
PARAM_PICK  = nil  -- the "Add a parameter" window: { tr, guid, filter, fx = { { guid, name, params } } }

function param_esc(s)
  return (s:gsub('[%%|;\n\r]', function(ch) return ('%%%02X'):format(ch:byte()) end))
end

function param_unesc(s)
  return (s:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end))
end

-- the rows of a rack (the same table is returned while the saved text is unchanged)
function params_read(tr)
  local guid = reaper.GetTrackGUID(tr)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, EXT_PARAMS, '', false)
  if not ok then s = '' end
  local c = PARAM_CACHE[guid]
  if c and c.raw == s then return c.rows end
  local rows = {}
  for rec in s:gmatch('[^;]+') do
    local g, i, pn, nm = rec:match('^([^|]*)|(%d+)|([^|]*)|([^|]*)$')
    if g then
      rows[#rows + 1] = { guid = g, idx = tonumber(i), pname = param_unesc(pn),
                          name = nm ~= '' and param_unesc(nm) or nil }
    end
  end
  PARAM_CACHE[guid] = { raw = s, rows = rows }
  return rows
end

function params_write(tr, rows)
  local t = {}
  for _, r in ipairs(rows) do
    t[#t + 1] = ('%s|%d|%s|%s'):format(r.guid, r.idx, param_esc(r.pname or ''), param_esc(r.name or ''))
  end
  reaper.GetSetMediaTrackInfo_String(tr, EXT_PARAMS, table.concat(t, ';'), true)
end

function params_add(tr, fxguid, idx, pname)
  local rows = {}
  for _, r in ipairs(params_read(tr)) do rows[#rows + 1] = r end
  rows[#rows + 1] = { guid = fxguid, idx = idx, pname = pname }
  params_write(tr, rows)
end

function params_remove(tr, k)
  local rows = {}
  for i, r in ipairs(params_read(tr)) do
    if i ~= k then rows[#rows + 1] = r end
  end
  params_write(tr, rows)
end

-- FX guid -> index, for the FX of a rack
function fx_guid_map(tr)
  local m = {}
  for i = 0, reaper.TrackFX_GetCount(tr) - 1 do m[reaper.TrackFX_GetFXGUID(tr, i)] = i end
  return m
end

-- the value as the vertical box can write it: what the plug-in says when the little stroke font
-- has every character of it, otherwise the position as a percentage
function param_vtext(txt, norm)
  if txt and txt ~= '' and #txt <= 9 then
    local ok = true
    for i = 1, #txt do
      local ch = txt:sub(i, i)
      if ch ~= ' ' and not VFONT[ch] then ok = false; break end
    end
    if ok then return txt end
  end
  return ('%d%%'):format(math.floor(norm * 100 + 0.5))
end

---------------------------------------------------------------- the "Add a parameter" window

function param_picker_open(tr)
  local fxs = {}
  for _, it in ipairs(chain_info(tr).list) do
    local names = {}
    for p = 0, reaper.TrackFX_GetNumParams(tr, it.fx) - 1 do
      local _, nm = reaper.TrackFX_GetParamName(tr, it.fx, p, '')
      names[p + 1] = nm
    end
    fxs[#fxs + 1] = { guid = reaper.TrackFX_GetFXGUID(tr, it.fx), name = it.name, names = names }
  end
  PARAM_PICK = { tr = tr, filter = '', fx = fxs }
end

function draw_param_picker()
  local P = PARAM_PICK
  if not P then return end
  if not valid(P.tr) then PARAM_PICK = nil; return end
  local vis, open = begin_window('parampick', 'Add a parameter###parampick', 420, 520, true)
  if vis then
    ig.TextDisabled(ctx, 'Click a parameter to add it to the column. The window stays open for more.')
    ig.SetNextItemWidth(ctx, -1)
    local rv, f = ig.InputTextWithHint(ctx, '##pf', 'Search', P.filter)
    if rv then P.filter = f end
    local low = P.filter:lower()
    local taken = {}
    for _, r in ipairs(params_read(P.tr)) do taken[r.guid .. ':' .. r.idx] = true end
    if ig.BeginChild(ctx, 'pplist', 0, 0) then
      if #P.fx == 0 then ig.TextDisabled(ctx, 'This rack has no FX yet.') end
      for _, fx in ipairs(P.fx) do
        if low ~= '' then ig.SetNextItemOpen(ctx, true, ig.Cond_Always()) end
        if ig.CollapsingHeader(ctx, fx.name .. '##h' .. fx.guid) then
          local shown = 0
          for p, nm in ipairs(fx.names) do
            if low == '' or nm:lower():find(low, 1, true) then
              shown = shown + 1
              if shown > 300 then ig.TextDisabled(ctx, 'More... type in the search to narrow it down.'); break end
              local used = taken[fx.guid .. ':' .. (p - 1)]
              if used then ig.PushStyleColor(ctx, ig.Col_Text(), T.dim) end
              if ig.Selectable(ctx, (used and '(added)  ' or '') .. nm .. '##p' .. fx.guid .. p) and not used then
                params_add(P.tr, fx.guid, p - 1, nm)
              end
              if used then ig.PopStyleColor(ctx) end
            end
          end
          if shown == 0 then ig.TextDisabled(ctx, 'Nothing matches.') end
        end
      end
      ig.EndChild(ctx)
    end
    ig.End(ctx)
  end
  if not open then PARAM_PICK = nil end
end
