-- FOHMate/controls.lua: the controls (rotary encoder, width / Q band, pan, stepped encoder, drop-down,
-- toggle), drawn by hand (ReaImGui has none), and draw_control, which turns one through limits, a list of
-- values and a curve. They know nothing about REAPER or racks, so any module can use them.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- the controls

-- The encoder turns from the 7:30 mark
-- (minimum) clockwise to the 4:30 mark (maximum), 270 degrees, and stops there.

ENC = {}                    -- per encoder: what the current drag started from
ENC_DEFAULT_COL = 0xFFD21EFF   -- the default value's mark: yellow
ENC_POS_COL = 0xFF3D9EFF       -- with a curve and limits, the dot on the ring where the control is turned to: pink
ENC_POS_COL_DAY, ENC_POS_EDGE_DAY = 0xD6006EFF, 0x3A0A24FF   -- the same dot in Daylight: darker, with an outline
ENC_A0, ENC_A1 = math.rad(135), math.rad(405)   -- screen angles of 7:30 and 4:30 (y points down)

-- a tiny arrow just outside the circle, pointing at it (perpendicular to the circumference)
function enc_mark(dl, cx, cy, r, ang, col, s)
  local ux, uy = math.cos(ang), math.sin(ang)
  local px, py = -uy, ux
  local tip, base, hw = r + 2 * s, r + 6.5 * s, 2.6 * s
  ig.DrawList_AddTriangleFilled(dl, cx + ux * tip, cy + uy * tip,
    cx + ux * base + px * hw, cy + uy * base + py * hw,
    cx + ux * base - px * hw, cy + uy * base - py * hw, col)
end

-- How far a band reaches on each side of the top, for a width w (0..1): from nothing at the minimum to a
-- half circle (9 to 3 o'clock) in the middle of the range, a normal stereo width (100% of a 0-200%
-- width, the center of an M-S one), then on to the min and max marks (7:30 to 4:30) at the maximum.
function band_half(w)
  local half, full = math.rad(90), (ENC_A1 - ENC_A0) / 2
  local h = w <= 0.5 and half * w / 0.5 or half + (full - half) * (w - 0.5) / 0.5
  return math.max(math.rad(1.5), h)
end

-- a short line just outside the circle, perpendicular to the circumference (min, max and value marks)
function enc_tick(dl, cx, cy, r, ang, col, s)
  local ux, uy = math.cos(ang), math.sin(ang)
  ig.DrawList_AddLine(dl, cx + ux * (r + 2.5 * s), cy + uy * (r + 2.5 * s),
                      cx + ux * (r + 6.5 * s), cy + uy * (r + 6.5 * s), col, 2 * s)
end

