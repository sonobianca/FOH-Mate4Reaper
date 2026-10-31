-- FOHMate/stereo.lua: mono / stereo, FX versions, the stereo point.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- mono / stereo
--
-- A rack's width follows its routing: the input side from its hardware input
-- (or, without one, its receives), the output side from its hardware outputs
-- (or, without any, its sends). Racks can be asymmetrical.
--   mono   -> mono   : every FX mono
--   stereo -> any    : every FX stereo (a mono output sums at the hardware out)
--   mono   -> stereo : mono up to the "stereo point", then stereo. The stereo
--                      point is the FX picked with right-click > Stereo from here,
--                      or else the first FX that comes in a mono-to-stereo
--                      version; without either the whole chain stays mono and
--                      the output carries it on both sides.
-- Each FX gets the matching version: REAPER's channel request when the plug-in
-- supports it (VST3: "Request VST3 bus channel count", settings are kept), or
-- else its Mono / Stereo / Mono-Stereo sibling when one is installed (Waves-style
-- names), with every parameter copied over by name. The single output of a mono
-- FX feeds both track channels, so meters, outputs and sends stay consistent.
-- FX versions are swapped only when the routing (or the stereo point) changes,
-- and on FX added to the rack; otherwise what you pick stays.

W_MONO, W_STEREO, W_MS = 1, 2, 3

function rack_io(tr)
  local iw, ow
  local rin = math.floor(reaper.GetMediaTrackInfo_Value(tr, 'I_RECINPUT'))
  if reaper.GetMediaTrackInfo_Value(tr, 'I_RECARM') == 1 and rin >= 0 and rin & 4096 == 0 then
    iw = (rin & 3072 ~= 0) and W_STEREO or W_MONO
  else
    local n, mono = 0, 0
    for i = 0, reaper.GetTrackNumSends(tr, -1) - 1 do
      local src = reaper.GetTrackSendInfo_Value(tr, -1, i, 'P_SRCTRACK')
      if not (src and valid(src) and is_sc_track(src)) then
        n = n + 1
        if math.floor(reaper.GetTrackSendInfo_Value(tr, -1, i, 'I_SRCCHAN')) & 1024 ~= 0 then mono = mono + 1 end
      end
    end
    iw = (n > 0 and mono == n) and W_MONO or W_STEREO
  end
  local nh = reaper.GetTrackNumSends(tr, 1)
  if nh > 0 then
    ow = W_MONO
    for i = 0, nh - 1 do
      if math.floor(reaper.GetTrackSendInfo_Value(tr, 1, i, 'I_DSTCHAN')) & 1024 == 0 then ow = W_STEREO end
    end
  else
    local n, mono = 0, 0
    for i = 0, reaper.GetTrackNumSends(tr, 0) - 1 do
      local d = reaper.GetTrackSendInfo_Value(tr, 0, i, 'P_DESTTRACK')
      if not (d and valid(d) and is_sc_bus(d)) then
        n = n + 1
        if math.floor(reaper.GetTrackSendInfo_Value(tr, 0, i, 'I_SRCCHAN')) & 1024 ~= 0 then mono = mono + 1 end
      end
    end
    if n == 0 then ow = iw else ow = (mono == n) and W_MONO or W_STEREO end
  end
  return iw, ow
end

function width_text(w)
  return (w == W_MONO and 'mono') or (w == W_MS and 'mono to stereo') or 'stereo'
end

---------------------------------------- FX versions (Mono / Stereo / Mono-Stereo siblings)

-- "VST3: C6 Mono/Stereo (Waves)" -> width 3, key "vst3: c6 (waves)". The width
-- word has to end the plug-in's name (before the developer), so names like
-- "Stereo Width" are left alone.
WIDTH_END = {
  { '[%s%-_]*%(?mono%s*[/%->_]+%s*stereo%)?$', W_MS }, { '[%s%-_]+%(?m%s*>%s*s%)?$', W_MS },
  { '[%s%-_]+%(?stereo%)?$', W_STEREO }, { '[%s%-_]+%(?mono%)?$', W_MONO },
}

