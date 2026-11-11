-- FOHMate/curve_graph.lua: the curve editor (a square graph, its points, the kind of curve, saved curves), a
-- widget any module can use.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: MIT

---------------------------------------------------------------- curve editor
--
-- draw_curve_graph(id, spec, pos, stp) draws: the kind of curve (Linear, Ease in, Ease out, Custom
-- points, or a saved curve), the graph (position across, value up, always square, 1:1; custom points
-- are added, dragged and removed on it), then the strength or smoothing and saving / deleting curves.
-- spec: the curve as text (curve_spec, curves.lua), nil for a straight line. pos: where the control is
-- now, along the stretch the curve covers (0..1), drawn as a dot (nil: none). stp: a stepped control,
-- { n = steps, A, B = the stretch it covers }: a dot per step, the curve itself fainter.
-- Returns the new curve when it was changed: its text, or false for a straight line (nil: unchanged).

CURVE_DRAG = nil   -- the point being dragged in the graph: its number

function draw_curve_graph(id, spec, pos, stp)
  ig.PushID(ctx, id)
  local cv = spec and curve_parse(spec)
  local out                                        -- the new curve: its text, or false for a straight line
  local function set(s) out = s or false end
  -- the graph: position across, value up; always square (1:1), as wide as there is room for (120 to 260 px)
  local pad = 8
  local W = math.floor(math.max(120, math.min(260, select(1, ig.GetContentRegionAvail(ctx)) - 2 * pad)))
  local H = W
  -- the kind of curve, above the graph (from its left edge)
  ig.Indent(ctx, pad)
  local capw = math.max((ig.CalcTextSize(ctx, 'Type')), (ig.CalcTextSize(ctx, 'Strength'))) + 8   -- the captions' column
  local kinds = { { nil, 'Linear' }, { 'in', 'Ease in' }, { 'out', 'Ease out' }, { 'pts', 'Custom points' } }
  local now = 'Linear'
  for _, o in ipairs(kinds) do if cv and o[1] == cv.kind then now = o[2] end end
  field_caption('Type', capw)
  ig.SetNextItemWidth(ctx, W - capw)
  if ig.BeginCombo(ctx, '##crv', now) then
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
        if ig.Selectable(ctx, c[1] .. '##sv' .. li .. ':' .. i, spec == c[2]) then set(c[2]) end
      end
    end
    ig.EndCombo(ctx)
  end
  ig.Unindent(ctx, pad)
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
  -- stp (a stepped encoder): { n = its steps, A, B = the stretch the curve covers }: the control sits on
  -- a step and the value lands on one, so a dot for each step, on the curve rounded to a step (the curve
  -- itself fainter)
  local function yat(x)
    local y = cv and curve_eval(cv, x) or x
    if not stp then return y end
    local L = stp.B - stp.A
    if L <= 0 then return y end
    return math.max(0, math.min(1, (param_on_step(stp.A + y * L, stp.n) - stp.A) / L))
  end
  for i = 0, 64 do
    local x = i / 64
    ig.DrawList_PathLineTo(dl, sx(x), sy(cv and curve_eval(cv, x) or x))
  end
  ig.DrawList_PathStroke(dl, stp and ((ink & 0xFFFFFF00) | 0x50) or ink, 0, stp and 1.5 or 2)
  if stp and stp.B > stp.A then
    for i = 0, stp.n - 1 do
      local p = i / (stp.n - 1)
      if p >= stp.A - 1e-9 and p <= stp.B + 1e-9 then
        local x = (p - stp.A) / (stp.B - stp.A)
        ig.DrawList_AddCircleFilled(dl, sx(x), sy(yat(x)), 2.5, ink, 0)
      end
    end
  end
  -- where the control is now
  if pos then
    ig.DrawList_AddCircleFilled(dl, sx(pos), sy(yat(pos)), 4, T.link, 0)
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
      local nspec = curve_spec({ kind = 'pts', smooth = cv.smooth, pts = pts })
      if nspec ~= spec then set(nspec) end
    elseif not act then
      CURVE_DRAG = nil
    end
    -- right-click a point (not an end): remove it; anywhere else: a menu to reset the curve
    if hov and ig.IsMouseClicked(ctx, 1) then
      local i = near()
      if i and i > 1 and i < #pts then
        table.remove(pts, i)
        set(curve_spec({ kind = 'pts', smooth = cv.smooth, pts = pts }))
      else
        ig.OpenPopup(ctx, 'crv_menu')
      end
    end
    if ig.BeginPopup(ctx, 'crv_menu') then
      if ig.MenuItem(ctx, 'Reset the curve (a straight line)') then
        set(curve_spec({ kind = 'pts', smooth = cv.smooth, pts = { { x = 0, y = 0 }, { x = 1, y = 1 } } }))
      end
      ig.EndPopup(ctx)
    end
    if hov then
      ig.SetTooltip(ctx, 'Click: add a point  \194\183  drag a point: move it  \194\183  right-click a point: remove it\n'
                      .. 'Right-click elsewhere: reset the curve')
    end
  end

  -- under the graph, as wide as it (captions included): the curve's strength or smoothing, then saving
  -- and (only when there are saved curves of your own) deleting one
  ig.Indent(ctx, pad)
  local spx = select(1, ig.GetStyleVar(ctx, ig.StyleVar_ItemSpacing()))
  if cv and cv.kind ~= 'pts' then
    field_caption('Strength', capw)
    ig.SetNextItemWidth(ctx, W - capw)
    local rv, k = ig.SliderDouble(ctx, '##crvk', cv.k, 1, 6, '%.1f')
    if rv then set(curve_spec({ kind = cv.kind, k = k })) end
  elseif cv then
    local rv, sm = ig.Checkbox(ctx, 'Smooth (off: straight lines)', cv.smooth)
    if rv then set(curve_spec({ kind = 'pts', smooth = sm, pts = cv.pts })) end
  end
  local lib = curve_lib()
  local half = (cv and #lib > 0) and (W - spx) / 2 or W
  if cv then
    if ig.Button(ctx, 'Save this curve...', half) then curve_prompt_save(spec) end
  end
  if #lib > 0 then
    if cv then ig.SameLine(ctx) end
    ig.SetNextItemWidth(ctx, half)
    if ig.BeginCombo(ctx, '##crvdel', 'Delete a curve...') then
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

  ig.Unindent(ctx, pad)
  ig.PopID(ctx)
  return out
end
