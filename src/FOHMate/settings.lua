-- FOHMate/settings.lua: editable settings, settings saved under the old name, panel settings.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- editable settings

-- Everything here shows up in Options > Settings... (group, label, range).
-- kind: 'f' = decimal slider, 'i' = integer slider, 'mod' = modifier key.
SCHEMA = {
  { group = 'Colors', key = 'color_l_min', label = 'Lightness, min', kind = 'f', min = 0.05, max = 0.95, def = 0.38, fmt = '%.2f',
    tip = 'Darkest automatic rack color (0 = black). Keep it away from 0.' },
  { group = 'Colors', key = 'color_l_max', label = 'Lightness, max', kind = 'f', min = 0.05, max = 0.95, def = 0.68, fmt = '%.2f',
    tip = 'Lightest automatic rack color (1 = white). Keep it away from 1.' },
  { group = 'Colors', key = 'color_s_min', label = 'Saturation, min', kind = 'f', min = 0.0, max = 1.0, def = 0.55, fmt = '%.2f',
    tip = 'Least saturated automatic color.' },
  { group = 'Colors', key = 'color_s_max', label = 'Saturation, max', kind = 'f', min = 0.0, max = 1.0, def = 0.90, fmt = '%.2f',
    tip = 'Most saturated automatic color.' },
  { group = 'Colors', key = 'hue_step', label = 'Hue jump between racks', kind = 'f', min = 30, max = 180, def = 137.5, fmt = '%.1f deg',
    tip = 'How far the hue moves from one rack to the next (137.5 = golden angle).' },

  { group = 'Meters', key = 'meter_min', label = 'Meter floor (dB)', kind = 'f', min = -90, max = -20, def = -60, fmt = '%.0f',
    tip = 'Bottom of the meters.' },
  { group = 'Meters', key = 'meter_max', label = 'Meter top (dB)', kind = 'f', min = -6, max = 12, def = 6, fmt = '%.0f',
    tip = 'Top of the meters.' },
  { group = 'Meters', key = 'meter_fall', label = 'Fall speed (dB/s)', kind = 'f', min = 5, max = 120, def = 40, fmt = '%.0f',
    tip = 'How fast the meters fall back.' },
  { group = 'Meters', key = 'clip_db', label = 'Clip level (dB)', kind = 'f', min = -6, max = 0, def = -0.1, fmt = '%.1f',
    tip = 'Peaks at or above this level light the clip marker.' },

  { group = 'Level match', key = 'match_secs', label = 'Measuring time (s)', kind = 'f', min = 1, max = 10, def = 3, fmt = '%.1f',
    tip = 'How long Level match listens.' },
  { group = 'Level match', key = 'match_gate', label = 'Signal gate (dB)', kind = 'f', min = -80, max = -20, def = -50, fmt = '%.0f',
    tip = 'Quieter input than this is ignored while measuring.' },

  { group = 'Latency', key = 'lat_limit', label = 'Limit per FX (samples)', kind = 'i', min = 0, max = 4096, def = 0, fmt = '%d smp',
    tip = 'An FX reporting more latency than this raises an alert (0 = any latency).\nFX marked "Allow latency" are never counted.' },
  { group = 'Latency', key = 'lat_rack_limit', label = 'Limit per rack (samples)', kind = 'i', min = 0, max = 8192, def = 0, fmt = '%d smp',
    tip = 'A rack whose FX add up to more latency than this raises an alert,\neven when each FX is under the per-FX limit (0 = any latency).' },
  { group = 'Latency', key = 'lat_silence', label = 'Silence alerts for (min)', kind = 'i', min = 1, max = 240, def = 15, fmt = '%d min',
    tip = 'How long Options > Silence latency alerts lasts.' },
  { group = 'Latency', key = 'scan_pause', label = 'Scan: pause between FX (s)', kind = 'f', min = 0, max = 2, def = 0.2, fmt = '%.2f s',
    tip = 'A short rest between one FX being removed and the next one loading.\nRaise it if scans crash REAPER often.' },
  { group = 'Latency', key = 'scan_au_wait', label = 'Scan: extra wait for AU (s)', kind = 'f', min = 0, max = 5, def = 1.5, fmt = '%.1f s',
    tip = 'An Audio Unit that reports no latency is read a second time after this extra wait\n(some AUs only report once fully loaded). 0 = no second look.' },

  { group = 'FX type colors', key = 'col_VST3', label = 'VST3', kind = 'color', def = 0x5FB3F0 },
  { group = 'FX type colors', key = 'col_VST', label = 'VST', kind = 'color', def = 0x6FD08A },
  { group = 'FX type colors', key = 'col_CLAP', label = 'CLAP', kind = 'color', def = 0xF0A050 },
  { group = 'FX type colors', key = 'col_AU', label = 'AU', kind = 'color', def = 0xC48FF0 },
  { group = 'FX type colors', key = 'col_JS', label = 'JS', kind = 'color', def = 0xE8D25A },
  { group = 'FX type colors', key = 'col_LV2', label = 'LV2', kind = 'color', def = 0x4FD0C8 },
  { group = 'FX type colors', key = 'col_DX', label = 'DX', kind = 'color', def = 0xB0B0B0 },
  { group = 'FX type colors', key = 'col_Other', label = 'Other', kind = 'color', def = 0x9A9A9A },

  { group = 'Behavior', key = 'copy_mod', label = 'Copy modifier key', kind = 'mod', def = 'ctrl',
    tip = 'Hold while dropping an FX to copy it (Ctrl is Cmd on macOS).' },
  { group = 'Behavior', key = 'move_mod', label = 'Move modifier key', kind = 'mod', def = 'alt',
    tip = 'Hold while dropping an FX on another rack to move it.' },
  { group = 'Behavior', key = 'recent_n', label = 'Recently used FX', kind = 'i', min = 0, max = 30, def = 5, fmt = '%d FX',
    tip = 'How many different FX the "Recently used" menu lists (0 = no such menu).' },
  { group = 'Behavior', key = 'long_list', label = 'Split FX lists above', kind = 'i', min = 10, max = 100, def = 30, fmt = '%d items',
    tip = 'FX lists longer than this are split by first letter.' },
  { group = 'Behavior', key = 'scan_every', label = 'Rack scan interval (s)', kind = 'f', min = 0.2, max = 2, def = 0.5, fmt = '%.1f',
    tip = 'How often the panel looks for new racks.' },
  { group = 'Behavior', key = 'stats_every', label = 'Status bar refresh (s)', kind = 'f', min = 0.25, max = 5, def = 1.0, fmt = '%.2f',
    tip = 'How often CPU, memory and latency are refreshed.' },

  { group = 'Appearance', key = 'rounding', label = 'Corner rounding', kind = 'i', min = 0, max = 14, def = 6, fmt = '%d px',
    tip = 'Corner radius of buttons, boxes and sections.' },

  { group = 'Layout', key = 'center_w', label = 'Middle area width', kind = 'i', min = 140, max = 320, def = 180, fmt = '%d px',
    tip = 'Width of the part of a rack between the meters.' },
  { group = 'Layout', key = 'meter_w', label = 'Meter width', kind = 'i', min = 14, max = 32, def = 20, fmt = '%d px',
    tip = 'Width of each meter; also the size of the round R and ... buttons.' },
  { group = 'Layout', key = 'pad', label = 'Rack padding', kind = 'i', min = 2, max = 20, def = 8, fmt = '%d px',
    tip = 'Space between the rack border and what is inside.' },
  { group = 'Layout', key = 'gap', label = 'Meter gap', kind = 'i', min = 0, max = 16, def = 6, fmt = '%d px',
    tip = 'Space between a meter and the middle area.' },
  { group = 'Layout', key = 'si', label = 'Section padding', kind = 'i', min = 0, max = 12, def = 4, fmt = '%d px',
    tip = 'Space inside the three boxes of a rack.' },
  { group = 'Layout', key = 'sg', label = 'Section gap', kind = 'i', min = 0, max = 16, def = 6, fmt = '%d px',
    tip = 'Space between the three boxes of a rack.' },
  { group = 'Layout', key = 'rack_space', label = 'Space between racks', kind = 'i', min = 0, max = 24, def = 8, fmt = '%d px',
    tip = 'Also the space under the top bar and above the status bar.' },
  { group = 'Layout', key = 'clip_h', label = 'Clip marker height', kind = 'i', min = 2, max = 12, def = 6, fmt = '%d px',
    tip = 'Height of the clip markers above the meters.' },
}

