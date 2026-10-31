-- FOHMate/window.lua: the Plugins Host window and Settings window.
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
          if landed then fit_new_fx(op.dst_tr, landed) end
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
      else
        S.default_rgb = new
        save_setting('defcolor', new)
      end
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
      local yes = ig.Button(ctx, confirm.label, 110, 0)
      ig.SameLine(ctx)
      local no = ig.Button(ctx, 'Cancel', 110, 0)
      if yes then
        local f = confirm.yes
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

-- status bar: same size, border and color as the top bar
function draw_status_bar(dl, x, y, w, h, M, nracks, nfx)
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
-- more beyond it, and a slim bar on the right marks the position.
function draw_perf_column(inf, x, y, w, h, M)
  local tr = inf.tr
  local c = rack_colors(track_color(tr), inf.bypassed)
  local pdl = ig.GetWindowDrawList(ctx)
  ig.DrawList_AddRectFilled(pdl, x, y, x + w, y + h, c.bg, ROUNDING + 2)
  ig.DrawList_AddRect(pdl, x, y, x + w, y + h, c.border, ROUNDING + 2, 0, 2)

  ig.SetCursorScreenPos(ctx, x + PAD, y + PAD)
  local no_bar = ig.WindowFlags_NoScrollbar()
  if begin_child('col' .. reaper.GetTrackGUID(tr), w - 2 * PAD, h - 2 * PAD, no_bar) then
    local dl = ig.GetWindowDrawList(ctx)
    local cx, cy = ig.GetWindowPos(ctx)
    local cw, ch = ig.GetWindowSize(ctx)
    local rw = cw - 6 - PAD                                -- room for the position bar: the gap left of it equals the gap right of it (1 px + PAD)
    local pushed = push_bold(name_font, NAME_FONT_SIZE)
    local blh = ig.GetTextLineHeight(ctx)                  -- bold line height: a name may take two lines
    if pushed then ig.PopFont(ctx) end
    local rh = math.floor(2 * blh + 12)
    local n = math.floor(CFG.perf_demo_rows)
    local names = { 'Threshold', 'Ratio', 'Attack time', 'Low band crossover frequency', 'Output gain',
                    'Mix', 'High shelf frequency', 'Sidechain high-pass filter' }
    local mx_in = ig.IsWindowHovered(ctx)
    ig.Dummy(ctx, 1, 3)                                    -- room for the glow of the first row
    for k = 1, n do
      local rx, ry = ig.GetCursorScreenPos(ctx)
      rx = rx + 3; local rw2 = rw - 6                      -- a little room for the hover glow
      local cd = rh - 8                                    -- the control, outside the name box
      local box_w = rw2 - cd - 6
      local left = (k % 2 == 1)                            -- odd rows: name left; even rows: name right
      local bx = left and rx or (rx + rw2 - box_w)
      local kx = left and (rx + rw2 - cd) or rx
      -- hover: the whole row (name box and control) glows
      if mx_in and mouse_in(rx, ry, rx + rw2, ry + rh) then
        local base = T.glow & 0xFFFFFF00
        for i = 1, 3 do
          local a = math.floor(170 * (1 - (i - 1) / 3) ^ 2)
          ig.DrawList_AddRect(dl, rx - i, ry - i, rx + rw2 + i, ry + rh + i, base | a, ROUNDING + i, 0, 1)
        end
      end
      ig.DrawList_AddRectFilled(dl, bx, ry, bx + box_w, ry + rh, c.name_bg, ROUNDING)
      ig.DrawList_AddRect(dl, bx, ry, bx + box_w, ry + rh, c.sec_bd, ROUNDING, 0, 1)
      -- the name: bold, up to two lines
      local pb = push_bold(name_font, NAME_FONT_SIZE)
      local l1, l2 = names[(k - 1) % #names + 1], nil
      if ig.CalcTextSize(ctx, l1) > box_w - 8 then
        local cut = l1
        while #cut > 1 and ig.CalcTextSize(ctx, cut) > box_w - 8 do
          cut = cut:match('^(.*)%s+%S*$') or cut:sub(1, #cut - 1)
        end
        l2 = fit_text((l1:sub(#cut + 1):gsub('^%s+', '')), box_w - 8)
        l1 = cut
      end
      local ty = ry + (rh - blh * (l2 and 2 or 1)) / 2
      ig.DrawList_AddText(dl, bx + (box_w - ig.CalcTextSize(ctx, l1)) / 2, ty, c.name_txt, l1)
      if l2 then ig.DrawList_AddText(dl, bx + (box_w - ig.CalcTextSize(ctx, l2)) / 2, ty + blh, c.name_txt, l2) end
      if pb then ig.PopFont(ctx) end
      -- placeholder control: a knob
      local kcx, kcy, kr = kx + cd / 2, ry + rh / 2, cd / 2 - 1
      ig.DrawList_AddCircleFilled(dl, kcx, kcy, kr, c.sec_bg, 0)
      ig.DrawList_AddCircle(dl, kcx, kcy, kr, c.border, 0, 2)
      local ang = math.rad(135 + 270 * (((k * 37) % 100) / 100))
      ig.DrawList_AddLine(dl, kcx + math.cos(ang) * kr * 0.3, kcy + math.sin(ang) * kr * 0.3,
                          kcx + math.cos(ang) * kr * 0.85, kcy + math.sin(ang) * kr * 0.85, T.dots, 3)
      ig.Dummy(ctx, rw, rh)
    end
    -- the empty row at the end: a "+" in a circle as tall as a row, in the color of the names
    -- (opens the parameter dialog in the next version). Only the circle and the + light up.
    local px, py = ig.GetCursorScreenPos(ctx)
    ig.SetCursorScreenPos(ctx, px + (rw - rh) / 2, py)
    ig.InvisibleButton(ctx, '##addparam', rh, rh)
    local hov = ig.IsItemHovered(ctx)
    local pcx, pcy, pr = px + rw / 2, py + rh / 2, rh / 2 - 2
    local pcol = (c.name_txt & 0xFFFFFF00) | (hov and 0xFF or 0xB0)
    if hov then ig.DrawList_AddCircleFilled(dl, pcx, pcy, pr, (c.name_txt & 0xFFFFFF00) | 0x30, 0) end
    ig.DrawList_AddCircle(dl, pcx, pcy, pr, pcol, 0, hov and 3 or 2)
    local pl = pr * 0.45
    ig.DrawList_AddLine(dl, pcx - pl, pcy, pcx + pl, pcy, pcol, hov and 3 or 2)
    ig.DrawList_AddLine(dl, pcx, pcy - pl, pcx, pcy + pl, pcol, hov and 3 or 2)
    if hov then ig.SetTooltip(ctx, 'Add a parameter (coming in the next version)') end
    ig.Dummy(ctx, 1, 3)

    -- fade at the edges and the position bar
    local sy, smax = ig.GetScrollY(ctx), ig.GetScrollMaxY(ctx)
    if smax > 1 then
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
end

-- Performance mode, Show mode: each rack folds its FX section under the name. The state per
-- rack: open (what was asked) and t (0 folded .. 1 open, moving toward it so it animates).
PERF_FOLD, PERF_ACT, PERF_MX, PERF_MY, PERF_FRAME, PERF_FOLD_SECS = {}, 0, 0, 0, 0, 0.2

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

-- the last time the user did something: moved or clicked the mouse, used the wheel, pressed a key.
-- Keys are only looked at while an FX section is open, and every third frame.
function perf_activity(now, any_open)
  local mx, my = ig.GetMousePos(ctx)
  local wv, wh = ig.GetMouseWheel(ctx)
  if mx ~= PERF_MX or my ~= PERF_MY or wv ~= 0 or wh ~= 0
     or ig.IsMouseDown(ctx, 0) or ig.IsMouseDown(ctx, 1) then
    PERF_ACT = now
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
  perf_activity(now, any_open)
  -- no activity for a while: every FX section folds back (Settings > Performance mode)
  local after = CFG.perf_fold_after
  if any_open and after > 0 and now - PERF_ACT >= after then
    for _, st in pairs(PERF_FOLD) do st.open = false end
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
    draw_perf_column(inf, x, col_y, RACK_W, math.max(60, bottom - col_y), M)
    deepest = math.max(deepest, col_y + math.max(60, bottom - col_y))
  end

  empty_space_click(rects, math.huge)

  -- make the area as wide as the racks (the sideways scrollbar follows), as tall as the columns
  ig.SetCursorScreenPos(ctx, x_left, deepest)
  ig.Dummy(ctx, total_w, 1)
end

-- the grey help line: what the mouse can do with what is under it, or with what is being dragged
function draw_hint(dl, x, y, w)
  local copy, move = mod_label(COPY_MOD), mod_label(MOVE_MOD)
  if drag_prev_rack then
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
  hover_prev_rack, hover_now_rack = hover_now_rack, nil
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
  local infos, nfx = {}, 0
  for i, tr in ipairs(racks) do
    if valid(tr) then
      local info = chain_info(tr)
      info.tr = tr
      info.slot = i - 1
      info.bypassed = is_bypassed(tr, info.list)
      info.box = latbox_on(S.lat_box == 'auto' and rack_latency(tr, reaper.GetTrackGUID(tr), info.list, now).total or 0)
      info.nat = natural_height(#info.list, M, info.box, perf_compact())
      nfx = nfx + #info.list
      infos[#infos + 1] = info
    end
  end

  ------------------------------------------------ top bar (stays put): Plugins Host, centered | + Options
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
  local ttw = ig.CalcTextSize(ctx, 'Plugins Host')
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
  ig.DrawList_AddText(dl, title_x, title_y, T.title, 'Plugins Host')
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
  if S.perf then
    if begin_child('racks_perf', bar_w, child_h, ig.WindowFlags_HorizontalScrollbar()) then
      draw_perf_area(infos, M, dt, now)
      ig.EndChild(ctx)
    end
  elseif begin_child('racks', bar_w, child_h) then
    draw_rack_area(infos, M, dt, now, bar_w - sbw)
    ig.EndChild(ctx)
  end

  ------------------------------------------------ help line: what the mouse can do right now
  draw_hint(dl, wx + 6, top + child_h + (sb_y - top - child_h - M.tlh) / 2, bar_w - 12)

  ------------------------------------------------ status bar (stays put)
  draw_status_bar(dl, wx, sb_y, bar_w, tb_h, M, #infos, nfx)

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
    local group, group_open = nil, false
    for _, e in ipairs(SCHEMA) do
      if e.group ~= group then
        group = e.group
        if S.settings_focus == group then
          ig.SetNextItemOpen(ctx, true, ig.Cond_Always())
        end
        group_open = ig.CollapsingHeader(ctx, group, nil, (group == 'Colors') and ig.TreeNodeFlags_DefaultOpen() or 0)
        if S.settings_focus == group then
          ig.SetScrollHereY(ctx, 0)
          S.settings_focus = nil
        end
      end
      if group_open then
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