function split_width(name)
  local low = name:lower()
  local pre, core, dev = low:match('^(%w+:%s*)(.-)(%s*%b()%s*)$')
  if not pre then
    pre, core = low:match('^(%w+:%s*)(.-)%s*$')
    dev = ''
  end
  if not pre then pre, core, dev = '', low, '' end
  for _, t in ipairs(WIDTH_END) do
    local at = core:find(t[1])
    if at and at > 1 then return t[2], pre .. core:sub(1, at - 1) .. dev end
  end
  return nil, nil
end

-- [key] = { [width] = installed FX item }, built with the FX list
function build_variants(items)
  local v = {}
  for _, it in ipairs(items) do
    local w, key = split_width(it.name)
    if w then
      v[key] = v[key] or {}
      v[key][w] = v[key][w] or it
    end
  end
  return v
end

function fx_orig_name(tr, fx)
  local ok, n = reaper.TrackFX_GetNamedConfigParm(tr, fx, 'fx_name')
  if ok and n ~= '' then return n end
  local _, name = reaper.TrackFX_GetFXName(tr, fx, '')
  return name
end

-- current width (from the name) and the installed sibling for width w, if any
function find_variant(tr, fx, w)
  if not fx_db then fx_db = build_fx_db() end
  local cur, key = split_width(fx_orig_name(tr, fx))
  if not cur then return nil, nil end
  local fam = fx_db.variants[key]
  if not fam then return cur, nil end
  local want = { w }
  if w == W_MS then want = { W_MS, W_STEREO } end
  for _, ww in ipairs(want) do
    if ww == cur then return cur, nil end
    if fam[ww] then return cur, fam[ww] end
  end
  return cur, nil
end

function has_ms_version(tr, fx)
  local cur, item = find_variant(tr, fx, W_MS)
  return cur == W_MS or (item ~= nil and split_width(item.name) == W_MS)
end

-- every parameter with the same name gets the same value
function copy_params(tr, from, to)
  local vals = {}
  for p = 0, reaper.TrackFX_GetNumParams(tr, from) - 1 do
    local _, n = reaper.TrackFX_GetParamName(tr, from, p, '')
    if n and n ~= '' and vals[n] == nil then vals[n] = reaper.TrackFX_GetParamNormalized(tr, from, p) end
  end
  for p = 0, reaper.TrackFX_GetNumParams(tr, to) - 1 do
    local _, n = reaper.TrackFX_GetParamName(tr, to, p, '')
    local v = n and vals[n]
    if v then reaper.TrackFX_SetParamNormalized(tr, to, p, v) end
  end
end

-- swaps the FX at `fx` for another version of it; returns the new index
function swap_version(tr, fx, item)
  local old_guid = reaper.TrackFX_GetFXGUID(tr, fx)
  local was_enabled = reaper.TrackFX_GetEnabled(tr, fx)
  local was_open = reaper.TrackFX_GetFloatingWindow(tr, fx) ~= nil
  local idx = reaper.TrackFX_AddByName(tr, item.ident or item.name, false, -1)
  if idx < 0 then idx = reaper.TrackFX_AddByName(tr, item.name, false, -1) end
  if idx < 0 then return fx end
  local new_guid = reaper.TrackFX_GetFXGUID(tr, idx)
  move_fx(tr, idx, fx)
  local ni = fx_index_by_guid(tr, new_guid)
  local oi = fx_index_by_guid(tr, old_guid)
  copy_params(tr, oi, ni)
  reaper.TrackFX_SetEnabled(tr, ni, was_enabled)
  -- the sidechain key, and the stereo point, follow the FX
  local map = sc_read(tr)
  if map[old_guid] then
    if sc_kind(tr, ni) > 0 then map[new_guid] = map[old_guid] end
    map[old_guid] = nil
    sc_write(tr, map)
  end
  if get_split(tr) == old_guid then set_split_ext(tr, new_guid) end
  if latdb_allowed(fx_orig_name(tr, oi)) then latdb_set_allowed(fx_orig_name(tr, ni), true) end
  reaper.TrackFX_Delete(tr, oi)
  ni = fx_index_by_guid(tr, new_guid)
  if was_open and ni then reaper.TrackFX_Show(tr, ni, 3) end
  return ni or fx
