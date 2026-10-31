-- FOHMate/modes.lua: modes and selection.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- modes and selection

-- Show mode locks everything that changes the structure of the racks:
-- creating, renaming, reordering, recoloring, routing, loading/removing FX.
-- Level, mute, bypass, FX on/off, A/B and opening FX windows stay usable.
function is_locked()
  return S.mode == 'show'
end

function lock_begin(on)
  if on and ig.BeginDisabled then ig.BeginDisabled(ctx, true) end
end

function lock_end(on)
  if on and ig.EndDisabled then ig.EndDisabled(ctx) end
end

function set_mode(mode)
  local was = S.mode
  S.mode = mode
  save_setting('mode', mode)
  if mode == 'show' and was ~= 'show' and S.show_off then
    local n = offline_for_show()
    if n > 0 then SHOWOFF_MSG = { text = ('%d FX taken offline for latency'):format(n), t = reaper.time_precise() } end
  elseif mode == 'edit' and was == 'show' then
    online_after_show()
  end
end

-- a rack's selection is REAPER's own track selection
function rack_selected(tr)
  return reaper.IsTrackSelected(tr)
end

-- click = only this rack; Cmd/Ctrl-click = add to / remove from the selection
function select_rack(tr, additive)
  if additive then
    reaper.SetTrackSelected(tr, not reaper.IsTrackSelected(tr))
  else
    reaper.SetOnlyTrackSelected(tr)
  end
end

function deselect_racks()
  for _, t in ipairs(racks) do
    if valid(t) then reaper.SetTrackSelected(t, false) end
  end
end

-- racks an action from the Rack Option Menu applies to: all selected racks when
-- the rack it was opened on is selected, otherwise just that rack
function targets_for(tr)
  if reaper.IsTrackSelected(tr) then
    local out = {}
    for _, t in ipairs(racks) do
      if valid(t) and reaper.IsTrackSelected(t) then out[#out + 1] = t end
    end
    if #out > 0 then return out end
  end
  return { tr }
end

-- runs fn(rack) on every target; with several racks it asks first
function rack_action(tr, what, fn, label)
  local trs = targets_for(tr)
  -- runs once the frame is drawn: changing a rack's FX while it is being
  -- drawn would leave the rest of the frame working on FX that are gone
  local function go()
    later[#later + 1] = function()
      for _, t in ipairs(trs) do
        if valid(t) then fn(t) end
      end
      last_scan = -math.huge
    end
  end
  if #trs > 1 then
    request_confirm(('%s\nfor the %d selected racks?'):format(what, #trs), go, label or 'Apply', 'multi_rack')
  else
    go()
  end
end

