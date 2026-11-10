-- FOHMate/range_bar.lua: the range selector (Min and Max on one bar), a widget any module can use.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- range selector
--
-- draw_range_bar(id, lo, hi, o) draws one line: a value box for Min, the bar, a value box for Max (the
-- number in the box, its unit after it), and returns lo, hi when one of them changed (nil otherwise), then
-- what o.right returned. lo and hi are 0..1.
--
-- The bar: the covered part in the link color; an arrow outside each end, its tip on the value (Min left
-- of it pointing right, Max right of it pointing left), and a thin line across the bar at each value.
-- Each arrow hangs a round handle under its base on a thin line, on a track of its own (Min, then Max
-- lower), and a round handle sits over the middle of the covered part. Grab:
--   a handle, an arrow or its line: that end (it follows the pointer from where it was);
--   the range handle or the covered part: the whole range;
--   where the arrows overlap: the nearest end, the range when both are as near;
--   anywhere else on the bar: the nearest end comes there.
-- What the pointer would grab lights up (arrow, line and handle together; the range handle and the
-- covered part together). The handles take room above and below the line (RANGE_PAD_TOP / _BOTTOM):
-- the boxes keep their height, the lines of a list are spaced further apart.
--
-- o: text(v) -> number, unit, is_number (what a box shows); find(typed, unit) -> v or nil (a number typed
-- in a box); inv (Min may go above Max: the covered part is then outside the arrows, up to Max and from
-- Min; no range handle then); steps (n: the ends move a step at a time, n steps over 0..1, never both on
-- the same one); width (instead of the room left on the line); right = { x = cursor x, fn = function } (drawn
-- at x on the same line, e.g. a remove button; what fn returns is returned third).

RANGE_DRAG = {}   -- id -> what is dragged: { what = 'lo' / 'hi' / 'both', mx, lo, hi (where it started) }
RANGE_EDIT = {}   -- id .. side -> the text being typed in a box
RANGE_HOT = {}    -- id -> what the pointer would grab (drawn lit), from the frame before

-- the sizes, from the frame height fh: arrow length tw and half height hh, handle radius hr, the tracks'
-- offsets from the bar's middle (range above; Min, then Max below), and the room they take above and below
function range_bar_sizes(fh)
  local z = {}
  z.tw, z.hh = math.floor(fh * 0.35), math.floor(fh * 0.3)
  z.hr = 3.5
  z.y_range = -(z.hh + 7)
  z.y_lo = z.hh + 6
  z.y_hi = z.hh + 15
  z.pad_top = math.max(0, math.ceil(z.hr - z.y_range - fh / 2) + 1)
  z.pad_bottom = math.max(0, math.ceil(z.y_hi + z.hr - fh / 2) + 1)
  return z
end

