-- FOHMate/racks.lua: racks.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- racks

function set_status(guid, text, secs)
  status[guid] = { text = text, untl = reaper.time_precise() + secs }
end

function metrics()
  local fh = ig.GetFrameHeight(ctx)
  local spx, spy = ig.GetStyleVar(ctx, ig.StyleVar_ItemSpacing())
  local fpx, fpy = ig.GetStyleVar(ctx, ig.StyleVar_FramePadding())
  local tlh = ig.GetTextLineHeight(ctx)
  return {
    fh = fh, spx = spx, spy = spy, fpx = fpx, fpy = fpy, tlh = tlh,
    sm = math.floor(fh * 0.85),                       -- small buttons
    btn_h = math.floor(fh * 1.35),                    -- bypass / mute
    name_h = name_font and (NAME_FONT_SIZE + 8) or (fh + 4),
    rowp = fh + spy,
  }
end

-- the three sections of a rack: header, FX, controls
function section_heights(n_fx, M)
  local rows = math.max(n_fx, 1)
  local hdr = SI + M.name_h + M.spy + M.fh + SI
  local fxs = SI + rows * M.rowp + M.sm + SI
  local ctl = SI + M.fh + M.spy + M.btn_h + SI
  return hdr, fxs, ctl
end

-- the optional latency box under a rack (Options > Show rack latency)
-- show the box for this rack? (rack_lat: its latency in samples, if known)
function latbox_on(rack_lat)
  if S.lat_box == 'always' then return true end
  if S.lat_box == 'auto' then return (rack_lat or 0) > 0 end
  return false
end

function latbox_h(M, on)
  return on and (M.fh + SG) or 0
end

function natural_height(n_fx, M, box)
  local hdr, fxs, ctl = section_heights(n_fx, M)
  return PAD + hdr + SG + fxs + SG + ctl + latbox_h(M, box) + PAD
end

-- one dot (n = 1, mono) or two overlapping dots, one solid and one outlined (n = 2,
-- stereo): side by side, or stacked when vertical. bg rings them, so they read on
-- top of the FX buttons they sit on.
function width_dots(dl, cx, cy, n, vertical, ink, bg, r)
  if n == 1 then
    ig.DrawList_AddCircleFilled(dl, cx, cy, r + 1.5, bg, 0)
    ig.DrawList_AddCircleFilled(dl, cx, cy, r, ink, 0)
    return
  end
  local d = r * 1.8
  local ax, ay, bx, by
  if vertical then ax, ay, bx, by = cx, cy - d / 2, cx, cy + d / 2
  else ax, ay, bx, by = cx - d / 2, cy, cx + d / 2, cy end
  ig.DrawList_AddCircleFilled(dl, bx, by, r + 1.5, bg, 0)
  ig.DrawList_AddCircleFilled(dl, ax, ay, r + 1.5, bg, 0)
  ig.DrawList_AddCircle(dl, bx, by, r - 0.6, ink, 0, 1.2)          -- the outlined one
  ig.DrawList_AddCircleFilled(dl, ax, ay, r + 0.8, bg, 0)           -- a thin gap where they overlap
  ig.DrawList_AddCircleFilled(dl, ax, ay, r, ink, 0)                -- the solid one
end

-- a color that stands out from the rack's own color (opposite hue)
function contrast_glow(tr)
  local h = track_hue(tr) or 210
  local r, g, b = hsl_to_rgb(h + 180, 0.9, S.daylight and 0.42 or 0.6)
  return (r << 24) | (g << 16) | (b << 8) | 0xFF
end

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

