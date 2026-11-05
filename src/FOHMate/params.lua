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
PARAM_PICK  = nil  -- the parameter window (Edit mode): { tr, filter, sel, anchor, order, fx }
PARAM_KIND  = {}   -- what kind of control a parameter gets, found once per parameter
ROW_MEMO    = {}   -- per row (FX guid:index:name): what the plug-in last said, so it isn't asked every frame

function param_esc(s)
  return (s:gsub('[%%|;\n\r]', function(ch) return ('%%%02X'):format(ch:byte()) end))
end

function param_unesc(s)
  return (s:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end))
end

-- The rows of a rack. The saved text is only read again every 20 frames (a third of a second), so
-- an undo still shows up; our own writes drop the copy at once.
function params_read(tr)
  local guid = reaper.GetTrackGUID(tr)
  local c = PARAM_CACHE[guid]
  if c and FRAME - c.frame < 20 then return c.rows end
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, EXT_PARAMS, '', false)
  if not ok then s = '' end
  if c and c.raw == s then c.frame = FRAME; return c.rows end
  local rows = {}
  for rec in s:gmatch('[^;]+') do
    local g, i, pn, nm, df, iv, cl, lo, hi, ft, vl, lm, vs, cu =
      rec:match('^([^|]*)|(%d+)|([^|]*)|([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)$')
    if g then
      local r = { guid = g, idx = tonumber(i), pname = param_unesc(pn),
                  name = nm ~= '' and param_unesc(nm) or nil, def = tonumber(df), inv = (iv == '1'),
                  col = tonumber(cl, 16), lo = tonumber(lo), hi = tonumber(hi), fit = (ft == '1'),
                  vraw = vl, vshow = (vs == 's' and 'steps') or (vs == 'd' and 'list') or nil,
                  curve = cu ~= '' and param_unesc(cu) or nil }   -- the value curve (curves.lua), nil = linear
      if r.curve and not curve_parse(r.curve) then r.curve = nil end
      if not (r.lo and r.hi and r.lo < r.hi) then r.lo, r.hi = nil, nil end
      if vl ~= '' then
        r.vals = {}
        for x in vl:gmatch('[^,]+') do r.vals[#r.vals + 1] = tonumber(x) end
      end
      -- the limit in use: 'mm' (Min / Max) or 'list'; a row saved before the list existed has Min / Max
      -- when it has a Min
      if lm == 'l' then r.lim = 'list' elseif lm == 'm' or (lm == '' and r.lo) then r.lim = 'mm' end
      if r.lim == 'mm' and not r.lo then r.lim = nil end
      rows[#rows + 1] = r
    end
  end
  PARAM_CACHE[guid] = { raw = s, rows = rows, frame = FRAME }
  return rows
end

function params_write(tr, rows)
  local t = {}
  for _, r in ipairs(rows) do
    local lim = r.lo and r.hi
    local vl = {}
    for j, v in ipairs(r.vals or {}) do vl[j] = ('%.6f'):format(v) end
    t[#t + 1] = ('%s|%d|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s'):format(r.guid, r.idx, param_esc(r.pname or ''), param_esc(r.name or ''),
                                                r.def and ('%.6f'):format(r.def) or '', r.inv and '1' or '',
                                                r.col and ('%06X'):format(r.col) or '',
                                                lim and ('%.6f'):format(r.lo) or '', lim and ('%.6f'):format(r.hi) or '',
                                                r.fit and '1' or '', table.concat(vl, ','),
                                                (r.lim == 'mm' and 'm') or (r.lim == 'list' and 'l') or 'o',
                                                (r.vshow == 'steps' and 's') or (r.vshow == 'list' and 'd') or '',
                                                param_esc(r.curve or ''))
  end
  reaper.GetSetMediaTrackInfo_String(tr, EXT_PARAMS, table.concat(t, ';'), true)
  PARAM_CACHE[reaper.GetTrackGUID(tr)] = nil
end

-- FX guid -> index, for the FX of a rack
-- changes fields of one row (inv, def...): changes = { inv = true, def = 0.5 }; a field set to false is cleared
function params_update(tr, guid, idx, changes)
  local rows = {}
  for _, r in ipairs(params_read(tr)) do
    local n = {}
    for k, v in pairs(r) do n[k] = v end
    if r.guid == guid and r.idx == idx then
      for k, v in pairs(changes) do n[k] = (v ~= false) and v or nil end
    end
    rows[#rows + 1] = n
  end
  params_write(tr, rows)
end

-- the row of a parameter in the Performance, if it is there
function params_find(tr, guid, idx)
  for _, r in ipairs(params_read(tr)) do
    if r.guid == guid and r.idx == idx then return r end
  end
end

function fx_guid_map(tr)
  local m = {}
  for i = 0, reaper.TrackFX_GetCount(tr) - 1 do m[reaper.TrackFX_GetFXGUID(tr, i)] = i end
  return m
end

-- The colors given to the FX of a rack (Performance mode: the parameters of an FX take its color): FX guid
-- -> 0xRRGGBB, saved with the rack. An FX without one has the rack's color. Read again every 20 frames.
FXCOL_CACHE = {}
function fxcol_read(tr)
  local g = reaper.GetTrackGUID(tr)
  local c = FXCOL_CACHE[g]
  if c and FRAME - c.frame < 20 then return c.map end
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, EXT_FXCOL, '', false)
  if not ok then s = '' end
  if c and c.raw == s then c.frame = FRAME; return c.map end
  local map = {}
  for gd, hx in s:gmatch('({[^}]+})=(%x+)') do map[gd] = tonumber(hx, 16) end
  FXCOL_CACHE[g] = { raw = s, map = map, frame = FRAME }
  return map
end

-- gives an FX a color (0xRRGGBB), or with nil the rack's again; the colors of FX that are gone are dropped
function fxcol_set(tr, guid, col)
  local map = {}
  for k, v in pairs(fxcol_read(tr)) do map[k] = v end
  map[guid] = col
  local gm, t = fx_guid_map(tr), {}
  for k, v in pairs(map) do if gm[k] then t[#t + 1] = ('%s=%06X'):format(k, v) end end
  table.sort(t)
  reaper.GetSetMediaTrackInfo_String(tr, EXT_FXCOL, table.concat(t, ';'), true)
  FXCOL_CACHE[reaper.GetTrackGUID(tr)] = nil
end

-- the color of an FX (0xRRGGBBAA): its own, or rack_col
function fx_color(tr, guid, rack_col)
  local c = fxcol_read(tr)[guid]
  return c and ((c << 8) | 0xFF) or rack_col
end

-- the color picker for an FX (right-click it > Color...)
function fx_open_picker(tr, guid, name)
  picker.kind, picker.tr, picker.guid = 'fx', tr, guid
  picker.title = 'Color of ' .. clean_fx_name(name)
  picker.rgb = fx_color(tr, guid, track_color(tr)) >> 8
  picker.open = true
end

-- A duplicated rack (or a template) has the same FX in the same order, but REAPER gives each of
-- them a new GUID: the copied rows are pointed at the copy's own FX, place by place.
function params_copy(src, new)
  local rows = params_read(src)
  local cols = fxcol_read(src)
  if #rows == 0 and next(cols) == nil then return end
  local a, b = chain_info(src).list, chain_info(new).list
  local map = {}
  for i, it in ipairs(a) do
    if b[i] then map[reaper.TrackFX_GetFXGUID(src, it.fx)] = reaper.TrackFX_GetFXGUID(new, b[i].fx) end
  end
  for old, c in pairs(cols) do                              -- the colors given to FX go along
    if map[old] then fxcol_set(new, map[old], c) end
  end
  if #rows == 0 then return end
  local out = {}
  for _, r in ipairs(rows) do
    local n = {}
    for k, v in pairs(r) do n[k] = v end
    n.guid = map[r.guid] or r.guid
    out[#out + 1] = n
  end
  params_write(new, out)
end

-- how many rows of the rack belong to the FX in `guids` (a set of FX GUIDs; nil = every row)
function params_count_fx(tr, guids)
  local n = 0
  for _, r in ipairs(params_read(tr)) do
    if not guids or guids[r.guid] then n = n + 1 end
  end
  return n
end

-- removes the rows of the FX in `guids` (nil = every row), inside the caller's undo block:
-- an FX that is deleted takes its rows along
function params_drop_fx(tr, guids)
  if params_count_fx(tr, guids) == 0 then return end
  local kept = {}
  for _, r in ipairs(params_read(tr)) do
    if guids and not guids[r.guid] then kept[#kept + 1] = r end
  end
  params_write(tr, kept)
end

-- A new FX on the rack (added, dropped from another rack, Replace FX) takes back the rows an FX of the
-- same plug-in left when it was deleted with "keep the rows": rows whose FX is gone, each of whose
-- parameters has the same name at the same place in the new FX. One deleted FX per new FX (the
-- first in the column), and only when the new FX has no rows yet. Inside the caller's undo block.
function params_relink(tr, guid)
  local rows = params_read(tr)
  if #rows == 0 then return end
  local gm = fx_guid_map(tr)
  local fxi = gm[guid]
  if not fxi then return end
  for _, r in ipairs(rows) do if r.guid == guid then return end end
  local np = reaper.TrackFX_GetNumParams(tr, fxi)
  local tried = {}
  for _, r in ipairs(rows) do
    local old = r.guid
    if not gm[old] and not tried[old] then
      tried[old] = true
      local fits = true
      for _, o in ipairs(rows) do
        if o.guid == old then
          local pn = o.idx < np and select(2, reaper.TrackFX_GetParamName(tr, fxi, o.idx, '')) or nil
          if pn ~= o.pname then fits = false; break end
        end
      end
      if fits then
        local out = {}
        for i, o in ipairs(rows) do
          local n = {}
          for k, v in pairs(o) do n[k] = v end
          if o.guid == old then n.guid = guid end
          out[i] = n
        end
        params_write(tr, out)
        return
      end
    end
  end
end

-- what the plug-in last said about a row (ROW_MEMO): whether its parameter is gone (missing) is
-- checked again every 30 frames (half a second) or when its FX moved (fxi = where its FX is now)
function param_row_memo(tr, r, fxi)
  local mk = r.guid .. ':' .. r.idx .. ':' .. (r.pname or '')
  local mm = ROW_MEMO[mk]
  if not mm then mm = {}; ROW_MEMO[mk] = mm end
  if fxi ~= mm.fxi or FRAME - (mm.f_name or -99) >= 30 then
    if fxi and r.idx < reaper.TrackFX_GetNumParams(tr, fxi) then
      local _, pn = reaper.TrackFX_GetParamName(tr, fxi, r.idx, '')
      mm.missing = (pn ~= r.pname)                      -- a changed plug-in: not the parameter it was
    else
      mm.missing = true
    end
    mm.fxi, mm.f_name, mm.f_txt = fxi, FRAME, nil
  end
  return mm
end

-- dragging a row (Edit mode): row `from` takes the place of row `to`, the rows in between shift by
-- one; to = the number of rows + 1 puts it at the end
function params_move(tr, from, to)
  local rows = {}
  for i, r in ipairs(params_read(tr)) do rows[i] = r end
  if not rows[from] or from == to then return end
  local r = table.remove(rows, from)
  table.insert(rows, math.min(to, #rows + 1), r)
  with_undo('Reorder Performance parameters', function() params_write(tr, rows) end)
end

-- the rows whose parameter is gone (its FX removed, or the plug-in changed), as { guid, idx, name }
-- each, for "Remove the rows not linked any more" (right-click on the +)
PARAM_UNLINKED = nil
function params_unlinked(tr)
  local gm, out = fx_guid_map(tr), {}
  for _, r in ipairs(params_read(tr)) do
    local fxi = gm[r.guid]
    local gone = not fxi or r.idx >= reaper.TrackFX_GetNumParams(tr, fxi)
    if not gone then
      local _, pn = reaper.TrackFX_GetParamName(tr, fxi, r.idx, '')
      gone = (pn ~= r.pname)
    end
    if gone then out[#out + 1] = { guid = r.guid, idx = r.idx, name = r.pname } end
  end
  return out
end

-- Limit values, Min / Max (r.lim == 'mm'): a parameter in the Performance may be kept between lo and
-- hi (0..1, as REAPER counts it). With fit (Use the full range of the control), the control's whole
-- travel covers lo..hi, for finer moves; without it, the control stops at lo and hi. Only for the
-- controls that turn (an encoder, a stepped encoder, a width or Q band, a pan); fit not for a stepped
-- encoder.
function param_limit_ok(kind) return kind ~= nil and kind ~= 'toggle' and kind ~= 'list' end
function param_fit_ok(kind) return kind == 'knob' or kind == 'band' or kind == 'qband' or kind == 'pan' end

-- the parameter's value -> where the control shows it (0..1), and back (invert included)
function param_to_ctl(r, kind, v)
  if r.lim == 'mm' and r.fit and param_fit_ok(kind) then v = math.max(0, math.min(1, (v - r.lo) / (r.hi - r.lo))) end
  if r.inv then v = 1 - v end
  return v
end

function param_from_ctl(r, kind, v)
  if r.inv then v = 1 - v end
  if r.lim == 'mm' and param_limit_ok(kind) then
    if r.fit and param_fit_ok(kind) then v = r.lo + v * (r.hi - r.lo)
    else v = math.max(r.lo, math.min(r.hi, v)) end
  end
  return v
end

-- what the control draws, in its own 0..1: the extra marks (a fader's dB marks: with fit, only those
-- inside the limits), the default mark, and the limits it stops at (without fit) as { lo, hi }
function param_ctl_view(r, kind, marks)
  local lim = r.lim == 'mm' and param_limit_ok(kind)
  local fit = lim and r.fit and param_fit_ok(kind)
  local function inside(m) return not fit or (m >= r.lo and m <= r.hi) end
  local pm
  if marks then
    pm = {}
    for _, m in ipairs(marks) do if inside(m) then pm[#pm + 1] = param_to_ctl(r, kind, m) end end
  end
  local pd = r.def and inside(r.def) and param_to_ctl(r, kind, r.def) or nil
  local range
  if lim and not fit then
    local a, b = param_to_ctl(r, kind, r.lo), param_to_ctl(r, kind, r.hi)
    range = { math.min(a, b), math.max(a, b) }
  end
  return pm, pd, range
end

-- Limit values, list (r.lim == 'list'): the parameter only takes the values of r.vals (0..1 each, in
-- the user's order, any order). The control becomes a stepped encoder with a step per value, or a
-- drop-down of them (param_list_show). Any kind of control but a toggle.
function param_list_ok(kind) return kind ~= nil and kind ~= 'toggle' end

-- What the plug-in prints for a position (ok, text). Some print their unit twice ("1000 Hz Hz"):
-- a last word that repeats the one before it is dropped.
function param_fmt(tr, fxi, idx, v)
  local ok, t = reaper.TrackFX_FormatParamValueNormalized(tr, fxi, idx, v, '')
  local head, w1, w2 = t:match('^(.-)(%S+)%s+(%S+)%s*$')
  if w1 and not w1:find('%d') and w1:lower() == w2:lower() then t = head .. w1 end
  return ok, t
end

-- the plug-in's own text for a position, when it can give it (otherwise a percentage)
function param_text_at(tr, fxi, idx, v)
  local ok, t = param_fmt(tr, fxi, idx, v)
  if not ok or t == '' then t = ('%d%%'):format(math.floor(v * 100 + 0.5)) end
  return t
end

-- a text split into its number and its unit ("1000 Hz" > "1000", "Hz"; "-6.0 dB"; "50%" > "50", "%");
-- a text that doesn't start with a number ("Low Pass", "-inf dB") is all text: text, "", false
function param_text_split(t)
  local num, unit = t:match('^%s*([%-%+]?%d[%d%.]*)%s*(.-)%s*$')
  if num then return num, unit, true end
  return t, '', false
end

-- The position that prints as a number (with this unit): the plug-in is asked at 401 positions for the
-- nearest, then between its neighbours by halving (16 times, for a text that rises or falls there).
-- Nothing when no position prints that unit.
function param_find_value(tr, fxi, idx, num, unit)
  local ok = param_fmt(tr, fxi, idx, 0)
  if not ok then return math.max(0, math.min(1, num / 100)) end        -- no text from the plug-in: a percentage
  local function at(v)
    local n, u, isnum = param_text_split(select(2, param_fmt(tr, fxi, idx, v)))
    if isnum then return tonumber(n), u end
  end
  local N, best, bd = 400, nil, nil
  for i = 0, N do
    local n, u = at(i / N)
    if n and u:lower() == unit:lower() then
      local d = math.abs(n - num)
      if not bd or d < bd then best, bd = i, d end
    end
  end
  if not best then return nil end
  local lo, hi = math.max(0, best - 1) / N, math.min(N, best + 1) / N
  local nlo, nhi = at(lo), at(hi)
  if not (nlo and nhi and nlo ~= nhi) then return best / N end
  local rising = nhi > nlo
  for _ = 1, 16 do
    local nm = at((lo + hi) / 2)
    if not nm then break end
    if (nm < num) == rising then lo = (lo + hi) / 2 else hi = (lo + hi) / 2 end
  end
  local a, b = at(lo), at(hi)
  return (math.abs((a or math.huge) - num) <= math.abs((b or math.huge) - num)) and lo or hi
end

-- what a list shows as: the user's choice (Show as), or else a drop-down for a plug-in's named values
-- (a drop-down already), a single value or a long list, and a stepped encoder otherwise
function param_list_show(r, kind, n)
  if n < 2 then return 'list' end
  if r.vshow then return r.vshow end
  if kind == 'list' or n > 12 then return 'list' end
  return 'steps'
end

-- the list as the row draws it, or nil without one: { items = { label, norm }, show, pos (the item
-- nearest to the value now), def (the step of the default mark, 0..1) }. The texts are asked once per
-- list, kept in the row's memo (mm).
-- k: the parameter's kind (param_kind): a stepped parameter some of whose values are placeholders
-- (sparse) is drawn like a list of its other values
function param_list_view(tr, fxi, r, kind, mm, norm, k)
  local own = r.lim == 'list' and r.vals and #r.vals > 0 and param_list_ok(kind)
  if not own and not (k and k.sparse and kind == 'steps' and r.lim ~= 'list') then return nil end
  local key = own and (r.vraw .. '|' .. tostring(r.vshow) .. '|' .. kind) or ('sparse|' .. #k.items)
  if mm.lkey ~= key then
    local items = {}
    if own then
      for i, v in ipairs(r.vals) do items[i] = { label = param_text_at(tr, fxi, r.idx, v), norm = v } end
    else
      for i, it in ipairs(k.items) do items[i] = it end
    end
    mm.lkey, mm.lv = key, { items = items, show = own and param_list_show(r, kind, #items) or 'steps' }
  end
  local lv = mm.lv
  local function nearest(v)
    local best, bd = 1, math.huge
    for i, it in ipairs(lv.items) do
      local d = math.abs(it.norm - v)
      if d < bd then best, bd = i, d end
    end
    return best
  end
  local n = #lv.items
  lv.pos = nearest(norm)
  lv.def = r.def and n > 1 and (nearest(r.def) - 1) / (n - 1) or nil
  return lv
end

-- a list was set or changed: a parameter whose value is not in it moves to the nearest value of the
-- list at once (as with Min / Max)
function param_list_snap(tr, fxi, idx, vals)
  if not vals or #vals == 0 then return end
  local cur = reaper.TrackFX_GetParamNormalized(tr, fxi, idx)
  local best, bd = nil, math.huge
  for _, v in ipairs(vals) do
    local d = math.abs(v - cur)
    if d < bd then best, bd = v, d end
  end
  if bd > 1e-5 then reaper.TrackFX_SetParamNormalized(tr, fxi, idx, best) end
end

-- how many parameters of the rack are in the Performance
function params_count(tr)
  return #params_read(tr)
end

-- the value as the vertical box can write it: what the plug-in says when the little stroke font
-- has every character of it, otherwise the position as a percentage. The text is tidied first
-- (µ and ° and other unusual characters dropped, a bare number of a frequency gets "Hz", spaces
-- squeezed out when it is too long). A text that still can't be written is noted once in
-- Data/FOHMate/param_text_rejects.txt (plug-in, parameter, text), so the rules can be improved.
PARAM_REJ = {}
function param_vtext(txt, norm, pname, tr, fxi)
  local t = (txt or ''):gsub('\194\181', 'u'):gsub('\194\176', ''):gsub('[\128-\255]', ''):gsub('%c', ' ')
  t = t:gsub('^%s+', ''):gsub('%s+$', '')
  if t ~= '' and tonumber(t) and (pname or ''):lower():find('freq', 1, true) then t = t .. ' Hz' end
  if #t > 12 then t = t:gsub('%s+', '') end
  if t ~= '' and #t <= 12 then
    local ok = true
    for i = 1, #t do
      local ch = t:sub(i, i)
      if ch ~= ' ' and not VFONT[ch] then ok = false; break end
    end
    if ok then return t end
  end
  if tr and txt and txt ~= '' then
    local key = (param_fx_key(tr, fxi) or '') .. '\t' .. (pname or '')
    if not PARAM_REJ[key] then
      PARAM_REJ[key] = true
      write_file(LATDB_DIR .. '/param_text_rejects.txt', key .. '\t' .. txt .. '\n', 'a')
    end
  end
  return ('%d%%'):format(math.floor(norm * 100 + 0.5))
end

-- Some parameters mean something else depending on another one: a band of an EQ has one Pan/Width
-- parameter that is a pan when the band's stereo placement is Stereo, a width when it is MS, and is
-- ignored for Left, Right, Mid, Side or Mono. The parameter that decides is found by its name: the
-- same band (the text before "Pan") and a name like placement / stereo / channel / mode.
function param_mode_sibling(tr, fxi, r)
  local prefix = (r.pname or ''):lower():match('^(.-)%s*pan') or ''
  local n = reaper.TrackFX_GetNumParams(tr, fxi)
  for i = 0, n - 1 do
    if i ~= r.idx then
      local _, nm = reaper.TrackFX_GetParamName(tr, fxi, i, '')
      nm = nm:lower()
      local same = prefix == '' or (nm:sub(1, #prefix) == prefix and not nm:sub(#prefix + 1, #prefix + 1):match('%d'))
      if same and (nm:find('placement', 1, true) or nm:find('stereo', 1, true) or nm:find('channel', 1, true)
                   or nm:find('mode', 1, true)) and not nm:find('pan', 1, true) and not nm:find('width', 1, true) then
        return i
      end
    end
  end
end

-- what such a parameter is right now: 'pan', 'band' (a width), or 'off' (the plug-in ignores it)
PARAM_MODE_REJ = {}
function param_dual_mode(tr, fxi, k)
  local _, txt = reaper.TrackFX_GetFormattedParamValue(tr, fxi, k.dual)
  local t = (txt or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
  if t:find('m/s', 1, true) or t:find('mid/side', 1, true) or t:find('mid-side', 1, true) or t:find('^ms') then return 'band' end
  if t:find('stereo', 1, true) or t == 'l/r' or t == 'lr' then return 'pan' end
  if t:find('^left') or t:find('^right') or t:find('^mid') or t:find('^side') or t:find('^mono')
     or t == 'l' or t == 'r' or t == 'm' or t == 's' then return 'off' end
  if t ~= '' and not PARAM_MODE_REJ[t] then
    PARAM_MODE_REJ[t] = true
    write_file(LATDB_DIR .. '/param_text_rejects.txt', 'placement text\t' .. t .. '\n', 'a')
  end
  return nil
end

-- What control a parameter gets. REAPER says little about a parameter (its range, its step, whether
-- it is a toggle, how it prints a value), so FOH-Mate guesses from that and from the name, and the
-- guess can be corrected by hand: right-click a row in Edit mode. The corrections are kept in
-- Data/FOHMate/param_controls.txt (for every project), together with what REAPER said about the
-- parameter, so the guesses can be improved from them.
--   toggle: on/off, or two values   list: a few named values (a drop-down)   steps: a few numeric
--   values (a stepped encoder)      band: a width or a range (a band centered at the top of the encoder)
--   pan: a pan or balance (a band from the center to the left or the right)
--   qband: a Q factor (a band that gets narrower as the value goes up)
--   knob: a smooth encoder
PARAM_OVR      = nil
PARAM_OVR_FILE = LATDB_DIR .. '/param_controls.txt'
-- the names of the controls, used everywhere (the tree, the menus, the section on the right)
PARAM_KIND_LABEL = { knob = 'Encoder', band = 'Width band', pan = 'Pan', qband = 'Q band', steps = 'Stepped encoder', toggle = 'Toggle', list = 'Drop-down' }
PARAM_CONTROL_OPTS = { { nil, 'Automatic' } }
for _, k in ipairs({ 'knob', 'band', 'qband', 'pan', 'steps', 'toggle', 'list' }) do
  PARAM_CONTROL_OPTS[#PARAM_CONTROL_OPTS + 1] = { k, PARAM_KIND_LABEL[k] }
end

---------------------------------------------------------------- row colors and nicknames

-- The group a parameter belongs to, from its name: a word followed by a number ("Band 1", "Band2 Gain",
-- "Gain-Band 3", "Ch 2"). Returns the number and a label ("Band 1"), or nothing.
function param_group(pname)
  local word, n = (pname or ''):match('(%a+)%s*[%-_]?%s*(%d+)')
  if not n then return nil end
  return tonumber(n), word .. ' ' .. n
end

-- The name of a parameter without its group ("Band1 Type" > "Type", "Gain-Band 2" > "Gain"), for the
-- tree, where the group is the branch it sits in.
function param_group_rest(pname)
  local s, e = pname:find('%a+%s*[%-_]?%s*%d+')
  if not s then return pname end
  local rest = pname:sub(1, s - 1) .. ' ' .. pname:sub(e + 1)
  rest = rest:gsub('^[%s%-_:]+', ''):gsub('[%s%-_:]+$', ''):gsub('%s%s+', ' ')
  return (rest)
end

-- A color shifted to be readable on the window: lighter on a dark window, darker on a light one.
PARAM_READ = {}
function param_name_color(c, dark)
  local key = c * 2 + (dark and 1 or 0)
  local v = PARAM_READ[key]
  if v then return v end
  local h, sat, l = rgb_to_hsl((c >> 24) & 255, (c >> 16) & 255, (c >> 8) & 255)
  l = dark and math.max(l, 0.66) or math.min(l, 0.34)
  local r, g, b = hsl_to_rgb(h, sat, l)
  v = (r << 24) | (g << 16) | (b << 8) | 0xFF
  PARAM_READ[key] = v
  return v
end

-- The color a row is drawn in (0xRRGGBBAA): its own (Recolor parameters), or the rack's. Rows of a
-- group (an EQ's band...) get the rack's color shifted a little, one way for odd groups and the other
-- way for even ones, so neighbouring groups stand apart.
function param_row_color(rack_col, r)
  if r.col then return (r.col << 8) | 0xFF end
  local g = param_group(r.pname)
  if not g then return rack_col end
  local h, s, l = rgb_to_hsl((rack_col >> 24) & 255, (rack_col >> 16) & 255, (rack_col >> 8) & 255)
  local d = (g % 2 == 1) and -1 or 1
  local cr, cg, cb = hsl_to_rgb(h + d * 18, math.min(1, s * 1.1), math.max(0, math.min(1, l + d * 0.06)))
  return (cr << 24) | (cg << 16) | (cb << 8) | 0xFF
end

-- Recolor parameters: the color picker for some rows of a rack ({ guid, idx } each)
function param_open_picker(tr, targets, title)
  local r0 = params_find(tr, targets[1].guid, targets[1].idx)
  picker.kind, picker.tr, picker.rows, picker.title = 'param', tr, targets, title
  local fxg = targets[1].guid
  picker.rgb = r0 and param_row_color(fx_color(tr, fxg, track_color(tr)), r0) >> 8 or S.default_rgb
  picker.open = true
end

-- sets (rgb = 0xRRGGBB) or clears (nil: back to the automatic color) the color of those rows
function params_set_color(tr, targets, rgb)
  local pick = {}
  for _, t in ipairs(targets) do pick[t.guid .. ':' .. t.idx] = true end
  local rows = {}
  for _, r in ipairs(params_read(tr)) do
    local n = {}
    for k, v in pairs(r) do n[k] = v end
    if pick[r.guid .. ':' .. r.idx] then n.col = rgb end
    rows[#rows + 1] = n
  end
  params_write(tr, rows)
end

-- Nicknames: a name of the user's own for a parameter. With "Remember parameters nicknames" on
-- (Settings), it is also kept in Data/FOHMate/param_nicknames.txt (plug-in, parameter, nickname) and
-- given to that parameter whenever it is added to the Performance again, on any rack or project.
PARAM_NICK      = nil
PARAM_NICK_FILE = LATDB_DIR .. '/param_nicknames.txt'

function param_nick_load()
  PARAM_NICK = {}
  for _, ln in ipairs(read_lines(PARAM_NICK_FILE)) do
    local plug, pn, nick = ln:match('^([^\t]*)\t([^\t]*)\t(.+)$')
    if plug then PARAM_NICK[plug .. '\t' .. pn] = nick end
  end
end

function param_nick_get(plug, pname)
  if CFG.remember_nicks == 0 then return nil end
  if not PARAM_NICK then param_nick_load() end
  return PARAM_NICK[plug .. '\t' .. (pname or '')]
end

function param_nick_set(plug, pname, nick)
  if not PARAM_NICK then param_nick_load() end
  PARAM_NICK[plug .. '\t' .. (pname or '')] = nick
  local t = {}
  for k, v in pairs(PARAM_NICK) do t[#t + 1] = k .. '\t' .. v end
  table.sort(t)
  write_lines(PARAM_NICK_FILE, t)
end

-- asks for a row's nickname (outside of the ImGui frame); empty = the plug-in's own name again
function param_prompt_nick(tr, guid, idx)
  later[#later + 1] = function()
    if not valid(tr) then return end
    local r = params_find(tr, guid, idx)
    if not r then return end
    local ok, nick = reaper.GetUserInputs('Nickname parameter', 1, 'Nickname (empty: its own name):,extrawidth=160',
                                          r.name or r.pname or '')
    if ok then param_set_nick(tr, r, nick) end
  end
end

-- gives a row (r) a nickname; empty, or its own name = none
function param_set_nick(tr, r, nick)
  nick = nick:match('^%s*(.-)%s*$')
  if nick == r.pname then nick = '' end
  if nick == (r.name or '') then return end
  with_undo('Nickname parameter', function()
    params_update(tr, r.guid, r.idx, { name = nick ~= '' and nick or false })
  end)
  local fxi = fx_index_by_guid(tr, r.guid)
  if fxi and CFG.remember_nicks ~= 0 then param_nick_set(param_fx_key(tr, fxi), r.pname, nick ~= '' and nick or nil) end
end

-- the plug-in's name without its type, the way the corrections are filed
function param_plugin_key(fxname)
  return (fx_name_type(fxname))
end

-- the key of an FX of a rack
function param_fx_key(tr, fxi)
  local _, name = reaper.TrackFX_GetFXName(tr, fxi, '')
  return param_plugin_key(name or '')
end

function param_ovr_load()
  PARAM_OVR = {}
  for _, ln in ipairs(read_lines(PARAM_OVR_FILE)) do
    local f = {}
    for x in (ln .. '\t'):gmatch('([^\t]*)\t') do f[#f + 1] = x end
    if f[1] and f[2] and f[3] and f[3] ~= '' then PARAM_OVR[f[1] .. '\t' .. f[2]] = { kind = f[3], line = ln } end
  end
end

function param_ovr_save()
  local t = {}
  for _, o in pairs(PARAM_OVR) do t[#t + 1] = o.line end
  table.sort(t)
  write_lines(PARAM_OVR_FILE, t)
end

-- what REAPER says about a parameter
function param_facts(tr, fxi, idx)
  local ok, step, _, _, istoggle = reaper.TrackFX_GetParameterStepSizes(tr, fxi, idx)
  local _, mn, mx = reaper.TrackFX_GetParamEx(tr, fxi, idx)
  local _, t0 = param_fmt(tr, fxi, idx, 0, '')
  local _, t1 = param_fmt(tr, fxi, idx, 1, '')
  return { ok = ok, step = step, toggle = ok and istoggle, min = mn, max = mx, t0 = t0, t1 = t1 }
end

-- A parameter that is in dB gets the marks of a fader instead of one per step: where -60, -30, -10,
-- -5, 0 and +5 dB lie on it. REAPER can only say what text a position prints, so the parameter is
-- sampled at 41 positions (once) and the positions of those dB values are worked out from that.
-- Returns a list of positions 0..1, or nil when the parameter is not in dB.
FADER_DB = { -60, -30, -10, -5, 0, 5 }

function param_db_marks(tr, fxi, idx)
  local pts, is_db = {}, false
  for i = 0, 40 do
    local v = i / 40
    local _, txt = param_fmt(tr, fxi, idx, v, '')
    if txt:lower():find('db', 1, true) then is_db = true end
    local num = tonumber((txt:match('^%s*([%-%+]?%d+%.?%d*)')))
    if num then pts[#pts + 1] = { v, num } end
  end
  if not is_db or #pts < 2 then return nil end
  local marks = {}
  for _, target in ipairs(FADER_DB) do
    for i = 1, #pts - 1 do
      local a, b = pts[i], pts[i + 1]
      if (a[2] - target) * (b[2] - target) <= 0 and a[2] ~= b[2] then
        local v = a[1] + (b[1] - a[1]) * (target - a[2]) / (b[2] - a[2])
        if v > 0.02 and v < 0.98 then marks[#marks + 1] = v end
        break
      end
    end
  end
  return marks
end

function param_kind(tr, fxi, r)
  local key = r.guid .. ':' .. r.idx .. ':' .. (r.pname or '')
  local k = PARAM_KIND[key]
  if k then return k end
  if not PARAM_OVR then param_ovr_load() end

  -- how many values there are, when there are few (the step is in the parameter's own units). Up to
  -- 128 values are read: past 32, they are only kept when every one is a word (a band's types, many
  -- of them "Reserved"), which makes a drop-down
  local ok, step, _, _, istoggle = reaper.TrackFX_GetParameterStepSizes(tr, fxi, r.idx)
  local _, mn, mx = reaper.TrackFX_GetParamEx(tr, fxi, r.idx)
  local n
  if ok and step and step > 0 and mn and mx and mx > mn then
    local cnt = (mx - mn) / step
    if cnt <= 127.5 then n = math.floor(cnt + 0.5) + 1 end
  end
  local items, numeric
  if n and n >= 2 then
    items, numeric = {}, true
    local words = true                                     -- no value is a number (placeholders aside)
    for i = 0, n - 1 do
      local v = i / (n - 1)
      local _, txt = param_fmt(tr, fxi, r.idx, v, '')
      if txt == '' then txt = ('%d%%'):format(math.floor(v * 100 + 0.5)) end
      items[#items + 1] = { label = txt, norm = v }
      if not param_hidden_value(txt) then
        if tonumber((txt:match('^%s*([%-%+]?[%d%.]+)'))) then words = false else numeric = false end
      end
      if n > 32 and not words then break end
    end
    if n > 32 and not words then n, items, numeric = nil, nil, nil end
  end

  -- the guess
  local low = (r.pname or ''):lower()
  -- two values: a toggle when they read on/off or numbers, a drop-down when they are words (Mono / Stereo)
  local two_words = false
  if n == 2 and items and not (ok and istoggle) then
    local function plain(t)
      t = t:lower()
      return t:find('^on') or t:find('^off') or t:find('^yes') or t:find('^no') or t:find('^enable') or t:find('^disable')
             or t:find('^active') or t:find('^bypass') or tonumber((t:match('^%s*([%-%+]?[%d%.]+)')))
    end
    two_words = not (plain(items[1].label) and plain(items[2].label))
  end
  local guess = 'knob'
  if two_words then
    guess = 'list'
  elseif (ok and istoggle) or n == 2 or low:find('bypass', 1, true) or low:find('^enable') or low:find('on/off', 1, true)
     or low:find('^mute') or low == 'on' or low:find('^power') then
    guess = 'toggle'
  elseif n and n > 32 then
    guess = 'list'      -- only words (see above)
  elseif n and n >= 3 then
    guess = numeric and 'steps' or 'list'
  elseif low == 'pan' or low:find('^pan[%s%-_]') or low:find('[%s%-_]pan$') or low:find('balance', 1, true) then
    guess = 'pan'
  elseif low == 'q' or low:find('^q[%s%-_]') or low:find('[%s%-_]q$') or low:find('quality', 1, true)
         or low:find('[%s%-_]q[%s%-_]') then
    guess = 'qband'     -- a higher Q is a tighter band
  elseif low:find('width', 1, true) or low:find('range', 1, true) or low:find('spread', 1, true)
         or low:find('knee', 1, true) then
    guess = 'band'
  end

  -- a Pan/Width parameter follows a stereo placement parameter of the same band, when there is one
  local dual
  if not two_words and low:find('pan', 1, true) and low:find('width', 1, true) then
    guess = 'pan'
    dual = param_mode_sibling(tr, fxi, r)
  end

  -- in dB: a smooth encoder with the marks of a fader, never one mark per step
  local marks
  if guess == 'steps' or guess == 'knob' or guess == 'band' or guess == 'qband' or guess == 'pan' then
    marks = param_db_marks(tr, fxi, r.idx)
    if marks and guess == 'steps' then guess = 'knob' end
  end

  -- a correction made by hand wins (a list or steps needs the values to be known)
  local kind, overridden = guess, false
  local ovr = PARAM_OVR[param_fx_key(tr, fxi) .. '\t' .. (r.pname or '')]
  if ovr and PARAM_KIND_LABEL[ovr.kind] then
    kind, overridden = ovr.kind, true
    if (kind == 'steps' or kind == 'list') and not items then
      -- the plug-in doesn't say what its values are: take 11 positions along it
      n, items = 11, {}
      for i = 0, 10 do
        local v = i / 10
        local _, txt = param_fmt(tr, fxi, r.idx, v, '')
        if txt == '' then txt = ('%d%%'):format(i * 10) end
        items[#items + 1] = { label = txt, norm = v }
      end
    end
  end
  k = { kind = kind, guess = guess, overridden = overridden, label = PARAM_KIND_LABEL[kind], marks = marks,
        dual = not overridden and dual or nil }
  if (kind == 'steps' or kind == 'list') and items then
    -- values that are placeholders ("Reserved"...) are left out; a stepped encoder that lost some then
    -- goes through the others only (sparse: param_list_view)
    local kept = {}
    for _, it in ipairs(items) do if not param_hidden_value(it.label) then kept[#kept + 1] = it end end
    if #kept >= 2 and #kept < #items then items, n, k.sparse = kept, #kept, true end
    k.steps, k.items = n, items
    k.label = ('%s (%d)'):format(PARAM_KIND_LABEL[kind], n)
  end
  PARAM_KIND[key] = k
  return k
end

-- Sets (or, with kind = nil, clears) the correction for a parameter and files what REAPER said about it.
function param_set_override(tr, fxi, r, kind)
  if not PARAM_OVR then param_ovr_load() end
  local plug = param_fx_key(tr, fxi)
  local key = plug .. '\t' .. (r.pname or '')
  if kind then
    local guess = param_kind(tr, fxi, r).guess
    local f = param_facts(tr, fxi, r.idx)
    PARAM_OVR[key] = { kind = kind, line = table.concat({
      plug, r.pname or '', kind, guess, tostring(f.min), tostring(f.max), tostring(f.step),
      tostring(f.toggle), f.t0 or '', f.t1 or '' }, '\t') }
  else
    PARAM_OVR[key] = nil
  end
  PARAM_KIND[r.guid .. ':' .. r.idx .. ':' .. (r.pname or '')] = nil
  param_ovr_save()
end

---------------------------------------------------------------- the parameter window (Edit mode)
--
-- A tree of the rack: the rack, its FX, and under each FX every parameter. Click selects, Cmd/Ctrl-click
-- adds to the selection, Shift-click selects a stretch. "Add to Performance" and "Remove from
-- Performance" work on the selection; selecting an FX means all of its parameters.

-- Parameters that are not meant for the user are left out of the window: placeholders ("Reserved",
-- "Unused", "-", nameless, "Param 12"), and the MIDI CC entries many VST3 plug-ins add by the hundred
-- ("MIDI CC 0|1"). "Show hidden", next to the search in the window, brings them back.
function param_hidden(name)
  local l = name:lower():gsub('^%s+', ''):gsub('%s+$', '')
  return l == '' or l:find('^%-+$') ~= nil or l:find('^reserved') ~= nil or l:find('^unused') ~= nil
         or l:find('^midi cc%s*%d') ~= nil or l:find('^param%s*%d+$') ~= nil or l:find('^parameter%s*%d+$') ~= nil
end

-- the same for the values of a drop-down or a stepped parameter (a band type's "Reserved" choices)
function param_hidden_value(label)
  local l = label:lower():gsub('^%s+', ''):gsub('%s+$', '')
  return l:find('^%-+$') ~= nil or l:find('^reserved') ~= nil or l:find('^unused') ~= nil
end

-- REAPER adds Bypass, Wet and Delta at the end of every FX's parameters: they get a branch of their
-- own ("REAPER") at the end of the FX. names: the FX's parameter names (1-based); returns a set of indexes.
REAPER_PARAMS = { bypass = true, wet = true, delta = true }
function param_reaper_set(names)
  local set = {}
  for p = #names - 1, math.max(0, #names - 3), -1 do
    if not REAPER_PARAMS[(names[p + 1] or ''):lower()] then break end
    set[p] = true
  end
  return set
end

-- parameters hidden by hand ("Hide this parameter", right-click in the window), per plug-in, for every
-- project: Data/FOHMate/param_hidden.txt (plug-in, parameter)
PARAM_UHIDE = nil
PARAM_UHIDE_FILE = LATDB_DIR .. '/param_hidden.txt'
function param_uhidden(plug, pname)
  if not PARAM_UHIDE then
    PARAM_UHIDE = {}
    for _, ln in ipairs(read_lines(PARAM_UHIDE_FILE)) do
      if ln:find('\t', 1, true) then PARAM_UHIDE[ln] = true end
    end
  end
  return PARAM_UHIDE[plug .. '\t' .. pname] == true
end

function param_set_uhidden(plug, pname, on)
  param_uhidden(plug, pname)
  PARAM_UHIDE[plug .. '\t' .. pname] = on or nil
  local t = {}
  for k in pairs(PARAM_UHIDE) do t[#t + 1] = k end
  table.sort(t)
  write_lines(PARAM_UHIDE_FILE, t)
  if PARAM_PICK then PARAM_PICK.cache = nil end      -- the window's lists are made again
end

-- sel_key: a parameter to select at once ('p:' .. FX guid .. ':' .. index), for the row menu
-- Opens the parameter windows from rack tr: the tree and the inspector, or only the inspector
-- (which = 'insp'); the state (what is selected, which racks are open in the tree) is kept between
-- openings. sel_key: a parameter to select at once ('p:' .. FX guid .. ':' .. index), for the row menu.
function param_picker_open(tr, sel_key, which)
  local P = PARAM_PICK
  if not P then P = { filter = '', sel = {}, order = {} }; PARAM_PICK = P end
  P.tr = tr
  P.open = P.open or {}
  P.open['R:' .. reaper.GetTrackGUID(tr)] = true
  if which ~= 'insp' then P.tree_open = true end
  P.insp_open = true
  if sel_key then
    P.sel, P.anchor = { [sel_key] = true }, sel_key
    local g, ix = sel_key:match('^p:({[^}]+}):(%d+)$')      -- its branches are opened to show it
    if g then P.reveal = { guid = g, idx = tonumber(ix) } end
  end
end

-- Display > Windows: shows or hides one of the two windows (which = 'tree' or 'insp')
function param_pick_toggle(which)
  local P = PARAM_PICK
  if not P or not valid(P.tr) then
    local racks = param_racks()
    if #racks == 0 then return end
    if not P then P = { filter = '', sel = {}, order = {} }; PARAM_PICK = P end
    P.tr = racks[1].tr
    P.open = P.open or {}
    P.open['R:' .. racks[1].guid] = true
  end
  local f = which == 'tree' and 'tree_open' or 'insp_open'
  P[f] = not P[f]
end

-- the racks of the project, in track order
function param_racks()
  local out = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local name = track_name(tr)
    if is_rack_name(name) then out[#out + 1] = { tr = tr, guid = reaper.GetTrackGUID(tr), name = name } end
  end
  return out
end

-- A parameter clicked in the rack's column is selected in the parameter window's tree, when it is open (the
-- window works as an inspector): its rack, FX and groups are opened, the tree scrolls to it, a search that
-- would hide it is cleared.
function param_pick_select(tr, r)
  local P = PARAM_PICK
  if not P or not (P.tree_open or P.insp_open) then return end
  P.no_focus = true                                         -- it was clicked in the rack: no need to scroll there
  local key = 'p:' .. r.guid .. ':' .. r.idx
  P.sel, P.anchor = { [key] = true }, key
  P.open = P.open or {}
  P.open['R:' .. reaper.GetTrackGUID(tr)] = true
  P.reveal, P.scroll_key, P.filter = { guid = r.guid, idx = r.idx }, key, ''
end

-- a rack folded: what was selected in its FX is not selected any more (it can't be seen)
function param_pick_forget(P, tr)
  local guids = {}
  for i = 0, reaper.TrackFX_GetCount(tr) - 1 do guids[reaper.TrackFX_GetFXGUID(tr, i)] = true end
  for k in pairs(P.sel) do
    local g = k:match('^%a:({[^}]+})')
    if g and guids[g] then P.sel[k] = nil end
  end
end

-- The tree of an FX: parameters of the same group (param_group: "Band 1"...) go in a branch of their
-- own, where the first of them is; the others stay as they are. In a group, parameters that start
-- with the same word ("Dyn. Threshold", "Dyn. Ratio"...) go in a branch of their own too, and so on
-- (3 levels at most). A branch is { label, path, ps = { every index in it }, pset, children }, a
-- parameter is { p = index, label = its name without the groups }. fx.items is the list, in the
-- plug-in's order; fx.gps has the indexes of each branch by its key (for the selection).
local function param_split(fx, node, mem, depth)
  node.children, node.pset = {}, {}
  for _, m in ipairs(mem) do node.pset[m.p] = true end
  fx.gps['G:' .. fx.guid .. ':' .. node.path] = node.ps
  local first, cnt = {}, {}
  if depth <= 2 then
    for i, m in ipairs(mem) do
      local w = m.rest:match('^(%S+)%s+%S')
      first[i] = w
      if w then cnt[w] = (cnt[w] or 0) + 1 end
    end
  end
  local sub, subs = {}, {}
  for i, m in ipairs(mem) do
    local w = first[i]
    local c = w and cnt[w] or 0
    -- a word shared by 3 or more (2 when it ends with a dot or a colon: "Dyn."), but not by all
    if w and c < #mem and (c >= 3 or (c >= 2 and w:find('[%.:]$'))) then
      local sg = sub[w]
      if not sg then
        sg = { label = w, path = node.path .. '/' .. w, ps = {}, mem = {} }
        sub[w] = sg
        subs[#subs + 1] = sg
        node.children[#node.children + 1] = sg
      end
      sg.ps[#sg.ps + 1] = m.p
      sg.mem[#sg.mem + 1] = { p = m.p, rest = m.rest:match('^%S+%s+(.*)$') }
    else
      node.children[#node.children + 1] = { p = m.p, label = m.rest ~= '' and m.rest or fx.names[m.p + 1] }
    end
  end
  for _, sg in ipairs(subs) do param_split(fx, sg, sg.mem, depth + 1) end
end

function param_pick_groups(fx)
  local count = {}
  for p = 0, #fx.names - 1 do
    if not fx.hide[p] and not fx.reaper[p] then
      local _, lbl = param_group(fx.names[p + 1])
      if lbl then count[lbl] = (count[lbl] or 0) + 1 end
    end
  end
  local items, at, rp = {}, {}, nil
  fx.gps = {}
  for p = 0, #fx.names - 1 do
    if fx.reaper[p] then
      -- REAPER's own (Bypass, Wet, Delta): their branch, at the end
      if not fx.hide[p] then
        rp = rp or { label = 'REAPER', path = 'REAPER', ps = {}, mem = {} }
        rp.ps[#rp.ps + 1] = p
        rp.mem[#rp.mem + 1] = { p = p, rest = '' }          -- (rest empty: the parameter's own name)
      end
    elseif not fx.hide[p] then
      local nm = fx.names[p + 1]
      local _, lbl = param_group(nm)
      if lbl and count[lbl] > 1 then
        if not at[lbl] then at[lbl] = { label = lbl, path = lbl, ps = {}, mem = {} }; items[#items + 1] = at[lbl] end
        local g = at[lbl]
        g.ps[#g.ps + 1] = p
        g.mem[#g.mem + 1] = { p = p, rest = param_group_rest(nm) }
      else
        items[#items + 1] = { p = p, label = nm }
      end
    end
  end
  for _, it in ipairs(items) do if it.mem then param_split(fx, it, it.mem, 1) end end
  if rp then param_split(fx, rp, rp.mem, 9); items[#items + 1] = rp end     -- (depth 9: no sub-branches)
  fx.items = items
end

-- the parameters of an FX node or of one parameter, as { guid, idx, name }
function param_pick_targets(P, fxs)
  local out, seen = {}, {}
  local function add(fx, p)
    local key = fx.guid .. ':' .. p
    if not seen[key] then seen[key] = true; out[#out + 1] = { guid = fx.guid, idx = p, name = fx.names[p + 1], tr = fx.tr } end
  end
  for _, fx in ipairs(fxs) do
    if P.sel['P:' .. fx.guid] then
      for p = 0, #fx.names - 1 do if not fx.hide[p] then add(fx, p) end end
    end
    for key, ps in pairs(fx.gps or {}) do
      if P.sel[key] then for _, p in ipairs(ps) do add(fx, p) end end
    end
    for p = 0, #fx.names - 1 do
      if P.sel['p:' .. fx.guid .. ':' .. p] then add(fx, p) end
    end
  end
  return out
end

-- the selection may be in several racks: each gets its own
function param_pick_apply(P, fxs, adding)
  local by, order = {}, {}
  for _, t in ipairs(param_pick_targets(P, fxs)) do
    if not by[t.tr] then by[t.tr] = {}; order[#order + 1] = t.tr end
    table.insert(by[t.tr], t)
  end
  for _, tr in ipairs(order) do params_apply(tr, by[tr], adding) end
end

-- adds (or removes) parameters, { guid, idx, name } each, to the rack's Performance
function params_apply(tr, targets, adding)
  if #targets == 0 then return end
  local gm = fx_guid_map(tr)
  local rows, have = {}, {}
  for _, r in ipairs(params_read(tr)) do
    rows[#rows + 1] = r
    have[r.guid .. ':' .. r.idx] = #rows
  end
  if adding then
    for _, t in ipairs(targets) do
      if not have[t.guid .. ':' .. t.idx] and gm[t.guid] then
        -- the value it has now is remembered as its default (REAPER doesn't say what the plug-in's own is)
        -- except a pan (center) and a stereo width (mono, the minimum), whose zero is known
        local def = reaper.TrackFX_GetParamNormalized(tr, gm[t.guid], t.idx)
        local low = (t.name or ''):lower()
        if low:find('^pan$') or low:find('[%s%-_]pan$') or low:find('^pan[%s%-_]') or low:find('balance', 1, true) then
          def = 0.5
        elseif low:find('width', 1, true) and not low:find('band', 1, true) then
          def = 0
        end
        rows[#rows + 1] = { guid = t.guid, idx = t.idx, pname = t.name, def = def,
                            name = param_nick_get(param_fx_key(tr, gm[t.guid]), t.name) }
      end
    end
  else
    local drop = {}
    for _, t in ipairs(targets) do drop[t.guid .. ':' .. t.idx] = true end
    local kept = {}
    for _, r in ipairs(rows) do
      if not drop[r.guid .. ':' .. r.idx] then kept[#kept + 1] = r end
    end
    rows = kept
  end
  with_undo(adding and 'Add parameters to Performance' or 'Remove parameters from Performance',
            function() params_write(tr, rows) end)
end

-- a check box, drawn (the font may not have a check mark): x, y = top left, h = its size; on = ticked,
-- part = some but not all (a dash)
function draw_check(dl, x, y, h, col, on, part)
  ig.DrawList_AddRect(dl, x, y, x + h, y + h, col, 3, 0, 1.5)
  if on then
    ig.DrawList_AddLine(dl, x + h * 0.22, y + h * 0.52, x + h * 0.42, y + h * 0.74, col, 2)
    ig.DrawList_AddLine(dl, x + h * 0.42, y + h * 0.74, x + h * 0.8, y + h * 0.26, col, 2)
  elseif part then
    ig.DrawList_AddLine(dl, x + h * 0.25, y + h * 0.5, x + h * 0.75, y + h * 0.5, col, 2)
  end
end

-- the plug-in's name without its type ("VST3: Foo (Dev)" -> "Foo (Dev)") and the type
function fx_name_type(name)
  local t, rest = name:match('^(%w+):%s*(.*)$')
  if t then return rest, t end
  return name, nil
end

-- the right-hand section: pick and set up the control of the selected parameter(s)
function draw_param_control_panel(P, fxs, gm, targets)
  local tr = targets[1] and targets[1].tr or P.tr
  if #targets == 0 then
    ig.TextDisabled(ctx, 'Select a parameter to choose\nits control.')
    return
  end
  local first = targets[1]
  local fxi = gm[first.guid]
  local fxname = ''
  for _, fx in ipairs(fxs) do if fx.guid == first.guid then fxname = fx.name end end
  -- the title: the parameter's name, big and bold, its nickname right under it, then its FX
  local row = #targets == 1 and params_find(tr, first.guid, first.idx)
  local pushed = push_bold(head_font, HEAD_FONT_SIZE)
  ig.TextWrapped(ctx, #targets == 1 and first.name or ('%d parameters selected'):format(#targets))
  if pushed then ig.PopFont(ctx) end
  if #targets == 1 then
    -- the nickname is kept with the row (a parameter in the Performance); it is set when the box is left,
    -- also by picking another parameter while typing
    local nkey = first.guid .. ':' .. first.idx
    if P.nick_key ~= nkey and P.nick_edit and P.nick_row and valid(P.nick_tr) then
      param_set_nick(P.nick_tr, P.nick_row, P.nick)
      P.nick_edit = false
    end
    if P.nick_key ~= nkey or not P.nick_edit then
      P.nick_key, P.nick, P.nick_row, P.nick_tr = nkey, row and row.name or '', row, tr
    end
    ig.SetNextItemWidth(ctx, -1)
    if not row then ig.BeginDisabled(ctx) end
    local rv, nv = ig.InputTextWithHint(ctx, '##nick' .. nkey, row and 'Nickname (empty: its own name)'
                                        or 'Nickname: put it in the Performance first', P.nick)
    if rv then P.nick = nv end
    P.nick_edit = ig.IsItemActive(ctx)
    if row and ig.IsItemDeactivatedAfterEdit(ctx) then param_set_nick(tr, row, P.nick) end
    if not row then ig.EndDisabled(ctx) end
    ig.TextDisabled(ctx, (fx_name_type(fxname)))
  else
    ig.TextDisabled(ctx, 'The choice applies to all of them.')
  end
  if not fxi then return end
  local r1 = { guid = first.guid, idx = first.idx, pname = first.name }
  local k = param_kind(tr, fxi, r1)
  ig.Spacing(ctx)
  if section_header('Control', true) then
    for _, o in ipairs(PARAM_CONTROL_OPTS) do
      local on = #targets == 1 and ((o[1] == nil and not k.overridden) or (o[1] ~= nil and k.overridden and k.kind == o[1]))
      local label = o[2] .. ((o[1] == nil and #targets == 1) and (' (now: ' .. PARAM_KIND_LABEL[k.guess] .. ')') or '')
      if ig.RadioButton(ctx, label .. '##ctl' .. tostring(o[1]), on) then
        for _, t in ipairs(targets) do
          local f = gm[t.guid]
          if f then param_set_override(t.tr or tr, f, { guid = t.guid, idx = t.idx, pname = t.name }, o[1]) end
        end
      end
    end
    ig.TextDisabled(ctx, 'Your choice is added to the training data.')
    ig.Spacing(ctx)
  end
  if #targets ~= 1 then return end

  -- how this row behaves (saved with the project: only for a parameter that is in the Performance)
  if not row then
    ig.TextDisabled(ctx, 'Put the parameter in the Performance\nto set the rest.')
  else
    if section_header('Direction and default', true) then
      local inv = row.inv == true
      local rv, v = ig.Checkbox(ctx, 'Invert (turns the other way)', inv)
      if rv then params_update(tr, first.guid, first.idx, { inv = v }) end
      local has_def = row.def ~= nil
      local rv2, v2 = ig.Checkbox(ctx, 'Default mark', has_def)
      if rv2 then
        params_update(tr, first.guid, first.idx, { def = v2 and reaper.TrackFX_GetParamNormalized(tr, fxi, first.idx) or false })
      end
      if has_def then
        ig.AlignTextToFramePadding(ctx)
        ig.TextDisabled(ctx, 'Put it at:')
        local at = { { 'Now', nil }, { 'Minimum', 0 }, { 'Middle', 0.5 }, { 'Maximum', 1 } }
        for i, a_ in ipairs(at) do
          ig.SameLine(ctx)
          if ig.SmallButton(ctx, a_[1] .. '##defat' .. i) then
            params_update(tr, first.guid, first.idx,
                          { def = a_[2] or reaper.TrackFX_GetParamNormalized(tr, fxi, first.idx) })
          end
        end
      end
      ig.Spacing(ctx)
    end
    -- Limit values: Min / Max (the controls that turn, param_limit_ok) or a list (param_list_ok)
    local can_mm, can_list = param_limit_ok(k.kind), param_list_ok(k.kind)
    if (can_mm or can_list) and section_header('Limit values', true) then
      local g, ix = first.guid, first.idx
      local function mm_on() params_update(tr, g, ix, { lim = 'mm', lo = row.lo or 0, hi = row.hi or 1 }) end
      -- choosing the list: when the value it has now isn't in it, ask whether to add it (once the list is
      -- on, the parameter only takes the values of the list, so this is the moment to keep it)
      local function list_on()
        local cur = reaper.TrackFX_GetParamNormalized(tr, fxi, ix)
        params_update(tr, g, ix, { lim = 'list' })
        for _, x in ipairs(row.vals or {}) do
          if math.abs(x - cur) < 1e-5 then param_list_snap(tr, fxi, ix, row.vals); return end
        end
        local function finish(add)
          if not valid(tr) then return end
          local r = params_find(tr, g, ix)
          if not r then return end
          local nv = {}
          for _, x in ipairs(r.vals or {}) do nv[#nv + 1] = x end
          if add then nv[#nv + 1] = cur; params_update(tr, g, ix, { vals = nv }) end
          param_list_snap(tr, fxi, ix, nv)
        end
        request_confirm(('Add the value it has now (%s) to the list?'):format(param_text_at(tr, fxi, ix, cur)),
          function() finish(true) end, 'Add it', nil, { label = "Don't add", fn = function() finish(false) end })
      end
      local rv3, v3 = ig.Checkbox(ctx, 'Use limits', row.lim ~= nil)
      if ig.IsItemHovered(ctx) then
        ig.SetTooltip(ctx, 'When it is moved from the Performance, the parameter only takes\nthe values between a Min and a Max, or the values of a list.')
      end
      if rv3 then
        if not v3 then params_update(tr, g, ix, { lim = false })
        elseif can_list and (row.vals or not can_mm) then list_on()
        else mm_on() end
      end
      if row.lim and can_mm and can_list then
        if ig.RadioButton(ctx, 'Min / Max', row.lim == 'mm') and row.lim ~= 'mm' then mm_on() end
        ig.SameLine(ctx)
        if ig.RadioButton(ctx, 'List of values', row.lim == 'list') and row.lim ~= 'list' then list_on() end
      end
      -- the plug-in's text for a position, as a slider can show it
      local function txt(v) return (param_text_at(tr, fxi, ix, v):gsub('%%', '%%%%')) end
      if row.lim == 'mm' and can_mm then
        local lo, hi = row.lo, row.hi
        for _, e in ipairs({ { 'Min', 'lo' }, { 'Max', 'hi' } }) do
          ig.SetNextItemWidth(ctx, 160)
          local rv, v = ig.SliderDouble(ctx, e[1] .. '##lim' .. e[2], row[e[2]], 0, 1, txt(row[e[2]]))
          ig.SameLine(ctx)
          if ig.SmallButton(ctx, 'Now##limnow' .. e[2]) then rv, v = true, reaper.TrackFX_GetParamNormalized(tr, fxi, ix) end
          if ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, 'Set ' .. e[1] .. ' to where the parameter is now') end
          if rv then
            if e[2] == 'lo' then lo = math.min(v, hi - 0.001) else hi = math.max(v, lo + 0.001) end
          end
        end
        if lo ~= row.lo or hi ~= row.hi then
          params_update(tr, g, ix, { lo = lo, hi = hi })
          -- the parameter moves inside the new limits at once
          local cur = reaper.TrackFX_GetParamNormalized(tr, fxi, ix)
          if cur < lo or cur > hi then reaper.TrackFX_SetParamNormalized(tr, fxi, ix, math.max(lo, math.min(hi, cur))) end
        end
        if param_fit_ok(k.kind) then
          local rv4, v4 = ig.Checkbox(ctx, 'Use the full range of the control', row.fit == true)
          if ig.IsItemHovered(ctx) then
            ig.SetTooltip(ctx, 'On: the control turns all the way from Min to Max, for finer moves.\n'
                            .. 'Off: the control stops at Min and Max (an arc shows where).')
          end
          if rv4 then params_update(tr, g, ix, { fit = v4 }) end
        else
          ig.TextDisabled(ctx, 'The control stops at Min and Max.')
        end
      elseif row.lim == 'list' and can_list then
        -- the values, in the list's order (any order), with on the right: move up, move down, remove (red)
        local vals = row.vals or {}
        local function put(nv)
          params_update(tr, g, ix, { vals = #nv > 0 and nv or false })
          param_list_snap(tr, fxi, ix, nv)
        end
        local function copy() local nv = {}; for i, v in ipairs(vals) do nv[i] = v end; return nv end
        if #vals == 0 then ig.TextDisabled(ctx, 'No values yet: add some below.') end
        local bw = ig.GetFrameHeight(ctx)
        local sp = select(1, ig.GetStyleVar(ctx, ig.StyleVar_ItemSpacing()))
        local bx = ig.GetCursorPosX(ctx) + math.max(0, select(1, ig.GetContentRegionAvail(ctx)) - 3 * bw - 2 * sp)
        -- the boxes are in the parameter's color (as readable as its name in the tree), the unit outside
        local rcol = param_row_color(fx_color(tr, g, track_color(tr)), row)
        local bgc = ig.GetStyleColor(ctx, ig.Col_WindowBg())
        local dk = ((bgc >> 24) & 255) * 0.3 + ((bgc >> 16) & 255) * 0.59 + ((bgc >> 8) & 255) * 0.11 < 128
        for i, v in ipairs(vals) do
          ig.PushID(ctx, 'lv' .. i)
          local num, unit, isnum = param_text_split(param_text_at(tr, fxi, ix, v))
          ig.PushStyleColor(ctx, ig.Col_FrameBg(), (rcol & 0xFFFFFF00) | 0x40)
          ig.PushStyleColor(ctx, ig.Col_Border(), (rcol & 0xFFFFFF00) | 0xB0)
          ig.PushStyleColor(ctx, ig.Col_Text(), param_name_color(rcol, dk))
          ig.PushStyleVar(ctx, ig.StyleVar_FrameBorderSize(), 1)
          ig.SetNextItemWidth(ctx, isnum and 84 or math.max(84, ig.CalcTextSize(ctx, num) + 16))
          -- a number can be typed: the parameter is asked for the position that prints it
          local rv, typed = ig.InputText(ctx, '##val', num, isnum and ig.InputTextFlags_AutoSelectAll() or ig.InputTextFlags_ReadOnly())
          ig.PopStyleVar(ctx)
          ig.PopStyleColor(ctx, 3)
          if rv then P.ve, P.ve_i = typed, i end
          if isnum and ig.IsItemDeactivatedAfterEdit(ctx) and P.ve_i == i then
            local tn, tu, tis = param_text_split((P.ve:gsub(',', '.')))
            local nv = tis and param_find_value(tr, fxi, ix, tonumber(tn), tu ~= '' and tu or unit)
            if nv then local nvals = copy(); nvals[i] = nv; put(nvals) end
          end
          if unit ~= '' then
            ig.SameLine(ctx, 0, 4)
            ig.AlignTextToFramePadding(ctx)
            ig.TextDisabled(ctx, unit)
          end
          ig.SameLine(ctx, bx)
          -- no up arrow on the first value, no down arrow on the last: an empty space keeps the others lined up
          if i == 1 then ig.Dummy(ctx, bw, bw)
          elseif ig.ArrowButton(ctx, 'up', ig.Dir_Up()) then
            local nv = copy(); nv[i], nv[i - 1] = nv[i - 1], nv[i]; put(nv)
          end
          ig.SameLine(ctx)
          if i == #vals then ig.Dummy(ctx, bw, bw)
          elseif ig.ArrowButton(ctx, 'dn', ig.Dir_Down()) then
            local nv = copy(); nv[i], nv[i + 1] = nv[i + 1], nv[i]; put(nv)
          end
          ig.SameLine(ctx)
          ig.PushStyleColor(ctx, ig.Col_Button(), 0xB03030FF)
          ig.PushStyleColor(ctx, ig.Col_ButtonHovered(), 0xD04040FF)
          ig.PushStyleColor(ctx, ig.Col_ButtonActive(), 0x902020FF)
          ig.PushStyleColor(ctx, ig.Col_Text(), 0xFFFFFFFF)
          if ig.Button(ctx, 'x', bw, bw) then local nv = copy(); table.remove(nv, i); put(nv) end
          ig.PopStyleColor(ctx, 4)
          if ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, 'Remove this value from the list') end
          ig.PopID(ctx)
        end
        -- adding, at the end: one of the plug-in's own values, or one picked. The field and the Add button
        -- together are as wide as the list.
        local function add(v)
          for _, x in ipairs(vals) do if math.abs(x - v) < 1e-5 then return end end
          local nv = copy(); nv[#nv + 1] = v; put(nv)
        end
        local W = select(1, ig.GetContentRegionAvail(ctx))
        if k.items then
          ig.SetNextItemWidth(ctx, W)
          if ig.BeginCombo(ctx, '##ladd', 'Add one of its values...') then
            for _, it in ipairs(k.items) do
              if ig.Selectable(ctx, it.label .. '##' .. it.norm, false) then add(it.norm) end
            end
            ig.EndCombo(ctx)
          end
        else
          if P.lpick_key ~= g .. ':' .. ix then
            P.lpick_key, P.lpick = g .. ':' .. ix, reaper.TrackFX_GetParamNormalized(tr, fxi, ix)
          end
          local addw = ig.CalcTextSize(ctx, 'Add') + 2 * select(1, ig.GetStyleVar(ctx, ig.StyleVar_FramePadding()))
          ig.SetNextItemWidth(ctx, W - addw - sp)
          local rv, v = ig.SliderDouble(ctx, '##lpick', P.lpick, 0, 1, txt(P.lpick))
          if rv then P.lpick = v end
          ig.SameLine(ctx)
          if ig.Button(ctx, 'Add', addw, 0) then add(P.lpick) end
        end
        -- what the control becomes: its caption right above the menu
        ig.Spacing(ctx)
        ig.Text(ctx, 'Show as')
        local auto = param_list_show({}, k.kind, #vals)
        local opts = { { false, ('Automatic (%s)'):format(PARAM_KIND_LABEL[auto == 'list' and 'list' or 'steps']) },
                       { 'steps', 'Stepped encoder' }, { 'list', 'Drop-down' } }
        local cur_l = opts[1][2]
        for _, o in ipairs(opts) do if o[1] and o[1] == row.vshow then cur_l = o[2] end end
        ig.SetNextItemWidth(ctx, W)
        if ig.BeginCombo(ctx, '##lshow', cur_l) then
          for _, o in ipairs(opts) do
            if ig.Selectable(ctx, o[2], (o[1] or nil) == row.vshow) then params_update(tr, g, ix, { vshow = o[1] }) end
          end
          ig.EndCombo(ctx)
        end
        if #vals == 1 then ig.TextDisabled(ctx, 'A single value is always a drop-down.') end
      end
      ig.Spacing(ctx)
    end
    -- the value curve (curves.lua), for encoders and width / Q bands
    if param_curve_ok(k.kind) and section_header('Curve', true) then
      if row.lim == 'list' then
        ig.TextDisabled(ctx, 'Not with a list of values.')
      else
        local u = param_to_ctl(row, k.kind, reaper.TrackFX_GetParamNormalized(tr, fxi, first.idx))
        local cvp = param_curve_of(row, k.kind)
        draw_curve_section(tr, row, cvp and curve_inv(cvp, u, param_row_memo(tr, row, fxi).cpos) or u)
      end
      ig.Spacing(ctx)
    end
  end

  -- a preview of the control, and what REAPER says about the parameter
  if section_header('Preview', true) then draw_param_preview(tr, fxi, first, row, k) end
  if section_header('Details', false) then
    local f = param_facts(tr, fxi, first.idx)
    local _, now = reaper.TrackFX_GetFormattedParamValue(tr, fxi, first.idx)
    ig.TextDisabled(ctx, ('Now: %s'):format(now or ''))
    ig.TextDisabled(ctx, ('At the minimum: %s'):format(f.t0 or ''))
    ig.TextDisabled(ctx, ('At the maximum: %s'):format(f.t1 or ''))
    ig.TextDisabled(ctx, ('Range: %s to %s, step %s'):format(tostring(f.min), tostring(f.max), tostring(f.step)))
    ig.TextDisabled(ctx, ('REAPER says toggle: %s'):format(f.toggle and 'yes' or 'no'))
  end
end

-- the control as the Performance draws it, in the parameter window
function draw_param_preview(tr, fxi, first, row, k)
  local norm = reaper.TrackFX_GetParamNormalized(tr, fxi, first.idx)
  local px, py = ig.GetCursorScreenPos(ctx)
  local dl = ig.GetWindowDrawList(ctx)
  local body = ig.GetStyleColor(ctx, ig.Col_FrameBg())
  local ring = ig.GetStyleColor(ctx, ig.Col_Text())
  local cx, cy, r = px + 36, py + 34, 20
  local lv = row and param_list_view(tr, fxi, row, k.kind, param_row_memo(tr, row, fxi), norm, k)
  if k.kind == 'toggle' then
    ig.DrawList_AddCircleFilled(dl, cx, cy, r, body, 0)
    ig.DrawList_AddCircle(dl, cx, cy, r, ring, 0, 2)
    if norm > 0.5 then ig.DrawList_AddCircleFilled(dl, cx, cy, r - 6, T.chk_dot, 0) end
  elseif lv and lv.show == 'steps' then
    draw_encoder('pv', cx, cy, r, (lv.pos - 1) / (#lv.items - 1), { body = body, col = ring, ptr = T.dots, s = 1, static = true,
                 style = 'line', steps = #lv.items, def = lv.def })
  elseif lv or k.kind == 'list' then
    ig.DrawList_AddCircleFilled(dl, cx, cy, r, body, 0)
    ig.DrawList_AddCircle(dl, cx, cy, r, ring, 0, 2)
    ig.DrawList_AddTriangleFilled(dl, cx - 6, cy - 3.5, cx + 6, cy - 3.5, cx, cy + 4, ring)
  else
    local rr = row or {}
    local pm, pd, range = param_ctl_view(rr, k.kind, k.marks)
    draw_encoder('pv', cx, cy, r, param_to_ctl(rr, k.kind, norm), { body = body, col = ring, ptr = T.dots, s = 1, static = true,
                 style = k.kind == 'pan' and 'pan' or (k.kind == 'band' or k.kind == 'qband') and 'band' or 'line', narrow = k.kind == 'qband', steps = k.steps, marks = pm, def = pd,
                 range = range })
  end
  ig.Dummy(ctx, 1, 72)
end

-- The parameters have two windows, the tree and the inspector, each of which opens, closes, floats and
-- docks on its own (Display > Windows). They are drawn from the same data, worked out once a frame here:
-- the racks (and the FX of the ones open in the tree, with the names of their parameters, read once per
-- FX), and what is selected.
function param_pick_data(P)
  -- every rack of the project is a branch; the FX of the racks that are open, and the names of their
  -- parameters, are read once per FX
  local racks = param_racks()
  P.open = P.open or {}
  local fxs, gm = {}, {}
  for _, rk in ipairs(racks) do
    rk.fxs = {}
    if P.open['R:' .. rk.guid] then
      for _, it in ipairs(chain_info(rk.tr).list) do
        local g = reaper.TrackFX_GetFXGUID(rk.tr, it.fx)
        local f = P.cache and P.cache[g]
        if not f or f.fx ~= it.fx or f.name ~= it.name then
          -- hidden: by the rules above (auto) or by hand (uhid); shown anyway with Show hidden
          local names, hide, auto, uhid, nvis = {}, {}, {}, {}, 0
          local plug = param_plugin_key(it.name)
          for p = 0, reaper.TrackFX_GetNumParams(rk.tr, it.fx) - 1 do
            local _, nm = reaper.TrackFX_GetParamName(rk.tr, it.fx, p, '')
            names[p + 1] = nm
            auto[p], uhid[p] = param_hidden(nm), param_uhidden(plug, nm)
            if (auto[p] or uhid[p]) and not P.show_hidden then hide[p] = true else nvis = nvis + 1 end
          end
          f = { guid = g, fx = it.fx, name = it.name, names = names, hide = hide, auto = auto, uhid = uhid,
                plug = plug, nvis = nvis, reaper = param_reaper_set(names) }
          param_pick_groups(f)
          P.cache = P.cache or {}
          P.cache[g] = f
        end
        f.tr = rk.tr
        gm[g] = it.fx
        rk.fxs[#rk.fxs + 1] = f
        fxs[#fxs + 1] = f
      end
    end
  end

  -- what is selected glows in the rack's column (window.lua); a single parameter picked here is also
  -- scrolled to, once (the rack into view, then the column to the row)
  local targets = param_pick_targets(P, fxs)
  P.hl = {}
  local sig = #targets .. ':' .. (targets[1] and (targets[1].guid .. ':' .. targets[1].idx) or '')
  for _, t in ipairs(targets) do P.hl[t.guid .. ':' .. t.idx] = true end
  if P.sel_sig ~= sig then
    P.sel_sig = sig
    P.focus = (#targets == 1 and not P.no_focus) and { guid = targets[1].guid, idx = targets[1].idx, t = reaper.time_precise() } or nil
    P.no_focus = false
  end
  if P.focus and reaper.time_precise() - P.focus.t > 1 then P.focus = nil end   -- not in any column: forget it

  P.data = { racks = racks, fxs = fxs, gm = gm, targets = targets }
  return P.data
end

-- the tree: the racks, their FX, groups and parameters, with the check boxes that add them to the Performance
function draw_param_tree(P, D)
  local racks, fxs, gm = D.racks, D.fxs, D.gm
  local vis, open = begin_window('parampick', 'Performance parameters###parampick', 480, 560, true)
  if vis then
    ig.SetNextItemWidth(ctx, -ig.CalcTextSize(ctx, 'Show hidden') - ig.GetFrameHeight(ctx) - 16)
    local rv, ftxt = ig.InputTextWithHint(ctx, '##pf', 'Search parameters', P.filter)
    if rv then P.filter = ftxt end
    ig.SameLine(ctx)
    local rvh, vh = ig.Checkbox(ctx, 'Show hidden', P.show_hidden == true)
    if rvh then P.show_hidden, P.cache = vh, nil end
    if ig.IsItemHovered(ctx) then
      ig.SetTooltip(ctx, 'Also list the parameters that are hidden: placeholders ("Reserved"...), MIDI CC\n'
                      .. 'entries, and those you hid (right-click a parameter > Hide this parameter).')
    end
    local low = P.filter:lower()

    local have, rowof = {}, {}
    for _, rk in ipairs(racks) do
      if P.open['R:' .. rk.guid] then
        for _, r in ipairs(params_read(rk.tr)) do
          have[r.guid .. ':' .. r.idx], rowof[r.guid .. ':' .. r.idx] = true, r
        end
      end
    end
    local lh = ig.GetTextLineHeightWithSpacing(ctx)
    local TXT = ig.GetStyleColor(ctx, ig.Col_Text())
    local bgc = ig.GetStyleColor(ctx, ig.Col_WindowBg())
    local dark = ((bgc >> 24) & 255) * 0.3 + ((bgc >> 16) & 255) * 0.59 + ((bgc >> 8) & 255) * 0.11 < 128
    local order = {}
    local box = lh - 6                                   -- the check boxes: this size whatever the text
    local function click(key, shift, ctrl)
      if shift and P.anchor then
        local a, b
        for i, k in ipairs(P.order) do
          if k == P.anchor then a = i end
          if k == key then b = i end
        end
        if a and b then
          if a > b then a, b = b, a end
          for i = a, b do P.sel[P.order[i]] = true end
          return
        end
      end
      if not ctrl then P.sel = {} end
      if ctrl and P.sel[key] then P.sel[key] = nil else P.sel[key] = true end
      P.anchor = key
    end
    local mx = ig.GetMousePos(ctx)

    -- the height of a line by what it holds: a rack (big name), an FX or a group (a smaller one), a parameter
    local function line_h(font, size)
      local pushed = push_bold(font, size)
      local h = ig.GetTextLineHeight(ctx)
      if pushed then ig.PopFont(ctx) end
      return math.floor(h)
    end
    local th0 = ig.GetTextLineHeight(ctx)
    local h_rack, h_grp, h_par = line_h(head_font, HEAD_FONT_SIZE) + 8, line_h(sect_font, SECT_FONT_SIZE) + 6, lh - 2

    local avail_w, avail_h = ig.GetContentRegionAvail(ctx)
    local foot = ig.GetFrameHeightWithSpacing(ctx) + 4
    if ig.BeginChild(ctx, 'pptree', avail_w, avail_h - foot) then
      -- Every line is drawn here, not by ImGui's tree: a branch has its arrow, then (FX, groups,
      -- parameters) a check box, then its name. What a branch holds is one step in, and the step is
      -- the width of a check box and its gap: the check boxes of what is in a branch start where the
      -- name of the branch starts, and a branch inside a branch has its check box with its siblings'
      -- (its arrow is left of it).
      local L = ig.GetCursorScreenPos(ctx) + 6
      local aw = 10                                       -- the arrow
      -- an FX is one more step in than its rack's name, so its arrow sits under the name's first letter
      local function cxof(depth) return L + aw + 6 + (aw + 4) + depth * (box + 8) end
      -- a thin dotted line down a branch, from under its row to its last line (only what is in view)
      local wx, wy = ig.GetWindowPos(ctx)
      local ww, wh = ig.GetWindowSize(ctx)
      local lastbot = 0                                   -- where the last line drawn ends
      local guide_col = (T.dim & 0xFFFFFF00) | 0xB0
      local function guide(x, y1, y2)
        for y = math.max(y1, wy), math.min(y2, wy + wh), 4 do
          ig.DrawList_AddRectFilled(ig.GetWindowDrawList(ctx), x - 0.5, y, x + 1, y + 1.5, guide_col)
        end
      end

      -- sp: id, sel (the key it selects by), depth, h, font + size (of the name), arrow + open + okey (the
      -- branches), check + on + part (the check box), name, col, type, count, right, tip, on_check, menu
      local function draw_row(sp)
        if sp.sel then order[#order + 1] = sp.sel end
        local scroll = sp.sel ~= nil and sp.sel == P.scroll_key        -- a parameter picked in the rack: brought into view
        if not scroll and not ig.IsRectVisible(ctx, 1, sp.h) then
          ig.Dummy(ctx, 1, sp.h)
          lastbot = select(2, ig.GetItemRectMax(ctx))
          return
        end
        local clicked = ig.Selectable(ctx, '##' .. sp.id, sp.sel ~= nil and P.sel[sp.sel] == true, 0, 0, sp.h)
        local ix, iy = ig.GetItemRectMin(ctx)
        local iw = ig.GetItemRectSize(ctx)
        lastbot = iy + sp.h
        if scroll then ig.SetScrollHereY(ctx, 0.35); P.scroll_key = nil end
        local midy = iy + sp.h / 2
        local cx = sp.check and cxof(sp.depth) or nil
        local ax = cx and (cx - aw - 4) or L
        local tx = cx and (cx + box + 8) or (L + aw + 6)
        if sp.tip and ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, sp.tip) end
        if sp.menu and ig.BeginPopupContextItem(ctx, 'pph' .. sp.id) then sp.menu(); ig.EndPopup(ctx) end
        if clicked then
          local toggle = sp.arrow and mx >= ax - 3 and mx <= ax + aw + 3
          if toggle or (sp.arrow and not sp.sel) then
            sp.on_toggle()
          elseif cx and mx >= cx - 3 and mx <= cx + box + 3 then
            sp.on_check()
          elseif sp.sel then
            click(sp.sel, has_mod('shift'), has_mod('ctrl'))
          end
        end
        local dl = ig.GetWindowDrawList(ctx)
        if sp.arrow then
          if sp.open then
            ig.DrawList_AddTriangleFilled(dl, ax, midy - 2.5, ax + aw, midy - 2.5, ax + aw / 2, midy + 3.5, TXT)
          else
            ig.DrawList_AddTriangleFilled(dl, ax + 2, midy - 4.5, ax + 2, midy + 4.5, ax + aw, midy, TXT)
          end
        end
        if cx then draw_check(dl, cx, midy - box / 2, box, TXT, sp.on, sp.part) end
        local rcol = sp.right and (ix + iw * 0.5)           -- the kind and value column: the same place on every line
        local pushed = sp.font and push_bold(sp.font, sp.size)
        local th = ig.GetTextLineHeight(ctx)
        local name = sp.name
        if rcol then name = fit_text(name, rcol - tx - 10) end
        ig.DrawList_AddText(dl, tx, midy - th / 2, sp.col or TXT, name)
        local nx = tx + ig.CalcTextSize(ctx, name) + 8
        if pushed then ig.PopFont(ctx) end
        local ty = midy - th0 / 2
        if sp.type then
          local ttxt = '(' .. sp.type .. ')'
          ig.DrawList_AddText(dl, nx, ty, type_color(sp.type), ttxt)
          nx = nx + ig.CalcTextSize(ctx, ttxt) + 8
        end
        if sp.count then ig.DrawList_AddText(dl, nx, ty, T.dim, sp.count) end
        if rcol then ig.DrawList_AddText(dl, rcol, ty, T.dim, fit_text(sp.right(), ix + iw - rcol - 6)) end
      end

      local function matches(fx, p) return low == '' or fx.names[p + 1]:lower():find(low, 1, true) end
      local function targets_of(fx, ps)
        local t = {}
        for _, p in ipairs(ps) do t[#t + 1] = { guid = fx.guid, idx = p, name = fx.names[p + 1] } end
        return t
      end
      local function count_have(fx, ps)
        local n = 0
        for _, p in ipairs(ps) do if have[fx.guid .. ':' .. p] then n = n + 1 end end
        return n
      end

      local function draw_leaf(fx, p, label, depth, rack_col)
        local nm = fx.names[p + 1]
        local key = 'p:' .. fx.guid .. ':' .. p
        local inn = have[fx.guid .. ':' .. p] == true
        local hid = fx.auto[p] or fx.uhid[p]
        local col = TXT
        if ig.IsRectVisible(ctx, 1, h_par) then
          -- the name in the color it has in the rack (its own, or the group's shift of the rack's), made readable
          col = hid and T.dim or param_name_color(
            param_row_color(rack_col, { col = rowof[fx.guid .. ':' .. p] and rowof[fx.guid .. ':' .. p].col, pname = nm }), dark)
          -- (rack_col here is the color of the FX the parameter is in)
        end
        draw_row({ id = key, sel = key, depth = depth, h = h_par, check = true, on = inn, col = col,
          name = label .. (hid and '  (hidden)' or ''),
          tip = label ~= nm and nm or nil,
          right = function()
            -- the kind of value and its value now
            local kind = param_kind(fx.tr, gm[fx.guid], { guid = fx.guid, idx = p, pname = nm })
            local _, txt = reaper.TrackFX_GetFormattedParamValue(fx.tr, gm[fx.guid], p)
            return ('%s:  %s'):format(kind.label, txt or '')
          end,
          on_check = function() params_apply(fx.tr, { { guid = fx.guid, idx = p, name = nm } }, not inn) end,
          -- right-click: hide it (for this plug-in, everywhere), or show it again
          menu = function()
            if fx.uhid[p] then
              if ig.MenuItem(ctx, 'Show this parameter again') then param_set_uhidden(fx.plug, nm, false) end
            elseif fx.auto[p] then
              ig.TextDisabled(ctx, 'Hidden by FOH-Mate (a placeholder or a MIDI CC entry)')
            elseif ig.MenuItem(ctx, 'Hide this parameter') then
              param_set_uhidden(fx.plug, nm, true)
            end
          end })
      end

      local draw_nodes
      -- a group ("Band 1"), or a branch of one ("Dyn."): folded at first, open while searching when something in it matches
      local function draw_group(fx, nd, depth, rack_col)
        if low ~= '' then
          local any = false
          for _, p in ipairs(nd.ps) do if matches(fx, p) then any = true; break end end
          if not any then return end
        end
        local gkey = 'G:' .. fx.guid .. ':' .. nd.path
        if P.reveal and P.reveal.guid == fx.guid and nd.pset[P.reveal.idx] then P.open[gkey] = true end
        local opened = low ~= '' or P.open[gkey] == true
        local g_have = count_have(fx, nd.ps)
        draw_row({ id = gkey, sel = gkey, depth = depth, h = h_grp, font = sect_font, size = SECT_FONT_SIZE,
          col = param_name_color(param_row_color(rack_col, { pname = nd.label }), dark),
          arrow = true, open = opened, check = true, on = g_have == #nd.ps, part = g_have > 0, name = nd.label,
          count = ('%d of %d in the Performance'):format(g_have, #nd.ps),
          on_toggle = function() P.open[gkey] = not opened end,
          -- the check box: every parameter of the branch in or out
          on_check = function() params_apply(fx.tr, targets_of(fx, nd.ps), g_have < #nd.ps) end })
        if opened then
          local y1 = lastbot
          draw_nodes(fx, nd.children, depth + 1, rack_col)
          guide(cxof(depth) - aw / 2 - 4, y1, lastbot - 5)
        end
      end
      draw_nodes = function(fx, nodes, depth, rack_col)
        for _, nd in ipairs(nodes) do
          if nd.p then
            if matches(fx, nd.p) then draw_leaf(fx, nd.p, nd.label, depth, rack_col) end
          else
            draw_group(fx, nd, depth, rack_col)
          end
        end
      end

      for _, rk in ipairs(racks) do
        local rkey = 'R:' .. rk.guid
        local ropen = P.open[rkey] == true
        draw_row({ id = rkey, h = h_rack, font = head_font, size = HEAD_FONT_SIZE, arrow = true, open = ropen,
          name = rk.name, col = param_name_color(track_color(rk.tr), dark),
          on_toggle = function()
            P.open[rkey] = not ropen
            if ropen then param_pick_forget(P, rk.tr) end
          end })
        if ropen then
          local rk_y1 = lastbot
          local rack_col = track_color(rk.tr)
          if #rk.fxs == 0 then ig.Indent(ctx, cxof(0) - L); ig.TextDisabled(ctx, 'This rack has no FX yet.'); ig.Unindent(ctx, cxof(0) - L) end
          for _, fx in ipairs(rk.fxs) do
            local pname, ptype = fx_name_type(fx.name)
            local pkey = 'P:' .. fx.guid
            local fkey = 'F:' .. fx.guid
            if P.reveal and P.reveal.guid == fx.guid then P.open[fkey] = true end
            local n_have = 0
            for p = 0, #fx.names - 1 do if not fx.hide[p] and have[fx.guid .. ':' .. p] then n_have = n_have + 1 end end
            local opened = low ~= '' or P.open[fkey] == true
            local fcol = fx_color(fx.tr, fx.guid, rack_col)           -- the FX's color: its own, or the rack's
            draw_row({ id = pkey, sel = pkey, depth = 0, h = h_grp, font = sect_font, size = SECT_FONT_SIZE,
              col = param_name_color(fcol, dark),
              menu = function() if ig.MenuItem(ctx, 'Color...') then fx_open_picker(fx.tr, fx.guid, fx.name) end end,
              arrow = true, open = opened, check = true, on = n_have == fx.nvis and n_have > 0, part = n_have > 0,
              name = pname, type = ptype, count = ('%d of %d in the Performance'):format(n_have, fx.nvis),
              on_toggle = function() P.open[fkey] = not opened end,
              -- the check box: every parameter of the FX in or out
              on_check = function()
                local all = {}
                for p = 0, #fx.names - 1 do if not fx.hide[p] then all[#all + 1] = p end end
                params_apply(fx.tr, targets_of(fx, all), n_have < fx.nvis)
              end })
            if opened then
              local y1 = lastbot
              draw_nodes(fx, fx.items or {}, 1, fcol)
              guide(cxof(0) - aw / 2 - 4, y1, lastbot - 5)
            end
          end
          guide(L + aw / 2, rk_y1, lastbot - 5)
        end
      end
      P.reveal, P.scroll_key = nil, nil
      ig.EndChild(ctx)
    end
    P.order = order

    local any = next(P.sel) ~= nil
    if not any and ig.BeginDisabled then ig.BeginDisabled(ctx, true) end
    if ig.Button(ctx, 'Add to Performance') then param_pick_apply(P, fxs, true) end
    ig.SameLine(ctx)
    if ig.Button(ctx, 'Remove from Performance') then param_pick_apply(P, fxs, false) end
    if not any and ig.EndDisabled then ig.EndDisabled(ctx) end
    ig.SameLine(ctx)
    ig.TextDisabled(ctx, ('%d selected'):format((function() local c = 0 for _ in pairs(P.sel) do c = c + 1 end return c end)()))
    ig.End(ctx)
  end
  if not open then P.tree_open = false end
end

-- the inspector: the settings of what is selected (its own window)
function draw_param_inspector(P, D)
  local vis, open = begin_window('paraminsp', 'Parameters inspector###paraminsp', 320, 560, true)
  if vis then
    draw_param_control_panel(P, D.fxs, D.gm, D.targets)
    ig.End(ctx)
  end
  if not open then P.insp_open = false end
end

function draw_param_picker()
  local P = PARAM_PICK
  if not P then return end
  if not (P.tree_open or P.insp_open) then P.hl, P.focus = nil, nil; return end
  if not valid(P.tr) or is_locked() then
    P.tree_open, P.insp_open, P.hl, P.focus = false, false, nil, nil     -- (Show mode closes them)
    return
  end
  local D = param_pick_data(P)
  if P.tree_open then draw_param_tree(P, D) end
  if P.insp_open then draw_param_inspector(P, D) end
end