function draw_range_bar(id, lo, hi, o)
  ig.PushID(ctx, id)
  local fh = ig.GetFrameHeight(ctx)
  local z = range_bar_sizes(fh)
  ig.SetCursorPosY(ctx, ig.GetCursorPosY(ctx) + z.pad_top)       -- room for the range handle
  local x0 = ig.GetCursorPosX(ctx)
  local width = o.width or (ig.GetContentRegionAvail(ctx))
  local nlo, ulo, islo = o.text(lo)
  local nhi, uhi, ishi = o.text(hi)
  local unitw = math.max((ig.CalcTextSize(ctx, ulo)), (ig.CalcTextSize(ctx, uhi)))
  local bw, gap = 58, 8                                   -- a value box, and the room between box and bar
  local uslot = unitw > 0 and unitw + 4 or 0
  local barw = math.max(40, width - 2 * (bw + uslot + gap))
  local out_lo, out_hi = lo, hi
  local function box(side, num, unit, isnum, x)
    ig.SameLine(ctx, x)
    local key = id .. side
    ig.SetNextItemWidth(ctx, bw)
    local rv, t = ig.InputText(ctx, '##' .. side, num, isnum and ig.InputTextFlags_AutoSelectAll() or ig.InputTextFlags_ReadOnly())
    if rv then RANGE_EDIT[key] = t end
    if isnum and ig.IsItemDeactivatedAfterEdit(ctx) and RANGE_EDIT[key] then
      local v = o.find(RANGE_EDIT[key], unit)
      RANGE_EDIT[key] = nil
      if v then
        if side == 'lo' then out_lo = o.inv and v or math.min(v, hi - 0.001)
        else out_hi = o.inv and v or math.max(v, lo + 0.001) end
      end
    end
    if unit ~= '' then
      ig.SameLine(ctx, x + bw + 4)
      ig.AlignTextToFramePadding(ctx)
      ig.Text(ctx, unit)
    end
  end
  ig.SetCursorPosX(ctx, x0)
  ig.Dummy(ctx, 0, 0)                                      -- (the line starts here; every part is placed by x)
  box('lo', nlo, ulo, islo, x0)
  -- the bar's place on the line, then the Max box and what the caller adds on the same line
  local barx = x0 + bw + uslot + gap
  ig.SameLine(ctx, barx)
  local sx, sy = ig.GetCursorScreenPos(ctx)
  ig.Dummy(ctx, barw, fh)
  box('hi', nhi, uhi, ishi, barx + barw + gap)
  local extra
  if o.right then
    ig.SameLine(ctx, o.right.x)
    extra = o.right.fn()
  end
  -- the bar itself: a button over it and the handles' tracks, above and below the line (placed after the
  -- line, then the cursor goes back under it)
  local after_x, after_y = ig.GetCursorScreenPos(ctx)
  ig.SetCursorScreenPos(ctx, sx, sy - z.pad_top)
  ig.InvisibleButton(ctx, '##bar', barw, fh + z.pad_top + z.pad_bottom)
  local dl = ig.GetWindowDrawList(ctx)
  local th = 4                                             -- the bar's thickness
  local my = math.floor(sy + fh / 2) + 0.5
  -- the ends of the travel: room on each side for an arrow and its handle
  local m = z.tw + z.hr + 1
  local x1, x2 = sx + m, sx + barw - m
  local function X(v) return x1 + v * (x2 - x1) end
  local function V(x) return (x - x1) / (x2 - x1) end
  local covered_at = function(v) return (lo <= hi and v > lo and v < hi) or (lo > hi and (v < hi or v > lo)) end
  -- what the pointer at (mx, py) would grab: 'lo', 'hi', 'both' or nil (nil: nothing in particular)
  local function hit(mx, py)
    local function near(x, y, r) return (mx - x) ^ 2 + (py - y) ^ 2 <= r * r end
    local function ends()                                  -- arrow (and its line, and the connector) hits, with a distance
      local found = {}
      local function try(what, v, dir)
        local xv = X(v)
        local xb = xv - dir * z.tw                         -- the arrow's base, where its handle hangs
        local ax1, ax2 = math.min(xv, xb), math.max(xv, xb)
        local hy = my + (what == 'lo' and z.y_lo or z.y_hi)
        if near(xb, hy, z.hr + 3) then found[#found + 1] = { what, 0 }; return end
        local in_arrow = mx >= ax1 - 2 and mx <= ax2 + 2 and py >= my - z.hh - 2 and py <= my + z.hh + 2
        local on_line = math.abs(mx - xb) <= 3 and py >= my and py <= hy
        if in_arrow or on_line then found[#found + 1] = { what, math.abs(mx - (ax1 + ax2) / 2) } end
      end
      try('lo', lo, 1)
      try('hi', hi, -1)
      return found
    end
    if not o.inv and lo <= hi and near((X(lo) + X(hi)) / 2, my + z.y_range, z.hr + 3) then return 'both' end
    local f = ends()
    if #f == 1 then return f[1][1] end
    if #f == 2 then                                        -- the arrows overlap: the nearer; as near: the range
      if f[1][2] == 0 and f[2][2] ~= 0 then return f[1][1] end
      if f[2][2] == 0 and f[1][2] ~= 0 then return f[2][1] end
      if math.abs(f[1][2] - f[2][2]) < 1 then return 'both' end
      return f[1][2] < f[2][2] and f[1][1] or f[2][1]
    end
    if math.abs(py - my) <= th / 2 + 3 and covered_at(V(mx)) then return 'both' end
  end
  local mx, py = ig.GetMousePos(ctx)
  if ig.IsItemActivated(ctx) then
    local what = hit(mx, py)
    local d = { what = what, mx = mx, lo = lo, hi = hi }
    if not what then                                       -- elsewhere: the nearest end comes there
      local v = math.max(0, math.min(1, V(mx)))
      what = math.abs(mx - X(lo)) < math.abs(mx - X(hi)) and 'lo' or 'hi'
      d.what = what
      if what == 'lo' then d.lo = o.inv and v or math.min(v, hi - 0.001) else d.hi = o.inv and v or math.max(v, lo + 0.001) end
    end
    RANGE_DRAG[id] = d
  end
  local dr = RANGE_DRAG[id]
  if ig.IsItemActive(ctx) and dr then
    -- every grab follows the pointer from where the end (or the range) was
    local dv = (mx - dr.mx) / (x2 - x1)
    if dr.what == 'both' then
      dv = math.max(-math.min(dr.lo, dr.hi), math.min(1 - math.max(dr.lo, dr.hi), dv))
      out_lo, out_hi = dr.lo + dv, dr.hi + dv
    elseif dr.what == 'lo' then
      local v = math.max(0, math.min(1, dr.lo + dv))
      out_lo = o.inv and v or math.min(v, hi - 0.001)
    else
      local v = math.max(0, math.min(1, dr.hi + dv))
      out_hi = o.inv and v or math.max(v, lo + 0.001)
    end
  elseif not ig.IsItemActive(ctx) then
    RANGE_DRAG[id] = nil
  end
  -- the steps of a stepped control: the ends sit on them (never both on the same one)
  local function on_steps()
    if not (o.steps and o.steps > 1) or (out_lo == lo and out_hi == hi) then return end
    out_lo, out_hi = param_on_step(out_lo, o.steps), param_on_step(out_hi, o.steps)
    if out_lo == out_hi then out_lo, out_hi = lo, hi end
  end
  on_steps()
  local hov = ig.IsItemHovered(ctx)
  local lit = RANGE_DRAG[id] and RANGE_DRAG[id].what or (hov and hit(mx, py)) or nil
  if hov then
    ig.SetTooltip(ctx, 'Drag an arrow or the round handle under it: Min (left) or Max (right)\n'
                    .. 'Drag the blue part or the handle above it: the whole range')
  end

  -- drawing, from the bottom up: the handles' lines, the bar and its covered part, the value lines,
  -- the arrows, the handles
  local ink = ig.GetStyleColor(ctx, ig.Col_Text())
  local thin = (T.dim & 0xFFFFFF00) | 0xA0
  local function lit_col(c, on) return on and mix(c, WHITE, 0.35) or c end
  local lo_on, hi_on, both_on = lit == 'lo', lit == 'hi', lit == 'both'
  local xl, xh = X(out_lo), X(out_hi)
  local bl, bh = xl - z.tw, xh + z.tw                      -- the arrows' bases
  local rx = (xl + xh) / 2
  local show_range = not o.inv and out_lo <= out_hi
  ig.DrawList_AddLine(dl, bl, my, bl, my + z.y_lo, lit_col(thin, lo_on), 1)
  ig.DrawList_AddLine(dl, bh, my, bh, my + z.y_hi, lit_col(thin, hi_on), 1)
  if show_range then ig.DrawList_AddLine(dl, rx, my + z.y_range, rx, my, lit_col(thin, both_on), 1) end
  ig.DrawList_AddRectFilled(dl, x1, my - th / 2, x2, my + th / 2, (T.dim & 0xFFFFFF00) | 0x70, th / 2)
  local cov = lit_col(T.link, both_on)
  if out_lo <= out_hi then
    ig.DrawList_AddRectFilled(dl, xl, my - th / 2, xh, my + th / 2, cov, 0)
  else
    ig.DrawList_AddRectFilled(dl, x1, my - th / 2, xh, my + th / 2, cov, th / 2)
    ig.DrawList_AddRectFilled(dl, xl, my - th / 2, x2, my + th / 2, cov, th / 2)
  end
  ig.DrawList_AddLine(dl, xl, my - z.hh, xl, my + z.hh, lit_col(ink, lo_on), 1)
  ig.DrawList_AddLine(dl, xh, my - z.hh, xh, my + z.hh, lit_col(ink, hi_on), 1)
  -- an arrow: its tip on the value, pointing at it (both listed the same way round, so they look alike)
  local function arrow(x, dir, col)
    ig.DrawList_AddTriangleFilled(dl, x, my, x - dir * z.tw, my - z.hh, x - dir * z.tw, my + z.hh, col)
  end
  arrow(xl, 1, lit_col(ink, lo_on))
  arrow(xh, -1, lit_col(ink, hi_on))
  ig.DrawList_AddCircleFilled(dl, bl, my + z.y_lo, z.hr, lit_col(ink, lo_on), 0)
  ig.DrawList_AddCircleFilled(dl, bh, my + z.y_hi, z.hr, lit_col(ink, hi_on), 0)
  if show_range then ig.DrawList_AddCircleFilled(dl, rx, my + z.y_range, z.hr, cov, 0) end

  ig.SetCursorScreenPos(ctx, after_x, after_y)
  ig.PopID(ctx)
  ig.Dummy(ctx, 0, z.pad_bottom)                           -- room for the handles below the line
  if out_lo ~= lo or out_hi ~= hi then return out_lo, out_hi, extra end
  return nil, nil, extra
end