-- a drop target that appends to the FX of a rack
function drop_zone(id, x, y, w, h, tr, append_idx)
  ig.SetCursorScreenPos(ctx, x, y)
  ig.InvisibleButton(ctx, id, w, h)
  if drag_prev_fx and mouse_in(x, y, x + w, y + h) then
    ig.DrawList_AddRect(ig.GetWindowDrawList(ctx), x, y, x + w, y + h, drag_copies() and COPY_BADGE or T.glow, ROUNDING, 0, 2)
  end
  if ig.BeginDragDropTarget(ctx) then
    local ok, payload = ig.AcceptDragDropPayload(ctx, 'RACKFX')
    if ok then
      pending_ops[#pending_ops + 1] = { payload = payload, dst_tr = tr, dst = append_idx }
    end
    ig.EndDragDropTarget(ctx)
  end
end

function draw_rack(info, x0, y0, H, M, dt, now)
  local tr = info.tr
  local guid = reaper.GetTrackGUID(tr)
  local list = info.list
  local bypassed = info.bypassed
  local col = track_color(tr)
  local slot = math.min(info.slot, 255)
  local locked = is_locked()
  local selected = rack_selected(tr)
  local metering = not S.no_meters
  local io_in, io_out = rack_io(tr)

  ------------------------------------------------ meter data
  local m = meters[guid]
  if not m then m = new_meter_state(); meters[guid] = m end

  local pl, pr = 0, 0
  local sl_i, sr_i, n_i = 0, 0, 0
  local sl_o, sr_o, n_o = 0, 0, 0
  if metering and info.in_fx then
    local cnt
    pl, pr, cnt, sl_i, sr_i, n_i = read_stage(slot * STRIDE)
    if cnt ~= m.cnt then m.cnt = cnt; m.stale = 0 else m.stale = m.stale + 1 end
    if m.stale > 8 then pl, pr = 0, 0 end
  end
  if metering and info.out_fx then
    local _, _, _, a, b, n = read_stage(slot * STRIDE + 8)
    sl_o, sr_o, n_o = a, b, n
  end

  if metering then
    local ol = reaper.Track_GetPeakInfo(tr, 0)
    local o_r = reaper.Track_GetPeakInfo(tr, 1)
    local fall = METER_FALL * dt
    local din_l, din_r = amp_to_db(pl), amp_to_db(pr)
    local dout_l, dout_r = amp_to_db(ol), amp_to_db(o_r)
    m.lv_in[1]  = math.max(din_l,  m.lv_in[1]  - fall)
    m.lv_in[2]  = math.max(din_r,  m.lv_in[2]  - fall)
    m.lv_out[1] = math.max(dout_l, m.lv_out[1] - fall)
    m.lv_out[2] = math.max(dout_r, m.lv_out[2] - fall)
    mark(m.hold_in,  m.clip_in,  1, din_l);  mark(m.hold_in,  m.clip_in,  2, din_r)
    mark(m.hold_out, m.clip_out, 1, dout_l); mark(m.hold_out, m.clip_out, 2, dout_r)
  end

  ------------------------------------------------ level match (RMS)
  if not metering then matches[guid] = nil end
  local mt = matches[guid]
  if mt then
    if mt.first then
      mt.first = false      -- the first read holds stale accumulated data
    elseif n_i > 0 and n_o > 0 then
      local in_pow = (sl_i + sr_i) / (2 * n_i)
      if in_pow > 10.0 ^ (MATCH_GATE / 10.0) then
        mt.sin  = mt.sin  + (sl_i + sr_i);  mt.nin  = mt.nin  + 2 * n_i
        mt.sout = mt.sout + (sl_o + sr_o);  mt.nout = mt.nout + 2 * n_o
        mt.frames = mt.frames + 1
      end
    end
    if now - mt.t0 >= MATCH_SECS then
      matches[guid] = nil
      if not (info.in_fx and info.out_fx) then
        set_status(guid, 'Match: meters missing', 4)
      elseif mt.frames < 20 then
        set_status(guid, 'Match: not enough signal', 4)
      elseif mt.sout <= 0 then
        set_status(guid, 'Match: output silent', 4)
      else
        -- the end-of-chain meter sits before the fader, so the fader
        -- value that makes output = input is simply the (negated) chain gain
        local chain_db = 10.0 * math.log((mt.sout / mt.nout) / (mt.sin / mt.nin), 10)
        local new_db = clamp(-chain_db, LEVEL_MIN, LEVEL_MAX)
        reaper.SetMediaTrackInfo_Value(tr, 'D_VOL', 10.0 ^ (new_db / 20.0))
        set_status(guid, ('Matched: %.1f dB'):format(new_db), 4)
      end
    end
  end

  ------------------------------------------------ geometry
  local fh, spx, spy, sm = M.fh, M.spx, M.spy, M.sm
  local hdr_h, fxs_h, ctl_h = section_heights(#list, M)

  local cx  = x0 + PAD + METER_W + GAP         -- middle area
  local wx  = cx + SI                          -- widgets inside a section
  local WW  = CENTER_W - 2 * SI                -- widget width

  local hdr_top = y0 + PAD
  local hdr_bot = hdr_top + hdr_h
  local ctl_bot = y0 + H - PAD - latbox_h(M, info.box)
  local ctl_top = ctl_bot - ctl_h
  local fxs_top = hdr_bot + SG
  local fxs_bot = ctl_top - SG

  local name_y = hdr_top + SI
  local io_y   = name_y + M.name_h + spy
  local lvl_y  = ctl_top + SI
  local btn_y  = lvl_y + fh + spy
  local add_y  = fxs_bot - SI - sm

  if mouse_in(x0, y0, x0 + RACK_W, y0 + H) then hover_now_rack = guid end

  ------------------------------------------------ frame, sections
  local dl = ig.GetWindowDrawList(ctx)
  local c = rack_colors(col, bypassed)
  if selected then
    -- selection glow: rings that fade out away from the rack
    local base = T.glow & 0xFFFFFF00
    for i = 1, GLOW_M do
      local a = math.floor(170 * (1 - (i - 1) / GLOW_M) ^ 2)
      ig.DrawList_AddRect(dl, x0 - i, y0 - i, x0 + RACK_W + i, y0 + H + i,
                          base | a, ROUNDING + 2 + i, 0, 1)
    end
  end
  ig.DrawList_AddRectFilled(dl, x0, y0, x0 + RACK_W, y0 + H, c.bg, ROUNDING + 2)
  ig.DrawList_AddRect(dl, x0, y0, x0 + RACK_W, y0 + H,
                      selected and mix(c.border, T.glow, 0.6) or c.border, ROUNDING + 2, 0, selected and 3 or 2)

  local function section(y1, y2)
    ig.DrawList_AddRectFilled(dl, cx, y1, cx + CENTER_W, y2, c.sec_bg, ROUNDING)
    ig.DrawList_AddRect(dl, cx, y1, cx + CENTER_W, y2, c.sec_bd, ROUNDING, 0, 1)
  end
  section(hdr_top, hdr_bot)
  section(fxs_top, fxs_bot)
  section(ctl_top, ctl_bot)

  -- the drag preview of this rack: its outline, sections and name, as a see-through shape
  local function rack_ghost()
    local gx, gy = ig.GetCursorScreenPos(ctx)
    local gdl = ig.GetWindowDrawList(ctx)
    local dx, dy = gx - x0, gy - y0
    local function fade(rgba, a) return (rgba & 0xFFFFFF00) | a end
    ig.DrawList_AddRectFilled(gdl, gx, gy, gx + RACK_W, gy + H, fade(c.bg, 0xC8), ROUNDING + 2)
    ig.DrawList_AddRect(gdl, gx, gy, gx + RACK_W, gy + H, c.border, ROUNDING + 2, 0, 3)
    for _, sec in ipairs({ { hdr_top, hdr_bot }, { fxs_top, fxs_bot }, { ctl_top, ctl_bot } }) do
      ig.DrawList_AddRectFilled(gdl, cx + dx, sec[1] + dy, cx + dx + CENTER_W, sec[2] + dy, fade(c.sec_bg, 0xB0), ROUNDING)
      ig.DrawList_AddRect(gdl, cx + dx, sec[1] + dy, cx + dx + CENTER_W, sec[2] + dy, fade(c.sec_bd, 0xFF), ROUNDING, 0, 1)
    end
    ig.DrawList_AddRectFilled(gdl, wx + dx, name_y + dy, wx + dx + WW, name_y + dy + M.name_h, c.name_bg, ROUNDING)
    local nm = fit_text(raw_name(tr) ~= '' and raw_name(tr) or '(unnamed)', WW - 8)
    ig.DrawList_AddText(gdl, wx + dx + (WW - ig.CalcTextSize(ctx, nm)) / 2,
                        name_y + dy + (M.name_h - ig.GetTextLineHeight(ctx)) / 2, c.name_txt, nm)
    ig.Dummy(ctx, RACK_W, H)
  end

  ig.PushID(ctx, guid)

  ------------------------------------------------ routing + Rack Option Menu (round, above the meters)
  local by = name_y + (M.name_h - METER_W) / 2

  lock_begin(locked)
  ig.SetCursorScreenPos(ctx, x0 + PAD, by)
  push_native()
  ig.PushStyleVar(ctx, ig.StyleVar_FrameRounding(), METER_W / 2)
  if ig.Button(ctx, 'R##route', METER_W, METER_W) then open_routing(tr) end
  ig.PopStyleVar(ctx)
  pop_native()
  if ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, 'Routing window') end
  hint_hovered('Click: REAPER\'s routing window for this rack')

  ig.SetCursorScreenPos(ctx, x0 + RACK_W - PAD - METER_W, by)
  ig.PushStyleVar(ctx, ig.StyleVar_FrameRounding(), METER_W / 2)
  if ig.Button(ctx, '...##opt', METER_W, METER_W) then ig.OpenPopup(ctx, 'rack_opt') end
  ig.PopStyleVar(ctx)
  if ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, 'Rack Option Menu') end
  hint_hovered('Click: rack options (level match, duplicate, color, remove FX...); they apply to every selected rack')
  lock_end(locked)

  if ig.BeginPopup(ctx, 'rack_opt') then
    local n_sel = #targets_for(tr)
    if n_sel > 1 then
      ig.TextDisabled(ctx, ('Applies to the %d selected racks'):format(n_sel))
      ig.Separator(ctx)
    end
    if ig.MenuItem(ctx, 'Level match', nil, false, metering) then
      rack_action(tr, 'Level match', function(t)
        matches[reaper.GetTrackGUID(t)] = { t0 = reaper.time_precise(), first = true, sin = 0, nin = 0, sout = 0, nout = 0, frames = 0 }
      end)
    end
    ig.Separator(ctx)
    if ig.MenuItem(ctx, 'Duplicate rack') then rack_action(tr, 'Duplicate rack', duplicate_rack) end
    if ig.MenuItem(ctx, 'Use as template (default parameters)') then
      rack_action(tr, 'Use as template', template_rack)
    end
    ig.Separator(ctx)
    if ig.MenuItem(ctx, 'Recolor automatically') then rack_action(tr, 'Recolor automatically', recolor_rack_auto) end
    if ig.MenuItem(ctx, 'Choose color...') then open_picker('rack', tr) end
    ig.Separator(ctx)
    if ig.MenuItem(ctx, 'Remove every FX') then rack_action(tr, 'Remove every FX', remove_all_fx) end
    if ig.MenuItem(ctx, 'Remove bypassed FX') then
      rack_action(tr, 'Remove bypassed FX', remove_bypassed_fx)
    end
    ig.Separator(ctx)
    if ig.MenuItem(ctx, 'Revert to regular track') then rack_action(tr, 'Revert to regular track', revert_to_track) end
    if ig.MenuItem(ctx, 'Delete rack...') then
      local trs = targets_for(tr)
      if #trs > 1 then
        request_confirm(('Delete the %d selected racks and all of their FX?\n(Ctrl+Z brings them back.)')
                        :format(#trs), function()
          for _, t in ipairs(trs) do if valid(t) then delete_rack(t) end end
        end, 'Delete')
      else
        request_confirm(('Delete the rack "%s" and all of its FX?\n(Ctrl+Z brings it back.)')
                        :format(raw_name(tr)), function() delete_rack(tr) end, 'Delete')
      end
    end
    ig.EndPopup(ctx)
  end

  ------------------------------------------------ name (bold, centered)
  local ns = name_state[guid]
  if not ns then ns = { editing = false }; name_state[guid] = ns end
  local pushed = push_bold(name_font, NAME_FONT_SIZE)
  ig.SetCursorScreenPos(ctx, wx, name_y)
  if locked then ns.editing = false end

  if ns.editing then
    if ns.fresh then ig.SetKeyboardFocusHere(ctx); ns.fresh = false end
    ig.PushStyleColor(ctx, ig.Col_Text(), c.name_txt)
    ig.PushStyleColor(ctx, ig.Col_FrameBg(), c.name_bg)
    ig.SetNextItemWidth(ctx, WW)
    local rv, new = ig.InputText(ctx, '##nm', ns.text, ig.InputTextFlags_AutoSelectAll())
    ig.PopStyleColor(ctx, 2)
    if rv then ns.text = new end
    local active = ig.IsItemActive(ctx)
    if active then ns.was_active = true end
    if ig.IsItemDeactivatedAfterEdit(ctx) then rename_rack(tr, new) end
    if ns.was_active and not active then ns.editing = false; ns.was_active = false end
  else
    ig.DrawList_AddRectFilled(dl, wx, name_y, wx + WW, name_y + M.name_h, c.name_bg, ROUNDING)
    ig.InvisibleButton(ctx, 'name', WW, M.name_h)
    -- click selects the rack (REAPER's track selection); Cmd/Ctrl-click adds or removes it
    if ig.IsItemClicked(ctx, 0) then select_rack(tr, has_mod('ctrl')) end
    if locked then
      hint_hovered(('Click: select the rack  \194\183  %s+click: add it to the selection, or take it out'):format(mod_label('ctrl')))
    else
      hint_hovered(('Click: select  \194\183  %s+click: add to / take out of the selection  \194\183  double-click: rename'
                    .. '  \194\183  drag: reorder  \194\183  %s+drag: duplicate'):format(mod_label('ctrl'), mod_label(COPY_MOD)))
    end
    local txt = fit_text(raw_name(tr) ~= '' and raw_name(tr) or '(unnamed)', WW - 8)
    local tw = ig.CalcTextSize(ctx, txt)
    local lh = ig.GetTextLineHeight(ctx)
    ig.DrawList_AddText(dl, wx + (WW - tw) / 2, name_y + (M.name_h - lh) / 2, c.name_txt, txt)

    if not locked then
      if ig.IsItemHovered(ctx) then
        if ig.IsMouseDoubleClicked(ctx, 0) then
          ns.editing, ns.text, ns.fresh, ns.was_active = true, raw_name(tr), true, false
        end
      end
      -- drag the name to reorder racks: the whole rack follows the cursor as a ghost
      if ig.BeginDragDropSource(ctx) then
        ig.SetDragDropPayload(ctx, 'RACKMOVE', guid)
        drag_now_rack = guid
        rack_ghost()
        ig.EndDragDropSource(ctx)
      end
    end
  end
  if pushed then ig.PopFont(ctx) end

  ------------------------------------------------ In / Out
  local iow = (WW - spx) / 2
  lock_begin(locked)
  ig.SetCursorScreenPos(ctx, wx, io_y)
  if ig.Button(ctx, 'In: ' .. in_text(tr) .. '##in', iow, fh) then ig.OpenPopup(ctx, 'in_pop') end
  if ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, 'Input: ' .. in_text(tr) .. ' (' .. width_text(io_in) .. ')') end
  hint_hovered('Click: choose the input (mono, stereo or MIDI); mono in makes the rack mono')

  ig.SetCursorScreenPos(ctx, wx + iow + spx, io_y)
  if ig.Button(ctx, 'Out: ' .. out_text(tr) .. '##out', iow, fh) then ig.OpenPopup(ctx, 'out_pop') end
  if ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, 'Output: ' .. out_text(tr) .. ' (' .. width_text(io_out) .. ')') end
  hint_hovered('Click: choose the hardware output (stereo pair or mono)')
  lock_end(locked)

  if ig.BeginPopup(ctx, 'in_pop') then
    local cur   = math.floor(reaper.GetMediaTrackInfo_Value(tr, 'I_RECINPUT'))
    local armed = reaper.GetMediaTrackInfo_Value(tr, 'I_RECARM') == 1
    local n = audio_device_header(false)
    if ig.MenuItem(ctx, 'None (receives only)', nil, (not armed) or cur < 0) then set_input(tr, -1) end
    if n >= 1 and ig.BeginMenu(ctx, 'Mono input') then
      for i = 0, n - 1 do
        local nm = reaper.GetInputChannelName(i) or ''
        if ig.MenuItem(ctx, ('%d  %s'):format(i + 1, nm), nil, armed and cur == i) then set_input(tr, i) end
      end
      ig.EndMenu(ctx)
    end
    if n >= 2 and ig.BeginMenu(ctx, 'Stereo input') then
      for i = 0, n - 2, pair_step() do
        local nm = reaper.GetInputChannelName(i) or ''
        if ig.MenuItem(ctx, ('%d/%d  %s'):format(i + 1, i + 2, nm), nil, armed and cur == (i | 1024)) then
          set_input(tr, i | 1024)
        end
      end
      ig.EndMenu(ctx)
    end
    local midi_all = 4096 | (63 << 5)
    if ig.MenuItem(ctx, 'MIDI (all devices, all channels)', nil, armed and cur == midi_all) then
      set_input(tr, midi_all)
    end
    ig.EndPopup(ctx)
  end

  if ig.BeginPopup(ctx, 'out_pop') then
    local nh = reaper.GetTrackNumSends(tr, 1)
    local d0 = (nh == 1) and math.floor(reaper.GetTrackSendInfo_Value(tr, 1, 0, 'I_DSTCHAN')) or nil
    local n = audio_device_header(true)
    -- an output kept from another interface that this one does not have
    for i = 0, nh - 1 do
      local d = math.floor(reaper.GetTrackSendInfo_Value(tr, 1, i, 'I_DSTCHAN'))
      local last = (d & 1023) + ((d & 1024 ~= 0) and 1 or 2)
      if n > 0 and last > n then
        ig.TextDisabled(ctx, ('Current output %s is not on this device.'):format(
          (d & 1024 ~= 0) and tostring((d & 1023) + 1) or ('%d/%d'):format((d & 1023) + 1, (d & 1023) + 2)))
        break
      end
    end
    if ig.MenuItem(ctx, 'No hardware output', nil, nh == 0) then set_hw_out(tr, nil) end
    if n >= 2 and ig.BeginMenu(ctx, 'Hardware out: stereo pair') then
      for i = 0, n - 2, pair_step() do
        local nm = reaper.GetOutputChannelName(i) or ''
        if ig.MenuItem(ctx, ('%d/%d  %s'):format(i + 1, i + 2, nm), nil, d0 == i) then set_hw_out(tr, i) end
      end
      ig.EndMenu(ctx)
    end
    if n >= 1 and ig.BeginMenu(ctx, 'Hardware out: mono') then
      for i = 0, n - 1 do
        local nm = reaper.GetOutputChannelName(i) or ''
        if ig.MenuItem(ctx, ('%d  %s'):format(i + 1, nm), nil, d0 == (i | 1024)) then set_hw_out(tr, i | 1024) end
      end
      ig.EndMenu(ctx)
    end
    ig.EndPopup(ctx)
  end

  ------------------------------------------------ FX section
  local fxs_y = fxs_top + SI
  local append_idx = info.out_fx or reaper.TrackFX_GetCount(tr)
  local keys = sc_sources(tr)
  local lat = rack_latency(tr, guid, list, now)
  local alert = lat.over and alerts_active()
  if alert then lat_over_racks = lat_over_racks + 1 end
  local blink = flash_on(now)
  local widen = io_in == W_MONO and io_out == W_STEREO     -- mono in, stereo out
  local split_i, split_manual = nil, false
  if widen then split_i, split_manual = split_index(tr, list) end
  local widths = chain_widths(io_in, io_out, split_i, #list)
  local rows = {}                                           -- where each FX name button is, for the dots
  local dot_r = math.max(2.5, fh * 0.16)

  for k, it in ipairs(list) do
    local fx = it.fx
    local y = fxs_y + (k - 1) * M.rowp
    local fx_guid = reaper.TrackFX_GetFXGUID(tr, fx)

    if circle_check(dl, '##en' .. fx, wx, y, fh, it.enabled) then
      reaper.TrackFX_SetEnabled(tr, fx, not it.enabled)
    end
    hint_hovered('Click: switch this FX on or off')

    -- FX with a key input get a round key button at the end of the row
    local kind = sc_key(tr, fx, widths[k] == W_MONO)     -- a mono FX always gets a mono key
    local name_w = WW - fh - spx
    if kind > 0 then
      name_w = name_w - fh - spx
      local key = keys[fx_guid]
      local lbl = key and source_label(key.src)
      if lbl then
        -- a connected key: its width (one dot = mono, two stacked = stereo) in the gap between the
        -- name and the key button (the name keeps its size)
        local x1, x2 = wx + fh + spx + name_w, wx + WW - fh
        -- the key's own width: a mono source into a stereo FX is still one dot
        local src = key.src
        local src_stereo = is_sc_bus(src) or (math.floor(reaper.GetMediaTrackInfo_Value(src, 'I_RECINPUT')) & 1024) ~= 0
        width_dots(dl, (x1 + x2) / 2, y + fh / 2, (kind == 2 and src_stereo) and 2 or 1, true, T.dots, c.sec_bg, dot_r)
      end
      lock_begin(locked)
      if round_button(dl, '##key' .. fx, wx + WW - fh, y, fh, lbl ~= nil,
                      function(kx, ky, ink) draw_key_icon(dl, kx, ky, fh * 0.8, ink) end,
                      lbl and ('Sidechain: ' .. lbl) or (kind == 1 and 'Sidechain input (mono)' or 'Sidechain input (stereo)')) then
        ig.OpenPopup(ctx, 'sc_pop' .. fx)
      end
      hint_hovered('Click: choose what feeds this FX\'s sidechain key (hardware input or sidechain bus)')
      lock_end(locked)
      if ig.BeginPopup(ctx, 'sc_pop' .. fx) then
        draw_sc_menu(tr, fx_guid, kind, key)
        ig.EndPopup(ctx)
      end
    end

    rows[k] = { x = wx + fh + spx, y = y, w = name_w }
    ig.SetCursorScreenPos(ctx, wx + fh + spx, y)
    push_native()
    if not it.enabled then ig.PushStyleColor(ctx, ig.Col_Text(), T.dim) end
    if ig.Button(ctx, clean_fx_name(it.name) .. '##fx' .. fx, name_w, fh) then
      if reaper.TrackFX_GetFloatingWindow(tr, fx) then
        reaper.TrackFX_Show(tr, fx, 2)
      else
        reaper.TrackFX_Show(tr, fx, 3)
      end
    end
    if not it.enabled then ig.PopStyleColor(ctx) end
    pop_native()
    if locked then
      hint_hovered('Click: open or close the FX window')
    else
      hint_hovered(('Click: open/close its window  \194\183  drag: reorder  \194\183  %s+drag: copy  \194\183  drag to another rack: copy, %s+drag: move'
                    .. '  \194\183  right-click: insert, replace, delete, latency, stereo point'):format(mod_label(COPY_MOD), mod_label(MOVE_MOD)))
    end
    local fx_lat = lat.fx[fx_guid] or 0
    local fx_ok = lat.allowed[fx_guid]
    if lat.offline[fx_guid] then
      -- offline: a strike through the name (Show mode puts latency FX offline)
      local bx1, bx2 = wx + fh + spx + 6, wx + fh + spx + name_w - 6
      ig.DrawList_AddLine(dl, bx1, y + fh / 2, bx2, y + fh / 2, T.dim, 1)
      if ig.IsItemHovered(ctx) then
        ig.SetTooltip(ctx, is_show_offline(tr, fx_guid) and 'Offline for Show mode (latency). Back to Edit brings it back.'
                                                        or 'Offline')
      end
    end
    if (fx_lat > 0 or S.lat_box == 'always') and ig.IsItemHovered(ctx) and not drag_prev_fx then
      ig.SetTooltip(ctx, 'Latency: ' .. samples_text(fx_lat) .. estimate_note(lat.est[fx_guid])
        .. (lat.disabled[fx_guid] and '\n(off: not counted)' or (fx_ok and '\n(allowed: not counted by the watchdog)' or '')))
    end
    -- latency watchdog: this FX adds latency to a rack over the limit
    if alert and fx_lat > 0 and not fx_ok and blink
       and (lat.fx_over[fx_guid] or (lat.rack_over and not lat.any_fx_over and lat.top == fx_guid)) then
      local bx2 = wx + fh + spx + name_w
      draw_alert_pill(dl, bx2 - 12, y + fh / 2, '!!')
    end

    -- drag: reorder, copy or move (also to another rack); edit mode only
    local fx_key = guid .. '|' .. fx
    if not locked and ig.BeginDragDropSource(ctx) then
      ig.SetDragDropPayload(ctx, 'RACKFX', fx_key)
      drag_now_fx = fx_key
      local hint = ''
      if drag_copies() then hint = '  (copy)' elseif has_mod(MOVE_MOD) then hint = '  (move)' end
      draw_fx_ghost(clean_fx_name(it.name), hint, name_w, fh)
      ig.EndDragDropSource(ctx)
    end
    if drag_prev_fx == fx_key then
      -- the FX being dragged stays behind, faded
      ig.DrawList_AddRectFilled(dl, wx, y, wx + WW, y + fh, S.daylight and 0xFFFFFF99 or 0x00000099, ROUNDING)
    elseif drag_prev_fx and not locked and mouse_in(wx, y, wx + WW, y + fh) then
      -- the slot the dragged FX would take
      ig.DrawList_AddRect(dl, wx - 1, y - 1, wx + WW + 1, y + fh + 1, drag_copies() and COPY_BADGE or T.glow, ROUNDING, 0, 2)
    end
    if not locked and ig.BeginDragDropTarget(ctx) then
      local ok, payload = ig.AcceptDragDropPayload(ctx, 'RACKFX')
      if ok then
        pending_ops[#pending_ops + 1] = { payload = payload, dst_tr = tr, dst = fx }
      end
      ig.EndDragDropTarget(ctx)
    end

    -- right-click: insert, replace, delete (edit mode only)
    if not locked and ig.BeginPopupContextItem(ctx, 'fx_ctx' .. fx) then
      if ig.BeginMenu(ctx, 'Insert FX') then
        draw_add_menu(function(item) insert_fx_at(tr, item.ident, fx) end)
        ig.EndMenu(ctx)
      end
      if ig.BeginMenu(ctx, 'Replace FX') then
        draw_add_menu(function(item)
          request_confirm(('Replace "%s" with "%s"?'):format(clean_fx_name(it.name), item.name),
            function() replace_fx(tr, fx_guid, item.ident) end, 'Replace', 'replace_fx')
        end)
        ig.EndMenu(ctx)
      end
      if ig.MenuItem(ctx, 'Delete FX...') then
        request_confirm(('Delete "%s" from this rack?'):format(clean_fx_name(it.name)),
          function() delete_fx(tr, fx_guid) end, 'Delete', 'delete_fx')
      end
      ig.Separator(ctx)
      local fl = lat.fx[fx_guid] or 0
      if ig.MenuItem(ctx, 'Allow latency' .. (fl > 0 and ('  (%d smp)'):format(fl) or ''), nil, lat.allowed[fx_guid] == true) then
        local on = not lat.allowed[fx_guid]
        local function go() set_latency_allowed(tr, fx_guid, on) end
        if on then confirm_allowed_one_format(fx_orig_name(tr, fx), go) else go() end
      end
      if widen then
        ig.Separator(ctx)
        if ig.MenuItem(ctx, 'Stereo from here', nil, split_manual and split_i == k) then
          local g = fx_guid
          if split_manual and split_i == k then g = nil end   -- ticked already: back to automatic
          later[#later + 1] = function() set_split(tr, g) end
        end
        if ig.MenuItem(ctx, 'Stereo point: automatic', nil, not split_manual) then
          if split_manual then later[#later + 1] = function() set_split(tr, nil) end end
        end
      end
      ig.EndPopup(ctx)
    end
  end

  -- mono / stereo dots on the chain: one dot = mono, two = stereo. Each FX shows what
  -- comes in (above it) and what goes out (below it); between two FX the dots are shared,
  -- centered on the narrower of the two. The FX where a mono-in, stereo-out rack turns
  -- stereo glows in a color that contrasts with the rack.
  if #rows > 0 then
    local function w_in(k) return widths[k] == W_STEREO and 2 or 1 end
    local function w_out(k) return widths[k] == W_MONO and 1 or 2 end
    local gcol = contrast_glow(tr)
    for k, rw in ipairs(rows) do
      if widths[k] == W_MS then
        for i, a in ipairs({ 0xE6, 0x8C, 0x3C }) do
          ig.DrawList_AddRect(dl, rw.x - i, rw.y - i, rw.x + rw.w + i, rw.y + fh + i, (gcol & 0xFFFFFF00) | a, ROUNDING + i, 0, 1.5)
        end
      end
    end
    for k, rw in ipairs(rows) do
      if k == 1 then width_dots(dl, rw.x + rw.w / 2, rw.y - spy / 2, w_in(1), false, T.dots, c.sec_bg, dot_r) end
      local nx = rows[k + 1]
      local w = nx and math.min(rw.w, nx.w) or rw.w
      width_dots(dl, rw.x + w / 2, rw.y + fh + spy / 2, w_out(k), false, T.dots, c.sec_bg, dot_r)
    end
  end

  -- empty space of the section: "(no FX)" and the append drop zone
  local zone_y = fxs_y + #list * M.rowp
  if #list == 0 then
    ig.SetCursorScreenPos(ctx, wx, zone_y + M.fpy)
    ig.TextDisabled(ctx, '(no FX)')
  end
  if not locked and add_y - zone_y > 4 then
    drop_zone('dz', wx, zone_y, WW, add_y - zone_y, tr, append_idx)
  end

  ------------------------------------------------ + / status / A/B (part of the FX section)
  lock_begin(locked)
  ig.SetCursorScreenPos(ctx, wx, add_y)
  ig.PushStyleVar(ctx, ig.StyleVar_FrameRounding(), sm / 2)
  if ig.Button(ctx, '+##add', sm, sm) then ig.OpenPopup(ctx, 'add_pop') end
  ig.PopStyleVar(ctx)
  if ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, 'Add an FX') end
  hint_hovered('Click: add an FX at the end of the rack (search, favorites, recently used...)')
  lock_end(locked)

  -- A/B: a rounded rectangle sized to its text
  local ab_w = ig.CalcTextSize(ctx, 'A/B') + 2 * M.fpx + 4
  ig.SetCursorScreenPos(ctx, wx + WW - ab_w, add_y)
  if ig.Button(ctx, 'A/B##ab', ab_w, sm) then ab_invert(tr) end
  if ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, 'A/B: invert the enabled state of every FX') end
  hint_hovered('Click: switch every FX of the rack to the opposite on/off state')

  local mid_x, mid_w = wx + sm + spx, WW - sm - ab_w - 2 * spx
  local stx = nil
  if matches[guid] then
    stx = ('Matching... %ds'):format(math.max(0, math.ceil(MATCH_SECS - (now - matches[guid].t0))))
  elseif status[guid] and now < status[guid].untl then
    stx = status[guid].text
  end
  if stx and mid_w > 10 then
    local t = fit_text(stx, mid_w)
    local tw = ig.CalcTextSize(ctx, t)
    ig.SetCursorScreenPos(ctx, mid_x + (mid_w - tw) / 2, add_y + (sm - M.tlh) / 2)
    ig.TextDisabled(ctx, t)
  end
  if not locked and mid_w > 10 then drop_zone('dz2', mid_x, add_y, mid_w, sm, tr, append_idx) end

  ig.SetNextWindowPos(ctx, wx, add_y + sm, ig.Cond_Appearing())
  if ig.BeginPopup(ctx, 'add_pop') then
    draw_add_menu(function(item) add_fx_to_rack(tr, item.ident) end)
    ig.EndPopup(ctx)
  end

  ------------------------------------------------ controls section
  local vol = reaper.GetMediaTrackInfo_Value(tr, 'D_VOL')
  local txt = (vol > 0.000001) and ('%.1f'):format(amp_to_db(vol)) or '-inf'
  local sbw = fh                                 -- round "send to sidechain bus" button
  ig.SetCursorScreenPos(ctx, wx, lvl_y)
  local lv = text_edit(guid .. ':lvl', txt, WW - 30 - spx - sbw - spx)
  -- Shift + double-click resets the level to 0 dB
  if ig.IsItemHovered(ctx) and ig.IsMouseDoubleClicked(ctx, 0) and has_mod('shift') then
    reaper.SetMediaTrackInfo_Value(tr, 'D_VOL', 1.0)
    local st = edit_state[guid .. ':lvl']
    if st then st.skip = true; st.active = false end
    lv = nil
  end
  -- Alt-click: 0 dB, or -inf when it already is at 0 dB
  if ig.IsItemHovered(ctx) and ig.IsMouseClicked(ctx, 0) and has_mod('alt') then
    local v = reaper.GetMediaTrackInfo_Value(tr, 'D_VOL')
    reaper.SetMediaTrackInfo_Value(tr, 'D_VOL', (math.abs(v - 1.0) < 0.0001) and 0.0 or 1.0)
    local st = edit_state[guid .. ':lvl']
    if st then st.skip = true; st.active = false end
    lv = nil
  end
  hint_hovered(('Click: type a level in dB, Enter to apply  \194\183  %s+click: 0 dB, again: -inf  \194\183  Shift+double-click: 0 dB')
               :format(mod_label('alt')))
  if lv then apply_level(tr, lv) end
  ig.SetCursorScreenPos(ctx, wx + WW - 30 - sbw - spx, lvl_y + M.fpy)
  ig.Text(ctx, 'dB')

  local nsend = n_bus_sends(tr)
  lock_begin(locked)
  if round_button(dl, '##scsend', wx + WW - sbw, lvl_y, sbw, nsend > 0,
                  function(kx, ky, ink)
                    local tw, th = ig.CalcTextSize(ctx, 'SC')
                    ig.DrawList_AddText(dl, kx - tw / 2, ky - th / 2, ink, 'SC')
                  end,
                  nsend > 0 and ('Sends to %d sidechain bus%s'):format(nsend, nsend > 1 and 'ses' or '')
                             or 'Send to a sidechain bus') then
    ig.OpenPopup(ctx, 'sc_send')
  end
  hint_hovered('Click: send this rack to sidechain busses, with a send level')
  lock_end(locked)
  if ig.BeginPopup(ctx, 'sc_send') then
    draw_bus_sends(tr)
    ig.EndPopup(ctx)
  end

  local hw = (WW - spx) / 2
  ig.SetCursorScreenPos(ctx, wx, btn_y)
  if bypassed then ig.PushStyleColor(ctx, ig.Col_Button(), T.byp) end
  if ig.Button(ctx, 'BYPASS##byp', hw, M.btn_h) then set_bypass(tr, not bypassed) end
  hint_hovered('Click: bypass the whole rack (FX that were off stay off when it comes back)')
  if bypassed then ig.PopStyleColor(ctx) end

  ig.SetCursorScreenPos(ctx, wx + hw + spx, btn_y)
  local muted = reaper.GetMediaTrackInfo_Value(tr, 'B_MUTE') == 1
  if muted then ig.PushStyleColor(ctx, ig.Col_Button(), T.mute) end
  if ig.Button(ctx, 'MUTE##mute', hw, M.btn_h) then
    reaper.SetMediaTrackInfo_Value(tr, 'B_MUTE', muted and 0 or 1)
  end
  hint_hovered('Click: mute the rack')
  if muted then ig.PopStyleColor(ctx) end

  ------------------------------------------------ meters: from under the name to the bottom of the buttons
  -- a rack is being dragged: fade the original, outline the one under the cursor and drop on it
  if drag_prev_rack then
    local copying = has_mod(COPY_MOD)
    local over = mouse_in(x0, y0, x0 + RACK_W, y0 + H)
    if drag_prev_rack == guid and not copying then
      ig.DrawList_AddRectFilled(dl, x0, y0, x0 + RACK_W, y0 + H, S.daylight and 0xFFFFFF99 or 0x00000099, ROUNDING + 2)
    elseif not locked and over then
      ig.DrawList_AddRect(dl, x0 - 2, y0 - 2, x0 + RACK_W + 2, y0 + H + 2, copying and COPY_BADGE or T.glow, ROUNDING + 4, 0, 3)
      if ig.IsMouseReleased(ctx, 0) then
        pending_racks[#pending_racks + 1] = { src = drag_prev_rack, dst = tr, copy = copying }
      end
    end
  end

  if metering then
    local my1, my2 = io_y, btn_y + M.btn_h
    draw_meter(dl, x0 + PAD, my1, my2, m.lv_in, m.hold_in, m.clip_in, 'min', io_in == W_MONO)
    draw_meter(dl, x0 + RACK_W - PAD - METER_W, my1, my2, m.lv_out, m.hold_out, m.clip_out, 'mout', io_out == W_MONO)
  end

  -- Options > Show rack latency: a box across the bottom of the rack
  if info.box then
    local bx1, bx2 = x0 + PAD, x0 + RACK_W - PAD
    local by1 = ctl_bot + SG
    local by2 = by1 + M.fh
    local over = lat.over
    ig.DrawList_AddRectFilled(dl, bx1, by1, bx2, by2, T.meter_bg, ROUNDING)
    ig.DrawList_AddRect(dl, bx1, by1, bx2, by2, over and ALERT_RED or c.sec_bd, ROUNDING, 0, 1)
    local txt
    if #list == 0 then
      txt = 'no FX'
    else
      txt = ('%.2f ms  -  %d smp'):format(lat.total * 1000 / sample_rate(), lat.total)
      if lat.counted ~= lat.total then txt = txt .. ('  (%d allowed)'):format(lat.total - lat.counted) end
    end
    txt = fit_text(txt, bx2 - bx1 - 8)
    local tw = ig.CalcTextSize(ctx, txt)
    ig.DrawList_AddText(dl, bx1 + (bx2 - bx1 - tw) / 2, by1 + (M.fh - M.tlh) / 2,
                        over and ALERT_RED or T.gauge_text, txt)
    if mouse_in(bx1, by1, bx2, by2) then
      HINT = 'Hover: the latency of each FX of this rack'
      local lines = { ('Rack latency: %s'):format(samples_text(lat.total)) }
      lines[#lines + 1] = ('Counted by the watchdog: %d smp (rack limit %d, FX limit %d)'):format(lat.counted, LAT_RACK_LIMIT, LAT_LIMIT)
      for _, it in ipairs(list) do
        local g = reaper.TrackFX_GetFXGUID(tr, it.fx)
        local n = lat.fx[g] or 0
        local tag = lat.offline[g] and '  (offline)' or (lat.disabled[g] and '  (off: not counted)' or (lat.allowed[g] and '  (allowed)' or ''))
        lines[#lines + 1] = ('  %s: %d smp%s%s'):format(clean_fx_name(it.name), n, estimate_note(lat.est[g]), tag)
      end
      if lat.chain then lines[#lines + 1] = ('REAPER reports for the chain: %d smp'):format(lat.chain) end
      if lat.chain_actual then lines[#lines + 1] = ('REAPER applies: %d smp (valid once playback ran)'):format(lat.chain_actual) end
      lines[#lines + 1] = 'Updated once a second, and when FX are added or removed.'
      ig.SetTooltip(ctx, table.concat(lines, '\n'))
    end
  end

  -- latency watchdog: flashing tag on the rack's top border
  if alert then
    local ms = lat.counted * 1000 / sample_rate()
    local px, py = x0 + RACK_W / 2, y0 + 1
    local what = lat.rack_over and 'RACK' or 'FX'
    if blink then
      if lat.rack_over then
        -- the whole rack is over its limit: its frame flashes red (drawn first, the tag goes on top).
        -- Same outline and corners as the rack's own frame, and thicker (2, or 3 when selected), so
        -- the rack's color doesn't show through
        ig.DrawList_AddRect(dl, x0, y0, x0 + RACK_W, y0 + H, ALERT_RED, ROUNDING + 2, 0, 4)
      end
      local x1, y1, x2, y2 = draw_alert_pill(dl, px, py, ('!!  %s  %.1f ms'):format(what, ms))
      ig.DrawList_AddRect(dl, x1, y1, x2, y2, WHITE, (y2 - y1) / 2, 0, 1)   -- thin outline, readable on any color
    end
    if mouse_in(px - 40, py - 8, px + 40, py + 8) then
      local names = {}
      for _, it in ipairs(list) do
        local g = reaper.TrackFX_GetFXGUID(tr, it.fx)
        local n = lat.fx[g] or 0
        if n > 0 and not lat.allowed[g] then
          names[#names + 1] = ('  %s: %d smp%s%s'):format(clean_fx_name(it.name), n, estimate_note(lat.est[g]),
                                                         lat.fx_over[g] and '  (over the FX limit)' or '')
        end
      end
      local head = lat.rack_over
        and ('RACK over its limit: %s in total (rack limit %d samples)'):format(samples_text(lat.counted), LAT_RACK_LIMIT)
        or  ('An FX is over its own limit (FX limit %d samples)'):format(LAT_LIMIT)
      ig.SetTooltip(ctx, ('%s\n%s\n\nRight-click an FX > Allow latency to leave it out.')
                         :format(head, table.concat(names, '\n')))
    end
  end

  ig.PopID(ctx)
end

