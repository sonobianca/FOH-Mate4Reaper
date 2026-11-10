-- FOHMate/limit_map.lua: how limits and a curve turn a control (the maths, no drawing), for any module.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- limits and curve of a control
--
-- How another module uses it: give param_map a table of limit settings `r` (the same fields a quick
-- access row has: lim = 'mm' with lo, hi, or 'ranges' with rngs = { { lo, hi }, ... } and rinv; fit, vonly,
-- noskip, snapnear, inv, curve; the fields ending in _ are its caches), the kind of control ('knob',
-- 'band', 'qband', 'pan', 'steps') and the curve (curve_parse of the text, or nil). It returns M, the way
-- the control turns; then:
--   param_map_val(M, param_map_flip(M, c), prev): the control at c (0..1 as drawn) -> the value
--   param_ctl_pos(M, v, memo, steps): the value -> where the control is (memo: a table kept per control)
--   param_map_flip(M, param_map_hand(M, v)): where the hand shows the value
--   param_ctl_view(r, kind, marks, M): the marks, default mark, arcs and junctions to draw (draw_encoder)
-- A table read again after a change must be a new table (the caches are kept on it).

-- Limit values, Range (r.lim == 'mm') and List of ranges (r.lim == 'ranges'): a parameter (of the quick
-- access panel, or of another module) may be kept to some parts of its travel (0..1), its "segments":
--   Range: from lo to hi; lo above hi is an inverted range: from 0 to hi, and from lo to 1 (two parts);
--   List of ranges: r.rngs, { lo, hi } each, in any order (shown and used from low to high), never overlapping; with r.rinv, the
--   gaps between them are the parts instead (from low to high).
-- How the control turns (param_map, worked out once per row and kind): x is where the control is along
-- its travel (0..1, before Invert), v the parameter's value.
--   No limit: the value is the position.
--   Range, one part (lo..hi):
--     the control turns from lo to hi only, and the value is the position;
--     Limit only values (r.vonly): the control turns all the way, the value stays in lo..hi (it waits at
--     an end while the control turns on);
--     full range (r.fit): the whole travel covers lo..hi.
--   Several parts (a List of ranges, a Range with Max below Min): the control turns from the lowest limit
--   to the highest one;
--     Skip the gaps (not r.noskip): it jumps over a gap, so it never sits in one;
--     not skipped: it turns through a gap; the value waits at the last allowed value it left until the
--     control reaches the next part, or (Snap to nearest limit, r.snapnear) takes the nearest one;
--     full range: the whole travel covers the lowest to the highest limit (gaps included), or, skipping
--     the gaps, the parts one after the other, each as long as it is (a mark shows each junction).
-- A curve (curves.lua) covers the stretch the control turns through: at position t along it (0..1), it
-- says where along that same stretch the value goes (y), which then keeps to the limits as above.
-- Only for the controls that turn (an encoder, a stepped encoder, a width or Q band, a pan); fit not for
-- a stepped encoder.
function param_limit_ok(kind) return kind ~= nil and kind ~= 'toggle' and kind ~= 'list' end
function param_fit_ok(kind) return kind == 'knob' or kind == 'band' or kind == 'qband' or kind == 'pan' end

