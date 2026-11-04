-- FOHMate/curves.lua: value curves of the Performance controls.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- curves
--
-- A curve says which value (y, 0..1) a control gives at each position (x, 0..1): the control turns
-- evenly, the value follows the curve. It is kept as a short text (the "spec"), saved with the row:
--   'in:K' / 'out:K'          ease in (y = x^K) / ease out (y = 1 - (1-x)^K), K from 1 to 6
--   'pts:S:x,y x,y ...'       points from x = 0 to x = 1, joined smoothly (S = 1) or by straight lines
-- No spec = straight (linear). Any y is allowed at any x, so a curve can go up and down.

CURVE_CACHE = {}   -- spec -> the curve, read once: { kind, k, smooth, pts, lut }
CURVE_COUNT = 0    -- how many are in it (dragging a point makes a new one each frame: emptied past 200)
CURVE_N     = 256  -- the curve is also kept as CURVE_N + 1 samples, to find a position from a value

-- the controls a curve is for: encoders (smooth and stepped) and width / Q bands
function param_curve_ok(kind) return kind == 'knob' or kind == 'steps' or kind == 'band' or kind == 'qband' end

local function curve_y(cv, x)
  if cv.kind == 'in' then return x ^ cv.k end
  if cv.kind == 'out' then return 1 - (1 - x) ^ cv.k end
  local p = cv.pts
  local i = 1
  while i < #p - 1 and x > p[i + 1].x do i = i + 1 end
  local a, b = p[i], p[i + 1]
  local t = (b.x > a.x) and (x - a.x) / (b.x - a.x) or 0
  if not cv.smooth then return a.y + (b.y - a.y) * t end
  -- smooth: a Catmull-Rom curve through the points (the ends repeated), kept inside 0..1
  local y0, y3 = (p[i - 1] or a).y, (p[i + 2] or b).y
  local y1, y2 = a.y, b.y
  local y = 0.5 * (2 * y1 + (y2 - y0) * t + (2 * y0 - 5 * y1 + 4 * y2 - y3) * t * t + (3 * y1 - y0 - 3 * y2 + y3) * t * t * t)
  return math.max(0, math.min(1, y))
end

