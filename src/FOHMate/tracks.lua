-- FOHMate/tracks.lua: tracks and routing.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- tracks

function save_selection()
  local prev = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    prev[#prev + 1] = reaper.GetSelectedTrack(0, i)
  end
  return prev
end

function restore_selection(prev)
  reaper.Main_OnCommand(40297, 0)          -- unselect all tracks
  for _, t in ipairs(prev) do
    if valid(t) then reaper.SetTrackSelected(t, true) end
  end
end

-- Runs an action with only `tr` selected, then restores the selection.
function run_with_only_selected(tr, cmd)
  local prev = save_selection()
  reaper.Main_OnCommand(40297, 0)
  reaper.SetTrackSelected(tr, true)
  reaper.Main_OnCommand(cmd, 0)
  restore_selection(prev)
end

-- 40293 opens the routing window of the *last touched* track, which is not
-- the same as the selected one (clicking around in the routing matrix, for
-- example, changes it). So the rack is made the last touched track first.
function open_routing(tr)
  local prev = save_selection()
  reaper.Main_OnCommand(40297, 0)          -- unselect all tracks
  reaper.SetTrackSelected(tr, true)
  reaper.Main_OnCommand(40914, 0)          -- Track: Set first selected track as last touched track
  reaper.Main_OnCommand(40293, 0)          -- Track: View routing and I/O for current/last touched track
  restore_selection(prev)
end

-- removes every input and output of a track
function disconnect_track(tr)
  for cat = 1, -1, -1 do                   -- 1 = hardware outs, 0 = sends, -1 = receives
    for i = reaper.GetTrackNumSends(tr, cat) - 1, 0, -1 do
      reaper.RemoveTrackSend(tr, cat, i)
    end
  end
  reaper.SetMediaTrackInfo_Value(tr, 'I_RECARM', 0)
  reaper.SetMediaTrackInfo_Value(tr, 'I_RECINPUT', -1)
  reaper.SetMediaTrackInfo_Value(tr, 'B_MAINSEND', 0)
end

-- duplicates a track with everything (FX, parameters, routing, level...)
function duplicate_track(tr)
  local prev = save_selection()
  reaper.Main_OnCommand(40297, 0)
  reaper.SetTrackSelected(tr, true)
  reaper.Main_OnCommand(40062, 0)          -- Track: Duplicate tracks
  local new = reaper.GetSelectedTrack(0, 0)
  restore_selection(prev)
  return new
end

-- naming, color and (optionally) disconnection shared by copies and templates
function finish_copy(new, src, suffix)
  reaper.GetSetMediaTrackInfo_String(new, 'P_NAME', PREFIX .. ' ' .. raw_name(src) .. ' ' .. suffix, true)
  if S.disconnect then disconnect_track(new) else sc_copy_keys(src, new) end
  latok_copy(src, new)
  local i = rack_index(src)
  local r, g, b = color_for_new(src, i and racks[i + 1] or nil)
  set_track_rgb(new, r, g, b)
end

function duplicate_rack(tr)
  local new
  with_undo('Rack: duplicate', function()
    new = duplicate_track(tr)
    if new then finish_copy(new, tr, 'copy') end
  end)
  last_scan = -math.huge
  return new
end

-- same rack, same FX, but every FX re-added with its default parameters
function template_rack(tr)
  with_undo('Rack: new rack from template', function()
    local new = duplicate_track(tr)
    if not new then return end
    finish_copy(new, tr, 'template')
    reaper.GetSetMediaTrackInfo_String(new, EXT_BYPASS, '', true)

    local list = chain_info(new).list
    local names = {}
    for i, it in ipairs(list) do
      local ok, ident = reaper.TrackFX_GetNamedConfigParm(new, it.fx, 'fx_ident')
      names[i] = { name = it.name, ident = ok and ident or nil }
    end
    for i = #list, 1, -1 do reaper.TrackFX_Delete(new, list[i].fx) end
    for _, n in ipairs(names) do
      local idx = reaper.TrackFX_AddByName(new, n.name, false, -1)
      if idx < 0 and n.ident then reaper.TrackFX_AddByName(new, n.ident, false, -1) end
    end
    if not S.disconnect then sc_copy_keys(tr, new) end
    latok_copy(tr, new)
  end)
  last_scan = -math.huge
end

-- a new empty rack after the last rack: no FX, no routing, default name
function create_rack()
  with_undo('Rack: new rack', function()
    local last = racks[#racks]
    local idx = last and math.floor(reaper.GetMediaTrackInfo_Value(last, 'IP_TRACKNUMBER'))
                or reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(idx, true)
    local tr = reaper.GetTrack(0, idx)
    if not tr then return end

    local n = #racks + 1
    local function used(name)
      for _, t in ipairs(racks) do if raw_name(t) == name then return true end end
      return false
    end
    while used('Rack ' .. n) do n = n + 1 end
    reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', PREFIX .. ' Rack ' .. n, true)
    disconnect_track(tr)
    local r, g, b = color_for_new(last, nil)
    set_track_rgb(tr, r, g, b)
  end)
  last_scan = -math.huge
end

-- moves a rack in the project track order (the panel follows track order)
function reorder_rack(src, dst)
  if src == dst then return end
  local sn = reaper.GetMediaTrackInfo_Value(src, 'IP_TRACKNUMBER')
  local dn = reaper.GetMediaTrackInfo_Value(dst, 'IP_TRACKNUMBER')
  if sn < 1 or dn < 1 then return end
  local before = (sn < dn) and dn or (dn - 1)   -- 0-based index to insert before
  with_undo('Rack: reorder racks', function()
    local prev = save_selection()
    reaper.Main_OnCommand(40297, 0)
    reaper.SetTrackSelected(src, true)
    reaper.ReorderSelectedTracks(before, 0)
    restore_selection(prev)
  end)
  last_scan = -math.huge
end

---------------------------------------------------------------- routing

-- stereo pairs offered in the In, Out and key menus: every channel, or odd-even
-- pairs only (1/2, 3/4...) with Options > Stereo pairs on odd-even channels only
function pair_step()
  return S.odd_even and 2 or 1
end

function in_text(tr)
  local parts = {}
  if reaper.GetMediaTrackInfo_Value(tr, 'I_RECARM') == 1 then
    local rin = math.floor(reaper.GetMediaTrackInfo_Value(tr, 'I_RECINPUT'))
    if rin >= 0 then
      if rin & 4096 ~= 0 then
        parts[#parts + 1] = 'MIDI'
      else
        local idx, pre = rin & 1023, ''
        if idx >= 512 then idx = idx - 512; pre = 'Rt ' end
        if rin & 2048 ~= 0 then
          parts[#parts + 1] = pre .. (idx + 1) .. '+'
        elseif rin & 1024 ~= 0 then
          parts[#parts + 1] = ('%s%d/%d'):format(pre, idx + 1, idx + 2)
        else
          parts[#parts + 1] = pre .. (idx + 1)
        end
      end
    end
  end
  local nrcv = reaper.GetTrackNumSends(tr, -1) - #sc_receives(tr)
  if nrcv > 0 then parts[#parts + 1] = 'rcv x' .. nrcv end
  if #parts == 0 then return '-' end
  return table.concat(parts, ', ')
end

function out_text(tr)
  local parts = {}
  for i = 0, reaper.GetTrackNumSends(tr, 1) - 1 do
    local d = math.floor(reaper.GetTrackSendInfo_Value(tr, 1, i, 'I_DSTCHAN'))
    local idx = d & 1023
    if d & 1024 ~= 0 then
      parts[#parts + 1] = tostring(idx + 1)
    else
      parts[#parts + 1] = ('%d/%d'):format(idx + 1, idx + 2)
    end
  end
  local ns = reaper.GetTrackNumSends(tr, 0) - n_bus_sends(tr)
  if ns > 0 then parts[#parts + 1] = 'snd x' .. ns end
  if #parts == 0 then return '-' end
  return table.concat(parts, ', ')
end

function set_input(tr, val)
  last_scan = -math.huge          -- the FX are refitted to the new width on the next frame
  if val < 0 then
    reaper.SetMediaTrackInfo_Value(tr, 'I_RECARM', 0)
    reaper.SetMediaTrackInfo_Value(tr, 'I_RECINPUT', -1)
  else
    reaper.SetMediaTrackInfo_Value(tr, 'I_RECINPUT', val)
    reaper.SetMediaTrackInfo_Value(tr, 'I_RECMODE', 2)   -- monitor only, never record
    reaper.SetMediaTrackInfo_Value(tr, 'I_RECMON', 1)
    reaper.SetMediaTrackInfo_Value(tr, 'I_RECARM', 1)
  end
end

function set_hw_out(tr, dst)
  last_scan = -math.huge
  for i = reaper.GetTrackNumSends(tr, 1) - 1, 0, -1 do
    reaper.RemoveTrackSend(tr, 1, i)
  end
  if dst then
    local idx = reaper.CreateTrackSend(tr, nil)
    reaper.SetTrackSendInfo_Value(tr, 1, idx, 'I_DSTCHAN', dst)
  end
end