-- the parts a row allows, from low to high (nil: no limit); a list's are worked out once per row (the
-- rows are read again when they change)
function param_segs(r, kind)
  if not param_limit_ok(kind) then return nil end
  if r.lim == 'mm' and r.lo and r.hi then
    if r.lo < r.hi then return { { r.lo, r.hi } } end
    return { { 0, r.hi }, { r.lo, 1 } }
  elseif r.lim == 'ranges' and r.rngs and #r.rngs > 0 then
    if not r.segs_ then
      local srt = {}
      for i, v in ipairs(r.rngs) do srt[i] = v end
      table.sort(srt, function(a, b) return a[1] < b[1] end)
      if r.rinv then                                   -- inverted: the gaps between them
        local out, x = {}, 0
        for _, v in ipairs(srt) do
          if v[1] > x + 1e-6 then out[#out + 1] = { x, v[1] } end
          x = math.max(x, v[2])
        end
        if x < 1 - 1e-6 then out[#out + 1] = { x, 1 } end
        srt = out
      end
      r.segs_ = srt
    end
    if #r.segs_ > 0 then return r.segs_ end
  end
end

-- the allowed value nearest to v
function param_seg_near(segs, v)
  local best, bd = v, math.huge
  for _, sg in ipairs(segs) do
    local x = math.max(sg[1], math.min(sg[2], v))
    local d = math.abs(x - v)
    if d == 0 then return v end
    if d < bd then best, bd = x, d end
  end
  return best
end

-- a stepped control (n steps over its whole travel): v on its nearest step
function param_on_step(v, n) return math.floor(v * (n - 1) + 0.5) / (n - 1) end

-- full range, skipping the gaps: where each part lies along the control's travel, { lo, hi, from, to }
-- each, from low to high
function param_fit_layout(segs)
  local total = 0
  for _, sg in ipairs(segs) do total = total + (sg[2] - sg[1]) end
  local out, c = {}, 0
  for i, sg in ipairs(segs) do
    local w = total > 0 and (sg[2] - sg[1]) / total or 1 / #segs
    out[i] = { sg[1], sg[2], c, c + w }
    c = c + w
  end
  return out
end

-- the way a row's control turns, for a kind of control and its curve (cv, or nil): { mode, A, B (the
-- stretch it turns through), segs, S, E (the lowest and highest limits), skip, lay, inv, cv, dot }. mode:
-- 'free' (no limit), 'span' (turns from the lowest to the highest limit), 'clamp' (Limit only values),
-- 'fit' (full range, one part), 'stretch' (full range, gaps included), 'chain' (full range, gaps skipped).
-- dot: the value and the position can differ (the control then shows a dot where it is turned to).
function param_map(r, kind, cv)
  local c = r.map_ and r.map_[kind]
  if c and c.cv == cv then return c end
  local segs = param_segs(r, kind)
  local M = { mode = 'free', A = 0, B = 1, segs = segs, inv = r.inv, cv = cv }
  if segs then
    local fit = r.fit and param_fit_ok(kind)
    M.S, M.E = segs[1][1], segs[#segs][2]
    if #segs == 1 then
      if fit then M.mode = 'fit'
      elseif r.vonly then M.mode = 'clamp'
      else M.mode, M.A, M.B = 'span', M.S, M.E end
    else
      M.skip = not r.noskip
      if fit and M.skip then
        M.mode = 'chain'
        M.lay = param_fit_layout(segs)
      elseif fit then M.mode = 'stretch'
      else M.mode, M.A, M.B = 'span', M.S, M.E end
    end
  end
  M.jumps = M.skip and M.mode == 'span' or false     -- the control itself jumps over the gaps
  -- in a gap, the value waits at the last allowed value it left (param_map_lim with prev)
  M.wait = segs ~= nil and #segs > 1 and r.noskip == true and not r.snapnear
           and (M.mode == 'span' or M.mode == 'stretch') or false
  M.dot = cv ~= nil or M.mode == 'clamp' or (segs ~= nil and #segs > 1 and r.noskip == true)
  -- the same way of turning (a row read again after a change elsewhere keeps its control where it is)
  M.sig = ('%s|%.6f|%.6f|%s|%s|%s|%s|%s'):format(M.mode, M.A, M.B, tostring(M.skip), tostring(M.wait), tostring(r.inv), r.curve or '',
                                            r.rraw or '')
  r.map_ = r.map_ or {}
  r.map_[kind] = M
  return M
end

-- the control's own direction (Invert): x <-> the position as the control shows it (the same both ways)
function param_map_flip(M, x) return M.inv and 1 - x or x end

-- position x -> where along its stretch the value goes (w, before the limits), through the curve
function param_map_w(M, x)
  if not M.cv then return x end
  local L = M.B - M.A
  if L <= 0 then return M.A end
  return M.A + curve_eval(M.cv, (x - M.A) / L) * L
end

-- in a gap (M.wait): the value it had (prev) waits at the edge of the part it left: going up, the top of
-- the part below the gap; going down, the bottom of the part above it
function param_map_gap(M, w, prev)
  local near = param_seg_near(M.segs, w)
  if not (M.wait and prev) or math.abs(near - w) < 1e-9 then return near end
  if w > prev then
    for i = #M.segs, 1, -1 do if M.segs[i][2] < w then return M.segs[i][2] end end
  else
    for _, sg in ipairs(M.segs) do if sg[1] > w then return sg[1] end end
  end
  return near
end

-- w -> the value (prev: the value it had, for a value that waits in a gap)
function param_map_lim(M, w, prev)
  local m = M.mode
  if m == 'free' then return w end
  if m == 'span' or m == 'clamp' then
    if #M.segs == 1 then return math.max(M.S, math.min(M.E, w)) end
    return param_map_gap(M, w, prev)
  end
  if m == 'fit' then return M.S + math.max(0, math.min(1, w)) * (M.E - M.S) end
  if m == 'stretch' then return param_map_gap(M, M.S + math.max(0, math.min(1, w)) * (M.E - M.S), prev) end
  for i, p in ipairs(M.lay) do                        -- chain
    if w <= p[4] or i == #M.lay then
      local t = p[4] > p[3] and (w - p[3]) / (p[4] - p[3]) or 0
      return p[1] + math.max(0, math.min(1, t)) * (p[2] - p[1])
    end
  end
  return w
end

function param_map_val(M, x, prev) return param_map_lim(M, param_map_w(M, x), prev) end

-- the value -> where it lies along the travel, without the curve (where the hand shows it)
function param_map_unlim(M, v)
  local m = M.mode
  if m == 'fit' or m == 'stretch' then
    local L = M.E - M.S
    return L > 0 and math.max(0, math.min(1, (v - M.S) / L)) or 0
  elseif m == 'chain' then
    local best, bd = v, math.huge
    for _, p in ipairs(M.lay) do
      local x = math.max(p[1], math.min(p[2], v))
      local d = math.abs(x - v)
      if d < bd - 1e-9 then
        bd = d
        best = (p[2] > p[1]) and p[3] + (x - p[1]) / (p[2] - p[1]) * (p[4] - p[3]) or p[3]
      end
    end
    return best
  elseif m == 'span' then
    return math.max(M.A, math.min(M.B, v))
  end
  return v
end

-- where the hand shows the value v: as param_map_unlim, but a value outside the stretch the control turns
-- through (set from elsewhere: the FX's own window, automation) is shown where it really is, past the arc
function param_map_hand(M, v)
  if M.mode == 'span' then return v end
  return param_map_unlim(M, v)
end

-- whether v is outside what the limits allow (set from elsewhere)
function param_map_out(M, v)
  return M.segs ~= nil and math.abs(param_seg_near(M.segs, v) - v) > 1e-4
end

-- the position that gives the value v (with a curve: of the places that do, the nearest to `near`)
function param_map_pos(M, v, near)
  local w = param_map_unlim(M, v)
  if not M.cv then return w end
  local L = M.B - M.A
  if L <= 0 then return M.A end
  return M.A + curve_inv(M.cv, (w - M.A) / L, near and (near - M.A) / L) * L
end

-- Skip the gaps: whether the control at x would give a value in a gap
function param_map_bad(M, x)
  if not M.jumps then return false end
  local w = param_map_w(M, x)
  for _, sg in ipairs(M.segs) do
    if w >= sg[1] - 1e-9 and w <= sg[2] + 1e-9 then return false end
  end
  return true
end

-- Skip the gaps: the control turned to x, going up (dir 1) or down (-1): x itself, or, in a gap, the
-- first place past it (nil: there is none that way). Without a curve, the edge of the next part; with
-- one, found along the curve.
function param_map_skip(M, x, dir)
  if not param_map_bad(M, x) then return x end
  if not M.cv then
    if dir > 0 then
      for _, sg in ipairs(M.segs) do if sg[1] > x then return sg[1] end end
    else
      for i = #M.segs, 1, -1 do if M.segs[i][2] < x then return M.segs[i][2] end end
    end
    return nil
  end
  local d = (M.B - M.A) / 1024
  local p = x
  for _ = 1, 1024 do
    p = p + dir * d
    if p < M.A - 1e-9 or p > M.B + 1e-9 then return nil end
    if not param_map_bad(M, p) then return p end
  end
end

-- a control: where it is turned to (0..1 as it shows it), for the value v. It remembers where it was (mm,
-- the row's memo), so a curve that reaches a value several times, or a value that waits at a limit,
-- doesn't make it jump; it looks again only when the value moved from elsewhere. Just after a turn
-- (mm.ct, 0.3 s), the value read back is taken as the turn's: the FX may round it (a stepped one).
-- A stepped encoder sits on a step.
function param_ctl_pos(M, v, mm, steps)
  if mm.cpos and mm.csig == M.sig then
    if mm.cu and math.abs(mm.cu - v) < 1e-5 then return mm.cpos end
    if mm.ct and reaper.time_precise() - mm.ct < 0.3 then mm.cu = v; return mm.cpos end
  end
  local near = mm.cpos and param_map_flip(M, mm.cpos)
  local c = param_map_flip(M, param_map_pos(M, v, near))
  if steps and steps > 1 then c = math.floor(c * (steps - 1) + 0.5) / (steps - 1) end
  mm.cu, mm.cpos, mm.csig = v, c, M.sig
  return c
end

-- what the control draws, in its own 0..1: the extra marks (a fader's dB marks: with the full range,
-- only those inside the parts), the default mark, the parts it keeps to, when they are shown as arcs,
-- as { lo, hi, parts = { { a, b } } } (lo, hi: the ends of its travel), and (full range, gaps skipped)
-- the junctions
function param_ctl_view(r, kind, marks, M)
  M = M or param_map(r, kind, nil)
  local segs, m = M.segs, M.mode
  local full = m == 'fit' or m == 'stretch' or m == 'chain'
  local function inside(v)
    if not full then return true end
    for _, sg in ipairs(segs) do if v >= sg[1] and v <= sg[2] then return true end end
    return false
  end
  local function at(v) return param_map_flip(M, param_map_unlim(M, v)) end
  local pm
  if marks then
    pm = {}
    for _, mk in ipairs(marks) do if inside(mk) then pm[#pm + 1] = at(mk) end end
  end
  local pd = r.def and inside(r.def) and at(r.def) or nil
  local range, joins
  if m == 'span' or m == 'clamp' or m == 'stretch' then
    local parts = {}
    for _, sg in ipairs(segs) do
      local pa, pb = at(sg[1]), at(sg[2])
      if pa > pb then pa, pb = pb, pa end
      parts[#parts + 1] = { pa, pb }
    end
    local ta, tb = param_map_flip(M, M.A), param_map_flip(M, M.B)
    range = { math.min(ta, tb), math.max(ta, tb), parts = parts }
  elseif m == 'chain' and #M.lay > 1 then
    joins = {}
    for i = 1, #M.lay - 1 do joins[#joins + 1] = param_map_flip(M, M.lay[i][4]) end
  end
  return pm, pd, range, joins
end