end

---------------------------------------- the stereo point

function get_split(tr)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, EXT_SPLIT, '', false)
  return (ok and s ~= '') and s or nil
end

function set_split_ext(tr, guid)
  reaper.GetSetMediaTrackInfo_String(tr, EXT_SPLIT, guid or '', true)
end

-- index (in the FX list) of the stereo point; nil = the chain stays mono
function split_index(tr, list)
  local g = get_split(tr)
  if g then
    for i, it in ipairs(list) do
      if reaper.TrackFX_GetFXGUID(tr, it.fx) == g then return i, true end
    end
  end
  for i, it in ipairs(list) do
    if has_ms_version(tr, it.fx) then return i, false end
  end
  return nil, false
end

-- the width of each of n FX, for a rack with input width iw, output width ow and
-- stereo point s (index, or nil): W_MONO, W_STEREO, or W_MS (mono in, stereo out)
function chain_widths(iw, ow, s, n)
  local t = {}
  for i = 1, n do
    if iw == W_STEREO then t[i] = W_STEREO
    elseif ow == W_MONO then t[i] = W_MONO
    else t[i] = (not s or i < s) and W_MONO or (i == s and W_MS or W_STEREO) end
  end
  return t
end

-- the width each FX of the rack should have
function fx_widths(tr, list)
  local iw, ow = rack_io(tr)
  local s = (iw ~= W_STEREO and ow ~= W_MONO) and split_index(tr, list) or nil
  return chain_widths(iw, ow, s, #list), iw, ow
end

-- Background upkeep (run by scan) asks REAPER for the same change only once per
-- FX: if a plug-in does not take it, it is not asked again and again (each
-- request can make REAPER re-initialise the plug-in). A routing change, the
-- stereo point, or an explicit action start over (WRITES = {}).
WRITES = {}

function write_once(tr, fx, what, value, apply)
  local key = reaper.TrackFX_GetFXGUID(tr, fx) .. what
  if WRITES[key] == value then return false end
  WRITES[key] = value
  apply()
  return true
end

function set_out_pin(tr, fx, pin, mask)
  local cur = reaper.TrackFX_GetPinMappings(tr, fx, 1, pin)
  if cur ~= mask then
    write_once(tr, fx, ':out' .. pin, mask, function() reaper.TrackFX_SetPinMappings(tr, fx, 1, pin, mask, 0) end)
  end
end

-- requested channel count, supported flags; nil when the FX has no such setting
function fx_channel_config(tr, fx)
  local ok, s = reaper.TrackFX_GetNamedConfigParm(tr, fx, 'channel_config')
  if not ok or not s then return nil end
  local n = {}
  for v in s:gmatch('%-?%d+') do n[#n + 1] = tonumber(v) end
  if #n < 1 then return nil end
  return n[1], n[3] or 0
end

-- gives one FX the width w; `swap` allows replacing it with a sibling version
function fit_fx(tr, fx, w, swap)
  if swap then
    local _, item = find_variant(tr, fx, w)
    if item then fx = swap_version(tr, fx, item) end
  end
  -- the plug-in's bus size (REAPER's pin connector "Plug-in bus size"): 1 on the mono part of a
  -- rack, 2 on the stereo part. Asked whenever the FX has the setting: some plug-ins take it
  -- without listing it among what they support.
  local count = fx_channel_config(tr, fx)
  if count then
    if w == W_MONO and count ~= 1 then
      write_once(tr, fx, ':cc', '1', function() reaper.TrackFX_SetNamedConfigParm(tr, fx, 'channel_config', '1') end)
    elseif w ~= W_MONO and count == 1 then
      write_once(tr, fx, ':cc', '2', function() reaper.TrackFX_SetNamedConfigParm(tr, fx, 'channel_config', '2') end)
    end
  end
  local _, _, outs = reaper.TrackFX_GetIOSize(tr, fx)
  if w == W_MONO then
    if outs == 1 then set_out_pin(tr, fx, 0, 3) end          -- 3 = channels 1 and 2
  elseif outs and outs >= 1 then
    -- main inputs hear the audio only: going from a mono bus size back to stereo, the pin that
    -- was the key input becomes Main R and still listens to the key's channel
    for p = 0, math.min(outs, 2) - 1 do
      local lo = reaper.TrackFX_GetPinMappings(tr, fx, 0, p)
      if lo & ~3 ~= 0 then reaper.TrackFX_SetPinMappings(tr, fx, 0, p, 1 << p, 0) end
    end
    if reaper.TrackFX_GetPinMappings(tr, fx, 1, 0) == 3 then set_out_pin(tr, fx, 0, 1) end
  end
end

-- the stored routing shape; a change makes scan() refit the whole rack
function io_key(tr)
  local iw, ow = rack_io(tr)
  return iw .. '>' .. ow .. '|' .. (get_split(tr) or '')
end

function fit_rack(tr, swap)
  local list = chain_info(tr).list
  local t = fx_widths(tr, list)
  local guids = {}
  for i, it in ipairs(list) do guids[i] = reaper.TrackFX_GetFXGUID(tr, it.fx) end
  for i, g in ipairs(guids) do
    local fx = fx_index_by_guid(tr, g)
    if fx then fit_fx(tr, fx, t[i], swap) end
  end
end

-- run by scan(): a routing change refits every FX (with version swaps); otherwise
-- only the channel request and outputs are kept right (e.g. for FX added in REAPER)
function width_maintain(tr)
  local key = io_key(tr)
  local ok, stored = reaper.GetSetMediaTrackInfo_String(tr, EXT_IO, '', false)
  if not ok or stored == '' then
    reaper.GetSetMediaTrackInfo_String(tr, EXT_IO, key, true)   -- first time: never swap
    fit_rack(tr, false)
  elseif stored ~= key then
    WRITES = {}
    with_undo('Rack: fit FX to mono/stereo', function()
      fit_rack(tr, true)
      reaper.GetSetMediaTrackInfo_String(tr, EXT_IO, io_key(tr), true)
    end)
  else
    fit_rack(tr, false)
  end
end

-- an FX just added by FOH-Mate gets the right version for its place
function fit_new_fx(tr, guid)
  WRITES = {}
  local list = chain_info(tr).list
  local t = fx_widths(tr, list)
  for i, it in ipairs(list) do
    if reaper.TrackFX_GetFXGUID(tr, it.fx) == guid then fit_fx(tr, it.fx, t[i], true) return end
  end
end

function set_split(tr, guid)
  WRITES = {}
  with_undo('Rack: stereo point', function()
    set_split_ext(tr, guid)
    fit_rack(tr, true)
    reaper.GetSetMediaTrackInfo_String(tr, EXT_IO, io_key(tr), true)
  end)
end

-- copies of a rack: the copied FX get new GUIDs, so their keys follow by position
function sc_copy_keys(src, new)
  local map = sc_read(src)
  if next(map) == nil then return end
  local a, b = chain_info(src).list, chain_info(new).list
  local out = {}
  for i, it in ipairs(a) do
    local c = map[reaper.TrackFX_GetFXGUID(src, it.fx)]
    if c and b[i] then out[reaper.TrackFX_GetFXGUID(new, b[i].fx)] = c end
  end
  sc_write(new, out)
end