function curve_parse(spec)
  local cv = CURVE_CACHE[spec]
  if cv then return cv end
  local kind, rest = spec:match('^(%a+):?(.*)$')
  if kind == 'in' or kind == 'out' then
    cv = { kind = kind, k = math.max(1, math.min(6, tonumber(rest) or 2)) }
  elseif kind == 'pts' then
    local sm, list = rest:match('^(%d):(.*)$')
    local pts = {}
    for x, y in (list or ''):gmatch('([%d%.%-]+),([%d%.%-]+)') do
      pts[#pts + 1] = { x = math.max(0, math.min(1, tonumber(x))), y = math.max(0, math.min(1, tonumber(y))) }
    end
    table.sort(pts, function(a, b) return a.x < b.x end)
    if #pts < 2 then pts = { { x = 0, y = 0 }, { x = 1, y = 1 } } end
    pts[1].x, pts[#pts].x = 0, 1
    cv = { kind = 'pts', smooth = sm == '1', pts = pts }
  else
    return nil
  end
  cv.lut = {}
  for i = 0, CURVE_N do cv.lut[i + 1] = curve_y(cv, i / CURVE_N) end
  if CURVE_COUNT > 200 then CURVE_CACHE, CURVE_COUNT = {}, 0 end
  CURVE_CACHE[spec], CURVE_COUNT = cv, CURVE_COUNT + 1
  return cv
end

function curve_spec(cv)
  if cv.kind ~= 'pts' then return ('%s:%.2f'):format(cv.kind, cv.k) end
  local t = {}
  for i, p in ipairs(cv.pts) do t[i] = ('%.3f,%.3f'):format(p.x, p.y) end
  return ('pts:%d:%s'):format(cv.smooth and 1 or 0, table.concat(t, ' '))
end

-- the value at a position
function curve_eval(cv, x)
  return curve_y(cv, math.max(0, math.min(1, x)))
end

-- the position that gives a value: of all the places the curve reaches it, the one nearest to `near`
-- (where the control was), or the first one without it; a value the curve never reaches: the
-- position that comes closest
function curve_inv(cv, y, near)
  local lut, best, bd = cv.lut, nil, math.huge
  for i = 1, CURVE_N do
    local a, b = lut[i], lut[i + 1]
    if (y - a) * (y - b) <= 0 then
      local t = (a == b) and 0.5 or (y - a) / (b - a)
      local x = (i - 1 + t) / CURVE_N
      local d = near and math.abs(x - near) or x
      if d < bd then best, bd = x, d end
    end
  end
  if best then return best end
  for i = 1, CURVE_N + 1 do
    local d = math.abs(lut[i] - y)
    if d < bd then best, bd = (i - 1) / CURVE_N, d end
  end
  return best
end

-- the curve of a row, or nil: only for the controls above, and not with a list of values
function param_curve_of(r, kind)
  if not r.curve or r.lim == 'list' or not param_curve_ok(kind) then return nil end
  return curve_parse(r.curve)
end

-- a control with a curve: the position it shows for the value u (0..1, after invert and limits). It
-- remembers where it was (mm, the row's memo), so a curve that reaches a value several times doesn't
-- make it jump, and looks again only when the value moved. A stepped encoder sits on a step.
function curve_ctl_pos(cv, u, mm, steps)
  if mm.cu == u and mm.cpos and mm.ccv == cv then return mm.cpos end
  local c = curve_inv(cv, u, mm.cpos)
  if steps and steps > 1 then c = math.floor(c * (steps - 1) + 0.5) / (steps - 1) end
  mm.cu, mm.cpos, mm.ccv = u, c, cv
  return c
end

-- the control was turned to c: the value u it gives (on a step of the plug-in for a stepped one)
function curve_ctl_value(cv, c, mm, steps)
  mm.cpos, mm.cu = c, nil
  local u = curve_eval(cv, c)
  if steps and steps > 1 then u = math.floor(u * (steps - 1) + 0.5) / (steps - 1) end
  return u
end

---------------------------------------------------------------- saved curves

CURVE_FILE = LATDB_DIR .. '/param_curves.txt'
-- the examples, always there (they can be changed on a row, not deleted)
CURVE_EXAMPLES = {
  { 'Ease in',            'in:2.50' },
  { 'Ease out',           'out:2.50' },
  { 'S curve',            'pts:1:0.000,0.000 0.250,0.080 0.500,0.500 0.750,0.920 1.000,1.000' },
  { 'Fine in the middle', 'pts:1:0.000,0.000 0.300,0.440 0.700,0.560 1.000,1.000' },
  { 'Up and down',        'pts:1:0.000,0.000 0.500,1.000 1.000,0.000' },
  { 'Wave',               'pts:1:0.000,0.000 0.250,1.000 0.500,0.000 0.750,1.000 1.000,0.000' },
  { 'Zigzag',             'pts:0:0.000,0.000 0.333,1.000 0.667,0.000 1.000,1.000' },
}
CURVE_LIB = nil    -- the user's saved curves: { { name, spec } }, read once

function curve_lib()
  if not CURVE_LIB then
    CURVE_LIB = {}
    for _, ln in ipairs(read_lines(CURVE_FILE)) do
      local name, spec = ln:match('^([^\t]+)\t(.+)$')
      if name and curve_parse(spec) then CURVE_LIB[#CURVE_LIB + 1] = { name, spec } end
    end
  end
  return CURVE_LIB
end

function curve_lib_save()
  local t = {}
  for _, c in ipairs(curve_lib()) do t[#t + 1] = c[1] .. '\t' .. c[2] end
  write_lines(CURVE_FILE, t)
end

-- saves a curve under a name asked for (after the frame: the question box stops the script); a
-- curve of the same name is replaced
function curve_prompt_save(spec)
  later[#later + 1] = function()
    local ok, name = reaper.GetUserInputs('Save this curve', 1, 'Name:,extrawidth=120', '')
    if not ok then return end
    name = name:gsub('[\t\r\n]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then return end
    local lib = curve_lib()
    for _, c in ipairs(lib) do
      if c[1] == name then c[2] = spec; curve_lib_save(); return end
    end
    lib[#lib + 1] = { name, spec }
    curve_lib_save()
  end
end

function curve_lib_delete(name)
  local lib = curve_lib()
  for i, c in ipairs(lib) do
    if c[1] == name then table.remove(lib, i); curve_lib_save(); return end
  end
end

---------------------------------------------------------------- the curve section (parameter window)

CURVE_DRAG = nil   -- the point being dragged in the graph: its number

-- The "Curve" part of the parameter window, for a parameter in the Performance (row): the kind of
-- curve, its strength or its points, the graph, and the saved curves. pos = where the control is now.
function draw_curve_section(tr, row, pos)
  local g, ix = row.guid, row.idx
  local cv = row.curve and curve_parse(row.curve)
  local function set(spec) params_update(tr, g, ix, { curve = spec or false }) end
  local kinds = { { nil, 'Linear' }, { 'in', 'Ease in' }, { 'out', 'Ease out' }, { 'pts', 'Custom points' } }
  local now = 'Linear'
  for _, o in ipairs(kinds) do if cv and o[1] == cv.kind then now = o[2] end end
  ig.SetNextItemWidth(ctx, 220)
  if ig.BeginCombo(ctx, 'Curve##crv', now) then
    for _, o in ipairs(kinds) do
      if ig.Selectable(ctx, o[2], (cv and cv.kind or nil) == o[1]) then
        if not o[1] then set(nil)
        elseif o[1] == 'pts' then
          -- custom points start from the curve as it is (5 points of it), smooth
          local pts = {}
          for i = 0, 4 do pts[#pts + 1] = { x = i / 4, y = cv and curve_eval(cv, i / 4) or i / 4 } end
          if not (cv and cv.kind == 'pts') then set(curve_spec({ kind = 'pts', smooth = true, pts = pts })) end
        else
          set(curve_spec({ kind = o[1], k = cv and cv.k or 2.5 }))
        end
      end
    end
    ig.Separator(ctx)
    ig.TextDisabled(ctx, 'Saved curves')
    for li, list in ipairs({ CURVE_EXAMPLES, curve_lib() }) do
      for i, c in ipairs(list) do
        if ig.Selectable(ctx, c[1] .. '##sv' .. li .. ':' .. i, row.curve == c[2]) then set(c[2]) end
      end
    end
    ig.EndCombo(ctx)
  end
  if cv and cv.kind ~= 'pts' then
    ig.SetNextItemWidth(ctx, 220)
    local rv, k = ig.SliderDouble(ctx, 'Strength##crvk', cv.k, 1, 6, '%.1f')
    if rv then set(curve_spec({ kind = cv.kind, k = k })) end
  elseif cv then
    local rv, sm = ig.Checkbox(ctx, 'Smooth (off: straight lines)', cv.smooth)
    if rv then set(curve_spec({ kind = 'pts', smooth = sm, pts = cv.pts })) end
  end

  -- the graph: position across, value up
  local W, H, pad = 220, 150, 8
  local x0, y0 = ig.GetCursorScreenPos(ctx)
  ig.InvisibleButton(ctx, '##crvgraph', W + 2 * pad, H + 2 * pad)
  local hov, act = ig.IsItemHovered(ctx), ig.IsItemActive(ctx)
  local dl = ig.GetWindowDrawList(ctx)
  local gx, gy = x0 + pad, y0 + pad
  local function sx(x) return gx + x * W end
  local function sy(y) return gy + (1 - y) * H end
  local grid = ig.GetStyleColor(ctx, ig.Col_Border())
  local ink = ig.GetStyleColor(ctx, ig.Col_Text())
  ig.DrawList_AddRectFilled(dl, gx, gy, gx + W, gy + H, ig.GetStyleColor(ctx, ig.Col_FrameBg()), 4)
  for i = 1, 3 do
    ig.DrawList_AddLine(dl, sx(i / 4), gy, sx(i / 4), gy + H, grid, 1)
    ig.DrawList_AddLine(dl, gx, sy(i / 4), gx + W, sy(i / 4), grid, 1)
  end
  for i = 0, 64 do
    local x = i / 64
    ig.DrawList_PathLineTo(dl, sx(x), sy(cv and curve_eval(cv, x) or x))
  end
  ig.DrawList_PathStroke(dl, ink, 0, 2)
  -- where the control is now
  if pos then
    ig.DrawList_AddCircleFilled(dl, sx(pos), sy(cv and curve_eval(cv, pos) or pos), 4, T.link, 0)
  end
  if cv and cv.kind == 'pts' then
    local mx, my = ig.GetMousePos(ctx)
    local function near()
      for i, p in ipairs(cv.pts) do
        if (mx - sx(p.x)) ^ 2 + (my - sy(p.y)) ^ 2 < 49 then return i end
      end
    end
    local pts = {}
    for i, p in ipairs(cv.pts) do pts[i] = { x = p.x, y = p.y } end
    local hot = (hov or act) and (CURVE_DRAG or near())
    for i, p in ipairs(cv.pts) do
      ig.DrawList_AddCircleFilled(dl, sx(p.x), sy(p.y), i == hot and 5 or 4, ink, 0)
    end
    local mxv = math.max(0, math.min(1, (mx - gx) / W))
    local myv = math.max(0, math.min(1, 1 - (my - gy) / H))
    if ig.IsItemClicked(ctx, 0) then
      -- a point: drag it; elsewhere: a new point there, dragged at once
      CURVE_DRAG = near()
      if not CURVE_DRAG then
        local at = #pts
        for i = 2, #pts do if mxv < pts[i].x then at = i; break end end
        if mxv - pts[at - 1].x > 0.01 and pts[at].x - mxv > 0.01 then
          table.insert(pts, at, { x = mxv, y = myv })
          CURVE_DRAG = at
          set(curve_spec({ kind = 'pts', smooth = cv.smooth, pts = pts }))
        end
      end
    elseif act and CURVE_DRAG and pts[CURVE_DRAG] then
      -- the first and last points stay at the ends; the others stay between their neighbours
      local p = pts[CURVE_DRAG]
      if CURVE_DRAG > 1 and CURVE_DRAG < #pts then
        p.x = math.max(pts[CURVE_DRAG - 1].x + 0.01, math.min(pts[CURVE_DRAG + 1].x - 0.01, mxv))
      end
      p.y = myv
      local spec = curve_spec({ kind = 'pts', smooth = cv.smooth, pts = pts })
      if spec ~= row.curve then set(spec) end
    elseif not act then
      CURVE_DRAG = nil
    end
    -- right-click a point (not an end): remove it
    if hov and ig.IsMouseClicked(ctx, 1) then
      local i = near()
      if i and i > 1 and i < #pts then
        table.remove(pts, i)
        set(curve_spec({ kind = 'pts', smooth = cv.smooth, pts = pts }))
      end
    end
    if hov then ig.SetTooltip(ctx, 'Click: add a point  \194\183  drag a point: move it  \194\183  right-click a point: remove it') end
  end

  -- saving, and the user's saved curves
  if cv then
    if ig.Button(ctx, 'Save this curve...') then curve_prompt_save(row.curve) end
  end
  local lib = curve_lib()
  if #lib > 0 then
    if cv then ig.SameLine(ctx) end
    ig.SetNextItemWidth(ctx, 150)
    if ig.BeginCombo(ctx, '##crvdel', 'Delete a saved curve...') then
      for i, c in ipairs(lib) do
        if ig.Selectable(ctx, c[1] .. '##del' .. i, false) then
          local name = c[1]
          request_confirm(('Delete the saved curve "%s"?\n(Rows that use it keep their curve.)'):format(name),
            function() curve_lib_delete(name) end, 'Delete')
        end
      end
      ig.EndCombo(ctx)
    end
  end
end
