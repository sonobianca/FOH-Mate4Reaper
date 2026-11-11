-- FOHMate/curves.lua: value curves of the Performance controls.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: MIT

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
  -- (two points only: a straight line, smooth or not; smoothing them would make an S)
  if not cv.smooth or #p == 2 then return a.y + (b.y - a.y) * t end
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

-- a curve that is a straight line from 0 to 1 anyway (custom points on the diagonal)
function curve_is_linear(cv)
  if cv.kind ~= 'pts' then return cv.k <= 1.001 end
  for _, p in ipairs(cv.pts) do if math.abs(p.y - p.x) > 1e-3 then return false end end
  return true
end

---------------------------------------------------------------- saved curves

CURVE_FILE = LATDB_DIR .. '/param_curves.txt'
-- the examples, always there (they can be changed on a row, not deleted); none of them is one of
-- the curves the Type menu already gives (Ease in, Ease out)
CURVE_EXAMPLES = {
  { 'S curve',            'pts:1:0.000,0.000 0.250,0.080 0.500,0.500 0.750,0.920 1.000,1.000' },
  { 'Fine in the middle', 'pts:1:0.000,0.000 0.300,0.440 0.700,0.560 1.000,1.000' },
  { 'Rising wave',        'pts:1:0.000,0.000 0.042,0.112 0.083,0.183 0.125,0.196 0.167,0.167 0.208,0.138 0.250,0.150 '
                          .. '0.292,0.221 0.333,0.333 0.375,0.446 0.417,0.517 0.458,0.529 0.500,0.500 0.542,0.471 '
                          .. '0.583,0.483 0.625,0.554 0.667,0.667 0.708,0.779 0.750,0.850 0.792,0.862 0.833,0.833 '
                          .. '0.875,0.804 0.917,0.817 0.958,0.888 1.000,1.000' },
  { 'Parabola',           'pts:1:0.000,0.000 0.125,0.438 0.250,0.750 0.375,0.938 0.500,1.000 0.625,0.938 0.750,0.750 '
                          .. '0.875,0.438 1.000,0.000' },
  { 'Valley',             'pts:1:0.000,1.000 0.125,0.562 0.250,0.250 0.375,0.062 0.500,0.000 0.625,0.062 0.750,0.250 '
                          .. '0.875,0.562 1.000,1.000' },
  { 'Staircase',          'pts:0:0.000,0.000 0.240,0.000 0.260,0.333 0.490,0.333 0.510,0.667 0.740,0.667 0.760,1.000 1.000,1.000' },
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

-- (the curve editor, draw_curve_graph, is in curve_graph.lua)