CFG = {}

function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function load_cfg()
  for _, e in ipairs(SCHEMA) do
    local raw = reaper.GetExtState(EXT_SECTION, 'cfg_' .. e.key)
    if e.kind == 'mod' then
      CFG[e.key] = (raw == 'shift' or raw == 'ctrl' or raw == 'alt') and raw or e.def
    elseif e.kind == 'color' then
      CFG[e.key] = tonumber(raw) or e.def
    else
      local v = tonumber(raw)
      if v then v = clamp(v, e.min, e.max) else v = e.def end
      if e.kind == 'i' then v = math.floor(v + 0.5) end
      CFG[e.key] = v
    end
  end
end

-- 0.10 had one latency limit, used for the whole rack: it becomes the per-rack limit
function migrate_cfg()
  if reaper.GetExtState(EXT_SECTION, 'cfg_lat_rack_limit') == '' then
    local old = tonumber(reaper.GetExtState(EXT_SECTION, 'cfg_lat_limit'))
    if old then CFG.lat_rack_limit = math.floor(old) end
  end
end

function save_cfg_value(e)
  reaper.SetExtState(EXT_SECTION, 'cfg_' .. e.key, tostring(CFG[e.key]), true)
end

function reset_cfg()
  for _, e in ipairs(SCHEMA) do
    CFG[e.key] = e.def
    reaper.DeleteExtState(EXT_SECTION, 'cfg_' .. e.key, true)
  end