-- o: body (fill), col (ring and min/max marks, the encoder's color), ptr (pointer or arc color),
--    s (scale), style ('line' pointer, or 'pan' for a pan or balance, or 'band' for a width: a band centered at the top, wider with the value),
--    steps (n values: stepped, with a mark per value), marks (positions 0..1 of extra marks, like a fader's), def (default position 0..1, yellow mark),
--    range ({ lo, hi, parts = { { a, b } } }: it stops at lo and hi and keeps to the parts, each shown by
--    an arc in the link color outside the marks, with a handle from each end to the ring; for a band, two
--    arcs per part: where its edges can go), joins (positions where two ranges meet, with fit: a mark in
--    the link color), static (draw only, no mouse).
--    With a curve (o.curve, curves.lua), what is dragged is the position along the curve (o.pos), and
--    what is drawn is the value the curve gives (norm): the encoder rises and falls with the curve as
--    it is turned one way. o.def is then a value, o.def_pos where double-click goes.
-- Returns the new position 0..1 when the user changed it.
-- (that is draw_encoder, below)

-- a round "radio" checkbox: ring with a dot inside when on
function circle_check(dl, id, x, y, d, checked)
  ig.SetCursorScreenPos(ctx, x, y)
  local clicked = ig.InvisibleButton(ctx, id, d, d)
  local hovered = ig.IsItemHovered(ctx)
  local cx, cy, r = x + d / 2, y + d / 2, d / 2 - 2
  ig.DrawList_AddCircleFilled(dl, cx, cy, r, T.chk_bg, 0)
  ig.DrawList_AddCircle(dl, cx, cy, r, hovered and 0x6FB4FFFF or T.chk_ring, 0, 2)
  if checked then ig.DrawList_AddCircleFilled(dl, cx, cy, r - 4, T.chk_dot, 0) end
  return clicked
end

function draw_encoder(id, cx, cy, r, norm, o)
  local s = o.s or 1
  local dl = ig.GetWindowDrawList(ctx)
  local changed
  local hover = false
  -- o.pos: where the control is turned to, when it can differ from where the hand shows the value (norm);
  -- o.travel: { lo, hi }, the ends it turns between; o.jump(c, prev): where it goes when turned from prev
  -- to c (over a gap); o.hand(c): the hand for a place (drawn at once while it is turned); o.dot: a dot
  -- on the ring shows o.pos
  local cpos = o.pos
  if not o.static then
    local R = r + 6 * s
    ig.SetCursorScreenPos(ctx, cx - R, cy - R)
    ig.InvisibleButton(ctx, id, 2 * R, 2 * R)
    hover = ig.IsItemHovered(ctx)
    local st = ENC[id]
    if not st then st = {}; ENC[id] = st end
    local base = o.pos or norm                         -- where the drag starts from
    if ig.IsItemActivated(ctx) then st.raw, st.a = base, nil end
    if hover and ig.IsMouseDoubleClicked(ctx, 0) and o.def then
      local d = o.def_pos or o.def
      changed, st.raw, cpos = d, d, d
    elseif ig.IsItemActive(ctx) then
      local mx, my = ig.GetMousePos(ctx)
      local raw = st.raw or base
      if CFG.enc_mode == 'circle' then
        local a = math.atan(my - cy, mx - cx)
        if st.a then
          local d = a - st.a
          if d > math.pi then d = d - 2 * math.pi elseif d < -math.pi then d = d + 2 * math.pi end
          raw = raw + d / (ENC_A1 - ENC_A0)
        end
        st.a = a
      else
        local _, dy = ig.GetMouseDelta(ctx)
        local k = 0.006 / (1 + math.abs(mx - cx) / (40 * s))   -- farther to the side = finer
        if has_mod('shift') then k = k * 0.25 end
        raw = raw - dy * k
      end
      raw = math.max(0, math.min(1, raw))
      if o.travel then raw = math.max(o.travel[1], math.min(o.travel[2], raw)) end
      if o.jump then raw = o.jump(raw, st.raw or base) end
      st.raw = raw
      local v = raw
      if o.steps and o.steps > 1 then v = math.floor(raw * (o.steps - 1) + 0.5) / (o.steps - 1) end
      if v ~= base then changed = v end
      cpos = v
    end
  end
  local v = norm
  if changed then v = o.hand and o.hand(changed) or changed end
  local parts = o.range and o.range.parts and #o.range.parts > 1 and o.range.parts
  -- the pointer moves at most so far per frame (the whole range in about a sixth of a second): a value
  -- that jumps (a steep curve dragged quickly, the FX, automation) sweeps over the top, instead of
  -- seeming to pass under the encoder. Only the drawing; the value is set at once.
  -- (o.show: a table of the caller's, one per encoder, that keeps where the pointer was drawn and when)
  local ds = o.show
  if ds then
    local now = reaper.time_precise()
    if ds.sv then
      local step = math.max(0.02, (now - ds.st) * 6)
      if math.abs(v - ds.sv) > step then
        local sv = ds.sv + (v > ds.sv and step or -step)
        -- several parts: the sweep never shows a value in a gap; it jumps straight across it
        local inside = not parts
        if parts then
          for _, p in ipairs(parts) do
            if sv >= math.min(p[1], p[2]) - 1e-6 and sv <= math.max(p[1], p[2]) + 1e-6 then inside = true; break end
          end
        end
        if inside then v = sv end
      end
    end
    ds.sv, ds.st = v, now
  end
  ig.DrawList_AddCircleFilled(dl, cx, cy, r, o.body, 0)
  if o.range then
    -- the limits: under the ring and every mark, far enough out for the marks to sit between it and the ring
    local ra = r + 8.5 * s
    -- one line: from the ring out, along the arc, and back in to the ring, so the corners join cleanly
    local function limit_arc(a, b)
      ig.DrawList_PathLineTo(dl, cx + math.cos(a) * r, cy + math.sin(a) * r)
      ig.DrawList_PathArcTo(dl, cx, cy, ra, a, b)
      ig.DrawList_PathLineTo(dl, cx + math.cos(b) * r, cy + math.sin(b) * r)
      ig.DrawList_PathStroke(dl, T.link, 0, 1.5 * s)
    end
    for _, p in ipairs(o.range.parts or { { o.range[1], o.range[2] } }) do
      if o.style == 'band' then
        -- a band: where its two edges can go, one arc on each side of the top
        local function half(x) return band_half(o.narrow and 1 - x or x) end
        local h1, h2 = half(p[1]), half(p[2])
        if h1 > h2 then h1, h2 = h2, h1 end
        local mid = (ENC_A0 + ENC_A1) / 2
        limit_arc(mid - h2, mid - h1)
        limit_arc(mid + h1, mid + h2)
      else
        limit_arc(ENC_A0 + (ENC_A1 - ENC_A0) * p[1], ENC_A0 + (ENC_A1 - ENC_A0) * p[2])
      end
    end
  end
  ig.DrawList_AddCircle(dl, cx, cy, r, hover and mix(o.col, WHITE, 0.3) or o.col, 0, 2 * s)
  enc_tick(dl, cx, cy, r, ENC_A0, o.col, s)
  enc_tick(dl, cx, cy, r, ENC_A1, o.col, s)
  if o.steps and o.steps > 2 then
    for i = 1, o.steps - 2 do enc_tick(dl, cx, cy, r, ENC_A0 + (ENC_A1 - ENC_A0) * i / (o.steps - 1), o.col, 0.6 * s) end
  end
  if o.marks then
    for _, m in ipairs(o.marks) do enc_tick(dl, cx, cy, r, ENC_A0 + (ENC_A1 - ENC_A0) * m, o.col, 0.75 * s) end
  end
  if o.joins then                                   -- where two ranges meet (full range of the control)
    for _, m in ipairs(o.joins) do enc_tick(dl, cx, cy, r, ENC_A0 + (ENC_A1 - ENC_A0) * m, T.link, s) end
  end
  if o.def or o.style == 'pan' then
    if o.style == 'band' then
      -- a band: the default is a range, so two short lines at the edges of the band it would have
      local mid = (ENC_A0 + ENC_A1) / 2
      local half = band_half(o.narrow and 1 - o.def or o.def)
      enc_tick(dl, cx, cy, r, mid - half, ENC_DEFAULT_COL, s)
      enc_tick(dl, cx, cy, r, mid + half, ENC_DEFAULT_COL, s)
    else
      enc_mark(dl, cx, cy, r, ENC_A0 + (ENC_A1 - ENC_A0) * (o.style == 'pan' and 0.5 or o.def), ENC_DEFAULT_COL, s)
    end
  end
  local ang = ENC_A0 + (ENC_A1 - ENC_A0) * v
  if o.style == 'pan' then
    -- a pan: the default mark is the center; a band runs from the top to the position, left or right
    -- (7:30 = all the way left, 4:30 = all the way right); centered, a small vertical line under the mark
    local mid = (ENC_A0 + ENC_A1) / 2
    if math.abs(v - 0.5) < 0.0025 then
      -- centered: a small vertical line where the arrow's back would be
      local py = cy - (r - 4 * s)
      ig.DrawList_AddRectFilled(dl, cx - 0.75 * s, py - 2.5 * s, cx + 0.75 * s, py + 2.5 * s, o.ptr)
    elseif math.abs(v - 0.5) < 0.05 then        -- up to 9% either side (9L to 9R on a 100L-100R pan)
      -- off center by too little for a band to show: a tiny arrow pointing left or right, smaller than
      -- the default mark, its back on the center line
      local d = ang < mid and -1 or 1
      local px, py = cx, cy - (r - 4 * s)
      -- (the points go round the same way for both directions, or the left one's soft edge falls inside it)
      ig.DrawList_AddTriangleFilled(dl, px + d * 3.5 * s, py, px, py - 2 * d * s, px, py + 2 * d * s, o.ptr)
    else
      -- from 10% on: the band, never shorter than the arrow so the switch doesn't jump
      local rb = r - 4 * s
      local a = mid + (ang < mid and -1 or 1) * math.max(math.abs(ang - mid), 3.5 * s / rb)
      ig.DrawList_PathArcTo(dl, cx, cy, rb, math.min(mid, a), math.max(mid, a))
      ig.DrawList_PathStroke(dl, o.ptr, 0, 3.5 * s)
    end
  elseif o.style == 'band' then
    -- a width: a band centered at the top, as thin as it can be at the minimum, a half circle in the
    -- middle and reaching from the minimum mark to the maximum mark at the maximum (see band_half)
    local mid, half = (ENC_A0 + ENC_A1) / 2, band_half(o.narrow and 1 - v or v)
    ig.DrawList_PathArcTo(dl, cx, cy, r - 4 * s, mid - half, mid + half)
    ig.DrawList_PathStroke(dl, o.ptr, 0, 3.5 * s)
  else
    ig.DrawList_AddLine(dl, cx + math.cos(ang) * r * 0.3, cy + math.sin(ang) * r * 0.3,
                        cx + math.cos(ang) * r * 0.85, cy + math.sin(ang) * r * 0.85, o.ptr, 3 * s)
  end
  -- the value and the place can differ (o.dot: a curve, Limit only values, gaps not skipped): the hand
  -- shows the value, a small dot on the ring where the control itself is turned to (a band: one at each
  -- edge of the width it is turned to)
  if o.dot and cpos then
    local dr = 2.2 * s
    -- Daylight: a darker, more saturated pink with a thin dark outline, to stand out on the light ring
    local function dot(a)
      local px, py = cx + math.cos(a) * r, cy + math.sin(a) * r
      if S.daylight then
        ig.DrawList_AddCircleFilled(dl, px, py, dr, ENC_POS_COL_DAY, 0)
        ig.DrawList_AddCircle(dl, px, py, dr, ENC_POS_EDGE_DAY, 0, 1)
      else
        ig.DrawList_AddCircleFilled(dl, px, py, dr, ENC_POS_COL, 0)
      end
    end
    if o.style == 'band' then
      local mid, half = (ENC_A0 + ENC_A1) / 2, band_half(o.narrow and 1 - cpos or cpos)
      dot(mid - half); dot(mid + half)
    else
      dot(ENC_A0 + (ENC_A1 - ENC_A0) * cpos)
    end
  end
  return changed
end

-- a circle with a small arrow pointing down; a click opens a menu of the values.
-- items: { { label, norm }, ... }. Returns the norm of the one picked.
function draw_dropdown(id, cx, cy, r, norm, items, o)
  local s = o.s or 1
  local dl = ig.GetWindowDrawList(ctx)
  ig.SetCursorScreenPos(ctx, cx - r, cy - r)
  if ig.InvisibleButton(ctx, id, 2 * r, 2 * r) then ig.OpenPopup(ctx, id .. '_dd') end
  local hover = ig.IsItemHovered(ctx)
  ig.DrawList_AddCircleFilled(dl, cx, cy, r, o.body, 0)
  ig.DrawList_AddCircle(dl, cx, cy, r, hover and mix(o.col, WHITE, 0.3) or o.col, 0, 2 * s)
  local w, h = 5.5 * s, 3.5 * s
  ig.DrawList_AddTriangleFilled(dl, cx - w, cy - h, cx + w, cy - h, cx, cy + h, o.ptr)
  local picked
  if ig.BeginPopup(ctx, id .. '_dd') then
    for _, it in ipairs(items) do
      if ig.Selectable(ctx, it.label .. '##' .. it.norm, math.abs(it.norm - norm) < 1e-4) then picked = it.norm end
    end
    ig.EndPopup(ctx)
  end
  return picked
end

-- draw_control(id, norm, o): one control, as o.kind says ({ kind = 'knob' / 'band' / 'qband' / 'pan' / 'steps'
-- / 'toggle' / 'list', steps, items, marks }), at o.cx, o.cy, radius o.r, scale o.s, colors o.colors
-- ({ body, col, ptr }); o.ekind: the kind it is drawn as, if another; o.limits: its limit settings and curve
-- (limit_map.lua; a quick access row, or a table of the module's own); o.memo: a table kept per control;
-- o.list: a list of values to step through (param_list_view's { items, pos, def, show }), if any;
-- o.wkey: the window it is in (it doesn't scroll under the control); o.ctrl_wheel(wv, wh) and o.ctrl_hint:
-- what Ctrl (Cmd) + the wheel does, if anything. Returns the new value (0..1) when it was changed.
--
-- The mouse wheel (or two fingers on a trackpad) over a control changes its value: a step at a time for a
-- stepped encoder, a list or a drop-down, on / off for a toggle.
CTL_HOVER_NOW, CTL_HOVER_PREV = {}, {}
WHEEL_STEPPED = 0.4                         -- a stepped encoder: 2.5 notches of the wheel per step (lists and drop-downs: 1)
WHEEL_STEP, WHEEL_FINE = 0.006, 0.0015     -- a notch of the wheel on a smooth control (Shift: finer), of its travel

function draw_control(id, norm, o)
  local r, kind, mm = o.limits or {}, o.kind, o.memo
  local ekind = o.ekind or kind.kind
  local kcx, kcy, kr, f, cl, wkey = o.cx, o.cy, o.r, o.s or 1, o.colors, o.wkey
  local dl = ig.GetWindowDrawList(ctx)
  local newv
  local m = kr + 6 * f
  local wv = 0
  if ig.IsWindowHovered(ctx) and mouse_in(kcx - m, kcy - m, kcx + m, kcy + m) then
    if wkey then CTL_HOVER_NOW[wkey] = true end
    local wh
    wv, wh = ig.GetMouseWheel(ctx)
    HINT = 'Scroll: change the value' .. (o.ctrl_hint or '')
    if (wv ~= 0 or wh ~= 0) and mod_down('ctrl') then
      if o.ctrl_wheel then o.ctrl_wheel(wv, wh) end
      wv = 0
    elseif wv == 0 and wh ~= 0 and mod_down('shift') then
      wv = wh                                     -- (a Mac turns Shift+wheel sideways: still the finer turn)
    end
  end
  -- whole steps from the wheel (a trackpad gives small amounts: they add up), one step at a time at
  -- most, so a fast swipe doesn't skip values and every step is felt
  local function wheel_steps(scale)
    mm.wacc = (mm.wacc or 0) + wv * (scale or 1)
    local n = mm.wacc >= 0 and math.floor(mm.wacc) or -math.floor(-mm.wacc)
    mm.wacc = mm.wacc - n
    if n > 1 or n < -1 then n, mm.wacc = (n > 0 and 1 or -1), 0 end
    return n
  end
  local function step_item(items, pos, scale)
    local n = wheel_steps(scale)
    if n == 0 then return nil end
    return items[math.max(1, math.min(#items, pos + n))].norm
  end
  -- Limit values, list: a stepped encoder or a drop-down of the listed values (param_list_view); two
  -- values only: a toggle, the lower one off
  local lv = o.list
  if lv and #lv.items == 2 then
    local a, b = lv.items[1].norm, lv.items[2].norm
    local low, high = math.min(a, b), math.max(a, b)
    local on = math.abs(norm - high) < math.abs(norm - low)
    local d = 2 * (kr + 3 * f)
    if circle_check(dl, id, kcx - d / 2, kcy - d / 2, d, on) then newv = on and low or high end
    if not newv and wv ~= 0 then newv = wv > 0 and high or low end
  elseif lv and lv.show == 'list' then
    newv = draw_dropdown(id, kcx, kcy, kr, lv.items[lv.pos].norm, lv.items, { body = cl.body, col = cl.col, ptr = cl.ptr, s = f })
    if not newv and wv ~= 0 then newv = step_item(lv.items, lv.pos) end
  elseif lv then
    local n_ = #lv.items
    local c_ = draw_encoder(id, kcx, kcy, kr, (lv.pos - 1) / (n_ - 1), { body = cl.body, col = cl.col, ptr = cl.ptr, s = f,
                            style = 'line', steps = n_, def = lv.def })
    if c_ then newv = lv.items[math.floor(c_ * (n_ - 1) + 0.5) + 1].norm end
    if not newv and wv ~= 0 then newv = step_item(lv.items, lv.pos, WHEEL_STEPPED) end
  elseif kind.kind == 'list' then
    newv = draw_dropdown(id, kcx, kcy, kr, norm, kind.items, { body = cl.body, col = cl.col, ptr = cl.ptr, s = f })
    if not newv and wv ~= 0 and kind.items and #kind.items > 0 then
      local pos, bd = 1, math.huge
      for i, it in ipairs(kind.items) do
        if math.abs(it.norm - norm) < bd then pos, bd = i, math.abs(it.norm - norm) end
      end
      newv = step_item(kind.items, pos)
    end
  else
    -- the control turns through the row's invert, limits and curve (param_map, params.lua): the hand
    -- shows the value (where it lies along the travel), the control keeps where it is turned to (cpos),
    -- and a dot shows that place when the two can differ
    local cv = param_curve_of(r, ekind)
    local M = param_map(r, ekind, cv)
    -- (a value set from elsewhere, outside the limits: the hand shows where it really is, and the dot
    -- where the control is, at the nearest end, until it is put back inside: param_ext_snap)
    local shown = param_map_flip(M, param_map_hand(M, norm))
    local outside = param_map_out(M, norm)
    local cpos = param_ctl_pos(M, norm, mm, kind.steps)
    local newc
    if kind.kind == 'toggle' then
      local d = 2 * (kr + 3 * f)
      if circle_check(dl, id, kcx - d / 2, kcy - d / 2, d, shown > 0.5) then newc = shown > 0.5 and 0 or 1 end
      if not newc and wv ~= 0 then newc = wv > 0 and 1 or 0 end
    else
      local marks, def, range, joins = param_ctl_view(r, ekind, kind.marks, M)
      -- the ends of the travel, and (made once per row) the hand for a place and the jump over a gap
      local ta, tb = param_map_flip(M, M.A), param_map_flip(M, M.B)
      if ta > tb then ta, tb = tb, ta end
      local trv = mm.trv or {}
      trv[1], trv[2], mm.trv, mm.M = ta, tb, trv, M
      mm.hand_fn = mm.hand_fn or function(c)
        local m = mm.M
        return param_map_flip(m, param_map_unlim(m, param_map_val(m, param_map_flip(m, c), mm.cu)))
      end
      mm.jump_fn = mm.jump_fn or function(c, prev)
        local m = mm.M
        local dir = (c >= prev) and 1 or -1
        if m.inv then dir = -dir end
        local x = param_map_skip(m, param_map_flip(m, c), dir)
        return x and param_map_flip(m, x) or prev
      end
      local def_pos = def
      if def and M.dot then def_pos = param_map_flip(M, param_map_pos(M, r.def, param_map_flip(M, cpos))) end
      newc = draw_encoder(id, kcx, kcy, kr, shown, { body = cl.body, col = cl.col, ptr = cl.ptr, s = f,
                          style = ekind == 'pan' and 'pan' or (ekind == 'band' or ekind == 'qband') and 'band' or 'line', narrow = ekind == 'qband', steps = kind.steps, marks = marks,
                          def = def, range = range, joins = joins, pos = cpos, def_pos = def_pos, travel = trv,
                          hand = mm.hand_fn, jump = M.jumps and mm.jump_fn or nil, dot = M.dot or outside, show = mm })
      if not newc and wv ~= 0 then
        -- the wheel: along the control, from where it is turned to, a step at a time when stepped
        local c1
        if kind.steps and kind.steps > 1 then
          local n = wheel_steps(WHEEL_STEPPED)
          if n ~= 0 then c1 = cpos + n / (kind.steps - 1) end
        else
          c1 = cpos + wv * (mod_down('shift') and WHEEL_FINE or WHEEL_STEP)
        end
        if c1 then
          c1 = math.max(ta, math.min(tb, c1))
          if M.jumps then c1 = mm.jump_fn(c1, cpos) end
          if c1 ~= cpos then newc = c1 end
        end
      end
    end
    if newc then
      -- the place -> the value (on a step of the FX for a stepped one, then back inside the limits)
      newv = param_map_val(M, param_map_flip(M, newc), norm)
      if kind.steps and kind.steps > 1 then
        newv = math.floor(newv * (kind.steps - 1) + 0.5) / (kind.steps - 1)
        if M.segs then newv = param_seg_near(M.segs, newv) end
      end
      mm.cpos, mm.cu, mm.csig, mm.ct = newc, newv, M.sig, reaper.time_precise()
    end
  end
  return newv
end
