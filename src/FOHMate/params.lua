-- FOHMate/params.lua: Performance mode parameter rows.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- parameter rows
--
-- The rows of a rack's column are saved on the rack (its track), so a duplicated rack takes them
-- along. Each row is one parameter of one FX of that rack: the FX's GUID and the parameter's
-- index, plus the name the FX reported when the row was made (to notice a changed FX)
-- and a name of the user's own (nil = the reported one). A row whose FX or parameter is gone is
-- kept and drawn greyed out, never silently dropped.

PARAM_CACHE = {}   -- per rack: the saved text and the rows parsed from it
PARAM_PICK  = nil  -- the parameter window (Edit mode): { tr, filter, sel, anchor, order, fx }
PARAM_KIND  = {}   -- what kind of control a parameter gets, found once per parameter
ROW_MEMO    = {}   -- per row (FX guid:index:name): what the FX last said, so it isn't asked every frame

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
    local g, i, pn, nm, df, iv, cl, lo, hi, ft, vl, lm, vs, cu, rg, nt, vo, sk, sn, so =
      rec:match('^([^|]*)|(%d+)|([^|]*)|([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)$')
    if g then
      local r = { guid = g, idx = tonumber(i), pname = param_unesc(pn),
                  name = nm ~= '' and param_unesc(nm) or nil, def = tonumber(df), inv = (iv == '1'),
                  col = tonumber(cl, 16), lo = tonumber(lo), hi = tonumber(hi), fit = (ft == '1'),
                  vraw = vl, vshow = (vs == 's' and 'steps') or (vs == 'd' and 'list') or nil,
                  curve = cu ~= '' and param_unesc(cu) or nil,    -- the value curve (curves.lua), nil = linear
                  rraw = rg, rinv = (nt == 'i') }       -- rinv: the gaps between the ranges are the ranges
      if r.curve and not curve_parse(r.curve) then r.curve = nil end
      -- a Range: lo above hi is an inverted range (from 0 to hi, and from lo to 1)
      if not (r.lo and r.hi and r.lo ~= r.hi) then r.lo, r.hi = nil, nil end
      if rg and rg ~= '' then                              -- a list of ranges: "lo:hi,lo:hi"
        r.rngs = {}
        for sa, sb in rg:gmatch('([%d%.]+):([%d%.]+)') do
          local a, b = tonumber(sa), tonumber(sb)
          if a and b and a < b then r.rngs[#r.rngs + 1] = { a, b } end
        end
        if #r.rngs == 0 then r.rngs = nil end
      end
      if vl ~= '' then
        r.vals = {}
        for x in vl:gmatch('[^,]+') do r.vals[#r.vals + 1] = tonumber(x) end
      end
      -- the limit in use: 'mm' (Min / Max) or 'list'; a row saved before the list existed has Min / Max
      -- when it has a Min
      if lm == 'l' then r.lim = 'list' elseif lm == 'r' then r.lim = 'ranges'
      elseif lm == 'm' or (lm == '' and r.lo) then r.lim = 'mm' end
      if r.lim == 'mm' and not r.lo then r.lim = nil end
      if r.lim == 'ranges' and not r.rngs then r.lim = nil end
      -- Limit only values (a Range), Skip the gaps (several parts). A row saved before Skip the gaps
      -- existed keeps what it did: a List of ranges without the full range turned through the gaps
      -- (kept as noskip: a field set to false is cleared by params_update)
      r.vonly = (vo == 'v')
      r.noskip = (sk == 'n') or (sk == '' and r.lim == 'ranges' and not r.fit)
      r.snapnear = (sn == 'e')                      -- Snap to nearest limit (off: the value waits)
      r.snapout = (so == 'o')                       -- brought back inside the limits when moved from outside
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
    local vl, rl = {}, {}
    for j, v in ipairs(r.vals or {}) do vl[j] = ('%.6f'):format(v) end
    for j, v in ipairs(r.rngs or {}) do rl[j] = ('%.6f:%.6f'):format(v[1], v[2]) end
    t[#t + 1] = ('%s|%d|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s'):format(r.guid, r.idx, param_esc(r.pname or ''), param_esc(r.name or ''),
                                                r.def and ('%.6f'):format(r.def) or '', r.inv and '1' or '',
                                                r.col and ('%06X'):format(r.col) or '',
                                                lim and ('%.6f'):format(r.lo) or '', lim and ('%.6f'):format(r.hi) or '',
                                                r.fit and '1' or '', table.concat(vl, ','),
                                                (r.lim == 'mm' and 'm') or (r.lim == 'list' and 'l') or (r.lim == 'ranges' and 'r') or 'o',
                                                (r.vshow == 'steps' and 's') or (r.vshow == 'list' and 'd') or '',
                                                param_esc(r.curve or ''), table.concat(rl, ','), r.rinv and 'i' or '',
                                                r.vonly and 'v' or '', r.noskip and 'n' or 's', r.snapnear and 'e' or '', r.snapout and 'o' or '')
  end
  reaper.GetSetMediaTrackInfo_String(tr, EXT_PARAMS, table.concat(t, ';'), true)
  PARAM_CACHE[reaper.GetTrackGUID(tr)] = nil
end

-- FX guid -> index, for the FX of a rack
-- changes fields of one row (inv, def...): changes = { inv = true, def = 0.5 }; a field set to false is cleared
function params_update(tr, guid, idx, changes)
  undo_mark('Rack: edit parameter settings')
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

-- A new FX on the rack (added, dropped from another rack, Replace FX) takes back the rows left by a
-- removed FX with "keep the rows": each parameter must have the same name and index in the new FX.
-- Only one removed FX is matched to each new one (the first in the column), and only when the new FX
-- has no rows yet. Inside the caller's undo block.
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

-- what the FX last said about a row (ROW_MEMO): whether its parameter is gone (missing) is
-- checked again every 30 frames (half a second) or when its FX moved (fxi = where its FX is now)
function param_row_memo(tr, r, fxi)
  local mk = r.guid .. ':' .. r.idx .. ':' .. (r.pname or '')
  local mm = ROW_MEMO[mk]
  if not mm then mm = {}; ROW_MEMO[mk] = mm end
  if fxi ~= mm.fxi or FRAME - (mm.f_name or -99) >= 30 then
    if fxi and r.idx < reaper.TrackFX_GetNumParams(tr, fxi) then
      local _, pn = reaper.TrackFX_GetParamName(tr, fxi, r.idx, '')
      mm.missing = (pn ~= r.pname)                      -- a changed FX: not the parameter it was
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
  with_undo('Reorder quick access parameters', function() params_write(tr, rows) end)
end

-- the rows whose parameter is gone (its FX removed, or the FX changed), as { guid, idx, name }
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

-- (How limits and a curve turn a control, param_map and the rest, is in limit_map.lua; a quick access
-- row is the table of limit settings it is given.)

-- A stepped encoder: its Range or List of ranges moved onto its steps, so the arc starts and ends on a
-- step mark. Looked at once per row as it is read (r.onsteps_). A range that shrinks to a single step
-- gets one step wider; ranges with no step left between them become one.
function param_limits_to_steps(tr, r, n)
  if not (n and n > 1) or r.onsteps_ == n or not r.guid then return end
  r.onsteps_ = n
  local d = 1 / (n - 1)
  local function apart(a, b, inv)
    if a ~= b then return a, b end
    if inv then                                        -- Max below Min: Min goes up a step (or Max down)
      if a + d <= 1 + 1e-9 then return a + d, b end
      return a, b - d
    end
    if b + d <= 1 + 1e-9 then return a, b + d end
    return a - d, b
  end
  local function moved(x, y) return math.abs(x - y) > 1e-5 end
  local ch
  if r.lim == 'mm' and r.lo and r.hi then
    local lo, hi = apart(param_on_step(r.lo, n), param_on_step(r.hi, n), r.lo > r.hi)
    if moved(lo, r.lo) or moved(hi, r.hi) then ch = { lo = lo, hi = hi } end
  elseif r.lim == 'ranges' and r.rngs then
    local old, srt = {}, {}
    for i, v in ipairs(r.rngs) do
      old[i] = v
      local a, b = apart(param_on_step(v[1], n), param_on_step(v[2], n))
      srt[i] = { a, b }
    end
    table.sort(old, function(a, b) return a[1] < b[1] end)
    table.sort(srt, function(a, b) return a[1] < b[1] end)
    local out = {}
    for _, v in ipairs(srt) do
      local last = out[#out]
      if last and v[1] < last[2] + 2 * d - 1e-9 then last[2] = math.max(last[2], v[2])
      else out[#out + 1] = { v[1], v[2] } end
    end
    local same = #out == #old
    for i = 1, same and #out or 0 do
      if moved(out[i][1], old[i][1]) or moved(out[i][2], old[i][2]) then same = false end
    end
    if not same then ch = { rngs = out } end
  end
  if ch then params_update(tr, r.guid, r.idx, ch) end
end

-- "Bring it back inside the limits when moved from outside" (r.snapout) is on: a small lock by the name
-- (draw_lock, widgets.lua) and, in the quick access panel, a red glow around the row
PARAM_SNAPOUT_TIP = 'Brought back inside its limits when moved from outside FOH-Mate\n(Inspector > Limit values, or right-click the row).'
PARAM_SNAPOUT_COL = 0xE5484DFF
function param_snapout_on(r) return r and r.snapout and r.lim ~= nil end

-- Changes from outside FOH-Mate (the FX's own window, MIDI learn, another script): a parameter of the
-- quick access panel set to (r.snapout, off by default) with a Range, a List of ranges or a List of values that stays outside them for half a
-- second is put on the nearest allowed value. Every rack, shown or not, ten times a second; only the rows with those limits
-- are read. Not when the parameter has an automation envelope (it would fight the envelope, or be
-- written into it). Once per value: an FX that keeps it outside (it rounds the value) is left alone.
PARAM_EXT, PARAM_EXT_T = {}, 0   -- guid:idx -> { v = the value last seen, t = when it last moved, done }
function param_ext_snap(now)
  if now - PARAM_EXT_T < 0.1 then return end
  PARAM_EXT_T = now
  for _, tr in ipairs(racks or {}) do
    if valid(tr) then
      local gm
      for _, r in ipairs(params_read(tr)) do
        if r.snapout and (r.lim == 'mm' or r.lim == 'ranges' or (r.lim == 'list' and r.vals and #r.vals > 0)) then
          gm = gm or fx_guid_map(tr)
          local fxi = gm[r.guid]
          if fxi and r.idx < reaper.TrackFX_GetNumParams(tr, fxi) then
            local kind = param_kind(tr, fxi, r).kind
            local segs
            if r.lim == 'list' then                    -- a list of values: each one a part of its own
              if param_list_ok(kind) then
                if not r.lsegs_ then
                  r.lsegs_ = {}
                  for i, x in ipairs(r.vals) do r.lsegs_[i] = { x, x } end
                end
                segs = r.lsegs_
              end
            else
              segs = param_segs(r, kind)
            end
            if segs then
              local v = reaper.TrackFX_GetParamNormalized(tr, fxi, r.idx)
              local key = r.guid .. ':' .. r.idx
              local s = PARAM_EXT[key]
              if not s then s = { v = v, t = now }; PARAM_EXT[key] = s end
              if math.abs(v - s.v) > 1e-7 then
                s.v, s.t, s.done = v, now, nil
              elseif not s.done and now - s.t >= 0.5 then
                s.done = true
                local near = param_seg_near(segs, v)
                if math.abs(near - v) > 1e-4 and not reaper.GetFXEnvelope(tr, fxi, r.idx, false) then
                  reaper.TrackFX_SetParamNormalized(tr, fxi, r.idx, near)
                end
              end
            end
          end
        end
      end
    end
  end
end

-- The list of ranges keeps them apart: the smallest gap between two ranges (Settings, a % of the travel)
function param_range_gap() return (CFG.range_gap or 2) / 100 end

-- the room range i of a list may take: up to its neighbours (by value), the gap away from them
function param_range_room(rngs, i, gap)
  local a, b = rngs[i][1], rngs[i][2]
  local lo, hi = 0, 1
  for j, o in ipairs(rngs) do
    if j ~= i then
      if o[2] <= a + 1e-9 then lo = math.max(lo, o[2] + gap)
      elseif o[1] >= b - 1e-9 then hi = math.min(hi, o[1] - gap) end
    end
  end
  return lo, hi
end

-- Where range i (w wide) goes when it is moved as a whole to lo: the nearest place it fits, on either
-- side of the other ranges (the gap away from them): it can be moved past another one.
function param_range_place(rngs, i, gap, lo, w)
  local others = {}
  for j, o in ipairs(rngs) do if j ~= i then others[#others + 1] = o end end
  table.sort(others, function(a, b) return a[1] < b[1] end)
  local best, bd
  local function try(f0, f1)                     -- a free stretch: the nearest start in it that fits
    if f1 - f0 < w - 1e-9 then return end
    local a = math.max(f0, math.min(f1 - w, lo))
    local d = math.abs(a - lo)
    if not bd or d < bd then best, bd = a, d end
  end
  local x = 0
  for _, o in ipairs(others) do
    try(x, o[1] - gap)
    x = o[2] + gap
  end
  try(x, 1)
  return best
end

-- Where a new range goes: a small one (5% of the travel at most) as close to v as can be, outside the
-- other ranges and the gap away from them; nil when there is no room left.
function param_range_new(rngs, gap, v)
  local srt = {}
  for i, o in ipairs(rngs) do srt[i] = o end
  table.sort(srt, function(a, b) return a[1] < b[1] end)
  local free, x = {}, 0
  for i, o in ipairs(srt) do
    local f1 = o[1] - gap
    if f1 - x >= 0.005 then free[#free + 1] = { x, f1 } end
    x = o[2] + gap
    if i == #srt and 1 - x >= 0.005 then free[#free + 1] = { x, 1 } end
  end
  if #srt == 0 then free[1] = { 0, 1 } end
  local best, bd
  for _, f in ipairs(free) do
    local d = (v < f[1] and f[1] - v) or (v > f[2] and v - f[2]) or 0
    if not bd or d < bd then best, bd = f, d end
  end
  if not best then return nil end
  local w = math.min(0.05, best[2] - best[1])
  local a = math.max(best[1], math.min(best[2] - w, v - w / 2))
  return { a, a + w }
end

-- Ctrl + wheel over a control: the current range (the one value v is in, or the nearest) moves up / down
-- with wv (it stops when an end reaches v, or the gap before another range, or the ends of the travel)
-- or gets wider / narrower with wh (v stays inside). A Range (not inverted) or a List of ranges.
function param_wheel_range_ok(r, kind)
  if not param_limit_ok(kind) then return false end
  return (r.lim == 'mm' and r.lo and r.hi and r.lo < r.hi) or (r.lim == 'ranges' and r.rngs and #r.rngs > 0 and not r.rinv)
end

function param_wheel_range(tr, fxi, r, kind, wv, wh, v)
  local lo, hi, L, R, i
  if r.lim == 'mm' then
    lo, hi, L, R = r.lo, r.hi, 0, 1
  else
    local bd = math.huge
    for j, o in ipairs(r.rngs) do
      local d = (v < o[1] and o[1] - v) or (v > o[2] and v - o[2]) or 0
      if d < bd then i, bd = j, d end
    end
    lo, hi = r.rngs[i][1], r.rngs[i][2]
    L, R = param_range_room(r.rngs, i, param_range_gap())
  end
  local inside = v >= lo and v <= hi                 -- (the value may be outside the nearest range)
  local step = mod_down('shift') and WHEEL_FINE or WHEEL_STEP
  if wv ~= 0 then
    local d = wv * step
    d = math.max(d, L - lo)
    d = math.min(d, R - hi)
    if inside then d = math.max(math.min(d, v - lo), v - hi) end
    lo, hi = lo + d, hi + d
  end
  if wh ~= 0 then
    local d = wh * step / 2
    local nlo, nhi = math.max(L, lo - d), math.min(R, hi + d)
    if inside then nlo, nhi = math.min(nlo, v), math.max(nhi, v) end
    if nhi - nlo >= 0.002 then lo, hi = nlo, nhi end
  end
  if r.lim == 'mm' then
    if lo ~= r.lo or hi ~= r.hi then params_update(tr, r.guid, r.idx, { lo = lo, hi = hi }) end
  elseif lo ~= r.rngs[i][1] or hi ~= r.rngs[i][2] then
    local nr = {}
    for j, o in ipairs(r.rngs) do nr[j] = { o[1], o[2] } end
    nr[i] = { lo, hi }
    params_update(tr, r.guid, r.idx, { rngs = nr })
  end
end

-- moves the parameter into what row r allows now (after its limits changed): the nearest allowed value
function param_limits_snap(tr, fxi, idx, r, kind)
  local segs = param_segs(r, kind)
  if not segs then return end
  local cur = reaper.TrackFX_GetParamNormalized(tr, fxi, idx)
  local best, bd = cur, math.huge
  for _, sg in ipairs(segs) do
    local x = math.max(sg[1], math.min(sg[2], cur))
    local d = math.abs(x - cur)
    if d < bd then best, bd = x, d end
  end
  if bd > 1e-6 then reaper.TrackFX_SetParamNormalized(tr, fxi, idx, best) end
end

-- the move up / move down / remove buttons on the right of a line of a list (i of n), as in the list of
-- values: no up arrow on the first, no down arrow on the last, a red x. Returns 'up', 'dn', 'x' or nil.
-- (xonly: only the remove button, for a list kept in its own order)
function draw_list_buttons(i, n, bw, what, xonly)
  local act
  if not xonly then
    if i == 1 then ig.Dummy(ctx, bw, bw)
    elseif ig.ArrowButton(ctx, 'up', ig.Dir_Up()) then act = 'up' end
    ig.SameLine(ctx)
    if i == n then ig.Dummy(ctx, bw, bw)
    elseif ig.ArrowButton(ctx, 'dn', ig.Dir_Down()) then act = 'dn' end
    ig.SameLine(ctx)
  end
  ig.PushStyleColor(ctx, ig.Col_Button(), 0xB03030FF)
  ig.PushStyleColor(ctx, ig.Col_ButtonHovered(), 0xD04040FF)
  ig.PushStyleColor(ctx, ig.Col_ButtonActive(), 0x902020FF)
  ig.PushStyleColor(ctx, ig.Col_Text(), 0xFFFFFFFF)
  if ig.Button(ctx, 'x', bw, bw) then act = 'x' end
  ig.PopStyleColor(ctx, 4)
  if ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, 'Remove this ' .. what .. ' from the list') end
  return act
end

-- Limit values, list (r.lim == 'list'): the parameter only takes the values of r.vals (0..1 each, in
-- the user's order, any order). The control becomes a stepped encoder with a step per value, or a
-- drop-down of them (param_list_show). Any kind of control but a toggle.
function param_list_ok(kind) return kind ~= nil and kind ~= 'toggle' end

-- What the FX prints for a position (ok, text). Some print their unit twice ("1000 Hz Hz"):
-- a last word that repeats the one before it is dropped.
function param_fmt(tr, fxi, idx, v)
  local ok, t = reaper.TrackFX_FormatParamValueNormalized(tr, fxi, idx, v, '')
  local head, w1, w2 = t:match('^(.-)(%S+)%s+(%S+)%s*$')
  if w1 and not w1:find('%d') and w1:lower() == w2:lower() then t = head .. w1 end
  -- a "%" left after a unit by some FX ("12.0dB/oct %"): dropped ("50 %" stays)
  local h2 = t:match('^(.-%d.-%a)%s+%%%s*$')
  if h2 then t = h2 end
  return ok, t
end

-- the FX's own text for a position, when it can give it (otherwise a percentage)
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

-- The position that prints as a number (with this unit): the FX is asked at 401 positions for the
-- nearest, then between its neighbours by halving (16 times, for a text that rises or falls there).
-- Nothing when no position prints that unit.
function param_find_value(tr, fxi, idx, num, unit)
  local ok = param_fmt(tr, fxi, idx, 0)
  if not ok then return math.max(0, math.min(1, num / 100)) end        -- no text from the FX: a percentage
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

-- what a list shows as: the user's choice (Show as), or else a drop-down for an FX's named values
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

-- the value as the vertical box can write it: what the FX says when the little stroke font
-- has every character of it, otherwise the position as a percentage. The text is tidied first
-- (µ and ° and other unusual characters dropped, a bare number of a frequency gets "Hz", spaces
-- squeezed out when it is too long). A text that still can't be written is noted once in
-- Data/FOHMate/param_text_rejects.txt (FX, parameter, text), so the rules can be improved.
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

-- what such a parameter is right now: 'pan', 'band' (a width), or 'off' (the FX ignores it)
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
-- (Settings), it is also kept in Data/FOHMate/param_nicknames.txt (FX, parameter, nickname) and
-- given to that parameter whenever it is added to the Performance again, on any rack or project.
PARAM_NICK      = nil
PARAM_NICK_FILE = LATDB_DIR .. '/param_nicknames.txt'

function param_nick_load()
  PARAM_NICK = {}
  for _, ln in ipairs(read_lines(PARAM_NICK_FILE)) do
    local fx_key, pn, nick = ln:match('^([^\t]*)\t([^\t]*)\t(.+)$')
    if fx_key then PARAM_NICK[fx_key .. '\t' .. pn] = nick end
  end
end

function param_nick_get(fx_key, pname)
  if CFG.remember_nicks == 0 then return nil end
  if not PARAM_NICK then param_nick_load() end
  return PARAM_NICK[fx_key .. '\t' .. (pname or '')]
end

function param_nick_set(fx_key, pname, nick)
  if not PARAM_NICK then param_nick_load() end
  PARAM_NICK[fx_key .. '\t' .. (pname or '')] = nick
  local t = {}
  for k, v in pairs(PARAM_NICK) do t[#t + 1] = k .. '\t' .. v end
  table.sort(t)
  write_lines(PARAM_NICK_FILE, t)
end

-- asks for a row's nickname (outside of the ImGui frame); empty = the FX's own name again
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

-- the FX's name without its type, the way the corrections are filed
function param_fx_name_key(fxname)
  return (fx_name_type(fxname))
end

-- the key of an FX of a rack
function param_fx_key(tr, fxi)
  local _, name = reaper.TrackFX_GetFXName(tr, fxi, '')
  return param_fx_name_key(name or '')
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
    local lt = txt:lower()                                 -- (a slope in dB/oct is not a level)
    if lt:find('db', 1, true) and not lt:find('db/', 1, true) then is_db = true end
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
  -- 128 values are read: past 32, they are only kept when they are mostly words (a band's types, many
  -- of them "Reserved", a few starting with a number like "1st Order"), which makes a drop-down. A long
  -- list of numbers stops being read after its first numbers.
  local ok, step, _, _, istoggle = reaper.TrackFX_GetParameterStepSizes(tr, fxi, r.idx)
  local _, mn, mx = reaper.TrackFX_GetParamEx(tr, fxi, r.idx)
  local n
  if ok and step and step > 0 and mn and mx and mx > mn then
    local cnt = (mx - mn) / step
    if cnt <= 127.5 then n = math.floor(cnt + 0.5) + 1 end
  end
  local items, numeric, all
  if n and n >= 2 then
    items = {}
    local nw, nn, whole = 0, 0, true                       -- words, numbers (placeholders aside)
    for i = 0, n - 1 do
      local v = i / (n - 1)
      local _, txt = param_fmt(tr, fxi, r.idx, v, '')
      if txt == '' then txt = ('%d%%'):format(math.floor(v * 100 + 0.5)) end
      items[#items + 1] = { label = txt, norm = v }
      if not param_hidden_value(txt) then
        if tonumber((txt:match('^%s*([%-%+]?[%d%.]+)'))) then nn = nn + 1 else nw = nw + 1 end
      end
      if n > 32 and nw == 0 and nn >= 8 then whole = false; break end
    end
    numeric = nw == 0
    if whole then all = items end                          -- every value, for a drop-down chosen by hand
    if n > 32 and not (whole and nw >= 0.8 * (nw + nn)) then n, items, numeric = nil, nil, nil end
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
         or low:find('knee', 1, true) or low:find('%f[%a]bw%f[%A]') then
    guess = 'band'      -- (BW on its own, as in "BW", "Band 2 BW" or "BW1": bandwidth)
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
    if (kind == 'steps' or kind == 'list') and not items and all then
      n, items = #all, all                                 -- the FX's own values, even many of them
    elseif (kind == 'steps' or kind == 'list') and not items then
      -- the FX doesn't say what its values are: take 11 positions along it
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
  local fx_key = param_fx_key(tr, fxi)
  local key = fx_key .. '\t' .. (r.pname or '')
  if kind then
    local guess = param_kind(tr, fxi, r).guess
    local f = param_facts(tr, fxi, r.idx)
    PARAM_OVR[key] = { kind = kind, line = table.concat({
      fx_key, r.pname or '', kind, guess, tostring(f.min), tostring(f.max), tostring(f.step),
      tostring(f.toggle), f.t0 or '', f.t1 or '' }, '\t') }
  else
    PARAM_OVR[key] = nil
  end
  PARAM_KIND[r.guid .. ':' .. r.idx .. ':' .. (r.pname or '')] = nil
  param_ovr_save()
end

---------------------------------------------------------------- copy / paste of limits and curves
--
-- Right-click a parameter (a rack's row in Edit mode, or the tree): copy its limits (Range, List of values,
-- List of ranges, or none), its curve, or both, and paste them on other parameters. The values are kept as
-- positions along the control (0..1), like everything else in a row. Pasting puts the parameter in the
-- Performance if it isn't, and changes its control when the current one can't have what is pasted (a
-- toggle can't have a range, a drop-down can't have a curve...): it gets the control of the one copied.
PARAM_CLIP = nil   -- { lims = {...} or nil, curve = text or false or nil, kind, from }

PARAM_CLIP_FIELDS = { 'lim', 'lo', 'hi', 'fit', 'vals', 'vshow', 'rngs', 'rinv', 'vonly', 'noskip', 'snapnear', 'snapout' }

function param_clip_copy(tr, fxi, r, what)
  local row = params_find(tr, r.guid, r.idx) or {}
  local c = { kind = param_kind(tr, fxi, r).kind, from = row.name or r.pname }
  if what ~= 'curve' then
    c.lims = {}
    for _, f in ipairs(PARAM_CLIP_FIELDS) do
      local v = row[f]
      if type(v) == 'table' then                             -- a copy, not the row's own list
        local t = {}
        for i, x in ipairs(v) do t[i] = type(x) == 'table' and { x[1], x[2] } or x end
        v = t
      end
      c.lims[f] = v
    end
  end
  if what ~= 'lims' then c.curve = row.curve or false end   -- false: linear (pasting it takes the curve off)
  PARAM_CLIP = c
end

-- pastes what = 'lims', 'curve' or 'both' of the clipboard on targets ({ tr, guid, idx, name }); gm: FX guid -> index
function param_clip_paste(targets, gm, what)
  local c = PARAM_CLIP
  if not c then return end
  with_undo('Paste parameter limits / curve', function()
    for _, t in ipairs(targets) do
      local tr, fxi = t.tr, gm[t.guid]
      if tr and fxi then
        if not params_find(tr, t.guid, t.idx) then params_apply(tr, { { guid = t.guid, idx = t.idx, name = t.name } }, true) end
        local r = { guid = t.guid, idx = t.idx, pname = t.name }
        local ch = {}
        local lims = what ~= 'curve' and c.lims
        local curve = what ~= 'lims' and c.curve
        if lims then
          for _, f in ipairs(PARAM_CLIP_FIELDS) do
            local v = lims[f]
            if type(v) == 'table' then
              local n = {}
              for i, x in ipairs(v) do n[i] = type(x) == 'table' and { x[1], x[2] } or x end
              v = n
            end
            ch[f] = (v == nil) and false or v
          end
        end
        if what ~= 'lims' and c.curve ~= nil then ch.curve = c.curve end
        -- the control: changed only when the one it has can't take what is pasted
        local k = param_kind(tr, fxi, r).kind
        local lim = lims and lims.lim
        local bad = (lim == 'list' and not param_list_ok(k))
                    or ((lim == 'mm' or lim == 'ranges') and not param_limit_ok(k))
                    or (curve and lim ~= 'list' and not param_curve_ok(k))
        if bad then
          local nk = c.kind
          if curve and not param_curve_ok(nk) then nk = 'knob' end
          if nk ~= k then param_set_override(tr, fxi, r, nk) end
        end
        params_update(tr, t.guid, t.idx, ch)
        local fresh = params_find(tr, t.guid, t.idx)
        if fresh then param_limits_snap(tr, fxi, t.idx, fresh, param_kind(tr, fxi, r).kind) end
      end
    end
  end)
end

-- the menu items: copy from parameter r (tr, fxi), paste on targets (the parameter itself, or the selection)
function param_clip_menu(tr, fxi, r, targets, gm)
  if ig.BeginMenu(ctx, 'Copy') then
    if ig.MenuItem(ctx, 'Limits') then param_clip_copy(tr, fxi, r, 'lims') end
    if ig.MenuItem(ctx, 'Curve') then param_clip_copy(tr, fxi, r, 'curve') end
    if ig.MenuItem(ctx, 'Limits and curve') then param_clip_copy(tr, fxi, r, 'both') end
    ig.EndMenu(ctx)
  end
  local c = PARAM_CLIP
  local n = #targets
  local label = n > 1 and ('Paste on the %d selected'):format(n) or 'Paste'
  if ig.BeginMenu(ctx, label, c ~= nil) then
    ig.TextDisabled(ctx, 'Copied from: ' .. (c.from or '?'))
    if c.lims and ig.MenuItem(ctx, 'Limits') then param_clip_paste(targets, gm, 'lims') end
    if c.curve ~= nil and ig.MenuItem(ctx, 'Curve') then param_clip_paste(targets, gm, 'curve') end
    if c.lims and c.curve ~= nil and ig.MenuItem(ctx, 'Limits and curve') then param_clip_paste(targets, gm, 'both') end
    ig.EndMenu(ctx)
  end
end

---------------------------------------------------------------- the parameter window (Edit mode)
--
-- A tree of the rack: the rack, its FX, and under each FX every parameter. Click selects, Cmd/Ctrl-click
-- adds to the selection, Shift-click selects a stretch. "Add to Performance" and "Remove from
-- Performance" work on the selection; selecting an FX means all of its parameters.

-- Parameters that are not meant for the user are left out of the window: placeholders ("Reserved",
-- "Unused", "-", nameless, "Param 12"), and the MIDI CC entries many VST3 FX add by the hundred
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

-- a parameter whose every value is a placeholder ("Reserved" at the start, middle and end: a choice the FX
-- doesn't use, like Kirchhoff-EQ's Speakers Type in stereo) is hidden too. Read when the FX's list is made.
function param_dead_values(tr, fxi, idx)
  for _, v in ipairs({ 0, 0.5, 1 }) do
    local _, t = param_fmt(tr, fxi, idx, v)
    if t == '' or not param_hidden_value(t) then return false end
  end
  return true
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

-- parameters hidden by hand ("Hide this parameter", right-click in the window), per FX, for every
-- project: Data/FOHMate/param_hidden.txt (FX, parameter)
PARAM_UHIDE = nil
PARAM_UHIDE_FILE = LATDB_DIR .. '/param_hidden.txt'
function param_uhidden(fx_key, pname)
  if not PARAM_UHIDE then
    PARAM_UHIDE = {}
    for _, ln in ipairs(read_lines(PARAM_UHIDE_FILE)) do
      if ln:find('\t', 1, true) then PARAM_UHIDE[ln] = true end
    end
  end
  return PARAM_UHIDE[fx_key .. '\t' .. pname] == true
end

function param_set_uhidden(fx_key, pname, on)
  param_uhidden(fx_key, pname)
  PARAM_UHIDE[fx_key .. '\t' .. pname] = on or nil
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
  param_win_save()
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
  param_win_save()
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

-- Right-click a rack's name: the rack is selected in the tree (when a parameter window is open) and the
-- tree scrolls to it; with unfold (Shift), it opens, with every FX and group in it.
function param_pick_rack(tr, unfold)
  local P = PARAM_PICK
  if not P or not (P.tree_open or P.insp_open) then return end
  P.no_focus = true
  local key = 'R:' .. reaper.GetTrackGUID(tr)
  P.sel, P.anchor, P.scroll_key, P.filter = { [key] = true }, key, key, ''
  P.open = P.open or {}
  if unfold then
    P.open[key] = true
    P.unfold = {}
    for i = 0, reaper.TrackFX_GetCount(tr) - 1 do
      local g = reaper.TrackFX_GetFXGUID(tr, i)
      P.open['F:' .. g], P.unfold[g] = true, true            -- its groups open when they are drawn
    end
  end
end

-- FX right-click > Inspect FX...: the FX is selected (every parameter of it) and opened in the tree, and the
-- Inspector opens
function param_pick_fx(tr, guid)
  param_picker_open(tr, 'P:' .. guid)                      -- both windows: the tree is what you work with there
  local P = PARAM_PICK
  P.open['F:' .. guid], P.scroll_key, P.filter = true, 'P:' .. guid, ''
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
        -- the value it has now is remembered as its default (REAPER doesn't say what the FX's own is)
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
  with_undo(adding and 'Add parameters to the quick access panel' or 'Remove parameters from the quick access panel',
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

-- the FX's name without its type ("VST3: Foo (Dev)" -> "Foo (Dev)") and the type
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
  local title = #targets == 1 and first.name or ('%d parameters selected'):format(#targets)
  if param_snapout_on(row) then                    -- brought back inside its limits: a lock before the title
    local x, y = ig.GetCursorScreenPos(ctx)
    local lh = ig.GetTextLineHeight(ctx)
    ig.Dummy(ctx, lh * 0.8, lh)
    draw_lock(ig.GetWindowDrawList(ctx), x + lh * 0.4, y + lh / 2, lh * 0.75, PARAM_SNAPOUT_COL)
    if ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, PARAM_SNAPOUT_TIP) end
    ig.SameLine(ctx)
  end
  ig.TextWrapped(ctx, title)
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
                                        or 'Nickname: add it to the quick access panel first', P.nick)
    if rv then P.nick = nv end
    P.nick_edit = ig.IsItemActive(ctx)
    if row and ig.IsItemDeactivatedAfterEdit(ctx) then param_set_nick(tr, row, P.nick) end
    if not row then ig.EndDisabled(ctx) end
    ig.TextDisabled(ctx, (fx_name_type(fxname)))
  else
    ig.TextDisabled(ctx, 'The choice applies to all of them.')
  end
  if not fxi then return end
  ig.Separator(ctx)
  -- the rest scrolls under the title, which stays at the top
  local function body()
    local r1 = { guid = first.guid, idx = first.idx, pname = first.name }
    local k = param_kind(tr, fxi, r1)
    ig.Spacing(ctx)
    if section_header('Control', false) then
      for _, o in ipairs(PARAM_CONTROL_OPTS) do
        local on = #targets == 1 and ((o[1] == nil and not k.overridden) or (o[1] ~= nil and k.overridden and k.kind == o[1]))
        local label = o[2] .. ((o[1] == nil and #targets == 1) and (' (now: ' .. PARAM_KIND_LABEL[k.guess] .. ')') or '')
        if ig.RadioButton(ctx, label .. '##ctl' .. tostring(o[1]), on) then
          local function apply()
            for _, t in ipairs(targets) do
              local f = gm[t.guid]
              if f then param_set_override(t.tr or tr, f, { guid = t.guid, idx = t.idx, pname = t.name }, o[1]) end
            end
          end
          if #targets > 1 then                             -- several at once: asked first (can be switched off)
            request_confirm(('Change the control of %d parameters to "%s"?'):format(#targets, o[2]),
              apply, 'Change', 'ctl_multi')
          else
            apply()
          end
        end
      end
      ig.TextDisabled(ctx, 'Your choice is added to the training data.')
      ig.Spacing(ctx)
    end
    if #targets ~= 1 then return end

    -- how this row behaves (saved with the project: only for a parameter that is in the Performance)
    if not row then
      ig.TextDisabled(ctx, 'Add the parameter to the quick access\npanel to set the rest.')
    else
      if section_header('Direction and default', false) then
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
      if (can_mm or can_list) and section_header('Limit values', false) then
        local g, ix = first.guid, first.idx
        -- a stepped encoder: the limits sit on its steps, and the range controls move a step at a time
        local stp = k.kind == 'steps' and k.steps and k.steps > 1 and k.steps or nil
        if stp then param_limits_to_steps(tr, row, stp) end
        -- after a change: the parameter moves into what is allowed now
        local function snap()
          local fresh = params_find(tr, g, ix)
          if fresh then param_limits_snap(tr, fxi, ix, fresh, k.kind) end
        end
        local function mm_on() params_update(tr, g, ix, { lim = 'mm', lo = row.lo or 0, hi = row.hi or 1 }); snap() end
        local function ranges_on()
          local first_r = { math.min(row.lo or 0, row.hi or 1), math.max(row.lo or 0, row.hi or 1) }
          params_update(tr, g, ix, { lim = 'ranges', rngs = row.rngs or { first_r } })
          snap()
        end
        -- choosing the list: when the value it has now isn't in it, ask whether to add it (once the list is
        -- on, the parameter only takes the values of the list, so this is the moment to keep it)
        local function list_on()
          local cur = reaper.TrackFX_GetParamNormalized(tr, fxi, ix)
          for _, x in ipairs(row.vals or {}) do
            if math.abs(x - cur) < 1e-5 then
              params_update(tr, g, ix, { lim = 'list' })
              param_list_snap(tr, fxi, ix, row.vals)
              return
            end
          end
          -- the list is only turned on by an answer: Cancel leaves the limits as they were
          local function finish(add)
            if not valid(tr) then return end
            local r = params_find(tr, g, ix)
            if not r then return end
            local nv = {}
            for _, x in ipairs(r.vals or {}) do nv[#nv + 1] = x end
            if add then nv[#nv + 1] = cur end
            params_update(tr, g, ix, { lim = 'list', vals = #nv > 0 and nv or false })
            param_list_snap(tr, fxi, ix, nv)
          end
          request_confirm(('Add the value it has now (%s) to the list?'):format(param_text_at(tr, fxi, ix, cur)),
            function() finish(true) end, 'Add it', nil, { label = "Don't add", fn = function() finish(false) end })
        end
        local rv3, v3 = ig.Checkbox(ctx, 'Use limits', row.lim ~= nil)
        if ig.IsItemHovered(ctx) then
          ig.SetTooltip(ctx, 'When it is moved from the quick access panel, the parameter only takes the values of a\nrange, of a list of values, or of a list of ranges.')
        end
        if rv3 then
          if not v3 then params_update(tr, g, ix, { lim = false })
          elseif can_list and (row.vals or not can_mm) then list_on()
          else mm_on() end
        end
        -- the kind of limits: a menu right of the check box (choosing one also turns the limits on)
        local modes = {}
        if can_mm then modes[#modes + 1] = { 'mm', 'Range', mm_on } end
        if can_list then modes[#modes + 1] = { 'list', 'List of values', list_on } end
        if can_mm then modes[#modes + 1] = { 'ranges', 'List of ranges', ranges_on } end
        if #modes > 1 then
          local shown = row.lim or ((can_list and (row.vals or not can_mm)) and 'list' or 'mm')
          local label = modes[1][2]
          for _, m in ipairs(modes) do if m[1] == shown then label = m[2] end end
          ig.SameLine(ctx)
          ig.SetNextItemWidth(ctx, -1)
          if ig.BeginCombo(ctx, '##limmode', label) then
            for _, m in ipairs(modes) do
              if ig.Selectable(ctx, m[2], row.lim == m[1]) and row.lim ~= m[1] then m[3]() end
            end
            ig.EndCombo(ctx)
          end
        end
        if row.lim then
          local rv8, v8 = ig.Checkbox(ctx, 'Bring it back inside the limits when moved from outside', row.snapout == true)
          if ig.IsItemHovered(ctx) then
            ig.SetTooltip(ctx, 'On: when the parameter is moved from outside FOH-Mate (the FX\'s own window, MIDI learn)\n'
                            .. 'and stays outside the limits for half a second, it goes back to the nearest allowed value.\n'
                            .. 'Not when the parameter has an automation envelope. Its name is highlighted while this is on.')
          end
          if rv8 then params_update(tr, g, ix, { snapout = v8 }) end
          ig.Spacing(ctx)
        end
        -- the plug-in's number and unit for a position, and the position of a typed number (range controls)
        local function rtext(v) return param_text_split(param_text_at(tr, fxi, ix, v)) end
        local function rfind(typed, unit)
          local tn, tu, tis = param_text_split((typed:gsub(',', '.')))
          if not tis then return nil end
          return param_find_value(tr, fxi, ix, tonumber(tn), tu ~= '' and tu or unit)
        end
        -- how the control turns with the limits (param_map): the full range, and Limit only values (one
        -- range) or Skip the gaps (several)
        local function fit_box()
          local sg = param_segs(row, k.kind)
          local multi = sg and #sg > 1
          local fit = param_fit_ok(k.kind)
          if fit then
            local rv4, v4 = ig.Checkbox(ctx, 'Use the full range of the control', row.fit == true)
            if ig.IsItemHovered(ctx) then
              ig.SetTooltip(ctx, 'On: the whole travel of the control covers the allowed values, for finer moves.\n'
                              .. 'Off: the control turns between the lowest and the highest limit (an arc shows the allowed values).')
            end
            if rv4 then params_update(tr, g, ix, { fit = v4 }) end
          end
          if multi then
            local rv5, v5 = ig.Checkbox(ctx, 'Skip the gaps', not row.noskip)
            if ig.IsItemHovered(ctx) then
              ig.SetTooltip(ctx, 'On: the control jumps over the gaps between the allowed values (with the full range: the\n'
                              .. 'allowed values follow one another over the whole travel, a mark where they meet).\n'
                              .. 'Off: the control turns through a gap (see Snap to nearest limit).')
            end
            if rv5 then params_update(tr, g, ix, { noskip = not v5 }) end
            local skip_on = not row.noskip
            if skip_on then ig.BeginDisabled(ctx) end
            local rv7, v7 = ig.Checkbox(ctx, 'Snap to nearest limit', row.snapnear == true)
            if skip_on then ig.EndDisabled(ctx) end
            if ig.IsItemHovered(ctx, ig.HoveredFlags_AllowWhenDisabled()) then
              ig.SetTooltip(ctx, 'While the control turns through a gap:\n'
                              .. 'On: the value takes the nearest allowed value (it jumps half way across).\n'
                              .. 'Off: the value waits at the last allowed value until the control reaches the next one.'
                              .. (skip_on and '\n(Only when the gaps are not skipped.)' or ''))
            end
            if rv7 then params_update(tr, g, ix, { snapnear = v7 }) end
          else
            local off = fit and row.fit
            if off then ig.BeginDisabled(ctx) end
            local rv5, v5 = ig.Checkbox(ctx, 'Limit only values', row.vonly == true)
            if off then ig.EndDisabled(ctx) end
            if ig.IsItemHovered(ctx, ig.HoveredFlags_AllowWhenDisabled()) then
              ig.SetTooltip(ctx, 'On: the control turns all the way, the value stays between Min and Max (it waits there).\n'
                              .. 'Off: the control itself stops at Min and Max.' .. (off and '\n(Not with the full range of the control.)' or ''))
            end
            if rv5 then params_update(tr, g, ix, { vonly = v5 }) end
          end
        end
        if row.lim == 'mm' and can_mm then
          -- Min and Max on one range control; Max below Min is an inverted range (two ranges)
          local nlo, nhi = draw_range_bar('rng', row.lo, row.hi, { text = rtext, find = rfind, inv = true, steps = stp })
          ig.AlignTextToFramePadding(ctx)
          ig.TextDisabled(ctx, 'Set to the value now:')
          ig.SameLine(ctx)
          local cur = reaper.TrackFX_GetParamNormalized(tr, fxi, ix)
          if ig.SmallButton(ctx, 'Min##limnow') then nlo, nhi = cur, nhi or row.hi end
          ig.SameLine(ctx)
          if ig.SmallButton(ctx, 'Max##limnow') then nlo, nhi = nlo or row.lo, cur end
          if nlo and math.abs(nlo - nhi) > 1e-4 and (nlo ~= row.lo or nhi ~= row.hi) then
            params_update(tr, g, ix, { lo = nlo, hi = nhi })
            snap()
          end
          if row.lo > row.hi then
            ig.TextDisabled(ctx, 'Max below Min: up to Max, and from Min up.')
          end
          fit_box()
        elseif row.lim == 'ranges' and can_mm then
          -- each range on its range control, from low to high (the order they take on the control), with
          -- a remove button on the right
          local rngs = row.rngs or {}
          local function put(nr)
            params_update(tr, g, ix, { rngs = #nr > 0 and nr or false })
            snap()
          end
          local function copy()
            local nr = {}
            for i, v in ipairs(rngs) do nr[i] = { v[1], v[2] } end
            return nr
          end
          if #rngs == 0 then ig.TextDisabled(ctx, 'No ranges yet: add one below.') end
          local bw = ig.GetFrameHeight(ctx)
          local sp = select(1, ig.GetStyleVar(ctx, ig.StyleVar_ItemSpacing()))
          local btns = bw
          local bx = ig.GetCursorPosX(ctx) + math.max(0, select(1, ig.GetContentRegionAvail(ctx)) - btns)
          -- the ranges never overlap: each stays the gap (Settings) away from the others
          -- (stepped: at least two steps, so a step between them stays out)
          local gap = param_range_gap()
          if stp then gap = math.max(gap, 2 / (stp - 1)) end
          local order = {}
          for i = 1, #rngs do order[i] = i end
          table.sort(order, function(a, b) return rngs[a][1] < rngs[b][1] end)
          for _, i in ipairs(order) do
            local v = rngs[i]
            ig.PushID(ctx, 'rg' .. i)
            local nlo, nhi, act = draw_range_bar('rg' .. i, v[1], v[2], { text = rtext, find = rfind, width = bx - ig.GetCursorPosX(ctx) - sp,
              steps = stp, right = { x = bx, fn = function() return draw_list_buttons(i, #rngs, bw, 'range', true) end } })
            if act == 'x' then local nr = copy(); table.remove(nr, i); put(nr)
            elseif nlo then
              local L, R = param_range_room(rngs, i, gap)
              local w = v[2] - v[1]
              if math.abs((nhi - nlo) - w) < 1e-6 then          -- moved as a whole: it keeps its size, and goes
                nlo = param_range_place(rngs, i, gap, nlo, w) or v[1]   -- to the nearest place it fits (past others too)
                nhi = nlo + w
              else
                nlo = math.max(L, math.min(nlo, nhi - 0.001))
                nhi = math.min(R, math.max(nhi, nlo + 0.001))
              end
              if nlo < nhi and (nlo ~= v[1] or nhi ~= v[2]) then local nr = copy(); nr[i] = { nlo, nhi }; put(nr) end
            end
            ig.PopID(ctx)
          end
          -- a new one: small, as close to the value it has now as it can be (no button when there is no room)
          local cur = reaper.TrackFX_GetParamNormalized(tr, fxi, ix)
          local new = param_range_new(rngs, gap, cur)
          if new and ig.Button(ctx, 'Add a range') then local nr = copy(); nr[#nr + 1] = new; put(nr) end
          if not new then ig.TextDisabled(ctx, 'No room for another range (Settings: gap between ranges).') end
          -- the gaps become the ranges; the value moves only when a control is turned
          local rv6, v6 = ig.Checkbox(ctx, 'Invert: the gaps between the ranges are the ranges', row.rinv == true)
          if ig.IsItemHovered(ctx) then
            ig.SetTooltip(ctx, 'On: the parameter takes the values outside the ranges of the list instead.\n'
                            .. 'Its value moves to the nearest allowed one when a control is next turned.')
          end
          if rv6 then params_update(tr, g, ix, { rinv = v6 }) end
          fit_box()
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
            local act = draw_list_buttons(i, #vals, bw, 'value')
            if act == 'up' then local nv = copy(); nv[i], nv[i - 1] = nv[i - 1], nv[i]; put(nv)
            elseif act == 'dn' then local nv = copy(); nv[i], nv[i + 1] = nv[i + 1], nv[i]; put(nv)
            elseif act == 'x' then local nv = copy(); table.remove(nv, i); put(nv) end
            ig.PopID(ctx)
          end
          -- adding, at the end: one of the FX's own values, or one picked. The field and the Add button
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
            -- the value (the plug-in's number), its unit, then Add
            local addw = ig.CalcTextSize(ctx, 'Add') + 2 * select(1, ig.GetStyleVar(ctx, ig.StyleVar_FramePadding()))
            local num, unit = param_text_split(param_text_at(tr, fxi, ix, P.lpick))
            local unitw = unit ~= '' and ig.CalcTextSize(ctx, unit) + 4 or 0
            ig.SetNextItemWidth(ctx, W - addw - sp - unitw)
            local rv, v = ig.SliderDouble(ctx, '##lpick', P.lpick, 0, 1, (num:gsub('%%', '%%%%')))
            if rv then P.lpick = v end
            field_unit(unit)
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
          local two = #vals == 2                               -- two values: always a toggle (draw_param_ctl)
          if two then cur_l = PARAM_KIND_LABEL.toggle; ig.BeginDisabled(ctx) end
          ig.SetNextItemWidth(ctx, W)
          if ig.BeginCombo(ctx, '##lshow', cur_l) then
            for _, o in ipairs(opts) do
              if ig.Selectable(ctx, o[2], (o[1] or nil) == row.vshow) then params_update(tr, g, ix, { vshow = o[1] }) end
            end
            ig.EndCombo(ctx)
          end
          if two then ig.EndDisabled(ctx); ig.TextDisabled(ctx, 'Two values are always a toggle, the lower one off.') end
          if #vals == 1 then ig.TextDisabled(ctx, 'A single value is always a drop-down.') end
        end
        ig.Spacing(ctx)
      end
      -- the value curve (curves.lua), for encoders and width / Q bands
      if param_curve_ok(k.kind) and section_header('Curve', false) then
        if row.lim == 'list' then
          ig.TextDisabled(ctx, 'Not with a list of values.')
        else
          -- the graph's dot: where the control is turned to, along the stretch the curve covers
          local cvp = param_curve_of(row, k.kind)
          local M = param_map(row, k.kind, cvp)
          local v = reaper.TrackFX_GetParamNormalized(tr, fxi, first.idx)
          local x = param_map_flip(M, param_ctl_pos(M, v, param_row_memo(tr, row, fxi), k.steps))
          local L = M.B - M.A
          local nspec = draw_curve_graph('crv', row.curve, L > 0 and (x - M.A) / L or 0,
                             k.kind == 'steps' and k.steps and k.steps > 1 and { n = k.steps, A = M.A, B = M.B } or nil)
          if nspec ~= nil then params_update(tr, row.guid, row.idx, { curve = nspec }) end
          local note
          if cvp and M.mode == 'clamp' then
            note = 'Limit only values: the curve covers the whole travel of the control; the value waits at '
                .. 'Min or Max while the control turns on.'
          elseif cvp and M.jumps and not curve_is_linear(cvp) then
            note = 'Skip the gaps with a curve: the control jumps over every part of its turn where the curve '
                .. 'gives a value in a gap, so it may jump several times.'
          end
          if note then
            ig.PushTextWrapPos(ctx, 0)
            ig.TextColored(ctx, T.byp, note)              -- (orange, like a warning)
            ig.PopTextWrapPos(ctx)
          end
        end
        ig.Spacing(ctx)
      end
    end

    -- a preview of the control, and what REAPER says about the parameter
    if section_header('Preview', false) then draw_param_preview(tr, fxi, first, row, k) end
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
  if begin_child('insp_body', 0, 0, CTL_HOVER_PREV['insp'] and ig.WindowFlags_NoScrollWithMouse() or 0) then
    body()
    ig.EndChild(ctx)
  end
end

-- the control as the Performance draws it, in the Inspector, with its value box on its right: it can be
-- turned too
PREVIEW_MM = {}   -- a parameter that is not in the Performance: its memo here (guid:idx -> table)
PREVIEW_VT = {}   -- the value box's text and drawing, per parameter (apart from the rack's, which is another size)
function draw_param_preview(tr, fxi, first, row, k)
  local norm = reaper.TrackFX_GetParamNormalized(tr, fxi, first.idx)
  local px, py = ig.GetCursorScreenPos(ctx)
  local r = row or { guid = first.guid, idx = first.idx, pname = first.name }
  local key = first.guid .. ':' .. first.idx
  local mm = row and param_row_memo(tr, row, fxi) or PREVIEW_MM[key]
  if not mm then mm = {}; PREVIEW_MM[key] = mm end
  local newv = draw_param_ctl('pv', tr, fxi, r, k, k.kind, mm, norm, px + 36, py + 34, 20, 1,
                              { body = ig.GetStyleColor(ctx, ig.Col_FrameBg()), col = ig.GetStyleColor(ctx, ig.Col_Text()), ptr = T.dots }, 'insp')
  if newv then reaper.TrackFX_SetParamNormalized(tr, fxi, first.idx, newv) end
  -- the value box, as in the rack (the text read again when the value moves, or every 30 frames)
  local vt = PREVIEW_VT[key]
  if not vt then vt = {}; PREVIEW_VT[key] = vt end
  if norm ~= vt.norm or FRAME - (vt.f or -99) >= 30 then
    local _, txt = reaper.TrackFX_GetFormattedParamValue(tr, fxi, first.idx)
    vt.text, vt.norm, vt.f = param_vtext(txt, norm, first.name, tr, fxi), norm, FRAME
  end
  local dl = ig.GetWindowDrawList(ctx)
  local vx, vy, vw, vh = px + 36 + 20 + 16, py + 34 - 26, 22, 52
  ig.DrawList_AddRectFilled(dl, vx, vy, vx + vw, vy + vh, ig.GetStyleColor(ctx, ig.Col_FrameBg()), ROUNDING)
  ig.DrawList_AddRect(dl, vx, vy, vx + vw, vy + vh, ig.GetStyleColor(ctx, ig.Col_Border()), ROUNDING, 0, 1)
  draw_vtext(dl, vt.text, vx, vy, vw, vh, ig.GetStyleColor(ctx, ig.Col_Text()), true, 1, vt)
  ig.SetCursorScreenPos(ctx, px, py)
  ig.Dummy(ctx, 1, 72)
end

-- The parameters have two windows, the tree and the inspector, each of which opens, closes, floats and
-- docks on its own (Display > Windows). They are drawn from the same data, worked out once a frame here:
-- the racks (and the FX of the ones open in the tree, with the names of their parameters, read once per
-- FX), and what is selected.
-- the Parameters window: the tree (param_tree.lua), its tick boxes and buttons for the quick access panel
PARAM_TREE_QA = {
  in_label = 'in the quick access panel',
  add_label = 'Add to the quick access panel',
  add_tip = 'The selected parameters go to the quick access panel of their rack\n(the column of controls under it, in Performance mode).',
  remove_label = 'Remove from the quick access panel',
  remove_tip = 'The selected parameters leave the quick access panel of their rack\n(their limits, curve and other settings go with them; Ctrl+Z brings them back).',
  have = function(racks, P)
    local have = {}
    for _, rk in ipairs(racks) do
      if P.open['R:' .. rk.guid] then
        for _, r in ipairs(params_read(rk.tr)) do have[r.guid .. ':' .. r.idx] = r end
      end
    end
    return have
  end,
  apply = function(tr, targets, adding) params_apply(tr, targets, adding) end,
  -- copy / paste its limits and curve: pasted on the whole selection when it is part of it (selected
  -- itself, or through its group, its FX or its rack)
  leaf_menu = function(P, D, fx, p, nm)
    ig.Separator(ctx)
    local tg = { { tr = fx.tr, guid = fx.guid, idx = p, name = nm } }
    local all = param_pick_targets(P, D.fxs)
    if #all > 1 then
      for _, t in ipairs(all) do
        if t.guid == fx.guid and t.idx == p then tg = all; break end
      end
    end
    param_clip_menu(fx.tr, D.gm[fx.guid], { guid = fx.guid, idx = p, pname = nm }, tg, D.gm)
  end,
}

function draw_param_tree(P, D)
  local vis, open = begin_window('parampick', 'Parameters###parampick', 480, 560, true, nil, true)
  if vis then
    draw_tree(P, D, PARAM_TREE_QA)
    ig.End(ctx)
  end
  if not open then P.tree_open = false; param_win_save() end
end

-- the inspector: the settings of what is selected (its own window)
function draw_param_inspector(P, D)
  local vis, open = begin_window('paraminsp', 'Inspector###paraminsp', 320, 560, true, nil, true)
  if vis then
    CONFIRM_HOST = 'insp'                                  -- a question asked here opens here
    draw_param_control_panel(P, D.fxs, D.gm, D.targets)
    draw_confirm('insp')
    CONFIRM_HOST = nil
    ig.End(ctx)
  end
  if confirm and confirm.host == 'insp' and not (vis and open) then confirm = nil end   -- closed while asking: Cancel
  if not open then P.insp_open = false; param_win_save() end
end

-- Which of the two windows are open is kept ('t' tree, 'i' inspector) when you open or close them (not when
-- Show mode closes them), so they come back when FOH-Mate starts again (Settings > Performance mode).
function param_win_save()
  local P = PARAM_PICK
  reaper.SetExtState(EXT_SECTION, 'param_windows', (P and P.tree_open and 't' or '') .. (P and P.insp_open and 'i' or ''), true)
end

PARAM_WIN_RESTORE = nil   -- set at start: the windows to open again, once (in Edit mode, with a rack)

function draw_param_picker()
  if PARAM_WIN_RESTORE then
    local w = PARAM_WIN_RESTORE
    PARAM_WIN_RESTORE = nil
    if not is_locked() and #param_racks() > 0 then
      if w:find('t') then param_pick_toggle('tree') end
      if w:find('i') then param_pick_toggle('insp') end
    end
  end
  local P = PARAM_PICK
  if not P then return end
  -- Show mode closes them; back in Edit mode they come back (Settings > Reopen the Parameters and Inspector windows)
  if P.back and not is_locked() then
    if CFG.reopen_windows ~= 0 and valid(P.tr) and #param_racks() > 0 then P.tree_open, P.insp_open = P.back.tree, P.back.insp end
    P.back = nil
  end
  if not (P.tree_open or P.insp_open) then P.hl, P.focus = nil, nil; return end
  if not valid(P.tr) or is_locked() then
    if is_locked() then P.back = { tree = P.tree_open, insp = P.insp_open } end
    P.tree_open, P.insp_open, P.hl, P.focus = false, false, nil, nil     -- (Show mode closes them)
    return
  end
  local D = param_pick_data(P)
  -- each in a context of its own, so a docker tab shows its name
  if P.tree_open then in_sub_ctx('tree', 'Parameters##FOH-Mate', function() draw_param_tree(P, D) end) end
  if P.insp_open then in_sub_ctx('insp', 'Inspector##FOH-Mate', function() draw_param_inspector(P, D) end) end
end