end

-- copies the editable settings into the names the rest of the script uses
function apply_settings()
  COLOR_L_MIN, COLOR_L_MAX = CFG.color_l_min, CFG.color_l_max
  COLOR_S_MIN, COLOR_S_MAX = CFG.color_s_min, CFG.color_s_max
  HUE_STEP    = CFG.hue_step
  METER_MIN, METER_MAX = CFG.meter_min, CFG.meter_max
  METER_FALL  = CFG.meter_fall
  CLIP_DB     = CFG.clip_db
  MATCH_SECS, MATCH_GATE = CFG.match_secs, CFG.match_gate
  COPY_MOD, MOVE_MOD = CFG.copy_mod, CFG.move_mod
  LONG_LIST   = math.floor(CFG.long_list)
  SCAN_EVERY  = CFG.scan_every
  LAT_LIMIT   = CFG.lat_limit          -- per FX
  LAT_RACK_LIMIT = CFG.lat_rack_limit  -- per rack
  STATS_EVERY = CFG.stats_every
  ROUNDING    = CFG.rounding
  CENTER_W, METER_W = CFG.center_w, CFG.meter_w
  PAD, GAP, SI, SG  = CFG.pad, CFG.gap, CFG.si, CFG.sg
  RACK_SPACE, CLIP_H = CFG.rack_space, CFG.clip_h
  RACK_W     = CENTER_W + 2 * METER_W + 2 * GAP + 2 * PAD
  MIN_W, MIN_H = RACK_W + 50, 260
end

---------------------------------------------------------------- settings saved under the old name

