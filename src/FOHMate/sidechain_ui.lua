-- FOHMate/sidechain_ui.lua: sidechain UI.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- sidechain UI

-- a little key, drawn (so it looks the same on every system and theme)
function draw_key_icon(dl, cx, cy, s, col)
  local th = math.max(1.5, s * 0.11)
  local r  = s * 0.2
  local bx = cx - s * 0.26
  ig.DrawList_AddCircle(dl, bx, cy, r, col, 0, th)
  local x2 = cx + s * 0.4
  ig.DrawList_AddLine(dl, bx + r, cy, x2, cy, col, th)
  ig.DrawList_AddLine(dl, x2 - th / 2, cy, x2 - th / 2, cy + s * 0.22, col, th)
  ig.DrawList_AddLine(dl, x2 - s * 0.2, cy, x2 - s * 0.2, cy + s * 0.16, col, th)
end

-- a round button drawn by hand; `on` fills it with the sidechain color
function round_button(dl, id, x, y, d, on, paint, tip)
  ig.SetCursorScreenPos(ctx, x, y)
  local clicked = ig.InvisibleButton(ctx, id, d, d)
  local hov, act = ig.IsItemHovered(ctx), ig.IsItemActive(ctx)
  local bg
  if on then
    bg = T.sc_on
    if act then bg = mix(bg, BLACK, 0.15) elseif hov then bg = mix(bg, WHITE, 0.15) end
  else
    bg = ig.GetStyleColor(ctx, act and ig.Col_ButtonActive() or (hov and ig.Col_ButtonHovered() or ig.Col_Button()))
  end
  ig.DrawList_AddCircleFilled(dl, x + d / 2, y + d / 2, d / 2, bg, 0)
  paint(x + d / 2, y + d / 2, on and T.sc_ink_on or T.sc_ink)
  if hov and tip then ig.SetTooltip(ctx, tip) end
  return clicked
end

-- the key source menu of one FX
function draw_sc_menu(tr, fx_guid, kind, cur)
  local src = cur and cur.src
  if src and not valid(src) then src = nil end
  local cur_rin = src and is_sc_in(src) and math.floor(reaper.GetMediaTrackInfo_Value(src, 'I_RECINPUT')) or nil
  local cur_bus = src and is_sc_bus(src) and reaper.GetTrackGUID(src) or nil

  ig.TextDisabled(ctx, kind == 1 and 'Sidechain input (mono)' or 'Sidechain input (stereo)')
  ig.Separator(ctx)
  if ig.MenuItem(ctx, 'None', nil, src == nil) then set_sidechain(tr, fx_guid, nil) end

  local n = reaper.GetNumAudioInputs()
  if n == 0 then ig.TextDisabled(ctx, '(no hardware inputs: see Preferences > Audio > Device)') end
  if n >= 1 and ig.BeginMenu(ctx, 'Mono Input') then
    for i = 0, n - 1 do
      local nm = reaper.GetInputChannelName(i) or ''
      if ig.MenuItem(ctx, ('%d  %s'):format(i + 1, nm), nil, cur_rin == i) then
        set_sidechain(tr, fx_guid, { input = i })
      end
    end
    ig.EndMenu(ctx)
  end
  if n >= 2 and ig.BeginMenu(ctx, kind == 1 and 'Stereo Input (summed to mono)' or 'Stereo Input') then
    for i = 0, n - 2, pair_step() do
      local nm = reaper.GetInputChannelName(i) or ''
      if ig.MenuItem(ctx, ('%d/%d  %s'):format(i + 1, i + 2, nm), nil, cur_rin == (i | 1024)) then
        set_sidechain(tr, fx_guid, { input = i | 1024 })
      end
    end
    ig.EndMenu(ctx)
  end
  if ig.BeginMenu(ctx, 'Bus') then
    if #sc_busses == 0 then ig.TextDisabled(ctx, '(no bus yet)') end
    for _, bus in ipairs(sc_busses) do
      if valid(bus) then
        local g = reaper.GetTrackGUID(bus)
        local loop = feeds(tr, bus)       -- this rack already feeds that bus
        local label = bus_name(bus) .. (loop and '   (fed by this rack)' or '') .. '##' .. g
        if ig.MenuItem(ctx, label, nil, cur_bus == g, not loop) then
          set_sidechain(tr, fx_guid, { bus = bus })
        end
      end
    end
    ig.Separator(ctx)
    if ig.MenuItem(ctx, 'Create new bus...') then
      prompt_new_bus('', function(bus) set_sidechain(tr, fx_guid, { bus = bus }) end)
    end
    ig.EndMenu(ctx)
  end
