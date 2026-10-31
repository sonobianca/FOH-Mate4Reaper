-- FOHMate/chain.lua: FX chain.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- chain

-- Splits the FX chain into: the input meter, the output meter, the real
-- FX (the only thing shown to the user) and leftovers to clean up.
-- Meter JSFX of earlier versions (named RackPanel, then LiveRack) are replaced automatically.
function is_legacy_meter(name)
  return name:find('RackPanel', 1, true) or name:find('LiveRack', 1, true)
end

-- P_EXT keys that tracks saved under the old names (Live Rack, RackPanel): moved once per track.
TRACK_EXT_MOVES = {
  { 'P_EXT:LiveRack_bypass',  EXT_BYPASS  },
  { 'P_EXT:LiveRack_sc',      EXT_SC      },
  { 'P_EXT:LiveRack_io',      EXT_IO      },
  { 'P_EXT:LiveRack_latok',   EXT_LATOK   },
  { 'P_EXT:LiveRack_showoff', EXT_SHOWOFF },
  { 'P_EXT:LiveRack_split',   EXT_SPLIT   },
}
ext_moved = {}
function migrate_track_ext(tr)
  local g = reaper.GetTrackGUID(tr)
  if ext_moved[g] then return end
  ext_moved[g] = true
  for _, m in ipairs(TRACK_EXT_MOVES) do
    local ok, v = reaper.GetSetMediaTrackInfo_String(tr, m[1], '', false)
    if ok and v ~= '' then
      local ok2, cur = reaper.GetSetMediaTrackInfo_String(tr, m[2], '', false)
      if not (ok2 and cur ~= '') then reaper.GetSetMediaTrackInfo_String(tr, m[2], v, true) end
      reaper.GetSetMediaTrackInfo_String(tr, m[1], '', true)
    end
  end
end

