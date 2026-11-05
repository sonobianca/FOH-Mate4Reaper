-- FOHMate/window.lua: the Racks window and Settings window.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- window

-- carries out the drag and drop requests collected while drawing
function apply_pending()
  if #pending_ops > 0 then
    local ops = pending_ops
    pending_ops = {}
    with_undo('Rack: move/copy FX', function()
      for _, op in ipairs(ops) do
        local g, s = op.payload:match('^(.-)|(%d+)$')
        local src_tr = g and rack_by_guid(g)
        local src = tonumber(s)
        if src_tr and src and valid(op.dst_tr) then
          local moved_guid = reaper.TrackFX_GetFXGUID(src_tr, src)
          local landed
          if src_tr == op.dst_tr then
            if has_mod(COPY_MOD) then
              reaper.TrackFX_CopyToTrack(src_tr, src, op.dst_tr, op.dst, false)
              landed = reaper.TrackFX_GetFXGUID(op.dst_tr, op.dst)
            else
              move_fx(src_tr, src, op.dst)
              landed = moved_guid
            end
          elseif has_mod(MOVE_MOD) then
            reaper.TrackFX_CopyToTrack(src_tr, src, op.dst_tr, op.dst, true)
            landed = reaper.TrackFX_GetFXGUID(op.dst_tr, op.dst)
          else
            reaper.TrackFX_CopyToTrack(src_tr, src, op.dst_tr, op.dst, false)
            landed = reaper.TrackFX_GetFXGUID(op.dst_tr, op.dst)
          end
          -- the FX takes the width of its new place (mono/stereo version)
          if landed then
            fit_new_fx(op.dst_tr, landed)
            params_relink(op.dst_tr, landed)   -- a new instance takes back the rows of a deleted one
          end
        end
      end
    end)
  end

  if #pending_racks > 0 then
    local rr = pending_racks
    pending_racks = {}
    for _, r in ipairs(rr) do
      local src = rack_by_guid(r.src)
      if src and valid(r.dst) then
        if r.copy then
          -- duplicate, then put the copy where it was dropped (right after the original when dropped on itself)
          with_undo('Rack: duplicate by drag', function()
            local new = duplicate_rack(src)
            if new and r.dst ~= src then reorder_rack(new, r.dst) end
          end)
        else
          reorder_rack(src, r.dst)
        end
      end
    end
  end
end