end

-- the "send to sidechain busses" list of a rack
function draw_bus_sends(tr)
  ig.TextDisabled(ctx, 'Send this rack to sidechain busses (after FX, before level)')
  ig.Separator(ctx)
  local pdl = ig.GetWindowDrawList(ctx)
  local fh = ig.GetFrameHeight(ctx)
  local spx = ig.GetStyleVar(ctx, ig.StyleVar_ItemSpacing())
  local fpy = select(2, ig.GetStyleVar(ctx, ig.StyleVar_FramePadding()))
  local name_w = 160

  if #sc_busses == 0 then ig.TextDisabled(ctx, '(no sidechain bus yet)') end
  for _, bus in ipairs(sc_busses) do
    if valid(bus) then
      ig.PushID(ctx, reaper.GetTrackGUID(bus))
      local i = bus_send(tr, bus)
      local on = i ~= nil
      local loop = (not on) and feeds(bus, tr)   -- that bus already feeds this rack
      local x, y = ig.GetCursorScreenPos(ctx)

      if loop then ig.BeginDisabled(ctx) end
      if circle_check(pdl, '##on', x, y, fh, on) then set_bus_send(tr, bus, not on) end
      if loop then ig.EndDisabled(ctx) end

      ig.SetCursorScreenPos(ctx, x + fh + spx, y)
      ig.InvisibleButton(ctx, '##nm', name_w, fh)
      if ig.IsItemHovered(ctx) then
        ig.SetTooltip(ctx, loop and 'This bus already feeds this rack (would loop)' or 'Right-click: rename or delete the bus')
      end
      if ig.BeginPopupContextItem(ctx, 'bus_ctx') then
        if ig.MenuItem(ctx, 'Rename bus...') then prompt_rename_bus(bus) end
        if ig.MenuItem(ctx, 'Delete bus...') then
          request_confirm(('Delete the sidechain bus "%s"?\nEvery send to it and every key listening to it goes too.')
                          :format(bus_name(bus)), function() delete_bus(bus) end, 'Delete')
        end
        ig.EndPopup(ctx)
      end
      local nm = fit_text(bus_name(bus), name_w)
      ig.DrawList_AddText(pdl, x + fh + spx, y + fpy, ig.GetStyleColor(ctx, loop and ig.Col_TextDisabled() or ig.Col_Text()), nm)

      ig.SetCursorScreenPos(ctx, x + fh + spx + name_w + spx, y)
      ig.SetNextItemWidth(ctx, 140)
      if on then
        local vol = reaper.GetTrackSendInfo_Value(tr, 0, i, 'D_VOL')
        local db = clamp(vol > 0.000001 and amp_to_db(vol) or LEVEL_MIN, LEVEL_MIN, LEVEL_MAX)
        local rv, nd = ig.SliderDouble(ctx, '##lv', db, LEVEL_MIN, LEVEL_MAX,
                                       db <= LEVEL_MIN + 0.05 and '-inf' or '%.1f dB')
        if rv then
          reaper.SetTrackSendInfo_Value(tr, 0, i, 'D_VOL', nd <= LEVEL_MIN + 0.05 and 0 or 10.0 ^ (nd / 20.0))
        end
        if ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, ('Send level (%s-click to type a value)'):format(IS_MAC and 'Cmd' or 'Ctrl')) end
        hint_hovered(('Drag: send level  \194\183  %s+click: type a value'):format(mod_label('ctrl')))
      else
        ig.BeginDisabled(ctx)
        ig.SliderDouble(ctx, '##lv', LEVEL_MIN, LEVEL_MIN, LEVEL_MAX, 'off')
        ig.EndDisabled(ctx)
      end
      ig.PopID(ctx)
    end
  end

  ig.Separator(ctx)
  if ig.Selectable(ctx, 'Create new sidechain bus...') then
    prompt_new_bus(raw_name(tr), function(bus) set_bus_send(tr, bus, true) end)
  end
end

