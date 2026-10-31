-- FOHMate/sidechain.lua: sidechain.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- sidechain
--
-- How it works (all plain REAPER routing, visible in the routing window):
--  * an FX with more than 2 input pins has a key input (3 pins = mono key,
--    4+ pins = stereo key on pins 3/4)
--  * each keyed FX gets its own pair of track channels (3/4, 5/6, ...); the
--    FX's key pins listen to that pair only. The pair is remembered per FX
--    (EXT_SC), so FX can be reordered freely.
--  * the key arrives on that pair as a receive, from either
--      - an "SC BUS:" track (racks send to it with the button next to the level), or
--      - an "SC IN:" track that monitors a hardware input (one per input, shared)
--  * a stereo source into a mono key is summed by two receives at -6 dB each.

function has_prefix(name, p)
  return name:sub(1, #p):upper() == p:upper()
end

function strip_prefix(name, p)
  return (name:sub(#p + 1):match('^%s*(.-)%s*$'))
end

function is_sc_bus(tr) return has_prefix(track_name(tr), SC_BUS_PREFIX) end
function is_sc_in(tr)  return has_prefix(track_name(tr), SC_IN_PREFIX) end
function is_sc_track(tr) return is_sc_bus(tr) or is_sc_in(tr) end

function bus_name(tr)
  local n = strip_prefix(track_name(tr), SC_BUS_PREFIX)
  return n ~= '' and n or '(unnamed)'
end

-- The key pins are the inputs beyond the main ones (main = as many as the
-- outputs): 4 in / 2 out = stereo key, 3/2 = mono key, and on mono plugins
-- 2/1 = mono key, 3/1 = stereo key.
-- Returns kind (0 = no key input, 1 = mono key, 2 = stereo key) and the first key pin.
-- (What the plug-in has; sc_key below says what the key is used as.)
function sc_kind(tr, fx)
  local _, ins, outs = reaper.TrackFX_GetIOSize(tr, fx)
  ins, outs = ins or 0, outs or 0
  if outs < 1 then return 0, 0 end
  local extra = ins - outs
  if extra >= 2 then return 2, outs elseif extra == 1 then return 1, outs end
  return 0, 0
end

function sc_read(tr)
  local map = {}
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, EXT_SC, '', false)
  if ok and s ~= '' then
    for g, c in s:gmatch('([^;=]+)=(%d+)') do map[g] = tonumber(c) end
  end
  return map
end

function sc_write(tr, map)
  local t = {}
  for g, c in pairs(map) do t[#t + 1] = g .. '=' .. c end
  table.sort(t)
  reaper.GetSetMediaTrackInfo_String(tr, EXT_SC, table.concat(t, ';'), true)
end

function chan_mask(c)
  if not c then return 0, 0 end
  if c < 32 then return 1 << c, 0 end
  return 0, 1 << (c - 32)
end

-- The key as it is used: a mono FX (one output, or on the mono part of its rack) always
-- gets a mono key, even when the plug-in has two key pins: both pins then hear the same
-- mono signal. mono: true/false when known (the FX's width in its rack), nil to look it up.
-- Returns the key kind used (0/1/2), the first key pin, and how many key pins it has.
function sc_key(tr, fx, mono)
  local kind, first = sc_kind(tr, fx)
  if kind ~= 2 then return kind, first, kind end
  if mono == nil then
    local list = chain_info(tr).list
    local t = fx_widths(tr, list)
    for i, it in ipairs(list) do
      if it.fx == fx then mono = (t[i] == W_MONO) break end
    end
  end
  local _, _, outs = reaper.TrackFX_GetIOSize(tr, fx)
  if mono or outs == 1 then return 1, first, 2 end
  return 2, first, 2
end

-- key pins of `fx` (from pin `first`) -> channel pair starting at c (nil = listen to nothing).
-- pins: how many key pins the plug-in has (a mono key on two pins feeds both from channel c)
function sc_set_pins(tr, fx, kind, c, first, pins)
  local lo, hi = chan_mask(c)
  local changed = false
  local function set(pin, l, h)
    local cl, ch = reaper.TrackFX_GetPinMappings(tr, fx, 0, pin)
    if cl ~= l or (ch or 0) ~= h then
      changed = write_once(tr, fx, ':in' .. pin, l .. '/' .. h,
                           function() reaper.TrackFX_SetPinMappings(tr, fx, 0, pin, l, h) end) or changed
    end
  end
  set(first, lo, hi)
  if kind == 2 then
    local lo2, hi2 = chan_mask(c and c + 1)
    set(first + 1, lo2, hi2)
  elseif (pins or kind) == 2 then
    set(first + 1, lo, hi)              -- mono key on a two-pin key input: same channel on both
  end
  return changed
end

-- receives of a rack that come from a sidechain helper track
function sc_receives(tr)
  local out = {}
  for i = 0, reaper.GetTrackNumSends(tr, -1) - 1 do
    local src = reaper.GetTrackSendInfo_Value(tr, -1, i, 'P_SRCTRACK')
    if src and valid(src) and is_sc_track(src) then
      local d = math.floor(reaper.GetTrackSendInfo_Value(tr, -1, i, 'I_DSTCHAN'))
      out[#out + 1] = { idx = i, src = src, chan = d & 1023 }
    end
  end
  return out
end

-- what feeds the key of each FX: [fx guid] = { chan, src }
function sc_sources(tr)
  local map = sc_read(tr)
  local res = {}
  if next(map) == nil then return res end
  local by_chan = {}
  for _, r in ipairs(sc_receives(tr)) do by_chan[r.chan] = by_chan[r.chan] or r.src end
  for g, c in pairs(map) do res[g] = { chan = c, src = by_chan[c] } end
  return res
end

function input_label(rin)
  local idx = rin & 1023
  if rin & 1024 ~= 0 then return ('In %d/%d'):format(idx + 1, idx + 2) end
  return ('In %d'):format(idx + 1)
end

-- text for a key source: bus name or hardware input
function source_label(src)
  if not src or not valid(src) then return nil end
  if is_sc_bus(src) then return 'Bus: ' .. bus_name(src) end
  local rin = math.floor(reaper.GetMediaTrackInfo_Value(src, 'I_RECINPUT'))
  if rin >= 0 then return input_label(rin) end
  return strip_prefix(track_name(src), SC_IN_PREFIX)
end

-- a hidden helper track at the end of the project
function make_helper_track(name)
  local n = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(n, false)
  local tr = reaper.GetTrack(0, n)
  reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', name, true)
  reaper.SetMediaTrackInfo_Value(tr, 'B_MAINSEND', 0)
  reaper.SetMediaTrackInfo_Value(tr, 'B_SHOWINTCP', 0)
  reaper.SetMediaTrackInfo_Value(tr, 'B_SHOWINMIXER', 0)
  reaper.SetMediaTrackInfo_Value(tr, 'I_NCHAN', 2)
  reaper.TrackList_AdjustWindows(false)
  return tr
end

-- hidden, never to the master, never to hardware outs; busses never take a hardware input
function keep_helper_clean(tr, bus)
  if reaper.GetMediaTrackInfo_Value(tr, 'B_MAINSEND') ~= 0 then reaper.SetMediaTrackInfo_Value(tr, 'B_MAINSEND', 0) end
  local changed = false
  if reaper.GetMediaTrackInfo_Value(tr, 'B_SHOWINTCP') ~= 0 then reaper.SetMediaTrackInfo_Value(tr, 'B_SHOWINTCP', 0); changed = true end
  if reaper.GetMediaTrackInfo_Value(tr, 'B_SHOWINMIXER') ~= 0 then reaper.SetMediaTrackInfo_Value(tr, 'B_SHOWINMIXER', 0); changed = true end
  for i = reaper.GetTrackNumSends(tr, 1) - 1, 0, -1 do reaper.RemoveTrackSend(tr, 1, i) end
  if bus and reaper.GetMediaTrackInfo_Value(tr, 'I_RECARM') ~= 0 then
    reaper.SetMediaTrackInfo_Value(tr, 'I_RECARM', 0)
    reaper.SetMediaTrackInfo_Value(tr, 'I_RECINPUT', -1)
  end
  return changed
end

function find_feeder(rin)
  for i = 0, reaper.CountTracks(0) - 1 do
    local t = reaper.GetTrack(0, i)
    if is_sc_in(t) and math.floor(reaper.GetMediaTrackInfo_Value(t, 'I_RECINPUT')) == rin then return t end
  end
  return nil
end

-- the SC IN track monitoring hardware input `rin` (created when missing)
function get_feeder(rin)
  local t = find_feeder(rin)
  if t then return t end
  t = make_helper_track(SC_IN_PREFIX .. ' ' .. input_label(rin))
  set_input(t, rin)
  return t
end

-- SC IN tracks nobody listens to any more go away
function remove_unused_feeders()
  for i = reaper.CountTracks(0) - 1, 0, -1 do
    local t = reaper.GetTrack(0, i)
    if is_sc_in(t) and reaper.GetTrackNumSends(t, 0) == 0 then reaper.DeleteTrack(t) end
  end
end

function unique_bus_name(base)
  local function used(n)
    for _, b in ipairs(sc_busses) do if valid(b) and bus_name(b):lower() == n:lower() then return true end end
    return false
  end
  if base ~= '' and not used(base) then return base end
  local root = base ~= '' and base or 'Bus'
  local n = 1
  while used(root .. ' ' .. n) do n = n + 1 end
  return root .. ' ' .. n
end

function create_bus(name)
  local tr = make_helper_track(SC_BUS_PREFIX .. ' ' .. unique_bus_name(name))
  sc_busses[#sc_busses + 1] = tr
  return tr
end

-- asks for a bus name (outside of the ImGui frame), then calls done(bus)
function prompt_new_bus(default, done)
  later[#later + 1] = function()
    local ok, name = reaper.GetUserInputs('New sidechain bus', 1, 'Bus name:,extrawidth=120', unique_bus_name(default or ''))
    if not ok then return end
    name = name:match('^%s*(.-)%s*$')
    with_undo('Rack: new sidechain bus', function()
      local bus = create_bus(name)
      if done then done(bus) end
    end)
    last_scan = -math.huge
  end
end

function prompt_rename_bus(bus)
  later[#later + 1] = function()
    if not valid(bus) then return end
    local ok, name = reaper.GetUserInputs('Rename sidechain bus', 1, 'Bus name:,extrawidth=120', bus_name(bus))
    if not ok then return end
    name = name:match('^%s*(.-)%s*$')
    if name == '' then return end
    with_undo('Rack: rename sidechain bus', function()
      reaper.GetSetMediaTrackInfo_String(bus, 'P_NAME', SC_BUS_PREFIX .. ' ' .. name, true)
    end)
  end
end

function delete_bus(bus)
  with_undo('Rack: delete sidechain bus', function()
    if valid(bus) then reaper.DeleteTrack(bus) end
  end)
  last_scan = -math.huge
end

-- would routing src -> dst make a loop? (true when dst already feeds src)
function feeds(dst, src)
  local target = reaper.GetTrackGUID(dst)
  local seen, stack = {}, { src }
  while #stack > 0 do
    local t = table.remove(stack)
    local g = reaper.GetTrackGUID(t)
    if g == target then return true end
    if not seen[g] then
      seen[g] = true
      for i = 0, reaper.GetTrackNumSends(t, -1) - 1 do
        local s = reaper.GetTrackSendInfo_Value(t, -1, i, 'P_SRCTRACK')
        if s and valid(s) then stack[#stack + 1] = s end
      end
    end
  end
  return false
end

function new_send(src, dst, srcchan, dstchan, vol)
  local i = reaper.CreateTrackSend(src, dst)
  if i < 0 then return end
  reaper.SetTrackSendInfo_Value(src, 0, i, 'I_SRCCHAN', srcchan)
  reaper.SetTrackSendInfo_Value(src, 0, i, 'I_DSTCHAN', dstchan)
  reaper.SetTrackSendInfo_Value(src, 0, i, 'D_VOL', vol or 1.0)
  reaper.SetTrackSendInfo_Value(src, 0, i, 'I_MIDIFLAGS', 31)   -- audio only
  return i
end

-- removes the key receives arriving on channel pair c
function sc_unhook(tr, c)
  for i = reaper.GetTrackNumSends(tr, -1) - 1, 0, -1 do
    local src = reaper.GetTrackSendInfo_Value(tr, -1, i, 'P_SRCTRACK')
    local d = math.floor(reaper.GetTrackSendInfo_Value(tr, -1, i, 'I_DSTCHAN'))
    if src and valid(src) and is_sc_track(src) and (d & 1023) == c then
      reaper.RemoveTrackSend(tr, -1, i)
    end
  end
end

-- first channel pair (from 3/4 up) that nothing else uses
function free_pair(tr, map)
  local used = {}
  for _, c in pairs(map) do used[c] = true; used[c + 1] = true end
  for i = 0, reaper.GetTrackNumSends(tr, -1) - 1 do
    local d = math.floor(reaper.GetTrackSendInfo_Value(tr, -1, i, 'I_DSTCHAN'))
    local c = d & 1023
    used[c] = true
    if d & 1024 == 0 then used[c + 1] = true end
  end
  local c = 2
  while used[c] or used[c + 1] do c = c + 2 end
  return c
end

-- source: nil (no key), { input = rin } or { bus = track }
function set_sidechain(tr, fx_guid, source)
  WRITES = {}
  with_undo('Rack: sidechain', function()
    local fx = fx_index_by_guid(tr, fx_guid)
    if not fx then return end
    local kind, first, pins = sc_key(tr, fx)
    local map = sc_read(tr)
    local c = map[fx_guid]
    if c then sc_unhook(tr, c) end

    if not source or kind == 0 then
      map[fx_guid] = nil
      sc_write(tr, map)
      if kind > 0 then sc_set_pins(tr, fx, kind, nil, first, pins) end
      remove_unused_feeders()
      return
    end

    c = c or free_pair(tr, map)
    map[fx_guid] = c
    sc_write(tr, map)
    if reaper.GetMediaTrackInfo_Value(tr, 'I_NCHAN') < c + 2 then
      reaper.SetMediaTrackInfo_Value(tr, 'I_NCHAN', c + 2)
    end
    sc_set_pins(tr, fx, kind, c, first, pins)

    local src, stereo
    if source.bus then
      src, stereo = source.bus, true
    else
      src, stereo = get_feeder(source.input), (source.input & 1024) ~= 0
    end
    if kind == 2 then
      new_send(src, tr, stereo and 0 or 1024, c)               -- mono source goes to both sides
    elseif stereo then
      new_send(src, tr, 1024 | 0, c | 1024, 0.5)                -- stereo summed to mono
      new_send(src, tr, 1024 | 1, c | 1024, 0.5)
    else
      new_send(src, tr, 1024, c | 1024)
    end
    remove_unused_feeders()
  end)
end

-- the rack's send to a bus (index), or nil
function bus_send(tr, bus)
  local bg = reaper.GetTrackGUID(bus)
  for i = 0, reaper.GetTrackNumSends(tr, 0) - 1 do
    local d = reaper.GetTrackSendInfo_Value(tr, 0, i, 'P_DESTTRACK')
    if d and valid(d) and reaper.GetTrackGUID(d) == bg then return i end
  end
  return nil
end

function n_bus_sends(tr)
  local n = 0
  for i = 0, reaper.GetTrackNumSends(tr, 0) - 1 do
    local d = reaper.GetTrackSendInfo_Value(tr, 0, i, 'P_DESTTRACK')
    if d and valid(d) and is_sc_bus(d) then n = n + 1 end
  end
  return n
end

-- racks feed busses after their FX, before their level (riding the level
-- or level matching never changes how hard a key hits)
function set_bus_send(tr, bus, on)
  with_undo(on and 'Rack: send to sidechain bus' or 'Rack: remove sidechain send', function()
    local i = bus_send(tr, bus)
    if on and not i then
      i = new_send(tr, bus, 0, 0)
      if i then reaper.SetTrackSendInfo_Value(tr, 0, i, 'I_SENDMODE', 3) end
    elseif not on and i then
      reaper.RemoveTrackSend(tr, 0, i)
    end
  end)
end

-- housekeeping for one rack, run by scan(): forget FX that are gone, drop
-- key receives nobody listens to, and keep the key pins where they belong
-- (REAPER maps the extra pins of newly added FX to channels 3/4 by default)
function sc_maintain(tr, info)
  local map = sc_read(tr)
  local nch = reaper.GetMediaTrackInfo_Value(tr, 'I_NCHAN')

  local present, dirty = {}, false
  for _, it in ipairs(info.list) do
    local g = reaper.TrackFX_GetFXGUID(tr, it.fx)
    present[g] = it.fx
  end
  for g in pairs(map) do
    if not present[g] then map[g] = nil; dirty = true end
  end
  if dirty then sc_write(tr, map) end

  local claimed = {}
  for _, c in pairs(map) do claimed[c] = true end
  local dropped = false
  for i = reaper.GetTrackNumSends(tr, -1) - 1, 0, -1 do
    local src = reaper.GetTrackSendInfo_Value(tr, -1, i, 'P_SRCTRACK')
    local d = math.floor(reaper.GetTrackSendInfo_Value(tr, -1, i, 'I_DSTCHAN'))
    if src and valid(src) and is_sc_track(src) and not claimed[d & 1023] then
      reaper.RemoveTrackSend(tr, -1, i)
      dropped = true
    end
  end
  if dropped then remove_unused_feeders() end

  local need = 2
  for _, c in pairs(map) do need = math.max(need, c + 2) end
  if nch < need then reaper.SetMediaTrackInfo_Value(tr, 'I_NCHAN', need); nch = need end
  -- key pins: on the channels of their key when one is assigned, else on nothing. Only pins that
  -- reach an existing track channel matter (a mono FX's key pin lands on channel 2 = the audio).
  local exists = (1 << math.min(31, math.floor(nch))) - 1
  local widths = fx_widths(tr, info.list)
  local rebuild = {}
  for i, it in ipairs(info.list) do
    local fx, g = it.fx, reaper.TrackFX_GetFXGUID(tr, it.fx)
    local kind, first, pins = sc_key(tr, fx, widths[i] == W_MONO)
    if kind > 0 then
      if map[g] then
        sc_set_pins(tr, fx, kind, map[g], first, pins)
        -- the key's receives must match its width: one summed channel for a mono key, a pair
        -- for a stereo one (an FX that changed width since, e.g. after a routing change)
        for _, r in ipairs(sc_receives(tr)) do
          if r.chan == map[g] then
            local mono_dst = math.floor(reaper.GetTrackSendInfo_Value(tr, -1, r.idx, 'I_DSTCHAN')) & 1024 ~= 0
            if mono_dst ~= (kind == 1) then rebuild[#rebuild + 1] = { g = g, src = r.src } end
            break
          end
        end
      else
        local hears = false
        for p = first, first + pins - 1 do
          if (reaper.TrackFX_GetPinMappings(tr, fx, 0, p) & exists) ~= 0 then hears = true end
        end
        if hears then sc_set_pins(tr, fx, kind, nil, first, pins) end
      end
    end
  end
  for _, rb in ipairs(rebuild) do
    if valid(rb.src) then
      local source
      if is_sc_bus(rb.src) then
        source = { bus = rb.src }
      else
        source = { input = math.floor(reaper.GetMediaTrackInfo_Value(rb.src, 'I_RECINPUT')) }
      end
      if source.bus or source.input >= 0 then set_sidechain(tr, rb.g, source) end
    end
  end
end