-- the color picker and the confirmation dialog
function draw_dialogs()
  if picker.open then
    ig.OpenPopup(ctx, 'Color##picker')
    picker.open = false
  end
  if ig.BeginPopup(ctx, 'Color##picker') then
    if picker.kind == 'default' then
      ig.Text(ctx, 'Default rack color')
    elseif picker.kind == 'param' or picker.kind == 'fx' then
      ig.Text(ctx, picker.title or 'Parameter color')
    elseif picker.trs and #picker.trs > 1 then
      ig.Text(ctx, ('Color for the %d selected racks'):format(#picker.trs))
    else
      ig.Text(ctx, 'Rack color')
    end
    local rv, new = ig.ColorPicker3(ctx, '##cp', picker.rgb)
    if rv then
      picker.rgb = new
      local r, g, b = (new >> 16) & 255, (new >> 8) & 255, new & 255
      if picker.kind == 'rack' then
        for _, t in ipairs(picker.trs or {}) do
          if valid(t) then set_track_rgb(t, r, g, b) end
        end
      elseif picker.kind == 'param' then
        if valid(picker.tr) then params_set_color(picker.tr, picker.rows, new) end
      elseif picker.kind == 'fx' then
        if valid(picker.tr) then fxcol_set(picker.tr, picker.guid, new) end
      else
        S.default_rgb = new
        save_setting('defcolor', new)
      end
    end
    if picker.kind == 'param' then                       -- back to the FX's color (shifted for a group)
      if ig.Button(ctx, 'Automatic', 80, 0) and valid(picker.tr) then params_set_color(picker.tr, picker.rows, nil) end
      hint_hovered('The FX\'s color again (a group of parameters, like an EQ band, gets it slightly shifted)')
      ig.SameLine(ctx)
    elseif picker.kind == 'fx' then                      -- back to the rack's color
      if ig.Button(ctx, 'Automatic', 80, 0) and valid(picker.tr) then
        fxcol_set(picker.tr, picker.guid, nil)
        picker.rgb = track_color(picker.tr) >> 8
      end
      hint_hovered('The rack\'s color again')
      ig.SameLine(ctx)
    end
    if ig.Button(ctx, 'Close', 80, 0) then ig.CloseCurrentPopup(ctx) end
    ig.EndPopup(ctx)
  end

  local wx, wy = ig.GetWindowPos(ctx)
  local ww, wh = ig.GetWindowSize(ctx)
  MAIN_CENTER, MAIN_DOCKED = { wx + ww / 2, wy + wh / 2 }, ig.IsWindowDocked(ctx)
  draw_confirm('main')
end

-- the "Please confirm" box, drawn inside the window that asked for it (host)
function draw_confirm(host)
  if confirm and confirm.host == host then
    if confirm_open then
      ig.OpenPopup(ctx, 'Please confirm')
      confirm_open = false
    end
    local cx, cy
    if confirm.over_main and MAIN_CENTER then
      cx, cy = MAIN_CENTER[1], MAIN_CENTER[2]
    else
      local wx, wy = ig.GetWindowPos(ctx)
      local ww, wh = ig.GetWindowSize(ctx)
      cx, cy = wx + ww / 2, wy + wh / 2
    end
    ig.SetNextWindowPos(ctx, cx, cy, ig.Cond_Appearing(), 0.5, 0.5)
    local shown = ig.BeginPopupModal(ctx, 'Please confirm', nil, ig.WindowFlags_AlwaysAutoResize())
    if shown then
      type_text(confirm.text)
      if confirm.id then
        local label = (confirm.id == 'new_fx') and "Don't ask again (Latency > Ask to scan new FX)"
                      or "Don't show this again"
        local _, v = ig.Checkbox(ctx, label, confirm.dont_show)
        confirm.dont_show = v
        if ig.IsItemHovered(ctx) then
          ig.SetTooltip(ctx, 'From now on this is answered "' .. confirm.label .. '" without asking.\n'
                          .. 'Settings > Reset warning popups brings it back.')
        end
      end
      ig.Separator(ctx)
      local bw = confirm.alt and 150 or 110
      local yes = ig.Button(ctx, confirm.label, bw, 0)
      local alt = false
      if confirm.alt then
        ig.SameLine(ctx)
        alt = ig.Button(ctx, confirm.alt.label, bw, 0)
      end
      ig.SameLine(ctx)
      local no = ig.Button(ctx, 'Cancel', bw, 0)
      if yes or alt then
        local f = alt and confirm.alt.fn or confirm.yes
        if confirm.dont_show then hide_popup(confirm.id) end
        confirm = nil
        ig.CloseCurrentPopup(ctx)
        later[#later + 1] = function() f(); last_scan = -math.huge end   -- after the frame
      elseif no then
        confirm = nil
        ig.CloseCurrentPopup(ctx)
      end
      ig.EndPopup(ctx)
    elseif not confirm_open then
      confirm = nil      -- closed some other way (Escape): treat as Cancel
    end
  end
end

-- a horizontal gauge with a label on it; frac = nil means "not available"
function draw_gauge(dl, id, x, y, w, h, frac, label, tip)
  ig.DrawList_AddRectFilled(dl, x, y, x + w, y + h, T.meter_bg, ROUNDING)
  if frac and frac > 0 then
    local col = (frac < 0.6) and 0x40C060FF or ((frac < 0.85) and 0xE0C040FF or 0xE04040FF)
    ig.DrawList_AddRectFilled(dl, x, y, x + math.max(2, w * frac), y + h, col, ROUNDING)
  end
  ig.DrawList_AddRect(dl, x, y, x + w, y + h, T.bar_border, ROUNDING, 0, 1)
  local tw = ig.CalcTextSize(ctx, label)
  local lh = ig.GetTextLineHeight(ctx)
  ig.DrawList_AddText(dl, x + (w - tw) / 2, y + (h - lh) / 2, T.gauge_text, label)
  ig.SetCursorScreenPos(ctx, x, y)
  ig.InvisibleButton(ctx, id, w, h)
  if ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, tip) end
end

-- Debug timer (DEBUG_TIMER): how long the script takes per frame, from the start of loop() to the
-- end of the drawing (native dialogs left out), and how much of it the racks area takes. Shown in
-- the status bar, smoothed over about half a second, with the slowest frame of the last 2 seconds.
-- ReaImGui's own work putting the frame on screen comes after and isn't counted.
TIMER = { avg = 0, area = 0, area_avg = 0, peak = 0, peak_shown = 0, peak_t = 0 }

function timer_frame(t0)
  local now = reaper.time_precise()
  local d = now - t0
  TIMER.avg = TIMER.avg + (d - TIMER.avg) * 0.06
  TIMER.area_avg = TIMER.area_avg + (TIMER.area - TIMER.area_avg) * 0.06
  TIMER.peak = math.max(TIMER.peak, d)
  if now - TIMER.peak_t > 2 then
    TIMER.peak_shown, TIMER.peak, TIMER.peak_t = TIMER.peak, 0, now
  end
end

-- status bar: same size, border and color as the top bar
function draw_status_bar(dl, x, y, w, h, M, nracks, nfx, nparams)
  ig.DrawList_AddRect(dl, x, y, x + w, y + h, T.bar_border, ROUNDING, 0, 1)
  local gw = 140
  local gy = y + (h - M.fh) / 2
  local gx = x + 8

  local cpu_label = STATS.cpu and ('CPU %d%%'):format(math.floor(STATS.cpu + 0.5)) or 'CPU n/a'
  draw_gauge(dl, 'g_cpu', gx, gy, gw, M.fh, STATS.cpu and STATS.cpu / 100 or nil, cpu_label,
    STATS.cpu and 'REAPER process CPU, as a share of all cores'
              or 'Not available on this system')
  gx = gx + gw + 10

  local ram_label = STATS.ram_pct and ('RAM %d%%'):format(math.floor(STATS.ram_pct + 0.5)) or 'RAM n/a'
  local ram_tip = 'Not available on this system'
  if STATS.ram_mb then
    ram_tip = ('REAPER memory: %d MB'):format(math.floor(STATS.ram_mb + 0.5))
    if STATS.memtotal then ram_tip = ram_tip .. ('\nof %.1f GB installed'):format(STATS.memtotal / 1073741824) end
  end
  draw_gauge(dl, 'g_ram', gx, gy, gw, M.fh, STATS.ram_pct and STATS.ram_pct / 100 or nil, ram_label, ram_tip)
  gx = gx + gw + 14

  -- latency: "Latency: in [33] ms  -  out [11] ms", the numbers in gauge-style boxes
  local ty = y + (h - M.tlh) / 2
  local function label(s)
    ig.SetCursorScreenPos(ctx, gx, ty)
    ig.Text(ctx, s)
    gx = gx + ig.CalcTextSize(ctx, s) + 6
  end
  if STATS.lat_in and STATS.lat_out then
    local bw = ig.CalcTextSize(ctx, '0000') + 16
    label('Latency: in')
    draw_gauge(dl, 'g_lat_in', gx, gy, bw, M.fh, nil, ('%i'):format(STATS.lat_in), STATS.latency_tip)
    gx = gx + bw + 6
    label('ms  -  out')
    draw_gauge(dl, 'g_lat_out', gx, gy, bw, M.fh, nil, ('%i'):format(STATS.lat_out), STATS.latency_tip)
    gx = gx + bw + 6
    label('ms')
  else
    label('Latency: n/a')
  end

  -- debug timer: "Script [1.4] ms  -  racks [0.6] ms"
  if DEBUG_TIMER then
    gx = gx + 10
    local bw = ig.CalcTextSize(ctx, '00.0') + 16
    local tip = ('Debug timer (not in public versions)\n' ..
                 'Time FOH-Mate takes per frame: %.2f ms on average\n' ..
                 'of which the racks area (Performance parameters included): %.2f ms\n' ..
                 'Slowest frame of the last 2 seconds: %.2f ms'):format(
                 TIMER.avg * 1000, TIMER.area_avg * 1000, TIMER.peak_shown * 1000)
    label('Script')
    draw_gauge(dl, 'g_timer', gx, gy, bw, M.fh, nil, ('%.1f'):format(TIMER.avg * 1000), tip)
    gx = gx + bw + 6
    label('ms  -  racks')
    draw_gauge(dl, 'g_timer_area', gx, gy, bw, M.fh, nil, ('%.1f'):format(TIMER.area_avg * 1000), tip)
    gx = gx + bw + 6
    label('ms')
  end

  -- latency watchdog
  gx = gx + 10
  local la, left = alerts_state()
  local wtxt, wcol
  if la == 'on' and lat_over_racks > 0 then
    if flash_on(reaper.time_precise()) then
      wtxt, wcol = ('!! %d rack(s) over the latency limit'):format(lat_over_racks), ALERT_RED
    else
      wtxt = ''
    end
  elseif la == 'silenced' then
    wtxt = ('Latency alerts silenced (%d min)'):format(math.ceil(left / 60))
  elseif la == 'off' then
    wtxt = 'Latency alerts off'
  end
  local nowp = reaper.time_precise()
  if SCAN.last and nowp - SCAN.last_t < 8 then
    wtxt, wcol = SCAN.last, nil
  elseif SHOWOFF_MSG and nowp - SHOWOFF_MSG.t < 8 then
    wtxt, wcol = SHOWOFF_MSG.text, nil
  end
  local ww = 0
  if wtxt then
    local full = ('!! %d rack(s) over the latency limit'):format(math.max(lat_over_racks, 1))
    ww = math.max(ig.CalcTextSize(ctx, wtxt), la == 'on' and ig.CalcTextSize(ctx, full) or 0)
    if wtxt ~= '' then
      if wcol then
        ig.DrawList_AddText(dl, gx, ty, wcol, wtxt)
      else
        ig.SetCursorScreenPos(ctx, gx, ty)
        ig.TextDisabled(ctx, wtxt)
      end
    end
    if mouse_in(gx, y, gx + ww, y + h) then
      ig.SetTooltip(ctx, ('Latency limit: %d samples (Options > Settings...)\nSilence or switch alerts off in the Options menu.'):format(LAT_LIMIT))
    end
    gx = gx + ww
  end

  -- rack and FX counts, bottom right
  local counts = ('%d rack(s)  |  %d FX'):format(nracks or 0, nfx or 0)
  if nparams then counts = counts .. '  |  ' .. nparams end
  local cw = ig.CalcTextSize(ctx, counts)
  local cx = x + w - cw - 10
  if cx > gx + 12 then
    ig.SetCursorScreenPos(ctx, cx, ty)
    ig.TextDisabled(ctx, counts)
  end
end

-- The one gap between racks (sideways and down) and between the top bar and the
-- first row: the room the latency alert tag needs (it is centered on a rack's top
-- edge, so its top half sits in the gap above) plus Settings > Space between racks.
function rack_gap()
  return RACK_SPACE + math.max(GLOW_M, math.ceil((ig.GetTextLineHeight(ctx) + 2) / 2) + 1)
end

-- empty space: a click deselects the racks, a double-click offers a new rack
function empty_space_click(rects, limit)
  if ig.IsWindowHovered(ctx) then
    local mx, my = ig.GetMousePos(ctx)
    local over_rack = false
    for _, r in ipairs(rects) do
      if mx >= r[1] and mx <= r[3] and my >= r[2] and my <= r[4] then over_rack = true; break end
    end
    if not over_rack and mx < limit then
      if ig.IsMouseClicked(ctx, 0) then deselect_racks() end
      if ig.IsMouseDoubleClicked(ctx, 0) and not is_locked() then
        request_confirm('Create a new rack?', create_rack, 'Create', 'new_rack')
      end
    end
  end
end

-- the scrolling part: every rack, tiled
function draw_rack_area(infos, M, dt, now, avail)
  local x_left, y_top = ig.GetCursorScreenPos(ctx)
  local limit = x_left + avail                       -- the scrollbar starts here
  local wx = x_left + GLOW_M                         -- room around the racks for the selection glow
  local gap = rack_gap()
  local y = y_top + gap                              -- the area starts right under the top bar
  local rects = {}
  local grid_x, last_row_y, last_row_h, grid_cols_n = wx, y, 0, 1

  if #infos == 0 then
    ig.SetCursorScreenPos(ctx, wx, y)
    ig.Text(ctx, ('No tracks named "%s ..." found. Double-click here or use + to create a rack.'):format(PREFIX))
  else
    -- each row is as tall as its tallest rack
    local cols = math.max(1, math.floor((avail - 2 * GLOW_M + gap) / (RACK_W + gap)))
    local i = 1
    while i <= #infos do
      local row_h = 0
      for c = 0, cols - 1 do
        local inf = infos[i + c]
        if inf then row_h = math.max(row_h, inf.nat) end
      end
      -- the grid is centered as a whole: every row starts at the same left edge,
      -- so a shorter last row stays aligned with the row above it
      local grid_cols = math.min(cols, #infos)
      local grid_w = grid_cols * RACK_W + (grid_cols - 1) * gap
      local row_x = math.max(wx, x_left + math.floor((avail - grid_w) / 2))
      grid_x, last_row_y, last_row_h, grid_cols_n = row_x, y, row_h, cols
      for c = 0, cols - 1 do
        local inf = infos[i + c]
        if inf then
          local x = row_x + c * (RACK_W + gap)
          draw_rack(inf, x, y, row_h, M, dt, now)
          rects[#rects + 1] = { x, y, x + RACK_W, y + row_h }
        end
      end
      y = y + row_h + gap
      i = i + cols
    end
    y = y - gap
  end

  empty_space_click(rects, limit)

  -- a rack dropped in the empty space around or below the racks goes to the last position
  if drag_prev_rack and not is_locked() and #infos > 0 then
    local last = infos[#infos].tr
    local src = rack_by_guid(drag_prev_rack)
    local area_x, area_y = ig.GetWindowPos(ctx)
    local _, area_h = ig.GetWindowSize(ctx)
    local mx, my = ig.GetMousePos(ctx)
    local in_area = mx >= area_x and mx < limit and my >= area_y and my <= area_y + area_h
    local over_rack = false
    for _, r in ipairs(rects) do
      if mx >= r[1] and mx <= r[3] and my >= r[2] and my <= r[4] then over_rack = true; break end
    end
    local copying = has_mod(COPY_MOD)
    if src and (src ~= last or copying) and in_area and not over_rack then
      -- show the free cell the rack would land in
      local used = (#infos - 1) % grid_cols_n + 1
      local sx, sy
      if used < grid_cols_n then
        sx, sy = grid_x + used * (RACK_W + gap), last_row_y
      else
        sx, sy = grid_x, last_row_y + last_row_h + gap
      end
      local gdl = ig.GetWindowDrawList(ctx)
      ig.DrawList_AddRectFilled(gdl, sx, sy, sx + RACK_W, sy + last_row_h, (T.glow & 0xFFFFFF00) | 0x28, ROUNDING + 2)
      ig.DrawList_AddRect(gdl, sx, sy, sx + RACK_W, sy + last_row_h, (T.glow & 0xFFFFFF00) | 0xC0, ROUNDING + 2, 0, 3)
      if ig.IsMouseReleased(ctx, 0) then
        pending_racks[#pending_racks + 1] = { src = drag_prev_rack, dst = last, copy = copying }
      end
    end
  end

  -- extend the scrollable area to the bottom of the last row
  ig.SetCursorScreenPos(ctx, wx, y)
  ig.Dummy(ctx, 1, GLOW_M + 2)
end

-- Performance mode: a column under a rack, scrolling on its own. The rows will be the
-- rack's parameters; for now it holds the "+" row and, for testing, placeholder rows.
-- Where you are in the column shows twice: the rows fade out at an edge while there is
-- more beyond it, and a slim bar marks the position.
-- The band at the top widens the column over its neighbours (e = how far, 0 .. 1): the rows
-- then flow in several columns, top to bottom, that scroll sideways. Folded again, it is one
-- column that scrolls up and down, showing the row that was touched last.
function draw_perf_column(inf, x, y, w, h, M, ps, e)
  local tr = inf.tr
  local guid = reaper.GetTrackGUID(tr)
  -- the parameter window (inspector) just selected a parameter: when it is a row of this rack and the
  -- rack is out of view, the window scrolls sideways to bring the rack into view (once)
  local focus = PARAM_PICK and PARAM_PICK.focus
  local focus_k
  if focus then
    for k, r in ipairs(params_read(tr)) do
      if r.guid == focus.guid and r.idx == focus.idx then focus_k = k; break end
    end
    if focus_k and not focus.hdone then
      focus.hdone = true
      local wxp = ig.GetWindowPos(ctx)
      local wwp = ig.GetWindowSize(ctx)
      if x < wxp or x + w > wxp + wwp then ig.SetScrollX(ctx, ig.GetScrollX(ctx) + (x - wxp) - (wwp - w) / 2) end
    end
  end
  local c = rack_colors(track_color(tr), inf.bypassed)
  -- a widened column sits over its neighbours, so it is drawn inside a window of its own with an
  -- opaque background: drawn straight on the area it would lie underneath their windows
  local outer = false
  if e > 0 then
    ig.SetCursorScreenPos(ctx, x, y)
    ig.PushStyleColor(ctx, ig.Col_ChildBg(), c.bg)
    ig.PushStyleVar(ctx, ig.StyleVar_ChildRounding(), ROUNDING + 2)
    outer = true
    begin_child('wide' .. guid, w, h, ig.WindowFlags_NoScrollbar() | ig.WindowFlags_NoScrollWithMouse())
    ig.PopStyleVar(ctx)
    ig.PopStyleColor(ctx)
  end
  local pdl = ig.GetWindowDrawList(ctx)
  local ins = outer and 1 or 0                             -- the border stays inside that window
  ig.DrawList_AddRectFilled(pdl, x, y, x + w, y + h, c.bg, ROUNDING + 2)
  ig.DrawList_AddRect(pdl, x + ins, y + ins, x + w - ins, y + h - ins, c.border, ROUNDING + 2, 0, 2)

  -- the band at the top, like the handle under the FX section: two small triangles, back to
  -- back to widen, face to face to fold back. The whole width is the button.
  local bh = HANDLE_H + PAD
  ig.PushID(ctx, guid)
  local menu_w = is_locked() and 0 or 18                 -- Edit mode: the "..." menu takes the right corner
  ig.SetCursorScreenPos(ctx, x + 2, y + 2)
  if not ps.open then ps.pin = false end                 -- a pin only holds a widened section
  if ig.InvisibleButton(ctx, 'widen', w - 4 - menu_w, bh - 2) then
    ps.open = not ps.open
    ps.pin = false                                       -- clicked: the pin is gone
    PERF_ACT = reaper.time_precise()
    if ps.open then
      for g, o in pairs(PERF_PARAMS) do if g ~= guid then o.open = false end end   -- one at a time
      for _, f in pairs(PERF_FOLD) do f.open = false end                            -- FX sections fold first
    end
  end
  local pinned = ps.open and ps.pin
  if ig.IsItemClicked(ctx, 1) then                       -- right-click: pin it widened, or take the pin off
    PERF_ACT = reaper.time_precise()
    if pinned then
      ps.pin = false
    else
      if not ps.open then
        ps.open = true
        for g, o in pairs(PERF_PARAMS) do if g ~= guid then o.open = false end end
        for _, f in pairs(PERF_FOLD) do f.open = false end
      end
      ps.pin = true
    end
  end
  pinned = ps.open and ps.pin
  local band_hov = ig.IsItemHovered(ctx)
  if band_hov then
    ig.SetTooltip(ctx, pinned and 'Pinned open: click to fold it back' or (ps.open and 'Fold the parameters back' or 'Widen the parameters'))
  end
  hint_hovered(pinned
    and 'Pinned open: it stays widened until you click the band (which folds it)  \194\183  right-click: take the pin off, it folds back by itself again as set in Display > Fold automatically'
    or (ps.open
      and 'Click: fold the parameters back  \194\183  right-click: pin them widened (a push pin: they stay until you click the band); they fold back by themselves otherwise, as set in Display > Fold automatically'
      or 'Click: widen the parameters over the other columns (they fold back by themselves as set in Display > Fold automatically)  \194\183  right-click: widen them pinned'))
  -- the "..." in the right corner, above the position bar (Edit mode): clean up the parameters
  if menu_w > 0 then
    ig.SetCursorScreenPos(ctx, x + w - 2 - menu_w, y + 2)
    if ig.InvisibleButton(ctx, 'pmenu', menu_w, bh - 2) then
      PARAM_UNLINKED = params_unlinked(tr)                 -- found once, when the menu opens
      ig.OpenPopup(ctx, 'plus_menu')
    end
    local mhov = ig.IsItemHovered(ctx)
    if mhov then ig.SetTooltip(ctx, 'Parameter menu') end
    hint_hovered('Click: remove the parameters not linked any more, or all of them')
    local dcol = (c.name_txt & 0xFFFFFF00) | (mhov and 0xFF or 0xA0)
    local rx, dy = x + w - PAD - 1, math.floor(y + bh / 2) + 1   -- the dots end where the position bar ends
    for i = 0, 2 do ig.DrawList_AddCircleFilled(pdl, rx - 1.5 - i * 4, dy, 1.5, dcol) end
    if ig.BeginPopup(ctx, 'plus_menu') then draw_param_menu(tr); ig.EndPopup(ctx) end
  end
  ig.PopID(ctx)
  do
    local bx, by = math.floor(x + w / 2), math.floor(y + bh / 2) + 1
    local bcol = (c.name_txt & 0xFFFFFF00) | (band_hov and 0xFF or 0xA0)
    local tw, th, tg = 7, 4.5, 2.5
    -- both triangles are listed the same way round (tip, then the base from the same side), so they
    -- are filled and smoothed alike
    local function tri(base, tip)
      local flip = tip < base and -1 or 1
      ig.DrawList_AddTriangleFilled(pdl, tip, by, base, by + th * flip, base, by - th * flip, bcol)
    end
    if pinned then        -- a push pin in a contrasting color
      draw_pin(pdl, bx, by, contrast_glow(tr))
    elseif ps.open then   -- face to face: tips toward the middle
      tri(bx - tg - tw, bx - tg)
      tri(bx + tg + tw, bx + tg)
    else                  -- back to back: tips away from the middle
      tri(bx - tg, bx - tg - tw)
      tri(bx + tg, bx + tg + tw)
    end
  end

  ig.SetCursorScreenPos(ctx, x + PAD, y + bh)
  local no_bar = ig.WindowFlags_NoScrollbar()
  if begin_child('col' .. guid, w - 2 * PAD, h - bh - PAD, no_bar) then
    local dl = ig.GetWindowDrawList(ctx)
    local cx, cy = ig.GetWindowPos(ctx)
    local cw, ch = ig.GetWindowSize(ctx)
    local colw = RACK_W - 2 * PAD - 6 - PAD                -- width of a column of rows: room for the position bar (the gap left of it equals the gap right of it, 1 px + PAD)
    local grid = e > 0                                     -- widened (or moving): rows flow in columns
    local f = 1 + 0.5 * e                                  -- widened, every row is 1.5 times as wide and tall, with bigger text and controls
    local pad = 12 * e                                     -- and room around each row, to let it breathe
    local rw = colw * f
    local pushed = push_bold(name_font, NAME_FONT_SIZE)
    local blh0 = ig.GetTextLineHeight(ctx)                 -- bold line height: a name may take two lines
    if pushed then ig.PopFont(ctx) end
    local blh = blh0 * f
    local rh0 = math.floor(2 * blh0 + 12)
    local rh = math.floor(rh0 * f)
    local gy = select(2, ig.GetStyleVar(ctx, ig.StyleVar_ItemSpacing()))
    local pitch = rh + gy + pad                                  -- from one row to the next (the gap is the same stacked or in columns)
    -- the rows are the rack's saved parameter rows (picked in the "+" window, Edit mode)
    local now_t = reaper.time_precise()
    local rows = params_read(tr)
    local gmap = fx_guid_map(tr)
    local rack_col = track_color(tr)
    local n = #rows
    -- the rows shown, by their place in the list (Display > Hide disabled parameters leaves out
    -- the rows not linked any more); the layout counts only those
    local vis = {}
    for k, r in ipairs(rows) do
      if not (S.hide_dead and param_row_memo(tr, r, gmap[r.guid]).missing) then vis[#vis + 1] = k end
    end
    local nv = #vis
    local show_plus = not is_locked()                      -- the + row is only there in Edit mode
    local slots = nv + (show_plus and 1 or 0)
    local mx_in = ig.IsWindowHovered(ctx)
    -- a row of this column being dragged (Edit mode): where it comes from, and where it is dropped
    local row_drag = not is_locked() and drag_prev_row ~= nil and drag_prev_row:match('^(.-)|') == guid
    local row_from = row_drag and tonumber(drag_prev_row:match('|(%d+)$'))
    local in_col = row_drag and mouse_in(cx, cy, cx + cw, cy + ch)
    local row_drop
    ig.Dummy(ctx, 1, 3)                                    -- room for the glow of the first row
    local ox, oy = ig.GetCursorScreenPos(ctx)
    local step_x = rw + 4 + 2 * pad                                -- widened: from one column of rows to the next
    local rpc = math.max(1, math.floor((ch - 3 - 8 - 12) / (math.floor(rh0 * 1.5) + gy + 12))) -- rows per column when widened, as it fits at full size (rows 1.5 times as tall, 12 px of room) (8: the sideways bar)
    if grid then
      if ig.GetScrollY(ctx) ~= 0 then ig.SetScrollY(ctx, 0) end
      if mx_in then                                        -- the wheel moves sideways here too
        local wv, wh = ig.GetMouseWheel(ctx)
        if wv ~= 0 and wh == 0 then ig.SetScrollX(ctx, ig.GetScrollX(ctx) - wv * 60) end
      end
    else
      if ig.GetScrollX(ctx) ~= 0 then ig.SetScrollX(ctx, 0) end
      if ps.reveal > 0 then                                -- just folded back: show the row touched last
        local j = ps.last
        if j and nv < n then for i, k in ipairs(vis) do if k <= ps.last then j = i end end end
        if j then ig.SetScrollY(ctx, math.max(0, 3 + (j - 1) * pitch - (ch - rh) / 2)) end
        ps.reveal = ps.reveal - 1
      end
    end
    if focus_k then                                        -- ... and the column scrolls to the row, when it is out of view
      for jf, kf in ipairs(vis) do
        if kf == focus_k then
          if grid then
            local cxr = pad + math.floor((jf - 1) / rpc) * step_x
            local sx = ig.GetScrollX(ctx)
            if cxr < sx or cxr + rw > sx + cw then ig.SetScrollX(ctx, math.max(0, cxr - (cw - rw) / 2)) end
          else
            local top, sy = 3 + (jf - 1) * pitch, ig.GetScrollY(ctx)
            if top < sy or top + rh > sy + ch then ig.SetScrollY(ctx, math.max(0, top - (ch - rh) / 2)) end
          end
          PARAM_PICK.focus = nil
          break
        end
      end
    end
    for j = 1, nv do
      local k = vis[j]                                     -- j: its place in the column, k: in the rack's list
      local rx, ry
      if grid then
        rx, ry = ox + pad + math.floor((j - 1) / rpc) * step_x, oy + pad + ((j - 1) % rpc) * pitch
      else
        rx, ry = ig.GetCursorScreenPos(ctx)
      end
      if rx + rw > cx and rx < cx + cw and ry + rh > cy - 4 and ry < cy + ch + 4 then   -- rows outside the column's view aren't drawn (or asked about)
        local rx0 = rx
        rx = rx + 3; local rw2 = rw - 6                      -- a little room for the hover glow
        -- what this row shows: the real parameter (fxi = where its FX is now)
        local r = rows[k]
        local rname, vtxt, norm, fxi, missing, kind = r.name or r.pname, '?', 0, gmap[r.guid], false, nil
        -- what the plug-in said is kept per row (ROW_MEMO): the name check is done again every 30
        -- frames (half a second) or when the FX moved, the value's text when the value moved or every
        -- 30 frames (a plug-in may print it differently after another parameter changed)
        local mm = param_row_memo(tr, r, fxi)
        missing = mm.missing
        if not missing then
          norm = reaper.TrackFX_GetParamNormalized(tr, fxi, r.idx)
          if norm ~= mm.norm or FRAME - (mm.f_txt or -99) >= 30 then
            local _, txt = reaper.TrackFX_GetFormattedParamValue(tr, fxi, r.idx)
            mm.vtxt, mm.norm, mm.f_txt = param_vtext(txt, norm, r.pname, tr, fxi), norm, FRAME
          end
          vtxt = mm.vtxt
          kind = param_kind(tr, fxi, r)
        end
        local cd = rh - 8 * f                                    -- the control, outside the name box
        -- the value box between control and name, a little closer to the name (gap vn) than to the control (vc)
        local vw, vn, vc = 22 * f, 2.5 * f, 5.5 * f
        local box_w = rw2 - cd - vw - vn - vc
        local left = (j % 2 == 1)                            -- odd rows: name left; even rows: name right
        local bx = left and rx or (rx + rw2 - box_w)
        local kx = left and (rx + rw2 - cd) or rx
        local vx = left and (bx + box_w + vn) or (kx + cd + vc)
        -- hover: the whole row (name box and control) glows; the rows of an FX whose name is
        -- pointed at in the rack glow in another color
        local over = mx_in and mouse_in(rx, ry, rx + rw2, ry + rh)
        local hot = hot_prev_fx ~= nil and hot_prev_fx == r.guid
        -- a row being dragged over this column: the row under the pointer shows the place it would take
        -- (the window doesn't count as hovered while the drag is on, so the pointer is checked directly)
        local row_key = guid .. '|' .. k
        local drop_here = row_drag and in_col and mouse_in(rx, ry, rx + rw2, ry + rh) and drag_prev_row ~= row_key
        if row_drag then
          if drop_here and ig.IsMouseReleased(ctx, 0) then row_drop = k end
          over, hot = false, false
        end
        if over then row_hot_now = r.guid end                -- its FX glows in the rack
        if over and ig.IsMouseClicked(ctx, 0) then
          ps.last = k                                        -- the row touched last
          if fxi then param_pick_select(tr, r) end          -- the parameter window, if open, selects it
        end
        -- double-click its name or value box (not the control: there it goes back to the default mark):
        -- the parameter window opens on it (Edit mode; it is the same window as the + opens)
        if fxi and over and not is_locked() and ig.IsMouseDoubleClicked(ctx, 0)
           and mouse_in(left and bx or vx, ry, left and (vx + vw) or (bx + box_w), ry + rh) then
          param_picker_open(tr, nil, 'insp')
          param_pick_select(tr, r)
        end
        if over and ig.IsMouseClicked(ctx, 1) and not is_locked() then      -- Edit mode: the row's menu
          PARAM_MENU_ROW = k
          ig.OpenPopup(ctx, 'prm_menu')
        end
        -- the parameter window's selection glows like the pointed row (the white glow)
        local picked = PARAM_PICK and PARAM_PICK.hl and PARAM_PICK.hl[r.guid .. ':' .. r.idx]
        if over or (picked and not row_drag) then
          local base = T.glow & 0xFFFFFF00
          for i = 1, 3 do
            local a = math.floor(170 * (1 - (i - 1) / 3) ^ 2)
            ig.DrawList_AddRect(dl, rx - i, ry - i, rx + rw2 + i, ry + rh + i, base | a, ROUNDING + i, 0, 1)
          end
        elseif hot then                                      -- its FX is pointed at: it glows in the FX's color
          draw_link_glow(dl, rx, ry, rx + rw2, ry + rh, fx_color(tr, r.guid, rack_col), ROUNDING)
        end
        -- the row's colors: its own (Recolor parameters), or the rack's, shifted a little for a group of
        -- parameters such as an EQ band (param_row_color); worked out again only when one of them changes
        local rcol = param_row_color(fx_color(tr, r.guid, rack_col), r)
        if over then row_hot_col_now = rcol end              -- its FX glows in this color
        local ckey = rcol .. '|' .. tostring(inf.bypassed) .. '|' .. tostring(S.daylight)
        if mm.ckey ~= ckey then mm.ckey, mm.rc = ckey, rack_colors(rcol, inf.bypassed) end
        local rc = mm.rc
        ig.DrawList_AddRectFilled(dl, bx, ry, bx + box_w, ry + rh, rc.name_bg, ROUNDING)
        ig.DrawList_AddRect(dl, bx, ry, bx + box_w, ry + rh, rc.sec_bd, ROUNDING, 0, 1)
        -- the name: bold, up to two lines
        local pb = push_bold(name_font, NAME_FONT_SIZE * f)
        -- the two lines and their widths are kept until the name, the box or the size change
        local wkey = rname .. '|' .. box_w .. '|' .. f
        if mm.wkey ~= wkey then
          local l1, l2 = rname, nil
          if ig.CalcTextSize(ctx, l1) > box_w - 8 then
            local cut = l1
            while #cut > 1 and ig.CalcTextSize(ctx, cut) > box_w - 8 do
              cut = cut:match('^(.*)%s+%S*$') or cut:sub(1, #cut - 1)
            end
            l2 = fit_text((l1:sub(#cut + 1):gsub('^%s+', '')), box_w - 8)
            l1 = cut
          end
          mm.wkey, mm.l1, mm.l2 = wkey, l1, l2
          mm.w1, mm.w2 = ig.CalcTextSize(ctx, l1), l2 and ig.CalcTextSize(ctx, l2)
        end
        local l1, l2 = mm.l1, mm.l2
        local ty = ry + (rh - blh * (l2 and 2 or 1)) / 2
        ig.DrawList_AddText(dl, bx + (box_w - mm.w1) / 2, ty, rc.name_txt, l1)
        if l2 then ig.DrawList_AddText(dl, bx + (box_w - mm.w2) / 2, ty + blh, rc.name_txt, l2) end
        if pb then ig.PopFont(ctx) end
        -- Edit mode: the name box is the handle to drag the row to another place in its column
        if not is_locked() then
          ig.SetCursorScreenPos(ctx, bx, ry)
          ig.InvisibleButton(ctx, '##prow' .. k, box_w, rh)
          hint_hovered('Drag: reorder  \194\183  right-click: control for this parameter, remove it')
          if ig.BeginDragDropSource(ctx) then
            ig.SetDragDropPayload(ctx, 'PERFROW', row_key)
            drag_now_row = row_key
            draw_fx_ghost(rname, '', box_w, M.fh)
            ig.EndDragDropSource(ctx)
          end
        end
        -- the control, a little further out than the middle of its box to leave room for the marks;
        -- in the middle when it has the arc of its limits (Limit values without the full range), which
        -- reaches farther out: it then stays inside the column and clear of the value box
        local arc = r.lim == 'mm' and kind and param_limit_ok(kind.kind) and not (r.fit and param_fit_ok(kind.kind))
        local kcx = kx + cd / 2 + (arc and 0 or (left and 1 or -1) * 3 * f)
        local kcy, kr = ry + rh / 2, cd / 2 - 6 * f
        local dead = missing or not fxi
        local newv
        -- a Pan/Width that follows a stereo placement: a pan, a width, or switched off, as it says now
        local ekind, off = kind and kind.kind, false
        if kind and kind.dual and not dead then
          if FRAME - (mm.f_mode or -99) >= 15 then             -- asked again every quarter second
            mm.mode, mm.f_mode = param_dual_mode(tr, fxi, kind), FRAME
          end
          local m = mm.mode
          if m == 'off' then off = true elseif m then ekind = m end
          -- some plug-ins keep printing L / R in MS: there it reads M / S
          -- ("100L", "L100", "-50 L", "Left 30"...: an L or R on its own, or the words Left / Right)
          if m == 'band' then
            vtxt = vtxt:gsub('%f[%a][Ll][Ee][Ff][Tt]%f[%A]', 'M'):gsub('%f[%a][Rr][Ii][Gg][Hh][Tt]%f[%A]', 'S')
                       :gsub('%f[%a][Ll]%f[%A]', 'M'):gsub('%f[%a][Rr]%f[%A]', 'S')
          end
        end
        -- the value, a quarter turn: counterclockwise when the control is on the left, clockwise on the right
        if ry + rh > cy and ry < cy + ch then
          ig.DrawList_AddRectFilled(dl, vx, ry, vx + vw, ry + rh, rc.sec_bg, ROUNDING)
          ig.DrawList_AddRect(dl, vx, ry, vx + vw, ry + rh, rc.sec_bd, ROUNDING, 0, 1)
          draw_vtext(dl, vtxt, vx, ry, vw, rh, contrast_text(rc.sec_bg, rcol), not left, f, mm)
        end
        -- Limit values, list: a stepped encoder or a drop-down of the listed values (param_list_view)
        local lv = not dead and kind and param_list_view(tr, fxi, r, kind.kind, mm, norm, kind)
        if off then
          draw_encoder('k' .. k, kcx, kcy, kr, norm, { body = rc.sec_bg, col = rc.border, ptr = T.dim, s = f, static = true,
                       style = 'pan' })
          if over then ig.SetTooltip(ctx, 'Not used with this stereo placement') end
        elseif dead then
          draw_encoder('k' .. k, kcx, kcy, kr, 0, { body = rc.sec_bg, col = rc.border, ptr = T.dim, s = f, static = true })
          ig.DrawList_AddRectFilled(dl, rx, ry, rx + rw2, ry + rh, (c.bg & 0xFFFFFF00) | 0xB0, ROUNDING)
          if over then ig.SetTooltip(ctx, 'This parameter is not there any more (the FX was removed or changed).') end
        elseif lv and lv.show == 'list' then
          newv = draw_dropdown('k' .. k, kcx, kcy, kr, lv.items[lv.pos].norm, lv.items, { body = rc.sec_bg, col = rc.border, ptr = T.dots, s = f })
        elseif lv then
          local n_ = #lv.items
          local c_ = draw_encoder('k' .. k, kcx, kcy, kr, (lv.pos - 1) / (n_ - 1), { body = rc.sec_bg, col = rc.border, ptr = T.dots, s = f,
                                  style = 'line', steps = n_, def = lv.def })
          if c_ then newv = lv.items[math.floor(c_ * (n_ - 1) + 0.5) + 1].norm end
        elseif kind.kind == 'list' then
          newv = draw_dropdown('k' .. k, kcx, kcy, kr, norm, kind.items, { body = rc.sec_bg, col = rc.border, ptr = T.dots, s = f })
        else
          -- the control shows (and sets) the value through the row's invert and limits (param_to_ctl),
          -- and its curve (curves.lua): the drag moves evenly along the curve (cpos), the encoder
          -- shows the value it gives, rising and falling with the curve
          local cv = param_curve_of(r, ekind)
          local shown = param_to_ctl(r, ekind, norm)
          local cpos = cv and curve_ctl_pos(cv, shown, mm, kind.steps)
          if kind.kind == 'toggle' then
            local d = 2 * (kr + 3 * f)
            if circle_check(dl, 'k' .. k, kcx - d / 2, kcy - d / 2, d, shown > 0.5) then newv = shown > 0.5 and 0 or 1 end
          else
            local marks, def, range = param_ctl_view(r, ekind, kind.marks)
            newv = draw_encoder('k' .. k, kcx, kcy, kr, shown, { body = rc.sec_bg, col = rc.border, ptr = T.dots, s = f,
                                style = ekind == 'pan' and 'pan' or (ekind == 'band' or ekind == 'qband') and 'band' or 'line', narrow = ekind == 'qband', steps = kind.steps, marks = marks,
                                def = def, range = range, curve = cv, pos = cpos, def_pos = cv and def and curve_inv(cv, def, cpos),
                                show = mm })
          end
          if newv then
            if cv then newv = curve_ctl_value(cv, newv, mm, kind.steps) end
            newv = param_from_ctl(r, ekind, newv)
          end
        end
        if drag_prev_row == row_key then
          -- the row being dragged stays behind, faded
          ig.DrawList_AddRectFilled(dl, rx, ry, rx + rw2, ry + rh, S.daylight and 0xFFFFFF99 or 0x00000099, ROUNDING)
        elseif drop_here then
          -- the place the dragged row would take
          ig.DrawList_AddRect(dl, rx - 1, ry - 1, rx + rw2 + 1, ry + rh + 1, T.glow, ROUNDING, 0, 2)
        end
        if newv then
          reaper.TrackFX_SetParamNormalized(tr, fxi, r.idx, newv)
          ps.last = k
          PERF_ACT = now_t
        end
        ig.SetCursorScreenPos(ctx, rx0, ry)
      end
      if not grid then ig.Dummy(ctx, rw, rh) end
    end
    -- widened: a divider between the columns of rows, fading in with the widening
    if grid then
      local dcol = (c.border & 0xFFFFFF00) | math.floor(0x90 * e)
      for col = 0, math.ceil(slots / rpc) - 2 do
        local dx = ox + pad + col * step_x + rw + 2 + pad
        if dx > cx - 2 and dx < cx + cw + 2 then
          ig.DrawList_AddLine(dl, dx, oy + pad, dx, oy + pad + rpc * pitch - gy, dcol, 2)
        end
      end
    end
    -- the empty row at the end, Edit mode only: a "+" in a circle as tall as a row, in the color of
    -- the names. It opens the parameter window. Only the circle and the + light up.
    if show_plus then
      local px, py
      if grid then
        px, py = ox + pad + math.floor(nv / rpc) * step_x, oy + pad + (nv % rpc) * pitch
      else
        px, py = ig.GetCursorScreenPos(ctx)
      end
      ig.SetCursorScreenPos(ctx, px + (rw - rh) / 2, py)
      if ig.InvisibleButton(ctx, '##addparam', rh, rh) then param_picker_open(tr) end
      local hov = ig.IsItemHovered(ctx)
      local pcx, pcy, pr = px + rw / 2, py + rh / 2, rh / 2 - 2
      -- a dragged row dropped here goes to the end
      if row_drag and in_col and mouse_in(px + 3, py, px + rw - 3, py + rh) and row_from ~= n then
        ig.DrawList_AddRect(dl, px + 2, py - 1, px + rw - 2, py + rh + 1, T.glow, ROUNDING, 0, 2)
        if ig.IsMouseReleased(ctx, 0) then row_drop = n + 1 end
      end
      local pcol = (c.name_txt & 0xFFFFFF00) | (hov and 0xFF or 0xB0)
      if hov then ig.DrawList_AddCircleFilled(dl, pcx, pcy, pr, (c.name_txt & 0xFFFFFF00) | 0x30, 0) end
      ig.DrawList_AddCircle(dl, pcx, pcy, pr, pcol, 0, hov and 3 or 2)
      local pl = pr * 0.45
      ig.DrawList_AddLine(dl, pcx - pl, pcy, pcx + pl, pcy, pcol, hov and 3 or 2)
      ig.DrawList_AddLine(dl, pcx, pcy - pl, pcx, pcy + pl, pcol, hov and 3 or 2)
      if hov then ig.SetTooltip(ctx, 'Add or remove parameters') end
      hint_hovered('Click: add or remove parameters')
    end
    if row_drop and row_from then                          -- the rows are rewritten once the frame is drawn
      local to = row_drop
      later[#later + 1] = function() if valid(tr) then params_move(tr, row_from, to) end end
      ps.last = math.min(to, n)
    end
    if ig.BeginPopup(ctx, 'prm_menu') then                  -- right-click on a row (Edit mode): its control, or remove it
      local mr = rows[PARAM_MENU_ROW or 0]
      local mfx = mr and gmap[mr.guid]
      if mr and mfx and ig.BeginMenu(ctx, 'Control') then
        local mk = param_kind(tr, mfx, mr)
        for _, o in ipairs(PARAM_CONTROL_OPTS) do
          local on = (o[1] == nil and not mk.overridden) or (o[1] ~= nil and mk.overridden and mk.kind == o[1])
          local label = o[2] .. ((o[1] == nil) and (' (now: ' .. PARAM_KIND_LABEL[mk.guess] .. ')') or '')
          if ig.MenuItem(ctx, label, nil, on) then param_set_override(tr, mfx, mr, o[1]) end
        end
        ig.EndMenu(ctx)
      end
      if mr then
        ig.Separator(ctx)
        if ig.MenuItem(ctx, 'Nickname parameter...') then param_prompt_nick(tr, mr.guid, mr.idx) end
        if ig.BeginMenu(ctx, 'Recolor parameters') then
          local one = { { guid = mr.guid, idx = mr.idx } }
          if ig.MenuItem(ctx, 'This parameter...') then param_open_picker(tr, one, 'Color of this parameter') end
          -- the rows of the same group (Band 1...) of the same FX, and every row of the FX
          local gnum, glabel = param_group(mr.pname)
          local same_g, same_fx = {}, {}
          for _, rr in ipairs(rows) do
            if rr.guid == mr.guid then
              same_fx[#same_fx + 1] = { guid = rr.guid, idx = rr.idx }
              if gnum and param_group(rr.pname) == gnum then same_g[#same_g + 1] = { guid = rr.guid, idx = rr.idx } end
            end
          end
          if #same_g > 1 and #same_g < #same_fx then
            local t = ('Every "%s" parameter (%d)...'):format(glabel, #same_g)
            if ig.MenuItem(ctx, t) then param_open_picker(tr, same_g, ('Color of the "%s" parameters'):format(glabel)) end
          end
          if #same_fx > 1 then
            local fxn = mfx and clean_fx_name(select(2, reaper.TrackFX_GetFXName(tr, mfx, ''))) or 'this FX'
            if ig.MenuItem(ctx, ('Every parameter of %s (%d)...'):format(fxn, #same_fx)) then
              param_open_picker(tr, same_fx, 'Color of the parameters of ' .. fxn)
            end
          end
          ig.EndMenu(ctx)
        end
        if mfx and ig.MenuItem(ctx, 'Inspect parameter...') then
          param_picker_open(tr, 'p:' .. mr.guid .. ':' .. mr.idx, 'insp')
        end
        ig.Separator(ctx)
      end
      if ig.MenuItem(ctx, 'Remove this parameter') and rows[PARAM_MENU_ROW or 0] then
        local mrow = rows[PARAM_MENU_ROW]
        params_apply(tr, { { guid = mrow.guid, idx = mrow.idx, name = mrow.pname } }, false)
      end
      ig.EndPopup(ctx)
    end
    if grid then                                           -- the area the columns take, for the sideways scroll
      ig.SetCursorScreenPos(ctx, ox, oy)
      ig.Dummy(ctx, math.ceil(slots / rpc) * step_x + pad, rpc * pitch + pad)
    else
      ig.Dummy(ctx, 1, 3)
    end

    -- a bypassed rack: its parameters are greyed out too (still usable)
    if inf.bypassed then
      ig.DrawList_AddRectFilled(dl, cx, cy, cx + cw, cy + ch, (c.bg & 0xFFFFFF00) | 0x99, 0)
    end

    -- fade at the edges and the position bar
    local sy, smax = ig.GetScrollY(ctx), ig.GetScrollMaxY(ctx)
    if grid then
      local sx, smx = ig.GetScrollX(ctx), ig.GetScrollMaxX(ctx)
      if smx > 1 then
        local fw = math.min(M.fh * 1.8, cw / 3)
        local solid, clear = c.bg, c.bg & 0xFFFFFF00
        if sx > 1 then
          ig.DrawList_AddRectFilledMultiColor(dl, cx, cy, cx + fw, cy + ch, solid, clear, clear, solid)
        end
        if sx < smx - 1 then
          ig.DrawList_AddRectFilledMultiColor(dl, cx + cw - fw, cy, cx + cw, cy + ch, clear, solid, solid, clear)
        end
        local by = cy + ch - 5
        local thumb = math.max(16, cw * cw / (cw + smx))
        local tx = cx + (cw - thumb) * (sx / smx)
        ig.DrawList_AddRectFilled(dl, cx, by, cx + cw, by + 4, (T.dim & 0xFFFFFF00) | 0x40, 2)
        ig.DrawList_AddRectFilled(dl, tx, by, tx + thumb, by + 4, (T.dim & 0xFFFFFF00) | 0xE0, 2)
      end
    elseif smax > 1 then
      local fh_ = math.min(M.fh * 1.8, ch / 3)
      local solid, clear = c.bg, c.bg & 0xFFFFFF00
      if sy > 1 then
        ig.DrawList_AddRectFilledMultiColor(dl, cx, cy, cx + cw, cy + fh_, solid, solid, clear, clear)
      end
      if sy < smax - 1 then
        ig.DrawList_AddRectFilledMultiColor(dl, cx, cy + ch - fh_, cx + cw, cy + ch, clear, clear, solid, solid)
      end
      local bx = cx + cw - 5
      local thumb = math.max(16, ch * ch / (ch + smax))
      local ty = cy + (ch - thumb) * (sy / smax)
      ig.DrawList_AddRectFilled(dl, bx, cy, bx + 4, cy + ch, (T.dim & 0xFFFFFF00) | 0x40, 2)
      ig.DrawList_AddRectFilled(dl, bx, ty, bx + 4, ty + thumb, (T.dim & 0xFFFFFF00) | 0xE0, 2)
    end
    ig.EndChild(ctx)
  end
  if outer then ig.EndChild(ctx) end
end

-- the "..." menu of a rack's parameters (Edit mode)
function draw_param_menu(tr)
  local n = #params_read(tr)

  local nu = PARAM_UNLINKED and #PARAM_UNLINKED or 0
  local label = nu > 0 and ('Remove the %d parameter%s not linked any more'):format(nu, nu == 1 and '' or 's')
                        or 'Every parameter is linked: nothing to remove'
  if ig.MenuItem(ctx, label, nil, false, nu > 0) then params_apply(tr, PARAM_UNLINKED, false) end
  ig.Separator(ctx)
  if ig.MenuItem(ctx, 'Clear all', nil, false, n > 0) then
    request_confirm(('Remove all %d parameter%s of this rack from the Performance?\n(Ctrl+Z brings them back.)')
                    :format(n, n == 1 and '' or 's'),
      function()
        if valid(tr) then with_undo('Clear Performance parameters', function() params_drop_fx(tr, nil) end) end
      end, 'Clear all')
  end
end

-- Performance mode, Show mode: each rack folds its FX section under the name. The state per
-- rack: open (what was asked) and t (0 folded .. 1 open, moving toward it so it animates).
PERF_FOLD, PERF_ACT, PERF_MX, PERF_MY, PERF_FRAME, PERF_FOLD_SECS = {}, 0, 0, 0, 0, 0.2

-- the same for a rack's parameter column: open = widened (asked for), t = how far it is,
-- last = the row touched last, reveal = frames left to scroll to it after folding back
PERF_PARAMS = {}

function perf_param_state(guid)
  local st = PERF_PARAMS[guid]
  if not st then st = { open = false, t = 0, last = nil, reveal = 0 }; PERF_PARAMS[guid] = st end
  return st
end

function perf_fold_state(guid)
  local st = PERF_FOLD[guid]
  if not st then st = { open = false, t = 0 }; PERF_FOLD[guid] = st end
  return st
end

-- every key ReaImGui knows (but not the mouse and the modifier flags), for the idle timer
function perf_keys()
  if not PERF_KEYS then
    PERF_KEYS = {}
    for name, fn in pairs(reaper) do
      if type(name) == 'string' and name:find('^ImGui_Key_')
         and not (name:find('Mouse') or name:find('Mod') or name:find('Reserved') or name:find('None')
                  or name:find('Gamepad') or name:find('KeysData') or name:find('COUNT')) then
        local ok, v = pcall(fn)
        if ok and type(v) == 'number' then PERF_KEYS[#PERF_KEYS + 1] = v end
      end
    end
  end
  return PERF_KEYS
end

-- the last time the user was active in the Racks window: moved the mouse over it, clicked
-- or dragged, scrolled, or pressed a key while it has the focus. Nothing outside the window
-- counts. Keys are only looked at while a section is open, and every third frame.
function perf_activity(now, any_open)
  local mx, my = ig.GetMousePos(ctx)
  if ig.IsWindowHovered(ctx, ig.HoveredFlags_ChildWindows()) then
    local wv, wh = ig.GetMouseWheel(ctx)
    if mx ~= PERF_MX or my ~= PERF_MY or wv ~= 0 or wh ~= 0
       or ig.IsMouseDown(ctx, 0) or ig.IsMouseDown(ctx, 1) then
      PERF_ACT = now
    end
  end
  PERF_MX, PERF_MY = mx, my
  PERF_FRAME = PERF_FRAME + 1
  if any_open and PERF_FRAME % 3 == 0 then
    for _, k in ipairs(perf_keys()) do
      if ig.IsKeyDown(ctx, k) then PERF_ACT = now; break end
    end
  end
end

-- Performance mode: every rack in one row (it scrolls sideways), a column under each.
-- In Show mode a rack is just its name until its handle is clicked; its column moves with it.
function draw_perf_area(infos, M, dt, now)
  local x_left, y_top = ig.GetCursorScreenPos(ctx)
  local gap = rack_gap()
  local wx = x_left + GLOW_M
  local y = y_top + gap
  local rects = {}

  if #infos == 0 then
    ig.SetCursorScreenPos(ctx, wx, y)
    ig.Text(ctx, ('No tracks named "%s ..." found. Double-click here or use + to create a rack.'):format(PREFIX))
    empty_space_click(rects, math.huge)
    return
  end

  local compact = perf_compact()
  local any_open = false
  if compact then
    for _, inf in ipairs(infos) do
      if perf_fold_state(reaper.GetTrackGUID(inf.tr)).open then any_open = true; break end
    end
  end
  for _, ps in pairs(PERF_PARAMS) do if ps.open then any_open = true; break end end
  perf_activity(now, any_open)
  -- no activity for a while: the FX sections and parameter sections fold back, except the ones pinned
  -- open (right-click the handle). Show mode, as set in Display > Fold automatically (Settings >
  -- Performance mode); Edit mode only when Settings says so.
  local after = CFG.perf_fold_after
  if any_open and CFG.perf_fold_auto ~= 0 and (is_locked() or CFG.perf_fold_edit ~= 0)
     and after > 0 and now - PERF_ACT >= after then
    for _, st in pairs(PERF_FOLD) do if not st.pin then st.open = false end end
    for _, ps in pairs(PERF_PARAMS) do if not ps.pin then ps.open = false end end
  end

  local row_h = 0                                  -- Edit mode: full racks, all as tall as the tallest
  for _, inf in ipairs(infos) do row_h = math.max(row_h, inf.nat) end
  local total_w = 2 * GLOW_M + #infos * RACK_W + (#infos - 1) * gap
  local win_x, win_y = ig.GetWindowPos(ctx)
  local win_w, win_h = ig.GetWindowSize(ctx)
  local sbw = ig.GetStyleVar(ctx, ig.StyleVar_ScrollbarSize())
  local bottom = win_y + win_h - (total_w > win_w and sbw or 0) - 2     -- above the sideways scrollbar
  local folded = folded_height(M)
  local deepest = y
  local wide = {}                                  -- widened columns are drawn last, over the others
  local fx_folded = true                           -- parameters widen only once every FX section is folded
  for _, st in pairs(PERF_FOLD) do if st.t > 0 then fx_folded = false; break end end
  local vis_w = math.max(RACK_W, win_w - 2 * GLOW_M)

  for i, inf in ipairs(infos) do
    local x = wx + (i - 1) * (RACK_W + gap)
    local H, vh = row_h, row_h
    if compact then
      local st = perf_fold_state(reaper.GetTrackGUID(inf.tr))
      local target = st.open and 1 or 0
      local step = math.min(dt, 0.05) / PERF_FOLD_SECS
      if st.t < target then st.t = math.min(target, st.t + step) elseif st.t > target then st.t = math.max(target, st.t - step) end
      local e = st.t * st.t * (3 - 2 * st.t)           -- smoothstep: eases in and out
      H = inf.nat
      vh = folded + (H - folded) * e
    else
      perf_fold_state(reaper.GetTrackGUID(inf.tr)).open = false
      perf_fold_state(reaper.GetTrackGUID(inf.tr)).t = 0
    end
    draw_rack(inf, x, y, H, M, dt, now, vh)
    rects[#rects + 1] = { x, y, x + RACK_W, y + vh }
    local col_y = y + vh + gap                     -- the same gap as between racks
    local ps = perf_param_state(reaper.GetTrackGUID(inf.tr))
    if ps.open and not fx_folded then
      -- wait for the FX sections to finish folding
    elseif ps.open then
      ps.t = math.min(1, ps.t + math.min(dt, 0.05) / PERF_FOLD_SECS)
    elseif ps.t > 0 then
      ps.t = math.max(0, ps.t - math.min(dt, 0.05) / PERF_FOLD_SECS)
      if ps.t == 0 then ps.reveal = 2 end
    end
    local pe = ps.t * ps.t * (3 - 2 * ps.t)
    local col_h = math.max(60, bottom - col_y)
    if pe > 0 then
      wide[#wide + 1] = { inf, x, col_y, col_h, ps, pe }
    else
      draw_perf_column(inf, x, col_y, RACK_W, col_h, M, ps, 0)
    end
    deepest = math.max(deepest, col_y + col_h)
  end
  for _, wd in ipairs(wide) do
    local inf, x, col_y, col_h, ps, pe = table.unpack(wd)
    local left = win_x + GLOW_M
    draw_perf_column(inf, x + (left - x) * pe, col_y, RACK_W + (vis_w - RACK_W) * pe, col_h, M, ps, pe)
  end

  empty_space_click(rects, math.huge)

  -- make the area as wide as the racks (the sideways scrollbar follows), as tall as the columns
  ig.SetCursorScreenPos(ctx, x_left, deepest)
  ig.Dummy(ctx, total_w, 1)
end

-- the grey help line: what the mouse can do with what is under it, or with what is being dragged
function draw_hint(dl, x, y, w)
  local copy, move = mod_label(COPY_MOD), mod_label(MOVE_MOD)
  if drag_prev_row then
    HINT = 'Moving the parameter: drop it on the parameter whose place it takes, or on the + to put it at the end'
  elseif drag_prev_rack then
    if has_mod(COPY_MOD) then
      HINT = ('Duplicating the rack: drop it where the copy should go  \194\183  let go of %s to move it instead'):format(copy)
    else
      HINT = ('Moving the rack: drop it on another rack, or after the last one  \194\183  hold %s to duplicate it instead'):format(copy)
    end
  elseif drag_prev_fx then
    local src = drag_prev_fx:match('^(.-)|')
    local other = hover_prev_rack ~= nil and hover_prev_rack ~= src
    if other then
      if drag_copies() then
        HINT = ('Copying the FX to this rack: drop it on an FX or on empty space  \194\183  hold %s to move it here instead'):format(move)
      else
        HINT = ('Moving the FX to this rack  \194\183  let go of %s to copy it instead'):format(move)
      end
    elseif drag_copies() then
      HINT = ('Copying the FX: drop it where the copy should go  \194\183  let go of %s to move it instead'):format(copy)
    else
      HINT = ('Moving the FX: drop it on the FX whose place it takes  \194\183  hold %s to copy it  \194\183  drop on another rack: copy (%s: move)')
             :format(copy, move)
    end
  end
  local txt = HINT
  if not txt then
    txt = is_locked() and 'Show mode: level, mute, bypass and FX on/off work; everything else is locked'
                      or 'Point at anything to see what the mouse can do with it  \194\183  double-click empty space: new rack'
  end
  ig.DrawList_AddText(dl, x, y, ig.GetStyleColor(ctx, ig.Col_TextDisabled()), fit_text(txt, w))
end

-- BeginChild takes a number (child flags) in recent ReaImGui and a boolean
-- (border) in older ones; try the number first and remember what works.
child_old_api = false
function begin_child(id, w, h, wflags)
  if not child_old_api then
    local ok, vis = pcall(ig.BeginChild, ctx, id, w, h, 0, wflags or 0)
    if ok then return vis end
    child_old_api = true
  end
  return ig.BeginChild(ctx, id, w, h, false, wflags or 0)
end

function draw(dt, now)
  drag_prev_rack, drag_prev_fx = drag_now_rack, drag_now_fx
  drag_now_rack, drag_now_fx = nil, nil
  drag_prev_row, drag_now_row = drag_now_row, nil
  hover_prev_rack, hover_now_rack = hover_now_rack, nil
  hot_prev_fx, hot_now_fx = hot_now_fx, nil
  row_hot_prev, row_hot_now = row_hot_now, nil
  row_hot_col_prev, row_hot_col_now = row_hot_col_now, nil
  lat_over_racks = 0
  HINT = nil

  local M  = metrics()
  local dl = ig.GetWindowDrawList(ctx)
  local padx, pady = ig.GetStyleVar(ctx, ig.StyleVar_WindowPadding())
  local sbw = ig.GetStyleVar(ctx, ig.StyleVar_ScrollbarSize())
  local ww, wh = ig.GetWindowSize(ctx)
  local win_x, win_y = ig.GetWindowPos(ctx)
  local wx, wy = ig.GetCursorScreenPos(ctx)
  local bar_w = ww - 2 * padx

  -- gather racks
  local infos, nfx, nsel, nparams = {}, 0, 0, nil
  for i, tr in ipairs(racks) do
    if valid(tr) then
      local info = chain_info(tr)
      info.tr = tr
      info.slot = i - 1
      info.bypassed = is_bypassed(tr, info.list)
      info.box = latbox_on(S.lat_box == 'auto' and rack_latency(tr, reaper.GetTrackGUID(tr), info.list, now).total or 0)
      info.nat = natural_height(#info.list, M, info.box, perf_compact())
      nfx = nfx + #info.list
      if S.perf and rack_selected(tr) then nsel = nsel + 1; nparams = (nparams or 0) + params_count(tr) end
      infos[#infos + 1] = info
    end
  end

  ------------------------------------------------ top bar (stays put): Racks, centered | + Options
  local tb_h = math.max(M.fh + 8, title_font and (TITLE_FONT_SIZE + 12) or 0)   -- one row

  -- Layout: cue light on the left, + and the menus on the right, the title
  -- centered in the space between. When the window is too narrow, the title
  -- keeps the first row (centered right of the cue light) and the buttons wrap
  -- onto as many rows as needed below it, right-aligned.
  local cue_w = ig.CalcTextSize(ctx, 'SHOW') + 36
  local cue_x = wx + 6
  local function menu_button(label, id, pop)
    return { w = ig.CalcTextSize(ctx, label) + 2 * M.fpx + 10, label = label .. '##' .. id, pop = pop, text = label }
  end
  local buttons = {
    { w = M.fh, plus = true },
    menu_button('Display', 'm_disp', 'disp_pop'),
    menu_button('FX', 'm_fx', 'fx_pop'),
    menu_button('Latency', 'm_lat', 'lat_pop'),
    menu_button('Options', 'm_opt', 'opts_pop'),
  }

  local tpushed = push_bold(title_font, TITLE_FONT_SIZE)
  local ttw = ig.CalcTextSize(ctx, 'Racks')
  local tlh = ig.GetTextLineHeight(ctx)
  if tpushed then ig.PopFont(ctx) end
  local vtxt = 'v' .. VERSION
  local vw = ig.CalcTextSize(ctx, vtxt)
  local title_w = ttw + 6 + vw

  local left, right = cue_x + cue_w + 12, wx + bar_w - 4
  local menus_w = -M.spx
  for _, bt in ipairs(buttons) do menus_w = menus_w + bt.w + M.spx end

  local rows, title_r
  if left + title_w + 24 + menus_w <= right then
    rows = { { items = buttons, w = menus_w, row = 1 } }          -- everything on one row
    title_r = right - menus_w - 12
  else
    rows = {}
    local cur = { items = {}, w = -M.spx, row = 2 }
    local avail = right - (wx + 4)
    for _, bt in ipairs(buttons) do
      if #cur.items > 0 and cur.w + M.spx + bt.w > avail then
        rows[#rows + 1] = cur
        cur = { items = {}, w = -M.spx, row = cur.row + 1 }
      end
      cur.items[#cur.items + 1] = bt
      cur.w = cur.w + M.spx + bt.w
    end
    rows[#rows + 1] = cur
    title_r = right
  end
  local top_h = tb_h * rows[#rows].row
  ig.DrawList_AddRect(dl, wx, wy, wx + bar_w, wy + top_h, T.bar_border, ROUNDING, 0, 1)

  -- title and version, centered in the free space of the first row
  local title_x = left + math.max(0, (title_r - left - title_w) / 2)
  local title_y = wy + (tb_h - tlh) / 2
  tpushed = push_bold(title_font, TITLE_FONT_SIZE)
  ig.DrawList_AddText(dl, title_x, title_y, T.title, 'Racks')
  if tpushed then ig.PopFont(ctx) end
  -- the version, small, on the title's baseline
  ig.DrawList_AddText(dl, title_x + ttw + 6, title_y + tlh - M.tlh - 2, T.dim, vtxt)

  -- mode switch, like a cue light: green = Edit, red = Show
  local editing = S.mode == 'edit'
  local cue = editing and T.cue_edit or T.cue_show
  local cue_label = editing and 'EDIT' or 'SHOW'
  local cue_y = wy + (tb_h - M.fh) / 2
  local halo = cue & 0xFFFFFF00
  for i = 1, 4 do
    local a = math.floor(130 * (1 - (i - 1) / 4) ^ 2)
    ig.DrawList_AddRect(dl, cue_x - i, cue_y - i, cue_x + cue_w + i, cue_y + M.fh + i,
                        halo | a, ROUNDING + i, 0, 1)
  end
  ig.DrawList_AddRectFilled(dl, cue_x, cue_y, cue_x + cue_w, cue_y + M.fh, cue, ROUNDING)
  ig.DrawList_AddCircleFilled(dl, cue_x + 12, cue_y + M.fh / 2, 4, mix(cue, WHITE, 0.8), 0)
  local cue_tw = ig.CalcTextSize(ctx, cue_label)
  ig.DrawList_AddText(dl, cue_x + 22 + (cue_w - 22 - cue_tw) / 2, cue_y + (M.fh - M.tlh) / 2, WHITE, cue_label)
  ig.SetCursorScreenPos(ctx, cue_x, cue_y)
  if ig.InvisibleButton(ctx, 'mode_switch', cue_w, M.fh) then
    set_mode(editing and 'show' or 'edit')
  end
  hint_hovered(editing and 'Click: switch to Show mode (racks and FX locked; level, mute, bypass and FX on/off still work)'
                        or 'Click: switch to Edit mode (everything can be changed)')
  if ig.IsItemHovered(ctx) then
    ig.SetTooltip(ctx, editing
      and 'Edit mode: everything can be changed.\nClick to switch to Show mode.'
      or  'Show mode: racks and FX are locked.\nLevel, mute, bypass and FX on/off still work.\nClick to switch to Edit mode.')
  end

  -- a JSFX problem, if any, shows next to it
  if meter_error then
    local ex = cue_x + cue_w + 12
    ig.SetCursorScreenPos(ctx, ex, wy + (tb_h - M.tlh) / 2)
    ig.TextColored(ctx, 0xFF6060FF, fit_text(meter_error, math.max(40, title_x - ex - 8)))
  end

  -- top bar buttons: + | Display | FX | Latency | Options, placed by the layout above
  local la = alerts_state()
  for _, r in ipairs(rows) do
    local x = right - r.w
    local y = wy + (r.row - 1) * tb_h + (tb_h - M.fh) / 2
    for _, bt in ipairs(r.items) do
      ig.SetCursorScreenPos(ctx, x, y)
      if bt.plus then
        -- + : new rack (edit mode only)
        lock_begin(is_locked())
        ig.PushStyleVar(ctx, ig.StyleVar_FrameRounding(), M.fh / 2)
        if ig.Button(ctx, '+##newrack', M.fh, M.fh) then create_rack() end
        ig.PopStyleVar(ctx)
        if ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, 'New empty rack') end
        hint_hovered('Click: new empty rack')
        lock_end(is_locked())
      else
        -- the Latency button turns red while alerts are silenced or off, as a reminder
        local red = bt.pop == 'lat_pop' and la ~= 'on'
        if red then ig.PushStyleColor(ctx, ig.Col_Text(), ALERT_RED) end
        if ig.Button(ctx, bt.label, bt.w, M.fh) then ig.OpenPopup(ctx, bt.pop) end
        if red then ig.PopStyleColor(ctx) end
        if red and ig.IsItemHovered(ctx) then
          ig.SetTooltip(ctx, la == 'off' and 'Latency alerts are off' or 'Latency alerts are silenced')
        end
      end
      x = x + bt.w + M.spx
    end
  end

  if ig.BeginPopup(ctx, 'disp_pop') then draw_display_menu(); ig.EndPopup(ctx) end
  if ig.BeginPopup(ctx, 'fx_pop') then draw_fx_menu(); ig.EndPopup(ctx) end
  if ig.BeginPopup(ctx, 'lat_pop') then draw_latency_menu(); ig.EndPopup(ctx) end
  if ig.BeginPopup(ctx, 'opts_pop') then draw_options_menu(); ig.EndPopup(ctx) end

  ------------------------------------------------ racks (the only part that scrolls)
  local top = wy + top_h                              -- the gap under the top bar is inside the area (rack_gap)
  local sb_y = win_y + wh - pady - tb_h               -- status bar top
  local hint_h = M.tlh + 4                            -- the help line, right above the status bar
  local child_h = math.max(40, sb_y - RACK_SPACE - hint_h - top)

  ig.SetCursorScreenPos(ctx, wx, top)
  local ta = reaper.time_precise()
  if S.perf then
    if begin_child('racks_perf', bar_w, child_h, ig.WindowFlags_HorizontalScrollbar()) then
      draw_perf_area(infos, M, dt, now)
      ig.EndChild(ctx)
    end
  elseif begin_child('racks', bar_w, child_h) then
    draw_rack_area(infos, M, dt, now, bar_w - sbw)
    ig.EndChild(ctx)
  end
  TIMER.area = reaper.time_precise() - ta

  ------------------------------------------------ help line: what the mouse can do right now
  draw_hint(dl, wx + 6, top + child_h + (sb_y - top - child_h - M.tlh) / 2, bar_w - 12)

  ------------------------------------------------ status bar (stays put)
  local ptxt = S.perf and (nsel > 0 and ('%d parameter(s) in the selected rack'):format(nparams) or 'no rack selected') or nil
  draw_status_bar(dl, wx, sb_y, bar_w, tb_h, M, #infos, nfx, ptxt)

  apply_pending()
  draw_dialogs()
  draw_copy_badge()
end

-- the settings window: edits SCHEMA values, saved as they change
function draw_settings()
  if not S.show_settings then return end
  local vis, open = begin_window('settings', 'FOH-Mate Settings', 440, 560, true)
  if vis then
    CONFIRM_HOST = 'settings'
    -- a search field: only the settings whose name has the text (or whose group does) are listed, the
    -- groups that have some are open
    ig.SetNextItemWidth(ctx, -1)
    local rvs, found = ig.InputTextWithHint(ctx, '##setfind', 'Search settings...', S.set_find or '')
    if rvs then S.set_find = found end
    local q = (S.set_find or ''):lower()
    local function entry_hit(e)
      if e.label:lower():find(q, 1, true) then return true end
      for _, o in ipairs(e.options or {}) do if o[2]:lower():find(q, 1, true) then return true end end
      return false
    end
    local group_hit, group_any = {}, {}
    if q ~= '' then
      for _, e in ipairs(SCHEMA) do
        if e.group:lower():find(q, 1, true) then group_hit[e.group], group_any[e.group] = true, true
        elseif entry_hit(e) then group_any[e.group] = true end
      end
      if next(group_any) == nil then ig.TextDisabled(ctx, 'No setting matches.') end
    end
    ig.Spacing(ctx)
    local group, group_open = nil, false
    for _, e in ipairs(SCHEMA) do
      if e.group ~= group then
        group, group_open = e.group, false
        if q == '' or group_any[group] then
          if q ~= '' or S.settings_focus == group then
            ig.SetNextItemOpen(ctx, true, ig.Cond_Always())
          end
          group_open = section_header(group, group == 'Colors')
          if S.settings_focus == group then
            ig.SetScrollHereY(ctx, 0)
            S.settings_focus = nil
          end
        end
      end
      if group_open and (q == '' or group_hit[group] or entry_hit(e)) then
        ig.SetNextItemWidth(ctx, 210)
        local label = e.label .. '##cfg_' .. e.key
        if e.kind == 'color' then
          local typ = e.key:match('^col_(.+)$')
          local rv, v = ig.ColorEdit3(ctx, typ and ('##cfg_' .. e.key) or label, CFG[e.key],
                                      ig.ColorEditFlags_NoInputs())
          if typ then                     -- the type name in its own color (picker stays plain)
            ig.SameLine(ctx)
            ig.TextColored(ctx, type_color(typ), e.label)
          end
          if rv then
            CFG[e.key] = v
            save_cfg_value(e)
          end
        elseif e.kind == 'choice' then
          local cur = e.options[1][2]
          for _, o in ipairs(e.options) do if o[1] == CFG[e.key] then cur = o[2] end end
          if ig.BeginCombo(ctx, label, cur) then
            for _, o in ipairs(e.options) do
              if ig.Selectable(ctx, o[2], CFG[e.key] == o[1]) then
                CFG[e.key] = o[1]
                save_cfg_value(e)
              end
            end
            ig.EndCombo(ctx)
          end
        elseif e.kind == 'bool' then
          local rv, v = ig.Checkbox(ctx, label, CFG[e.key] ~= 0)
          if rv then
            CFG[e.key] = v and 1 or 0
            save_cfg_value(e)
          end
        elseif e.kind == 'mod' then
          if ig.BeginCombo(ctx, label, CFG[e.key]) then
            for _, name in ipairs({ 'ctrl', 'shift', 'alt' }) do
              if ig.Selectable(ctx, name, CFG[e.key] == name) then
                CFG[e.key] = name
                save_cfg_value(e)
              end
            end
            ig.EndCombo(ctx)
          end
        else
          local rv, v
          if e.kind == 'i' then
            rv, v = ig.SliderInt(ctx, label, CFG[e.key], e.min, e.max, e.fmt)
          else
            rv, v = ig.SliderDouble(ctx, label, CFG[e.key], e.min, e.max, e.fmt)
          end
          if rv then CFG[e.key] = v end
          if ig.IsItemDeactivatedAfterEdit(ctx) then
            save_cfg_value(e)
            if e.key == 'lat_limit' or e.key == 'lat_rack_limit' then recheck_show_offline() end
          end
        end
        if e.tip and ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, e.tip) end
      end
    end
    ig.Separator(ctx)
    ig.TextDisabled(ctx, (IS_MAC and 'Cmd' or 'Ctrl') .. '+click a slider to type a value.')
    if ig.Button(ctx, 'Reset to defaults', 150, 0) then
      request_confirm('Reset every setting in this window to its default?', reset_cfg, 'Reset')
    end
    ig.SameLine(ctx)
    local n_hidden = 0
    for _ in pairs(S.hidden_popups) do n_hidden = n_hidden + 1 end
    if ig.Button(ctx, 'Reset warning popups', 170, 0) then
      local n = reset_popups()
      popups_reset_msg = n == 0 and 'No popup was hidden.'
                         or ('%d popup%s will show again.'):format(n, n == 1 and '' or 's')
    end
    if ig.IsItemHovered(ctx) then
      ig.SetTooltip(ctx, ('Shows again every popup hidden with "Don\'t show this again" (%d hidden now).'):format(n_hidden))
    end
    if popups_reset_msg then ig.TextDisabled(ctx, popups_reset_msg) end
    draw_confirm('settings')
    CONFIRM_HOST = nil
    ig.End(ctx)
  end
  if not open then
    S.show_settings = false
    popups_reset_msg = nil
    if confirm and confirm.host == 'settings' then confirm = nil end   -- closed while asking: Cancel
  end
end

