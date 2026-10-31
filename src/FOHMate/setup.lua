-- FOHMate/setup.lua: scan / setup.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- scan / setup

function add_meter(tr, stage, slot)
  local idx = reaper.TrackFX_AddByName(tr, 'JS:' .. METER_PATH, false, -1)
  if idx < 0 then idx = reaper.TrackFX_AddByName(tr, 'JS: ' .. METER_NAME, false, -1) end
  if idx < 0 then return nil end
  reaper.TrackFX_SetParam(tr, idx, 0, slot)
  reaper.TrackFX_SetParam(tr, idx, 1, stage)
  return idx
end

function ensure_setup(tr, slot)
  slot = math.min(slot, 255)

  -- racks are never routed to the master
  if reaper.GetMediaTrackInfo_Value(tr, 'B_MAINSEND') ~= 0 then
    reaper.SetMediaTrackInfo_Value(tr, 'B_MAINSEND', 0)
  end

  local changed = false
  if reaper.GetMediaTrackInfo_Value(tr, 'B_SHOWINTCP') ~= 0 then
    reaper.SetMediaTrackInfo_Value(tr, 'B_SHOWINTCP', 0); changed = true
  end
  if reaper.GetMediaTrackInfo_Value(tr, 'B_SHOWINMIXER') ~= 0 then
    reaper.SetMediaTrackInfo_Value(tr, 'B_SHOWINMIXER', 0); changed = true
  end

  local info = chain_info(tr)

  -- troubleshooting switch: no meters, so no meter JSFX in the audio path either
  if S.no_meters then
    local gone = {}
    for _, fx in ipairs(info.legacy) do gone[#gone + 1] = fx end
    for _, fx in ipairs(info.extras) do gone[#gone + 1] = fx end
    if info.in_fx then gone[#gone + 1] = info.in_fx end
    if info.out_fx then gone[#gone + 1] = info.out_fx end
    table.sort(gone, function(a, b) return a > b end)
    for _, fx in ipairs(gone) do reaper.TrackFX_Delete(tr, fx) end
    if changed then
      reaper.TrackList_AdjustWindows(false)
      reaper.UpdateArrange()
    end
    return
  end

  -- v0.2 meters and duplicates go away
  local kill = {}
  for _, fx in ipairs(info.legacy) do kill[#kill + 1] = fx end
  for _, fx in ipairs(info.extras) do kill[#kill + 1] = fx end
  if #kill > 0 then
    table.sort(kill, function(a, b) return a > b end)
    for _, fx in ipairs(kill) do reaper.TrackFX_Delete(tr, fx) end
    info = chain_info(tr)
  end

  -- input meter: always the first FX
  if not info.in_fx then
    local idx = add_meter(tr, 0, slot)
    if idx then move_fx(tr, idx, 0)
    else meter_error = 'Could not add the meter JSFX. Restart REAPER or refresh the FX list.' end
    info = chain_info(tr)
  elseif info.in_fx ~= 0 then
    move_fx(tr, info.in_fx, 0)
    info = chain_info(tr)
  end

  -- output meter: always the last FX
  if not info.out_fx then
    local idx = add_meter(tr, 1, slot)
    if idx then move_fx(tr, idx, reaper.TrackFX_GetCount(tr) - 1)
    else meter_error = 'Could not add the meter JSFX. Restart REAPER or refresh the FX list.' end
    info = chain_info(tr)
  elseif info.out_fx ~= reaper.TrackFX_GetCount(tr) - 1 then
    move_fx(tr, info.out_fx, reaper.TrackFX_GetCount(tr) - 1)
    info = chain_info(tr)
  end

  for _, fx in ipairs({ info.in_fx or -1, info.out_fx or -1 }) do
    if fx >= 0 then
      local cur = reaper.TrackFX_GetParam(tr, fx, 0)
      if math.floor(cur + 0.5) ~= slot then reaper.TrackFX_SetParam(tr, fx, 0, slot) end
    end
  end

  if changed then
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
  end
end

function scan()
  local found, busses, hid = {}, {}, false
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local name = track_name(tr)
    if is_rack_name(name) then
      found[#found + 1] = tr
    elseif has_prefix(name, SC_BUS_PREFIX) then
      busses[#busses + 1] = tr
      hid = keep_helper_clean(tr, true) or hid
    elseif has_prefix(name, SC_IN_PREFIX) then
      hid = keep_helper_clean(tr, false) or hid
    end
  end
  if hid then reaper.TrackList_AdjustWindows(false); reaper.UpdateArrange() end
  racks = found
  sc_busses = busses
  meter_error = nil
  for i, tr in ipairs(racks) do
    ensure_setup(tr, i - 1)
    width_maintain(tr)
    sc_maintain(tr, chain_info(tr))
  end
end

