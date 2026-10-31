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

-- the scrolling part: every rack, tiled
function draw_rack_area(infos, M, dt, now, avail)
  local x_left, y_top = ig.GetCursorScreenPos(ctx)
  local limit = x_left + avail                       -- the scrollbar starts here
  local wx, y = x_left + GLOW_M, y_top + GLOW_M      -- room around the racks for the selection glow
  local rects = {}
  local grid_x, last_row_y, last_row_h, grid_cols_n = wx, y, 0, 1

  if #infos == 0 then
    ig.SetCursorScreenPos(ctx, wx, y)
    ig.Text(ctx, ('No tracks named "%s ..." found. Double-click here or use + to create a rack.'):format(PREFIX))
  else
    -- each row is as tall as its tallest rack
    local cols = math.max(1, math.floor((avail - 2 * GLOW_M + RACK_SPACE) / (RACK_W + RACK_SPACE)))
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
      local grid_w = grid_cols * RACK_W + (grid_cols - 1) * RACK_SPACE
      local row_x = math.max(wx, x_left + math.floor((avail - grid_w) / 2))
      grid_x, last_row_y, last_row_h, grid_cols_n = row_x, y, row_h, cols
      for c = 0, cols - 1 do
        local inf = infos[i + c]
        if inf then
          local x = row_x + c * (RACK_W + RACK_SPACE)
          draw_rack(inf, x, y, row_h, M, dt, now)
          rects[#rects + 1] = { x, y, x + RACK_W, y + row_h }
        end
      end
      y = y + row_h + RACK_SPACE
      i = i + cols
    end
    y = y - RACK_SPACE
  end

  -- empty space: a click deselects the racks, a double-click offers a new rack
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
        sx, sy = grid_x + used * (RACK_W + RACK_SPACE), last_row_y
      else
        sx, sy = grid_x, last_row_y + last_row_h + RACK_SPACE
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
function begin_child(id, w, h)
  if not child_old_api then
    local ok, vis = pcall(ig.BeginChild, ctx, id, w, h, 0, 0)
    if ok then return vis end
    child_old_api = true
  end
  return ig.BeginChild(ctx, id, w, h, false, 0)
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
      info.nat = natural_height(#info.list, M, info.box)
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
  local top = wy + top_h + RACK_SPACE
  local sb_y = win_y + wh - pady - tb_h               -- status bar top
  local hint_h = M.tlh + 4                            -- the help line, right above the status bar
  local child_h = math.max(40, sb_y - RACK_SPACE - hint_h - top)

  ig.SetCursorScreenPos(ctx, wx, top)
  if begin_child('racks', bar_w, child_h) then
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
          if ig.IsItemDeactivatedAfterEdit(ctx) then save_cfg_value(e) end
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