function chain_info(tr)
  migrate_track_ext(tr)
  local info = { list = {}, legacy = {}, extras = {} }
  for fx = 0, reaper.TrackFX_GetCount(tr) - 1 do
    local _, name = reaper.TrackFX_GetFXName(tr, fx, '')
    if is_legacy_meter(name) then
      info.legacy[#info.legacy + 1] = fx
    elseif name:find(METER_NAME, 1, true) then
      local stage = math.floor(reaper.TrackFX_GetParam(tr, fx, 1) + 0.5)
      if stage == 0 then
        if info.in_fx then info.extras[#info.extras + 1] = fx else info.in_fx = fx end
      else
        if info.out_fx then info.extras[#info.extras + 1] = fx else info.out_fx = fx end
      end
    else
      info.list[#info.list + 1] = { fx = fx, name = name, enabled = reaper.TrackFX_GetEnabled(tr, fx) }
    end
  end
  return info
end

function fx_index_by_guid(tr, guid)
  for i = 0, reaper.TrackFX_GetCount(tr) - 1 do
    if reaper.TrackFX_GetFXGUID(tr, i) == guid then return i end
  end
  return nil
end

-- Moves an FX so that it ends up at index `dst`. The result is verified and
-- corrected once, so it does not matter how REAPER counts the destination.
function move_fx(tr, src, dst)
  if src == dst then return end
  local g = reaper.TrackFX_GetFXGUID(tr, src)
  reaper.TrackFX_CopyToTrack(tr, src, tr, dst, true)
  local f = fx_index_by_guid(tr, g)
  if f and f ~= dst then
    reaper.TrackFX_CopyToTrack(tr, f, tr, dst + (dst - f), true)
  end
end

function get_saved_bypass(tr)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, EXT_BYPASS, '', false)
  if ok and s ~= '' then return s end
  -- state saved by an earlier version: move it to the new key
  local ok2, old = reaper.GetSetMediaTrackInfo_String(tr, OLD_EXT_BYPASS, '', false)
  if ok2 and old ~= '' then
    reaper.GetSetMediaTrackInfo_String(tr, EXT_BYPASS, old, true)
    reaper.GetSetMediaTrackInfo_String(tr, OLD_EXT_BYPASS, '', true)
    return old
  end
  return nil
end

function is_bypassed(tr, list)
  if not get_saved_bypass(tr) then return false end
  for _, it in ipairs(list) do
    if it.enabled then
      -- an FX was re-enabled by hand: forget the stale bypass state
      reaper.GetSetMediaTrackInfo_String(tr, EXT_BYPASS, '', true)
      return false
    end
  end
  return true
end

-- bypass = disable every FX (the meters keep running)
function set_bypass(tr, on)
  local list = chain_info(tr).list
  if on then
    local t = {}
    for i, it in ipairs(list) do t[i] = it.enabled and '1' or '0' end
    reaper.GetSetMediaTrackInfo_String(tr, EXT_BYPASS, (#t > 0) and table.concat(t, ',') or 'x', true)
    for _, it in ipairs(list) do reaper.TrackFX_SetEnabled(tr, it.fx, false) end
  else
    local s = get_saved_bypass(tr)
    local states = {}
    if s then for v in s:gmatch('[01]') do states[#states + 1] = v end end
    for i, it in ipairs(list) do
      local st = states[i]
      reaper.TrackFX_SetEnabled(tr, it.fx, st == nil or st == '1')
    end
    reaper.GetSetMediaTrackInfo_String(tr, EXT_BYPASS, '', true)
  end
end

function unbypass_if_needed(tr)
  if get_saved_bypass(tr) then set_bypass(tr, false) end
end

function remove_all_fx(tr)
  with_undo('Rack: remove every FX', function()
    local list = chain_info(tr).list
    for i = #list, 1, -1 do reaper.TrackFX_Delete(tr, list[i].fx) end
    reaper.GetSetMediaTrackInfo_String(tr, EXT_BYPASS, '', true)
  end)
end

function remove_bypassed_fx(tr)
  with_undo('Rack: remove bypassed FX', function()
    unbypass_if_needed(tr)
    local list = chain_info(tr).list
    for i = #list, 1, -1 do
      if not list[i].enabled then reaper.TrackFX_Delete(tr, list[i].fx) end
    end
  end)
end

function ab_invert(tr)
  with_undo('Rack: A/B FX', function()
    unbypass_if_needed(tr)
    for _, it in ipairs(chain_info(tr).list) do
      reaper.TrackFX_SetEnabled(tr, it.fx, not it.enabled)
    end
  end)
end

function revert_to_track(tr)
  with_undo('Rack: revert to regular track', function()
    unbypass_if_needed(tr)
    for fx = reaper.TrackFX_GetCount(tr) - 1, 0, -1 do
      local _, name = reaper.TrackFX_GetFXName(tr, fx, '')
      if name:find(METER_NAME, 1, true) or is_legacy_meter(name) then
        reaper.TrackFX_Delete(tr, fx)
      end
    end
    reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', raw_name(tr), true)
    reaper.SetMediaTrackInfo_Value(tr, 'B_SHOWINTCP', 1)
    reaper.SetMediaTrackInfo_Value(tr, 'B_SHOWINMIXER', 1)
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
  end)
  last_scan = -math.huge
end

function delete_rack(tr)
  with_undo('Rack: delete rack', function()
    reaper.DeleteTrack(tr)
  end)
  last_scan = -math.huge
end

-- adds an FX at the end of the rack's FX (always before the output meter)
function add_fx_to_rack(tr, ident)
  with_undo('Rack: add FX', function()
    local idx = reaper.TrackFX_AddByName(tr, ident, false, -1)
    if idx >= 0 then
      local g = reaper.TrackFX_GetFXGUID(tr, idx)
      local info = chain_info(tr)
      if info.out_fx and idx > info.out_fx then move_fx(tr, idx, info.out_fx) end
      fit_new_fx(tr, g)
    end
  end)
end

-- inserts an FX at `pos`; the FX from there on move down
function insert_fx_at(tr, ident, pos)
  with_undo('Rack: insert FX', function()
    local idx = reaper.TrackFX_AddByName(tr, ident, false, -1)
    if idx >= 0 then
      local g = reaper.TrackFX_GetFXGUID(tr, idx)
      move_fx(tr, idx, pos)
      fit_new_fx(tr, g)
    end
  end)
end

-- swaps the FX identified by `old_guid` for a new one (keeps the enabled state)
function replace_fx(tr, old_guid, ident)
  with_undo('Rack: replace FX', function()
    local pos = fx_index_by_guid(tr, old_guid)
    if not pos then return end
    local was_enabled = reaper.TrackFX_GetEnabled(tr, pos)
    local idx = reaper.TrackFX_AddByName(tr, ident, false, -1)
    if idx < 0 then return end
    local new_guid = reaper.TrackFX_GetFXGUID(tr, idx)
    move_fx(tr, idx, pos)
    local old = fx_index_by_guid(tr, old_guid)
    if old then reaper.TrackFX_Delete(tr, old) end
    local ni = fx_index_by_guid(tr, new_guid)
    if ni then
      reaper.TrackFX_SetEnabled(tr, ni, was_enabled)
      local map = sc_read(tr)
      if map[old_guid] then
        if sc_kind(tr, ni) > 0 then map[new_guid] = map[old_guid] end
        map[old_guid] = nil
        sc_write(tr, map)
      end
      fit_new_fx(tr, new_guid)
    end
  end)
end

function delete_fx(tr, guid)
  with_undo('Rack: delete FX', function()
    local pos = fx_index_by_guid(tr, guid)
    if pos then reaper.TrackFX_Delete(tr, pos) end
  end)
end

