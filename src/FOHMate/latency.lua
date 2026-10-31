-- FOHMate/latency.lua: latency watchdog.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- latency watchdog
--
-- Every FX reports its latency (PDC, in samples). A rack whose FX add up to
-- more than the limit (Settings > Latency) raises an alert: a flashing !! on
-- the rack and on each FX that adds latency, and a line in the status bar.
-- FX marked "Allow latency" (right-click) are left out of the count.
-- Alerts can be silenced for a while or switched off in the Options menu.

LAT = {}            -- [rack guid] = { t, total, counted, fx = { [fx guid] = samples }, over }

function latok_read(tr)
  local set = {}
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, EXT_LATOK, '', false)
  if ok then for g in s:gmatch('[^;]+') do set[g] = true end end
  return set
end

function latok_write(tr, set)
  local t = {}
  for g in pairs(set) do t[#t + 1] = g end
  table.sort(t)
  reaper.GetSetMediaTrackInfo_String(tr, EXT_LATOK, table.concat(t, ';'), true)
end

-- "Allow latency" belongs to the FX itself (remembered in the FX latency list,
-- for every project); marks made per rack by 0.9 are moved there when seen
function set_latency_allowed(tr, fx_guid, on)
  local fx = fx_index_by_guid(tr, fx_guid)
  if not fx then return end
  latdb_set_allowed(fx_orig_name(tr, fx), on)
  local set = latok_read(tr)
  if set[fx_guid] then set[fx_guid] = nil; latok_write(tr, set) end
  LAT = {}
end

function fx_latency(tr, fx)
  local ok, s = reaper.TrackFX_GetNamedConfigParm(tr, fx, 'pdc')
  return (ok and tonumber(s)) or 0
end

function sample_rate()
  local sr = reaper.GetSetProjectInfo(0, 'PROJECT_SRATE', 0, false)
  local use = reaper.GetSetProjectInfo(0, 'PROJECT_SRATE_USE', 0, false)
  if not (use == 1 and sr and sr > 0) then
    local ok, dev = reaper.GetAudioDeviceInfo('SRATE')
    sr = ok and tonumber(dev) or sr
  end
  return (sr and sr > 0) and sr or 48000
end

function samples_text(n)
  return ('%d samples (%.2f ms)'):format(n, n * 1000 / sample_rate())
end

-- the latency picture of a rack, refreshed twice a second
-- refreshed once a second, and right away when FX are added or removed
function rack_latency(tr, guid, list, now)
  local L = LAT[guid]
  local nfx = reaper.TrackFX_GetCount(tr)
  local sig = { nfx }
  for _, it in ipairs(list) do sig[#sig + 1] = it.enabled and '1' or '0' end
  sig = table.concat(sig)
  if L and now - L.t < 1.0 and L.sig == sig then return L end
  L = { t = now, sig = sig, total = 0, counted = 0, fx = {}, offline = {}, disabled = {} }
  -- REAPER's own figure for the whole chain, when it gives one (for comparison)
  if nfx > 0 then
    local ok, v = reaper.TrackFX_GetNamedConfigParm(tr, 0, 'chain_pdc_reporting')
    L.chain = ok and tonumber(v) or nil
    local ok2, v2 = reaper.TrackFX_GetNamedConfigParm(tr, 0, 'chain_pdc_actual')
    L.chain_actual = ok2 and tonumber(v2) or nil
  end
  local legacy = latok_read(tr)
  local allowed, moved = {}, false
  for _, it in ipairs(list) do
    local g = reaper.TrackFX_GetFXGUID(tr, it.fx)
    if not g then goto continue end          -- removed since the list was read
    local name = fx_orig_name(tr, it.fx)
    if legacy[g] then
      latdb_set_allowed(name, true)
      legacy[g] = nil
      moved = true
    end
    allowed[g] = latdb_allowed(name)
    local off = reaper.TrackFX_GetOffline(tr, it.fx)
    L.offline[g] = off
    L.disabled[g] = not it.enabled
    -- an FX that is off or offline adds no latency (REAPER drops it from compensation)
    local n = 0
    if not off then
      n = fx_latency(tr, it.fx)
      latdb_record(name, n, 'seen')
      if not it.enabled then n = 0 end
    end
    L.fx[g] = n
    L.total = L.total + n
    if not allowed[g] then L.counted = L.counted + n end
    ::continue::
  end
  if moved then latok_write(tr, legacy) end
  L.allowed = allowed
  -- over: one FX over the per-FX limit, or all of them together over the per-rack limit
  L.fx_over, L.any_fx_over = {}, false
  for g, n in pairs(L.fx) do
    if not allowed[g] and n > LAT_LIMIT then L.fx_over[g] = true; L.any_fx_over = true end
  end
  L.rack_over = L.counted > LAT_RACK_LIMIT
  L.over = L.any_fx_over or L.rack_over
  -- the FX adding the most latency (the one flagged when only the rack total is over)
  local top_n = 0
  for g, n in pairs(L.fx) do
    if not allowed[g] and n > top_n then top_n, L.top = n, g end
  end
  LAT[guid] = L
  return L
end

-- 'on', 'off' or 'silenced' (with seconds left)
function alerts_state()
  if not S.lat_alerts then return 'off' end
  local left = (S.lat_silence_until or 0) - os.time()
  if left > 0 then return 'silenced', left end
  return 'on'
end

function alerts_active() return alerts_state() == 'on' end

function silence_alerts(minutes)
  S.lat_silence_until = minutes and (os.time() + math.floor(minutes * 60)) or 0
  save_setting('latsilence', S.lat_silence_until)
end

function flash_on(now) return math.floor(now * 3) % 2 == 0 end

-- red pill with white text, centered on (cx, cy)
function draw_alert_pill(dl, cx, cy, text)
  local tw, th = ig.CalcTextSize(ctx, text)
  local w, h = tw + 10, th + 2
  local x1, y1 = cx - w / 2, cy - h / 2
  ig.DrawList_AddRectFilled(dl, x1, y1, x1 + w, y1 + h, ALERT_RED, h / 2)
  ig.DrawList_AddText(dl, x1 + 5, y1 + 1, WHITE, text)
  return x1, y1, x1 + w, y1 + h
end

-- copies keep the "allowed" marks by position, like the sidechain keys
function latok_copy(src, new)
  local set = latok_read(src)
  if next(set) == nil then return end
  local a, b = chain_info(src).list, chain_info(new).list
  local out = {}
  for i, it in ipairs(a) do
    if set[reaper.TrackFX_GetFXGUID(src, it.fx)] and b[i] then out[reaper.TrackFX_GetFXGUID(new, b[i].fx)] = true end
  end
  latok_write(new, out)
end