-- Before it had its current name the app's settings lived in the "RackPanel" section
-- (and one layout setting was called "strip_space"). Copy them over once.
function migrate_ext_state()
  if reaper.GetExtState(EXT_SECTION, 'migrated') == '1' then return end
  local keys = { 'colormode', 'hiddentypes', 'daylight', 'defcolor', 'disconnect', 'mode', 'nometers', 'dock' }
  for _, e in ipairs(SCHEMA) do keys[#keys + 1] = 'cfg_' .. e.key end
  keys[#keys + 1] = 'cfg_strip_space'
  for _, k in ipairs(keys) do
    local v = reaper.GetExtState('RackPanel', k)
    if v ~= '' then
      local nk = (k == 'cfg_strip_space') and 'cfg_rack_space' or k
      if reaper.GetExtState(EXT_SECTION, nk) == '' then reaper.SetExtState(EXT_SECTION, nk, v, true) end
      reaper.DeleteExtState('RackPanel', k, true)
    end
  end
  reaper.SetExtState(EXT_SECTION, 'migrated', '1', true)
end
migrate_ext_state()

-- Settings saved before the rename to FOH-Mate (section "LiveRack"): copied once to the new section.
function migrate_from_liverack()
  if reaper.GetExtState(EXT_SECTION, 'migrated_liverack') == '1' then return end
  local keys = { 'colormode', 'hiddentypes', 'daylight', 'defcolor', 'disconnect', 'mode', 'nometers', 'dock',
                 'latalerts', 'latsilence', 'askscan', 'hideover', 'showoff', 'latbox', 'showlat', 'oddeven',
                 'cfg_lat_limit', 'win_latlist', 'win_settings' }
  for _, e in ipairs(SCHEMA) do keys[#keys + 1] = 'cfg_' .. e.key end
  for _, k in ipairs(keys) do
    local v = reaper.GetExtState(OLD_EXT_SECTION, k)
    if v ~= '' then
      if reaper.GetExtState(EXT_SECTION, k) == '' then reaper.SetExtState(EXT_SECTION, k, v, true) end
      reaper.DeleteExtState(OLD_EXT_SECTION, k, true)
    end
  end
  reaper.DeleteExtState(OLD_EXT_SECTION, 'migrated', true)
  reaper.SetExtState(EXT_SECTION, 'migrated_liverack', '1', true)
end
migrate_from_liverack()

---------------------------------------------------------------- panel settings (remembered)

function load_settings()
  local mode = reaper.GetExtState(EXT_SECTION, 'colormode')
  local hidden = {}
  for n in reaper.GetExtState(EXT_SECTION, 'hiddentypes'):gmatch('[^,]+') do hidden[n] = true end
  local hidden_popups = {}
  for n in reaper.GetExtState(EXT_SECTION, 'hiddenpopups'):gmatch('[^,]+') do hidden_popups[n] = true end
  return {
    daylight    = reaper.GetExtState(EXT_SECTION, 'daylight') == '1',
    color_mode  = (mode == 'default') and 'default' or 'auto',
    default_rgb = tonumber(reaper.GetExtState(EXT_SECTION, 'defcolor')) or 0x3D85C6,
    disconnect  = reaper.GetExtState(EXT_SECTION, 'disconnect') == '1',
    hidden      = hidden,           -- FX types left out of the menus
    hidden_popups = hidden_popups,  -- popups hidden with "Don't show this again"
    mode        = (reaper.GetExtState(EXT_SECTION, 'mode') == 'show') and 'show' or 'edit',
    no_meters   = reaper.GetExtState(EXT_SECTION, 'nometers') == '1',   -- troubleshooting switch
    lat_alerts  = reaper.GetExtState(EXT_SECTION, 'latalerts') ~= '0',  -- latency watchdog on/off
    lat_silence_until = tonumber(reaper.GetExtState(EXT_SECTION, 'latsilence')) or 0,
    ask_scan    = reaper.GetExtState(EXT_SECTION, 'askscan') ~= '0',    -- offer to scan new FX
    hide_over   = reaper.GetExtState(EXT_SECTION, 'hideover') == '1',   -- FX over the limit left out of the menus
    show_off    = reaper.GetExtState(EXT_SECTION, 'showoff') == '1',    -- Show mode takes them offline
    -- latency box under every rack: 'off', 'always' or 'auto' (only racks with latency)
    lat_box     = (function()
                    local v = reaper.GetExtState(EXT_SECTION, 'latbox')
                    if v == 'always' or v == 'auto' or v == 'off' then return v end
                    return (reaper.GetExtState(EXT_SECTION, 'showlat') == '1') and 'always' or 'off'
                  end)(),
    odd_even    = reaper.GetExtState(EXT_SECTION, 'oddeven') == '1',  -- stereo pairs start on odd channels
    show_settings = false,
  }
end

S = load_settings()

function save_setting(key, value)
  reaper.SetExtState(EXT_SECTION, key, tostring(value), true)
end

function hidden_list()
  local t = {}
  for n in pairs(S.hidden) do t[#t + 1] = n end
  table.sort(t)
  return t
end

function save_hidden()
  save_setting('hiddentypes', table.concat(hidden_list(), ','))
end

function save_hidden_popups()
  local t = {}
  for n in pairs(S.hidden_popups) do t[#t + 1] = n end
  table.sort(t)
  save_setting('hiddenpopups', table.concat(t, ','))
end

