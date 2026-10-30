-- FOHMate.lua
-- FOH-Mate: live sound tools for REAPER. Its first module, Plugins Host, is a rack-based
-- FX panel built with ReaImGui.
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- This program is free software: you can redistribute it and/or modify it under
-- the terms of the GNU General Public License as published by the Free Software
-- Foundation, either version 3 of the License, or (at your option) any later version.
-- It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
-- without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
-- PURPOSE. See the GNU General Public License for more details, in the LICENSE file
-- or at <https://www.gnu.org/licenses/>.
--
-- Every track whose name starts with PREFIX is a "rack". On detection the
-- script hides it from the TCP and the mixer and adds two small meter JSFX
-- to its chain: one at the very top (input meter) and one at the very end
-- (output RMS, used by Level match). The JSFX file is written automatically
-- to <REAPER resource path>/Effects/FOHMate/ on first run.
--
-- Requires: ReaImGui (install via ReaPack, "ReaTeam Extensions" repo).
--
-- Note for editing: every top-level name below lives in a private environment
-- (the line right under this note) instead of being a Lua "local". A script
-- may only have 200 locals; this keeps room to grow. It behaves the same.

local _ENV = setmetatable({}, { __index = _G })

VERSION         = '0.11.20'   -- major.minor.revision, shown in the window's title bar
PREFIX          = 'RACK:'   -- track name prefix (case-insensitive); not editable at run time
GLOW_M          = 6         -- room left around the racks for the selection glow
NAME_FONT_SIZE  = 16        -- rack name font (bold)
TITLE_FONT_SIZE = 24        -- "Plugins Host" title font (bold)

LEVEL_MIN, LEVEL_MAX = -60.0, 12.0   -- dB range of the level box

EXT_SECTION     = 'FOHMate'           -- where settings are saved (REAPER ExtState)
OLD_EXT_SECTION = 'LiveRack'          -- the same, before the app was renamed (copied once)
METER_NAME      = 'FOHMate Meter'
METER_PATH      = 'FOHMate/FOHMate_Meter'
GMEM            = 'FOHMateMeters'
STRIDE          = 16        -- gmem slots per rack (8 input stage, 8 output stage)
EXT_BYPASS      = 'P_EXT:FOHMate_bypass'
OLD_EXT_BYPASS  = 'P_EXT:RackPanel_bypass'   -- read once, then moved to EXT_BYPASS
STATS_FILE      = '/tmp/FOHMate_stats.txt'
IS_MAC          = ((reaper.GetOS() or ''):find('OSX') or (reaper.GetOS() or ''):find('mac')) ~= nil

-- sidechain helper tracks: hidden, never routed to the master or to hardware outs
SC_BUS_PREFIX   = 'SC BUS:'   -- sidechain busses (racks send to them, FX key inputs listen to them)
SC_IN_PREFIX    = 'SC IN:'    -- one per hardware input used as a key (created and removed automatically)
EXT_SC          = 'P_EXT:FOHMate_sc'    -- per rack: "fx guid=key channel;..."
EXT_IO          = 'P_EXT:FOHMate_io'    -- routing shape the FX were last fitted to ("1>2|split")
EXT_LATOK       = 'P_EXT:FOHMate_latok' -- guids of FX allowed to add latency
ALERT_RED       = 0xE02828FF
EXT_SHOWOFF     = 'P_EXT:FOHMate_showoff' -- guids of FX taken offline by Show mode
EXT_SPLIT       = 'P_EXT:FOHMate_split' -- guid of the FX picked as the stereo point
COPY_BADGE      = 0x2EB84EFF            -- the green "+" that follows the pointer when a drag copies

-- Buttons that open a native REAPER window (FX windows, routing) use this
-- color scheme: { normal, hovered, active }.
NATIVE_DARK     = { 0x1F7A7AFF, 0x2A9696FF, 0x34B0B0FF }
NATIVE_LIGHT    = { 0x7FCFCFFF, 0x6BC0C0FF, 0x58B0B0FF }

if not reaper.ImGui_CreateContext then
  reaper.MB('ReaImGui is not installed.\nInstall it from ReaPack (ReaTeam Extensions), then restart REAPER.',
            'FOH-Mate', 0)
  return
end

-- shorthand: ig.Button(...) == reaper.ImGui_Button(...)
ig = setmetatable({}, { __index = function(t, k)
  local f = reaper['ImGui_' .. k]
  rawset(t, k, f)
  return f
end })

cfg_flags = 0
if reaper.ImGui_ConfigFlags_DockingEnable then cfg_flags = reaper.ImGui_ConfigFlags_DockingEnable() end
ctx = nil   -- created by create_ctx() right before the first frame (see start)

math.randomseed(math.floor(reaper.time_precise() * 1000))

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
  return {
    daylight    = reaper.GetExtState(EXT_SECTION, 'daylight') == '1',
    color_mode  = (mode == 'default') and 'default' or 'auto',
    default_rgb = tonumber(reaper.GetExtState(EXT_SECTION, 'defcolor')) or 0x3D85C6,
    disconnect  = reaper.GetExtState(EXT_SECTION, 'disconnect') == '1',
    hidden      = hidden,           -- FX types left out of the menus
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

---------------------------------------------------------------- fonts

function reaimgui_version()
  if not reaper.ImGui_GetVersion then return 0 end
  local _, _, v = reaper.ImGui_GetVersion()
  local maj, min = tostring(v):match('^(%d+)%.(%d+)')
  return (tonumber(maj) or 0) * 1000 + (tonumber(min) or 0)
end

-- 0.10+: CreateFont(family, flags) + PushFont(ctx, font, size)
-- 0.9  : CreateFont(family, size, flags) + PushFont(ctx, font)
new_font_api = reaimgui_version() >= 10

function make_bold_font(size)
  local bold = reaper.ImGui_FontFlags_Bold and reaper.ImGui_FontFlags_Bold() or 0
  local ok, f = pcall(function()
    if new_font_api then
      return reaper.ImGui_CreateFont('sans-serif', bold)
    end
    return reaper.ImGui_CreateFont('sans-serif', size, bold)
  end)
  if ok and f then
    pcall(reaper.ImGui_Attach, ctx, f)
    return f
  end
  return nil
end

name_font, title_font = nil, nil

-- ReaImGui discards a context that does not run a frame soon after creation,
-- so the context (and its fonts) is created right before the first frame,
-- and re-created if it ever turns out to be invalid.
function create_ctx()
  ctx = reaper.ImGui_CreateContext('FOH-Mate', cfg_flags)
  name_font  = make_bold_font(NAME_FONT_SIZE)
  title_font = new_font_api and name_font or make_bold_font(TITLE_FONT_SIZE)
end

function ctx_is_valid()
  if not ctx then return false end
  if not reaper.ImGui_ValidatePtr then return true end
  return reaper.ImGui_ValidatePtr(ctx, 'ImGui_Context*')
end

function push_bold(font, size)
  if not font then return false end
  local ok
  if new_font_api then
    ok = pcall(reaper.ImGui_PushFont, ctx, font, size)
  else
    ok = pcall(reaper.ImGui_PushFont, ctx, font)
  end
  return ok
end

---------------------------------------------------------------- JSFX

JSFX_SRC = [==[
desc:FOHMate Meter
// Part of FOH-Mate (FOHMate.lua) - do not remove. Audio passes through untouched.
// Copyright (C) 2026 Bianca and the FOH-Mate contributors. GPL-3.0-or-later (see LICENSE).
// Stage 0 = chain input, stage 1 = chain output (before the track fader).
// Publishes peak and RMS data to the panel through gmem.
options:gmem=FOHMateMeters

slider1:0<0,255,1>-Slot (managed by FOH-Mate)
slider2:0<0,1,1>-Stage (0 input, 1 output)

in_pin:Left
in_pin:Right
out_pin:Left
out_pin:Right

@init
bpl = 0;
bpr = 0;
ssl = 0;
ssr = 0;
cnt = 0;
base = 0;

@slider
base = floor(slider1) * 16 + floor(slider2) * 8;

@block
gmem[base + 0] = max(gmem[base + 0], bpl);
gmem[base + 1] = max(gmem[base + 1], bpr);
gmem[base + 2] += 1;
gmem[base + 3] += ssl;
gmem[base + 4] += ssr;
gmem[base + 5] += cnt;
bpl = 0;
bpr = 0;
ssl = 0;
ssr = 0;
cnt = 0;

@sample
a = abs(spl0);
a > bpl ? bpl = a;
b = abs(spl1);
b > bpr ? bpr = b;
ssl += spl0 * spl0;
ssr += spl1 * spl1;
cnt += 1;
]==]

function install_jsfx()
  local dir  = reaper.GetResourcePath() .. '/Effects/FOHMate'
  local path = dir .. '/FOHMate_Meter'
  local f = io.open(path, 'r')
  if f then
    local cur = f:read('*a')
    f:close()
    if cur == JSFX_SRC then return true end
  end
  reaper.RecursiveCreateDirectory(dir, 0)
  f = io.open(path, 'w')
  if not f then return false end
  f:write(JSFX_SRC)
  f:close()
  return true
end

---------------------------------------------------------------- state

racks         = {}
last_scan     = -math.huge
meters        = {}      -- [guid] = meter state
matches       = {}      -- [guid] = level match measurement
status        = {}      -- [guid] = { text, untl }
edit_state    = {}      -- text boxes
name_state    = {}      -- [guid] = { editing, text, fresh, was_active }
pending_ops   = {}      -- FX reorders / copies / moves requested by drag and drop
pending_racks = {}      -- rack reorders requested by drag and drop
meter_error   = nil
fx_db         = nil     -- installed FX, built on first use
fx_view       = nil     -- fx_db without the hidden FX types
fx_view_key   = nil
confirm       = nil     -- pending confirmation dialog { text, yes, label }
confirm_open  = false
picker        = { open = false, kind = nil, tr = nil, rgb = 0x808080 }
sc_busses     = {}      -- SC BUS tracks, in project order (refreshed by scan)
later         = {}      -- calls that must wait until the frame is drawn (e.g. name prompts)
last_time     = reaper.time_precise()

win_w, win_h   = 840, 480   -- last good window size
prev_w, prev_h = nil, nil
was_visible    = true
force_size     = false
dock_request   = nil
cur_dock       = nil
saved_dock     = tonumber(reaper.GetExtState(EXT_SECTION, 'dock')) or 0
dock_applied   = false

ZONES = {
  { -60, -12, 0x40C060FF },
  { -12,  -3, 0xE0C040FF },
  {  -3,   6, 0xE04040FF },
}

TYPE_ORDER = { 'VST3', 'VST3i', 'VST', 'VSTi', 'CLAP', 'CLAPi', 'AU', 'AUi', 'JS', 'LV2', 'LV2i', 'DX', 'DXi' }

---------------------------------------------------------------- helpers

WHITE, BLACK = 0xFFFFFFFF, 0x000000FF

function amp_to_db(a)
  if a <= 0.0000001 then return -150.0 end
  return 20.0 * math.log(a, 10)
end

function meter_frac(db)
  return clamp((db - METER_MIN) / (METER_MAX - METER_MIN), 0, 1)
end

function valid(tr)
  return reaper.ValidatePtr2(0, tr, 'MediaTrack*')
end

function track_name(tr)
  local _, name = reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', '', false)
  return name
end

function is_rack_name(name)
  return name:sub(1, #PREFIX):upper() == PREFIX:upper()
end

function raw_name(tr)
  local n = track_name(tr)
  if is_rack_name(n) then n = n:sub(#PREFIX + 1) end
  return (n:match('^%s*(.-)%s*$'))
end

-- colors are 0xRRGGBBAA everywhere in the panel
function mix(a, b, t)
  local function ch(c, s) return (c >> s) & 255 end
  local r = math.floor(ch(a, 24) + (ch(b, 24) - ch(a, 24)) * t + 0.5)
  local g = math.floor(ch(a, 16) + (ch(b, 16) - ch(a, 16)) * t + 0.5)
  local bl = math.floor(ch(a, 8) + (ch(b, 8) - ch(a, 8)) * t + 0.5)
  return (r << 24) | (g << 16) | (bl << 8) | 0xFF
end

function darken(rgba, f)
  return mix(rgba, BLACK, 1 - f)
end

function lum(rgba)
  return (0.2126 * ((rgba >> 24) & 255) + 0.7152 * ((rgba >> 16) & 255)
        + 0.0722 * ((rgba >> 8) & 255)) / 255
end

-- readable text on top of `bg`, keeping a hint of `tint`
function contrast_text(bg, tint)
  if lum(bg) < 0.5 then return mix(tint, WHITE, 0.85) end
  return mix(tint, BLACK, 0.85)
end

function track_rgb(tr)
  local c = reaper.GetTrackColor(tr)
  if c == 0 then return nil end
  return reaper.ColorFromNative(c & 0xFFFFFF)
end

function track_color(tr)
  local r, g, b = track_rgb(tr)
  if not r then return 0xB0B0B0FF end
  return (r << 24) | (g << 16) | (b << 8) | 0xFF
end

function set_track_rgb(tr, r, g, b)
  reaper.SetMediaTrackInfo_Value(tr, 'I_CUSTOMCOLOR',
    reaper.ColorToNative(math.floor(r), math.floor(g), math.floor(b)) | 0x1000000)
end

function clean_fx_name(name)
  name = name:gsub('^[%w_%-]+:%s*', '')
  name = name:gsub('%s*%b()$', '')
  return name
end

function fit_text(s, w)
  if ig.CalcTextSize(ctx, s) <= w then return s end
  while #s > 1 and ig.CalcTextSize(ctx, s .. '...') > w do
    s = s:sub(1, (utf8.offset(s, -1) or #s) - 1)
  end
  return s .. '...'
end

function with_undo(label, fn)
  reaper.Undo_BeginBlock2(0)
  fn()
  reaper.Undo_EndBlock2(0, label, -1)
end

function has_mod(name)
  local mods = ig.GetKeyMods(ctx)
  local flag
  if name == 'shift' then flag = ig.Mod_Shift()
  elseif name == 'alt' then flag = ig.Mod_Alt()
  else flag = ig.Mod_Ctrl() end
  return (mods & flag) ~= 0
end

-- the name of a modifier key as printed on this system's keyboard
function mod_label(name)
  if name == 'shift' then return 'Shift' end
  if name == 'alt' then return IS_MAC and 'Opt' or 'Alt' end
  return IS_MAC and 'Cmd' or 'Ctrl'
end

-- the grey help line at the bottom of the window: what the mouse can do with the
-- thing under it (or with what is being dragged). Set while drawing, shown at the end.
HINT = nil
function hint_hovered(text)
  if ig.IsItemHovered(ctx) then HINT = text end
end

function mouse_in(x1, y1, x2, y2)
  local mx, my = ig.GetMousePos(ctx)
  return mx >= x1 and mx <= x2 and my >= y1 and my <= y2
end

-- what is being dragged right now (a rack's guid / "guid|fxindex"); the "prev" values
-- are last frame's, so every rack can react to a drag that started in another one
drag_now_rack, drag_now_fx, drag_prev_rack, drag_prev_fx = nil, nil, nil, nil
lat_over_racks = 0      -- racks over the latency limit, counted while drawing
SHOWOFF_MSG = nil       -- "N FX taken offline" after switching to Show
hover_now_rack, hover_prev_rack = nil, nil   -- rack under the pointer (guid), same idea

-- will dropping what is being dragged make a copy?
-- FX: copy key held, or dropped on another rack without the move key. Racks: copy key held.
function drag_copies()
  if drag_prev_rack then return has_mod(COPY_MOD) end
  if drag_prev_fx then
    if has_mod(COPY_MOD) then return true end
    if has_mod(MOVE_MOD) then return false end
    local src = drag_prev_fx:match('^(.-)|')
    return hover_prev_rack ~= nil and hover_prev_rack ~= src
  end
  return false
end

-- a green "+" in a circle, next to the pointer, while a drag would copy
function draw_copy_badge()
  if not drag_copies() then return end
  local fdl = ig.GetForegroundDrawList and ig.GetForegroundDrawList(ctx)
  if not fdl then return end
  local mx, my = ig.GetMousePos(ctx)
  local r = 8
  local cx, cy = mx + 14, my + 14
  ig.DrawList_AddCircleFilled(fdl, cx, cy, r + 1.5, 0x000000A0, 0)
  ig.DrawList_AddCircleFilled(fdl, cx, cy, r, COPY_BADGE, 0)
  ig.DrawList_AddLine(fdl, cx - r * 0.55, cy, cx + r * 0.55, cy, WHITE, 2)
  ig.DrawList_AddLine(fdl, cx, cy - r * 0.55, cx, cy + r * 0.55, WHITE, 2)
end

-- the drag preview of an FX: a button-shaped bar that follows the cursor
function draw_fx_ghost(name, hint, w, h)
  local x, y = ig.GetCursorScreenPos(ctx)
  local gdl = ig.GetWindowDrawList(ctx)
  ig.DrawList_AddRectFilled(gdl, x, y, x + w, y + h, (T.native[1] & 0xFFFFFF00) | 0xE6, ROUNDING)
  ig.DrawList_AddRect(gdl, x, y, x + w, y + h, T.glow, ROUNDING, 0, 2)
  local label = fit_text(name .. hint, w - 12)
  local tw = ig.CalcTextSize(ctx, label)
  ig.DrawList_AddText(gdl, x + (w - tw) / 2, y + (h - ig.GetTextLineHeight(ctx)) / 2, T.gauge_text, label)
  ig.Dummy(ctx, w, h)
end

function rack_by_guid(g)
  for _, tr in ipairs(racks) do
    if valid(tr) and reaper.GetTrackGUID(tr) == g then return tr end
  end
  return nil
end

function rack_index(tr)
  for i, t in ipairs(racks) do
    if t == tr then return i end
  end
  return nil
end

-- the window being drawn ('latlist', 'settings'; nil = Plugins Host). A confirmation opens over the
-- window that asked for it: opened over Plugins Host it can hide behind the other window and block
-- every FOH-Mate window until answered.
CONFIRM_HOST = nil
MAIN_CENTER, MAIN_DOCKED = nil, false   -- Plugins Host, as of its last frame

-- Plugins Host docked: the floating FOH-Mate windows stay in front of it and would hide its
-- boxes. Returns the open one used last (its id), or nil.
function floating_host()
  if not MAIN_DOCKED then return nil end
  local best, at = nil, -1
  for _, id in ipairs({ 'latlist', 'settings' }) do
    local st = WINSZ[id]
    if st and st.last >= FRAME - 1 and (st.focused or 0) > at then best, at = id, st.focused or 0 end
  end
  return best
end

function request_confirm(text, yes, label)
  local host, over_main = CONFIRM_HOST, false
  if not host then
    -- asked by Plugins Host: opened from a floating window when one would hide it, still centered
    -- on Plugins Host
    host = floating_host() or 'main'
    over_main = host ~= 'main'
  end
  confirm = { text = text, yes = yes, label = label or 'Yes', host = host, over_main = over_main }
  confirm_open = true
end

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
    request_confirm(('%s\nfor the %d selected racks?'):format(what, #trs), go, label or 'Apply')
  else
    go()
  end
end

---------------------------------------------------------------- theme

-- Dark is REAPER-like ImGui as before. Daylight is a light scheme that still
-- follows each rack's own color (pale tint as background, solid color for the name).
LIGHT_COLORS = {
  { 'WindowBg', 0xF2F2F2FF },     { 'Text', 0x141414FF },
  { 'TextDisabled', 0x6A6A6AFF }, { 'Button', 0xD9D9D9FF },
  { 'ButtonHovered', 0xC9C9C9FF }, { 'ButtonActive', 0xB5B5B5FF },
  { 'FrameBg', 0xFFFFFFFF },      { 'FrameBgHovered', 0xF0F0F0FF },
  { 'FrameBgActive', 0xE6E6E6FF }, { 'PopupBg', 0xFAFAFAFF },
  { 'Border', 0x9A9A9AFF },       { 'Header', 0xD0D8E8FF },
  { 'HeaderHovered', 0xBCC8E0FF }, { 'HeaderActive', 0xA8B8D8FF },
  { 'CheckMark', 0x141414FF },    { 'ScrollbarBg', 0xE0E0E0FF },
  { 'ScrollbarGrab', 0xB0B0B0FF }, { 'TextSelectedBg', 0x4296FA55 },
}

function theme()
  if S.daylight then
    return {
      native = NATIVE_LIGHT, byp = 0xFFB347FF, mute = 0xFF7B7BFF, dim = 0x606060FF,
      meter_bg = 0xC8C8C8FF, hold = 0x000000FF, clip_off = 0xC9A9A9FF,
      bar_border = 0x707070FF, title = 0x1B3A5BFF, gauge_text = 0x141414FF,
      chk_bg = 0xFFFFFFFF, chk_ring = 0x333333FF, chk_dot = 0x1E6FD9FF,
      glow = 0x1E6FD9FF, cue_edit = 0x2E9E4FFF, cue_show = 0xD23C3CFF,
      sc_on = 0x9B6FE0FF, sc_ink = 0x202020FF, sc_ink_on = 0xFFFFFFFF, dots = 0x202020FF,
    }
  end
  return {
    native = NATIVE_DARK, byp = 0xD08020FF, mute = 0xC03030FF, dim = 0xA0A0A0FF,
    meter_bg = 0x181818FF, hold = 0xFFFFFFFF, clip_off = 0x3A2020FF,
    bar_border = 0x707070FF, title = 0xFFD27AFF, gauge_text = 0xFFFFFFFF,
    chk_bg = 0x1A1A1AFF, chk_ring = 0xCCCCCCFF, chk_dot = 0x6FB4FFFF,
    glow = 0xFFFFFFFF, cue_edit = 0x2E9E4FFF, cue_show = 0xD23C3CFF,
    sc_on = 0x7A4FC4FF, sc_ink = 0xD8D8D8FF, sc_ink_on = 0xFFFFFFFF, dots = 0xEDEDEDFF,
  }
end

T = theme()

function rack_colors(col, bypassed)
  local c = {}
  if not S.daylight then
    if bypassed then
      c.bg, c.border, c.sec_bg, c.sec_bd = 0x2A2A2AFF, 0x666666FF, 0x1E1E1EFF, 0x505050FF
    else
      c.bg, c.border = darken(col, 0.25), col
      c.sec_bg, c.sec_bd = darken(col, 0.36), darken(col, 0.75)
    end
    c.name_bg = bypassed and 0x303030FF or darken(col, 0.5)
    c.line = 0xFFFFFF30
  else
    if bypassed then
      c.bg, c.border, c.sec_bg, c.sec_bd = 0xD6D6D6FF, 0x8A8A8AFF, 0xE8E8E8FF, 0xA0A0A0FF
    else
      c.bg, c.border = mix(col, WHITE, 0.80), mix(col, BLACK, 0.25)
      c.sec_bg, c.sec_bd = mix(col, WHITE, 0.90), mix(col, BLACK, 0.12)
    end
    c.name_bg = bypassed and 0xBEBEBEFF or col
    c.line = 0x00000040
  end
  c.name_txt = contrast_text(c.name_bg, col)
  return c
end

function push_native()
  ig.PushStyleColor(ctx, ig.Col_Button(),        T.native[1])
  ig.PushStyleColor(ctx, ig.Col_ButtonHovered(), T.native[2])
  ig.PushStyleColor(ctx, ig.Col_ButtonActive(),  T.native[3])
end

function pop_native()
  ig.PopStyleColor(ctx, 3)
end

---------------------------------------------------------------- colors

function rgb_to_hsl(r, g, b)
  r, g, b = r / 255, g / 255, b / 255
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local l = (mx + mn) / 2
  if mx == mn then return 0, 0, l end
  local d = mx - mn
  local s = (l > 0.5) and d / (2 - mx - mn) or d / (mx + mn)
  local h
  if mx == r then h = (g - b) / d + ((g < b) and 6 or 0)
  elseif mx == g then h = (b - r) / d + 2
  else h = (r - g) / d + 4 end
  return h * 60, s, l
end

function hsl_to_rgb(h, s, l)
  h = (h % 360) / 360
  local function hue2rgb(p, q, t)
    if t < 0 then t = t + 1 end
    if t > 1 then t = t - 1 end
    if t < 1 / 6 then return p + (q - p) * 6 * t end
    if t < 1 / 2 then return q end
    if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
    return p
  end
  local q = (l < 0.5) and l * (1 + s) or l + s - l * s
  local p = 2 * l - q
  return math.floor(hue2rgb(p, q, h + 1 / 3) * 255 + 0.5),
         math.floor(hue2rgb(p, q, h) * 255 + 0.5),
         math.floor(hue2rgb(p, q, h - 1 / 3) * 255 + 0.5)
end

function hue_dist(a, b)
  local d = math.abs(a - b) % 360
  return (d > 180) and 360 - d or d
end

function track_hue(tr)
  local r, g, b = track_rgb(tr)
  if not r then return nil end
  return (rgb_to_hsl(r, g, b))
end

-- a hue that contrasts with the given neighbour hues (either may be nil)
function contrast_hue(a, b)
  if not a and not b then return math.random() * 360 end
  if not a or not b then
    return ((a or b) + HUE_STEP + (math.random() - 0.5) * 30) % 360
  end
  local scores, best = {}, -1
  for h = 0, 355, 5 do
    local sc = math.min(hue_dist(h, a), hue_dist(h, b))
    scores[#scores + 1] = { h, sc }
    if sc > best then best = sc end
  end
  local cands = {}
  for _, e in ipairs(scores) do
    if e[2] >= best - 6 then cands[#cands + 1] = e[1] end
  end
  return cands[math.random(#cands)]
end

-- random saturation / lightness inside the allowed range
function rgb_for_hue(h)
  local s = COLOR_S_MIN + math.random() * (COLOR_S_MAX - COLOR_S_MIN)
  local l = COLOR_L_MIN + math.random() * (COLOR_L_MAX - COLOR_L_MIN)
  return hsl_to_rgb(h, s, l)
end

function default_rgb_parts()
  local c = S.default_rgb
  return (c >> 16) & 255, (c >> 8) & 255, c & 255
end

-- color for a rack that is created or copied between prev_tr and next_tr
function color_for_new(prev_tr, next_tr)
  if S.color_mode == 'default' then return default_rgb_parts() end
  local a = prev_tr and track_hue(prev_tr)
  local b = next_tr and track_hue(next_tr)
  return rgb_for_hue(contrast_hue(a, b))
end

function recolor_every_rack()
  with_undo('Rack: recolor every rack', function()
    local hue = math.random() * 360
    for i, tr in ipairs(racks) do
      if valid(tr) then
        if i > 1 then hue = (hue + HUE_STEP + (math.random() - 0.5) * 30) % 360 end
        set_track_rgb(tr, rgb_for_hue(hue))
      end
    end
  end)
end

function recolor_rack_auto(tr)
  local i = rack_index(tr)
  local a = i and racks[i - 1] and track_hue(racks[i - 1])
  local b = i and racks[i + 1] and track_hue(racks[i + 1])
  with_undo('Rack: recolor', function()
    set_track_rgb(tr, rgb_for_hue(contrast_hue(a, b)))
  end)
end

function open_picker(kind, tr)
  picker.kind = kind
  picker.trs = (kind == 'rack') and targets_for(tr) or nil     -- every selected rack, or just this one
  if kind == 'rack' then
    local r, g, b = track_rgb(tr)
    picker.rgb = r and ((r << 16) | (g << 8) | b) or S.default_rgb
  else
    picker.rgb = S.default_rgb
  end
  picker.open = true
end

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

---------------------------------------------------------------- FX latency list
--
-- One list for the whole computer, shared by every project:
--   <REAPER resource folder>/Data/FOHMate/fx_latency.txt
-- one line per FX (by its full name, e.g. "VST3: Pro-L 2 (FabFilter)"):
--   name <tab> latency <tab> highest seen <tab> allowed (0/1) <tab> source <tab> sample rate
-- source: "scan" (measured by the scan), "seen" (reported while in a rack),
-- "failed" (could not be loaded, or REAPER stopped while loading it).
-- FX marked "Allow latency" are flagged here, so they stay allowed everywhere.

LATDB_DIR  = reaper.GetResourcePath() .. '/Data/FOHMate'
LATDB_FILE = LATDB_DIR .. '/fx_latency.txt'
LATDB      = { by = {}, rev = 0, dirty = false, save_t = 0 }
SCAN_MARK  = LATDB_DIR .. '/scan_loading.txt'   -- the FX being loaded right now (survives a crash)
SCAN_LOG   = LATDB_DIR .. '/last_scan_log.txt'  -- every FX of the last scan, in order, with its result
SCAN_TODO  = LATDB_DIR .. '/scan_pending.txt'   -- the FX of a scan in progress, to continue it after a crash
SCAN_POS   = LATDB_DIR .. '/scan_position.txt'  -- how far that scan got

-- The latency list, favorites and recently used FX saved in Data/LiveRack (before the rename to
-- FOH-Mate) are copied once to Data/FOHMate. The old folder is left as it is.
function migrate_data_folder()
  if reaper.GetExtState(EXT_SECTION, 'migrated_data') == '1' then return end
  local old_dir = reaper.GetResourcePath() .. '/Data/LiveRack'
  for _, name in ipairs({ 'fx_latency.txt', 'favorites.txt', 'recent_fx.txt' }) do
    local from = io.open(old_dir .. '/' .. name, 'rb')
    if from then
      local data = from:read('*a')
      from:close()
      local to_path = LATDB_DIR .. '/' .. name
      local probe = io.open(to_path, 'rb')
      if probe then
        probe:close()
      else
        reaper.RecursiveCreateDirectory(LATDB_DIR, 0)
        local to = io.open(to_path, 'wb')
        if to then to:write(data); to:close() end
      end
    end
  end
  reaper.SetExtState(EXT_SECTION, 'migrated_data', '1', true)
end

function latdb_key(name) return (name or ''):lower() end

-- shows the data folder in Finder / Explorer
function open_data_folder()
  reaper.RecursiveCreateDirectory(LATDB_DIR, 0)
  local osn = reaper.GetOS() or ''
  if osn:find('Win') then
    reaper.ExecProcess('cmd.exe /C start "" "' .. LATDB_DIR:gsub('/', '\\') .. '"', -1)
  elseif osn:find('OSX') or osn:find('mac') then
    reaper.ExecProcess('/usr/bin/open "' .. LATDB_DIR .. '"', -1)
  else
    reaper.ExecProcess('xdg-open "' .. LATDB_DIR .. '"', -1)
  end
end

function latdb_load()
  LATDB.by = {}
  local f = io.open(LATDB_FILE, 'r')
  if not f then return end
  for line in f:lines() do
    local name, lat, mx, ok, src, sr = line:match('^([^\t]+)\t(%-?%d+)\t(%-?%d+)\t([01])\t([^\t]*)\t?(%d*)')
    if name then
      LATDB.by[latdb_key(name)] = { name = name, lat = tonumber(lat), max = tonumber(mx),
                                    allowed = ok == '1', src = src, sr = tonumber(sr) }
    end
  end
  f:close()
  LATDB.rev = LATDB.rev + 1
end

function latdb_save()
  reaper.RecursiveCreateDirectory(LATDB_DIR, 0)
  local f = io.open(LATDB_FILE, 'w')
  if not f then return end
  local keys = {}
  for k in pairs(LATDB.by) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do f:write(latdb_line(LATDB.by[k])) end
  f:close()
  LATDB.dirty = false
end

function latdb_line(e)
  local nm = e.name:gsub('[\t\r\n]', ' ')
  return ('%s\t%d\t%d\t%s\t%s\t%d\n'):format(nm, e.lat or 0, e.max or e.lat or 0,
         e.allowed and '1' or '0', e.src or 'seen', math.floor(e.sr or 0))
end

-- one entry added at the end of the file right away (the scan uses this, so a
-- crash never loses what was already measured). When the file is read, the
-- last line for an FX wins; the next full save tidies the file up.
function latdb_append(name)
  local e = LATDB.by[latdb_key(name)]
  if not e then return end
  reaper.RecursiveCreateDirectory(LATDB_DIR, 0)
  local f = io.open(LATDB_FILE, 'a')
  if f then f:write(latdb_line(e)); f:close() end
end

-- written at most a few seconds after the first unsaved change
function latdb_touch()
  if not LATDB.dirty then LATDB.save_t = reaper.time_precise() + 3 end
  LATDB.dirty = true
  LATDB.rev = LATDB.rev + 1
end

function latdb_tick(now)
  if LATDB.dirty and now >= LATDB.save_t then latdb_save() end
end

function latdb_get(name) return LATDB.by[latdb_key(name)] end

-- records what an FX reports (scan, or while it sits in a rack)
function latdb_record(name, lat, src)
  if not name or name == '' then return end
  local k = latdb_key(name)
  local e = LATDB.by[k]
  local sr = sample_rate()
  if not e then
    e = { name = name, lat = lat, max = lat, allowed = false, src = src, sr = sr }
    LATDB.by[k] = e
    latdb_touch()
    return
  end
  if e.lat ~= lat or (lat > (e.max or 0)) or (src == 'scan' and e.src ~= 'scan') or e.src == 'failed' then
    e.lat = lat
    e.max = math.max(e.max or 0, lat)
    if src == 'scan' or e.src ~= 'scan' then e.src = src end
    e.sr = sr
    latdb_touch()
  end
end

function latdb_allowed(name)
  local e = latdb_get(name)
  return e ~= nil and e.allowed
end

function latdb_set_allowed(name, on)
  local k = latdb_key(name)
  local e = LATDB.by[k]
  if not e then
    e = { name = name, lat = 0, max = 0, src = 'seen', sr = sample_rate() }
    LATDB.by[k] = e
  end
  e.allowed = on and true or false
  latdb_touch()
end

-- an FX is "over" on its own when its known latency is above the limit
function latdb_over(e)
  return e and not e.allowed and e.src ~= 'failed' and (e.lat or 0) > LAT_LIMIT
end

---------------------------------------- favorite and recently used FX
--
-- Both are plain lists of full FX names, one per line, in the data folder:
--   favorites.txt   FX starred in FX > Plugin list...
--   recent_fx.txt   FX picked from an FX menu, newest first

FAV_FILE    = LATDB_DIR .. '/favorites.txt'
RECENT_FILE = LATDB_DIR .. '/recent_fx.txt'
RECENT_KEEP = 30           -- how many are remembered (Settings decides how many are shown)
FAVS   = { by = {}, rev = 0 }   -- [lowercase name] = name
RECENT = {}                     -- names, newest first

function read_lines(path)
  local out = {}
  local f = io.open(path, 'r')
  if not f then return out end
  for line in f:lines() do
    line = line:gsub('\r$', '')
    if line ~= '' then out[#out + 1] = line end
  end
  f:close()
  return out
end

function write_lines(path, lines)
  reaper.RecursiveCreateDirectory(LATDB_DIR, 0)
  local f = io.open(path, 'w')
  if not f then return end
  for _, l in ipairs(lines) do f:write(l, '\n') end
  f:close()
end

function favs_load()
  FAVS.by = {}
  for _, n in ipairs(read_lines(FAV_FILE)) do FAVS.by[n:lower()] = n end
  FAVS.rev = FAVS.rev + 1
end

function is_fav(name) return FAVS.by[(name or ''):lower()] ~= nil end

function set_fav(name, on)
  FAVS.by[name:lower()] = on and name or nil
  FAVS.rev = FAVS.rev + 1
  local t = {}
  for _, n in pairs(FAVS.by) do t[#t + 1] = n end
  table.sort(t, function(a, b) return a:lower() < b:lower() end)
  write_lines(FAV_FILE, t)
end

function recent_load()
  RECENT = read_lines(RECENT_FILE)
end

function recent_add(name)
  if not name or name == '' then return end
  local t = { name }
  for _, n in ipairs(RECENT) do
    if n:lower() ~= name:lower() and #t < RECENT_KEEP then t[#t + 1] = n end
  end
  RECENT = t
  write_lines(RECENT_FILE, RECENT)
end

-- installed FX for a list of names (FX no longer installed are skipped)
function items_for(names, max, hide_over)
  if not fx_db then fx_db = build_fx_db() end
  local out = {}
  for _, n in ipairs(names) do
    local it = fx_db.by_name[n:lower()]
    if it and not (hide_over and latdb_over(latdb_get(it.name))) then
      out[#out + 1] = it
      if max and #out >= max then break end
    end
  end
  return out
end

function fav_items()
  local names = {}
  for _, n in pairs(FAVS.by) do names[#names + 1] = n end
  local items = items_for(names, nil, S.hide_over)
  sort_items(items)
  return items
end

---------------------------------------- new FX detection

function is_instrument_type(t)
  return t ~= nil and t:sub(-1) == 'i' and t ~= 'JS'
end

-- installed effects (instruments left out) that are not in the list yet
function unscanned_fx()
  local out = {}
  local i = 0
  while true do
    local ok, name, ident = reaper.EnumInstalledFX(i)
    if not ok then break end
    i = i + 1
    local t = name:match('^([%w_]+):')
    if not is_instrument_type(t) and not name:find(METER_NAME, 1, true) then
      local e = LATDB.by[latdb_key(name)]
      if not e or (e.src ~= 'scan' and e.src ~= 'failed') then
        out[#out + 1] = { name = name, ident = ident }
      end
    end
  end
  return out
end

-- every installed effect, for a full rescan
-- every installed effect, for a full rescan; FX that failed (could not load, or
-- stopped REAPER) are left out unless only_failed asks for exactly those
function all_effects(only_failed)
  local out = {}
  local i = 0
  while true do
    local ok, name, ident = reaper.EnumInstalledFX(i)
    if not ok then break end
    i = i + 1
    local t = name:match('^([%w_]+):')
    if not is_instrument_type(t) and not name:find(METER_NAME, 1, true) then
      local e = LATDB.by[latdb_key(name)]
      local failed = e ~= nil and e.src == 'failed'
      if failed == (only_failed == true) then out[#out + 1] = { name = name, ident = ident } end
    end
  end
  return out
end

NEWFX = { t = -math.huge, asked = false }

-- at start and once a minute: offer to scan FX that appeared since the last scan
function check_new_fx(now)
  if RESUME then return end          -- an interrupted scan is offered first
  if not S.ask_scan or SCAN.active or NEWFX.asked or S.mode ~= 'edit' then return end
  if now - NEWFX.t < 300 then return end
  NEWFX.t = now
  local list = unscanned_fx()
  if #list == 0 then return end
  NEWFX.asked = true            -- once per session; Options > Scan new FX is always there
  local first = next(LATDB.by) == nil
  local text = (first
      and 'FOH-Mate can measure the latency of your %d installed effects, so the\nlatency watchdog knows them before you load them.\n\n'
      or  '%d new effects were found since the last latency scan.\n\n')
      .. 'Each one is loaded once on a hidden track and removed. Audio may glitch while\n'
      .. 'it runs, so do it when nothing is live. Save your project first: a plug-in that\n'
      .. 'crashes on load can take REAPER down (it is skipped next time).\n\nScan now?'
  request_confirm(text:format(#list), function() start_scan(list) end, 'Scan')
end

---------------------------------------- the scan

SCAN = { active = false }

function write_file(path, text, mode)
  local f = io.open(path, mode or 'w')
  if f then f:write(text); f:close() end
end

function scan_log(line)
  write_file(SCAN_LOG, line .. '\n', 'a')
end

function start_scan(list)
  if SCAN.active or #list == 0 then return end
  if S.mode ~= 'edit' then
    request_confirm('Switch to Edit mode to scan FX for latency.', function() end, 'OK')
    return
  end
  reaper.RecursiveCreateDirectory(LATDB_DIR, 0)
  -- each scan adds to the log, so a scan resumed after a crash keeps the first part
  write_file(SCAN_LOG, ('\nFOH-Mate %s latency scan, %s, %d FX\n'):format(VERSION, os.date('%Y-%m-%d %H:%M'), #list), 'a')
  local n = reaper.CountTracks(0)
  reaper.PreventUIRefresh(1)
  reaper.InsertTrackAtIndex(n, false)
  local tr = reaper.GetTrack(0, n)
  reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', 'FOHMate latency scan (temporary)', true)
  -- silent without being muted (no master send, no outputs), so the FX really run
  reaper.SetMediaTrackInfo_Value(tr, 'B_MAINSEND', 0)
  reaper.SetMediaTrackInfo_Value(tr, 'B_SHOWINTCP', 0)
  reaper.SetMediaTrackInfo_Value(tr, 'B_SHOWINMIXER', 0)
  reaper.PreventUIRefresh(-1)
  SCAN = { active = true, list = list, i = 0, tr = tr, phase = 'next', cur = nil,
           found = 0, failed = 0, measured = 0 }
  -- the list and the position are kept on disk, so a crash or a quit can be continued
  local lines = {}
  for _, it in ipairs(list) do lines[#lines + 1] = it.name .. '\t' .. (it.ident or '') end
  write_file(SCAN_TODO, table.concat(lines, '\n') .. '\n')
  write_file(SCAN_POS, '0')
  RESUME = nil
end

function finish_scan(cancelled)
  if SCAN.tr and valid(SCAN.tr) then reaper.DeleteTrack(SCAN.tr) end
  os.remove(SCAN_MARK)
  os.remove(SCAN_TODO)                 -- done, or stopped on purpose: nothing to continue
  os.remove(SCAN_POS)
  latdb_save()
  local msg = cancelled and 'Latency scan stopped' or 'Latency scan done'
  local summary = ('%s: %d measured, %d with latency, %d could not load.')
                  :format(msg, SCAN.measured, SCAN.found, SCAN.failed)
  scan_log(summary)
  SCAN = { active = false, last = summary, last_t = reaper.time_precise() }
end

function scan_failed(item, why)
  local k = latdb_key(item.name)
  local e = LATDB.by[k] or { name = item.name, lat = 0, max = 0, allowed = false }
  e.src = 'failed'
  LATDB.by[k] = e
  latdb_touch()
  latdb_append(item.name)
  SCAN.failed = SCAN.failed + 1
  scan_log(item.name .. '\t' .. why)
end

-- One FX at a time, in three steps, one per frame or more:
--   next : show its name (so the window says which FX is loading, even if it hangs)
--   load : load it (with a marker file on disk while it loads)
--   wait : give it a moment to settle, read its latency, remove it
function scan_step()
  if not SCAN.active then return end
  if not valid(SCAN.tr) then finish_scan(true) return end
  local now = reaper.time_precise()

  if SCAN.phase == 'next' then
    if SCAN.rest_until and now < SCAN.rest_until then return end
    SCAN.i = SCAN.i + 1
    SCAN.cur = SCAN.list[SCAN.i]
    if not SCAN.cur then finish_scan(false) return end
    SCAN.phase = 'load'
    return

  elseif SCAN.phase == 'load' then
    local item = SCAN.cur
    write_file(SCAN_MARK, SCAN.i .. '\t' .. item.name)
    local idx = reaper.TrackFX_AddByName(SCAN.tr, item.ident or item.name, false, -1)
    if idx < 0 and item.ident then idx = reaper.TrackFX_AddByName(SCAN.tr, item.name, false, -1) end
    os.remove(SCAN_MARK)
    if idx < 0 then
      scan_failed(item, 'could not load')
      SCAN.rest_until = now + CFG.scan_pause
      SCAN.phase = 'next'
      write_file(SCAN_POS, tostring(SCAN.i))
    else
      reaper.TrackFX_Show(SCAN.tr, idx, 2)       -- never leave a window open: no floating window,
      reaper.TrackFX_Show(SCAN.tr, idx, 0)       -- no FX chain window
      -- Audio Units can take longer to report their latency once loaded
      SCAN.wait_until = now + (item.name:match('^AUi?:') and 0.8 or 0.25)
      SCAN.phase = 'wait'
    end
    return

  elseif SCAN.phase == 'wait' then
    if now < SCAN.wait_until then return end
    local item = SCAN.cur
    local n = reaper.TrackFX_GetCount(SCAN.tr)
    if n > 0 then
      local ok, s = reaper.TrackFX_GetNamedConfigParm(SCAN.tr, 0, 'pdc')
      local lat = (ok and tonumber(s)) or 0
      local ok2, c = reaper.TrackFX_GetNamedConfigParm(SCAN.tr, 0, 'chain_pdc_reporting')
      lat = math.max(lat, (ok2 and tonumber(c)) or 0)
      -- Audio Units can be slow to report: one that says 0 gets a second, later look
      if lat == 0 and item.name:match('^AUi?:') and not SCAN.second_look then
        SCAN.second_look = true
        SCAN.wait_until = now + CFG.scan_au_wait
        return
      end
      SCAN.second_look = nil
      latdb_record(item.name, lat, 'scan')
      latdb_append(item.name)
      SCAN.measured = SCAN.measured + 1
      if lat > 0 then SCAN.found = SCAN.found + 1 end
      scan_log(('%s\t%d samples'):format(item.name, lat))
      for fx = n - 1, 0, -1 do reaper.TrackFX_Delete(SCAN.tr, fx) end
    end
    -- a short pause before the next one: some plug-ins don't like being loaded right
    -- after another one was removed
    SCAN.rest_until = now + CFG.scan_pause
    SCAN.phase = 'next'
    write_file(SCAN_POS, tostring(SCAN.i))
  end
end

-- REAPER stopped during the last scan: the FX that was loading is marked
-- failed (never loaded by a scan again) and named on the next start
CRASH_FX = nil

function read_file(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local t = f:read('a')
  f:close()
  return t
end

RESUME = nil     -- the rest of a scan that did not finish: { list, crashed }

function scan_recover()
  local mark = read_file(SCAN_MARK) or ''
  local at, name = mark:match('^(%d+)\t(.*)$')
  if not at then name = mark end                     -- marker written by 0.10.2 - 0.11.5
  at = tonumber(at)
  if name == '' then
    -- marker kept by 0.10.0/0.10.1 in REAPER's settings
    name = reaper.GetExtState(EXT_SECTION, 'scan_current')
  end
  reaper.DeleteExtState(EXT_SECTION, 'scan_current', true)
  os.remove(SCAN_MARK)
  if name ~= '' then
    local e = LATDB.by[latdb_key(name)] or { name = name, lat = 0, max = 0, allowed = false }
    e.src = 'failed'
    LATDB.by[latdb_key(name)] = e
    latdb_save()
    scan_log(name .. '\tREAPER stopped while loading it')
    CRASH_FX = name
  end
  -- an interrupted scan: what is left after the crash, or after where it got to
  local todo = read_file(SCAN_TODO)
  if todo then
    local list = {}
    for line in todo:gmatch('[^\n]+') do
      local n, id = line:match('^(.-)\t(.*)$')
      if n then list[#list + 1] = { name = n, ident = (id ~= '' and id or nil) } end
    end
    local from = (at or tonumber(read_file(SCAN_POS) or '') or 0) + 1
    local rest = {}
    for i = from, #list do
      local e = LATDB.by[latdb_key(list[i].name)]
      if not (e and e.src == 'failed') then rest[#rest + 1] = list[i] end
    end
    if #rest > 0 then RESUME = { list = rest, crashed = CRASH_FX ~= nil } end
    os.remove(SCAN_TODO)
    os.remove(SCAN_POS)
  end
  -- a scan track left behind by a crash
  for i = reaper.CountTracks(0) - 1, 0, -1 do
    local t = reaper.GetTrack(0, i)
    local tn = track_name(t)
    if tn == 'FOHMate latency scan (temporary)' or tn == 'LiveRack latency scan (temporary)' then reaper.DeleteTrack(t) end
  end
end

-- shown once, on the first frame after a crash during a scan
function announce_crash()
  if confirm or not (CRASH_FX or RESUME) then return end
  local name, resume = CRASH_FX, RESUME
  CRASH_FX, RESUME = nil, nil        -- asked once
  NEWFX.asked = true          -- no scan offer on top of this
  local text
  if name then
    text = ('REAPER stopped during the last latency scan, while loading:\n\n    %s\n\n'
      .. 'It is marked "failed" in FX > Plugin list... Scans leave it out\n'
      .. '(Latency > Retry failed FX... tries again). The scan, in order, is in:\n%s\n\n'):format(name, SCAN_LOG)
  else
    text = 'The last latency scan did not finish.\n\n'
  end
  if resume then
    request_confirm(text .. ('Continue that scan where it stopped (%d FX left)?'):format(#resume.list),
      function() start_scan(resume.list) end, 'Continue')
  else
    request_confirm(text .. 'Scan the FX that are not measured yet?', function() ask_scan('new') end, 'Scan the rest')
  end
end

-- which: 'new' (not measured yet), 'all' (everything but failed FX), 'failed' (only those)
function ask_scan(which)
  local list
  if which == 'all' then list = all_effects(false)
  elseif which == 'failed' then list = all_effects(true)
  else list = unscanned_fx() end
  if #list == 0 then
    request_confirm(which == 'failed' and 'No FX is marked as failed.'
                    or 'Every installed effect is already in the latency list.', function() end, 'OK')
    return
  end
  local what = (which == 'all' and 'Rescan all %d effects (failed ones left out)')
            or (which == 'failed' and 'Retry the %d effects that failed before (some may crash REAPER again)')
            or 'Scan %d effects'
  request_confirm((what .. ' for latency?\n\nEach one is loaded once on a hidden track and removed. Audio may glitch\n'
    .. 'while it runs, so do it when nothing is live. Save your project first: a plug-in\n'
    .. 'that crashes on load can take REAPER down (it is skipped next time, and the scan\n'
    .. 'can be continued where it stopped).'):format(#list), function() start_scan(list) end, 'Scan')
end

-- progress window
function draw_scan_window()
  if not SCAN.active then return end
  ig.SetNextWindowSize(ctx, 420, 0, ig.Cond_Always())
  local vis = ig.Begin(ctx, 'FX latency scan###lr_scan', nil, ig.WindowFlags_NoCollapse())
  if vis then
    local n = #SCAN.list
    ig.Text(ctx, ('Measuring %d of %d'):format(math.min(SCAN.i, n), n))
    local cur = SCAN.cur
    type_text(cur and ((SCAN.phase == 'wait' and 'Reading: ' or 'Loading: ') .. fit_text(cur.name, 330)) or '')
    ig.ProgressBar(ctx, n > 0 and (SCAN.i - 1) / n or 0, -1, 0)
    ig.TextDisabled(ctx, ('%d with latency so far, %d could not load'):format(SCAN.found, SCAN.failed))
    if ig.Button(ctx, 'Stop', 100, 0) then finish_scan(true) end
    ig.End(ctx)
  end
end

---------------------------------------- the list window

-- FX > Plugin list...: every installed FX, with a star for favorites, its type, its
-- latency and scan status. Click a name to select it (Cmd/Ctrl-click adds, Shift-click
-- selects a range); the selection can be rescanned for latency.
LATWIN = { open = false, filter = '', type = nil, dev = nil, dev_filter = '', only_lat = false, only_fav = false,
           sort = 'name', desc = false, sel = {}, anchor = nil, cache_key = nil, rows = {} }

STATUS_TEXT = { scan = 'measured', seen = 'seen in a rack', failed = 'failed' }

-- a five-pointed star, filled (favorite) or outlined
function draw_star(dl, cx, cy, R, col, filled)
  local pts = {}
  for i = 0, 9 do
    local a = -math.pi / 2 + i * math.pi / 5
    local r = (i % 2 == 0) and R or R * 0.45
    pts[#pts + 1] = cx + math.cos(a) * r
    pts[#pts + 1] = cy + math.sin(a) * r
  end
  if filled then
    for i = 0, 9 do
      local j = (i + 1) % 10
      ig.DrawList_AddTriangleFilled(dl, cx, cy, pts[i * 2 + 1], pts[i * 2 + 2], pts[j * 2 + 1], pts[j * 2 + 2], col)
    end
  else
    ig.DrawList_AddPolyline(dl, reaper.new_array(pts), col, ig.DrawFlags_Closed(), 1.2)
  end
end

-- the columns: header, sort key, and how a row sorts on it (a number or a lowercase string)
STATUS_RANK = { failed = 1, scan = 2, seen = 3 }
PLIST_SORT = {
  fav     = function(r) return is_fav(r.it.name) and 0 or 1 end,
  type    = function(r) return type_rank(r.it.type) end,
  name    = function(r) return r.it.short:lower() end,
  dev     = function(r) return r.it.dev:lower() end,
  lat     = function(r) return (r.e and r.e.src ~= 'failed') and (r.e.lat or 0) or -1 end,
  max     = function(r) return (r.e and r.e.src ~= 'failed') and (r.e.max or 0) or -1 end,
  allowed = function(r) return (r.e and r.e.allowed) and 0 or 1 end,
  status  = function(r) return r.e and (STATUS_RANK[r.e.src] or 4) or 5 end,
}
PLIST_COLS = {
  { '##fav', 'fav' }, { 'Type', 'type' }, { 'FX', 'name' }, { 'Developer', 'dev' },
  { 'Latency', 'lat', true }, { 'Highest', 'max', true }, { 'Allowed', 'allowed' }, { 'Status', 'status' },
}   -- the third value: the first click sorts high to low (biggest latency first)

-- the rows shown, rebuilt only when something they depend on changes
function plugin_rows()
  if not fx_db then fx_db = build_fx_db() end
  local W = LATWIN
  local key = table.concat({ W.filter, tostring(W.type), tostring(W.dev), tostring(W.only_lat), tostring(W.only_fav), W.sort, tostring(W.desc),
                             LATDB.rev, FAVS.rev, LAT_LIMIT, tostring(fx_db) }, '|')
  if W.cache_key == key then return W.rows end
  local words = {}
  for w in W.filter:lower():gmatch('%S+') do words[#words + 1] = w end
  local rows = {}
  for _, it in ipairs(fx_db.all) do
    local low = it.name:lower()
    local ok = (not W.type or it.type == W.type) and (not W.dev or it.dev == W.dev)
               and not it.name:find(METER_NAME, 1, true)
    if ok then
      for _, w in ipairs(words) do
        if not low:find(w, 1, true) then ok = false; break end
      end
    end
    local e = ok and latdb_get(it.name) or nil
    if ok and W.only_fav and not is_fav(it.name) then ok = false end
    if ok and W.only_lat then ok = e ~= nil and ((e.max or 0) > 0 or e.allowed or e.src == 'failed') end
    if ok then rows[#rows + 1] = { it = it, e = e, key = low } end
  end
  -- the sort column's value for a row (ties: by name, then type)
  local sk = PLIST_SORT[W.sort] or PLIST_SORT.name
  for _, r in ipairs(rows) do r.sv = sk(r) end
  table.sort(rows, function(a, b)
    if a.sv ~= b.sv then
      if W.desc then return a.sv > b.sv end
      return a.sv < b.sv
    end
    local la, lb = a.it.label:lower(), b.it.label:lower()
    if la ~= lb then return la < lb end
    return type_rank(a.it.type) < type_rank(b.it.type)
  end)
  W.cache_key, W.rows = key, rows
  return rows
end

function plugin_selection()
  local out = {}
  for _, r in ipairs(LATWIN.rows) do
    if LATWIN.sel[r.key] then out[#out + 1] = r.it end
  end
  return out
end

function rescan_items(items)
  if #items == 0 then return end
  local list = {}
  for _, it in ipairs(items) do list[#list + 1] = { name = it.name, ident = it.ident } end
  local what = #list == 1 and ('Rescan "%s"'):format(list[1].name) or ('Rescan the %d selected FX'):format(#list)
  request_confirm(what .. ' for latency?\n\nEach one is loaded once on a hidden track and removed. Audio may glitch\n'
    .. 'while it runs, so do it when nothing is live. FX marked failed are tried again\n'
    .. '(one that crashes on load can take REAPER down).', function() start_scan(list) end, 'Scan')
end

function draw_plugin_list()
  if not LATWIN.open then return end
  local W = LATWIN
  local vis, open = begin_window('latlist', 'Plugin list###lr_latlist', 760, 520, true)
  if vis then
    CONFIRM_HOST = 'latlist'
    -- filters
    ig.SetNextItemWidth(ctx, 180)
    local rv, f = ig.InputTextWithHint(ctx, '##flt', 'Filter by name', W.filter)
    if rv then W.filter = f end
    ig.SameLine(ctx)
    ig.SetNextItemWidth(ctx, 110)
    if ig.BeginCombo(ctx, '##type', W.type or 'All types') then
      if ig.Selectable(ctx, 'All types', W.type == nil) then W.type = nil end
      for _, g in ipairs(fx_db and fx_db.types or {}) do
        ig.PushStyleColor(ctx, ig.Col_Text(), type_color(g.name))
        if ig.Selectable(ctx, ('%s (%d)'):format(g.name, #g.items), W.type == g.name) then W.type = g.name end
        ig.PopStyleColor(ctx)
      end
      ig.EndCombo(ctx)
    end
    ig.SameLine(ctx)
    -- developers, with a filter field at the top of the list (there can be a hundred or more)
    ig.SetNextItemWidth(ctx, 170)
    if ig.BeginCombo(ctx, '##dev', W.dev or 'All developers', ig.ComboFlags_HeightLarge()) then
      if ig.IsWindowAppearing(ctx) then W.dev_filter = ''; ig.SetKeyboardFocusHere(ctx) end
      ig.SetNextItemWidth(ctx, -1)
      local rvd, df = ig.InputTextWithHint(ctx, '##devflt', 'Find a developer', W.dev_filter)
      if rvd then W.dev_filter = df end
      if ig.Selectable(ctx, 'All developers', W.dev == nil) then W.dev = nil end
      local q = W.dev_filter:lower()
      for _, g in ipairs(fx_db and fx_db.devs or {}) do
        if q == '' or g.name:lower():find(q, 1, true) then
          if ig.Selectable(ctx, ('%s (%d)##d'):format(g.name, #g.items), W.dev == g.name) then W.dev = g.name end
        end
      end
      ig.EndCombo(ctx)
    end
    ig.SameLine(ctx)
    local c1, v1 = ig.Checkbox(ctx, 'Favorites', W.only_fav)
    if c1 then W.only_fav = v1 end
    ig.SameLine(ctx)
    local c2, v2 = ig.Checkbox(ctx, 'Latency, allowed or failed', W.only_lat)
    if c2 then W.only_lat = v2 end

    local rows = plugin_rows()
    local sel = plugin_selection()
    local can_scan = not SCAN.active and S.mode == 'edit'

    -- selection and actions
    if ig.Button(ctx, 'Select all shown') then
      for _, r in ipairs(rows) do W.sel[r.key] = true end
    end
    ig.SameLine(ctx)
    if ig.Button(ctx, 'Clear selection') then W.sel = {} end
    ig.SameLine(ctx)
    ig.BeginDisabled(ctx, #sel == 0 or not can_scan)
    if ig.Button(ctx, ('Rescan selected (%d)...'):format(#sel)) then rescan_items(sel) end
    ig.EndDisabled(ctx)
    if not can_scan and ig.IsItemHovered(ctx, ig.HoveredFlags_AllowWhenDisabled()) then
      ig.SetTooltip(ctx, SCAN.active and 'A scan is running' or 'Switch to Edit mode to scan')
    end
    ig.TextDisabled(ctx, ('%d FX shown, %d selected  -  limits: %d samples per FX, %d per rack (Latency > Latency limits...)')
                         :format(#rows, #sel, LAT_LIMIT, LAT_RACK_LIMIT))

    local flags = ig.TableFlags_RowBg() | ig.TableFlags_BordersInnerV() | ig.TableFlags_ScrollY() | ig.TableFlags_Resizable()
    if ig.BeginTable(ctx, 'lat_tbl', 8, flags, 0, -1) then
      local fixed = ig.TableColumnFlags_WidthFixed()
      ig.TableSetupScrollFreeze(ctx, 0, 1)
      ig.TableSetupColumn(ctx, '##fav', fixed | ig.TableColumnFlags_NoResize(), 28)
      ig.TableSetupColumn(ctx, 'Type', fixed, 50)
      ig.TableSetupColumn(ctx, 'FX', ig.TableColumnFlags_WidthStretch())
      ig.TableSetupColumn(ctx, 'Developer', fixed, 130)
      ig.TableSetupColumn(ctx, 'Latency', fixed, 120)
      ig.TableSetupColumn(ctx, 'Highest', fixed, 60)
      ig.TableSetupColumn(ctx, 'Allowed', fixed | ig.TableColumnFlags_NoResize(), 60)
      ig.TableSetupColumn(ctx, 'Status', fixed, 100)
      local fh = ig.GetFrameHeight(ctx)
      local tdl = ig.GetWindowDrawList(ctx)
      -- headers: click one to sort by it, click again to reverse; an arrow shows which and which way
      ig.TableNextRow(ctx, ig.TableRowFlags_Headers())
      for ci, col in ipairs(PLIST_COLS) do
        ig.TableSetColumnIndex(ctx, ci - 1)
        ig.TableHeader(ctx, col[1])
        if ig.IsItemClicked(ctx, 0) then
          if W.sort == col[2] then W.desc = not W.desc else W.sort, W.desc = col[2], col[3] == true end
        end
        if ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, 'Click to sort by this column, again to reverse') end
        local x1, y1 = ig.GetItemRectMin(ctx)
        local x2, y2 = ig.GetItemRectMax(ctx)
        local cy = (y1 + y2) / 2
        local ink = ig.GetStyleColor(ctx, ig.Col_Text())
        if col[2] == 'fav' then draw_star(tdl, x1 + 9, cy, 5.5, T.dim, false) end
        if W.sort == col[2] then
          local ax = (col[2] == 'fav') and (x1 + 19) or (x2 - 8)
          if W.desc then
            ig.DrawList_AddTriangleFilled(tdl, ax - 4, cy - 2, ax + 4, cy - 2, ax, cy + 3, ink)
          else
            ig.DrawList_AddTriangleFilled(tdl, ax - 4, cy + 2, ax + 4, cy + 2, ax, cy - 3, ink)
          end
        end
      end
      local sel_bg = (T.glow & 0xFFFFFF00) | 0x30
      -- only the rows on screen are drawn (the list can hold hundreds of FX)
      if ig.CreateListClipper and not (W.clipper and ig.ValidatePtr(W.clipper, 'ImGui_ListClipper*')) then
        W.clipper = ig.CreateListClipper(ctx)
      end
      local clipper = ig.CreateListClipper and W.clipper
      local function draw_row(i)
        local r = rows[i]
        local it, e = r.it, r.e
        ig.TableNextRow(ctx)
        if W.sel[r.key] and ig.TableSetBgColor then ig.TableSetBgColor(ctx, ig.TableBgTarget_RowBg1(), sel_bg) end
        ig.PushID(ctx, tostring(i))
        -- star
        ig.TableNextColumn(ctx)
        local sx, sy = ig.GetCursorScreenPos(ctx)
        local fav = is_fav(it.name)
        if ig.InvisibleButton(ctx, '##star', 18, ig.GetTextLineHeight(ctx)) then set_fav(it.name, not fav) end
        local hov = ig.IsItemHovered(ctx)
        draw_star(tdl, sx + 9, sy + ig.GetTextLineHeight(ctx) / 2, 6.5,
                  fav and 0xF2C230FF or (hov and T.gauge_text or T.dim), fav)
        if hov then ig.SetTooltip(ctx, fav and 'Favorite (click to remove)' or 'Add to favorites') end
        -- type
        ig.TableNextColumn(ctx)
        ig.TextColored(ctx, type_color(it.type), it.type)
        -- name: click to select
        ig.TableNextColumn(ctx)
        local over = latdb_over(e)
        if over then ig.PushStyleColor(ctx, ig.Col_Text(), ALERT_RED) end
        local clicked = ig.Selectable(ctx, it.short .. '##nm', W.sel[r.key] == true)
        if over then ig.PopStyleColor(ctx) end
        if clicked then
          if has_mod('shift') and W.anchor then
            local a
            for j, rr in ipairs(rows) do if rr.key == W.anchor then a = j; break end end
            if a then
              if not has_mod('ctrl') then W.sel = {} end
              for j = math.min(a, i), math.max(a, i) do W.sel[rows[j].key] = true end
            end
          elseif has_mod('ctrl') then
            W.sel[r.key] = (not W.sel[r.key]) or nil
            W.anchor = r.key
          else
            W.sel = { [r.key] = true }
            W.anchor = r.key
          end
        end
        if ig.BeginPopupContextItem(ctx, 'row_ctx') then
          if not W.sel[r.key] then W.sel = { [r.key] = true }; W.anchor = r.key end
          local items = plugin_selection()
          if ig.MenuItem(ctx, #items > 1 and ('Rescan the %d selected FX...'):format(#items) or 'Rescan this FX...',
                         nil, false, can_scan) then
            rescan_items(items)
          end
          ig.Separator(ctx)
          if ig.MenuItem(ctx, 'Add to favorites') then for _, x in ipairs(items) do set_fav(x.name, true) end end
          if ig.MenuItem(ctx, 'Remove from favorites') then for _, x in ipairs(items) do set_fav(x.name, false) end end
          ig.EndPopup(ctx)
        end
        -- developer: click to show only that developer
        ig.TableNextColumn(ctx)
        if ig.Selectable(ctx, it.dev .. '##dv', false) then
          if W.dev == it.dev then W.dev = nil else W.dev = it.dev end   -- not "x and nil or y": that never gives nil
        end
        if ig.IsItemHovered(ctx) then
          ig.SetTooltip(ctx, W.dev == it.dev and 'Click: every developer again' or ('Click: only ' .. it.dev))
        end
        -- latency
        ig.TableNextColumn(ctx)
        if not e or e.src == 'failed' then
          ig.TextDisabled(ctx, e and 'n/a' or '-')
        else
          local txt = ('%d (%.2f ms)'):format(e.lat or 0, (e.lat or 0) * 1000 / sample_rate())
          if over then ig.TextColored(ctx, ALERT_RED, txt) else ig.Text(ctx, txt) end
        end
        ig.TableNextColumn(ctx)
        if e and e.src ~= 'failed' then ig.Text(ctx, tostring(e.max or 0)) else ig.TextDisabled(ctx, '-') end
        -- allowed
        ig.TableNextColumn(ctx)
        local cw = ig.GetContentRegionAvail(ctx)
        ig.SetCursorPosX(ctx, ig.GetCursorPosX(ctx) + math.max(0, (cw - fh) / 2))
        local c, nv = ig.Checkbox(ctx, '##al', e ~= nil and e.allowed)
        if c then latdb_set_allowed(it.name, nv); LAT = {} end
        -- status
        ig.TableNextColumn(ctx)
        if e and e.src == 'failed' then
          ig.TextColored(ctx, ALERT_RED, 'failed')
        else
          ig.TextDisabled(ctx, e and (STATUS_TEXT[e.src] or e.src or '') or 'not scanned')
        end
        ig.PopID(ctx)
      end
      if clipper then
        ig.ListClipper_Begin(clipper, #rows)
        while ig.ListClipper_Step(clipper) do
          local d1, d2 = ig.ListClipper_GetDisplayRange(clipper)
          for i = d1 + 1, d2 do draw_row(i) end
        end
        ig.ListClipper_End(clipper)
      else
        for i = 1, #rows do draw_row(i) end
      end
      ig.EndTable(ctx)
    end
    draw_confirm('latlist')
    CONFIRM_HOST = nil
    ig.End(ctx)
  end
  if not open then
    LATWIN.open = false
    if confirm and confirm.host == 'latlist' then confirm = nil end   -- closed while asking: Cancel
  end
end

---------------------------------------- Show mode: FX over the limit go offline

-- in every rack over the limit, the biggest offenders go offline (unloaded, so
-- their latency is really gone) until the rack is back under the limit
function offline_for_show()
  local n = 0
  with_undo('Rack: FX offline for Show mode', function()
    for _, tr in ipairs(racks) do
      if valid(tr) then
        local list = chain_info(tr).list
        local items, total = {}, 0
        for _, it in ipairs(list) do
          local nm = fx_orig_name(tr, it.fx)
          local lat = fx_latency(tr, it.fx)
          if lat > 0 and not latdb_allowed(nm) and not reaper.TrackFX_GetOffline(tr, it.fx)
             and reaper.TrackFX_GetEnabled(tr, it.fx) then
            items[#items + 1] = { guid = reaper.TrackFX_GetFXGUID(tr, it.fx), lat = lat }
            total = total + lat
          end
        end
        table.sort(items, function(a, b) return a.lat > b.lat end)
        if total > LAT_RACK_LIMIT or (items[1] and items[1].lat > LAT_LIMIT) then
          local off = {}
          for _, x in ipairs(items) do
            if total <= LAT_RACK_LIMIT and x.lat <= LAT_LIMIT then break end
            local fx = fx_index_by_guid(tr, x.guid)
            if fx then
              reaper.TrackFX_SetOffline(tr, fx, true)
              off[#off + 1] = x.guid
              total = total - x.lat
              n = n + 1
            end
          end
          if #off > 0 then reaper.GetSetMediaTrackInfo_String(tr, EXT_SHOWOFF, table.concat(off, ';'), true) end
        end
        LAT[reaper.GetTrackGUID(tr)] = nil
      end
    end
  end)
  return n
end

-- back to Edit: the FX taken offline come back
function online_after_show()
  with_undo('Rack: FX back online after Show mode', function()
    for _, tr in ipairs(racks) do
      if valid(tr) then
        local ok, s = reaper.GetSetMediaTrackInfo_String(tr, EXT_SHOWOFF, '', false)
        if ok and s ~= '' then
          for g in s:gmatch('[^;]+') do
            local fx = fx_index_by_guid(tr, g)
            if fx then reaper.TrackFX_SetOffline(tr, fx, false) end
          end
          reaper.GetSetMediaTrackInfo_String(tr, EXT_SHOWOFF, '', true)
        end
        LAT[reaper.GetTrackGUID(tr)] = nil
      end
    end
  end)
end

function is_show_offline(tr, guid)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, EXT_SHOWOFF, '', false)
  return ok and s:find(guid, 1, true) ~= nil
end

---------------------------------------------------------------- add FX menu

-- Built from REAPER's own FX list (and, when it can be read, the folders
-- from the FX browser). Built once, on first use. The FX type (VST3, AU,
-- JS...) is part of every menu entry, so versions of the same FX can be told apart.
function read_ini(path)
  local secs = {}
  local f = io.open(path, 'r')
  if not f then return secs end
  local cur = nil
  for line in f:lines() do
    local s = line:match('^%[(.-)%]%s*$')
    if s then
      cur = {}
      secs[s] = cur
    elseif cur then
      local k, v = line:match('^([^=]+)=(.*)$')
      if k then cur[k] = (v:gsub('\r$', '')) end
    end
  end
  f:close()
  return secs
end

function type_rank(name)
  for i, n in ipairs(TYPE_ORDER) do
    if n == name then return i end
  end
  return 100
end

function sort_items(items)
  table.sort(items, function(a, b)
    local la, lb = a.label:lower(), b.label:lower()
    if la ~= lb then return la < lb end
    return type_rank(a.type) < type_rank(b.type)
  end)
end

function sorted_groups(map, by_type)
  local out = {}
  for name, items in pairs(map) do
    sort_items(items)
    out[#out + 1] = { name = name, items = items }
  end
  table.sort(out, function(a, b)
    if by_type then
      local ra, rb = type_rank(a.name), type_rank(b.name)
      if ra ~= rb then return ra < rb end
    end
    return a.name:lower() < b.name:lower()
  end)
  return out
end

function build_fx_db()
  local by_type, by_dev = {}, {}
  local idx_name, idx_ident, idx_label = {}, {}, {}
  local i = 0
  while true do
    local ok, name, ident = reaper.EnumInstalledFX(i)
    if not ok then break end
    i = i + 1
    local ftype, rest = name:match('^([%w_]+):%s*(.*)$')
    if not ftype then ftype, rest = 'Other', name end
    local dev = rest:match('%(([^()]+)%)%s*$') or 'Other'
    -- short: the name without the developer, for the plugin list's own Developer column
    local short = (dev ~= 'Other') and rest:gsub('%s*%([^()]+%)%s*$', '') or rest
    local it = { name = name, ident = ident, label = rest, type = ftype, dev = dev, short = short }
    by_type[ftype] = by_type[ftype] or {}
    table.insert(by_type[ftype], it)
    by_dev[dev] = by_dev[dev] or {}
    table.insert(by_dev[dev], it)
    idx_name[name:lower()] = it
    if ident then idx_ident[ident:lower()] = it end
    idx_label[rest:lower()] = it
  end

  -- folders of the FX browser (best effort: the file is only read, never written)
  local folders = {}
  local secs = read_ini(reaper.GetResourcePath() .. '/reaper-fxfolders.ini')
  local fs = secs['Folders']
  if fs then
    local n = 0
    while fs['Folder' .. n] do
      local fname = fs['Folder' .. n]
      local sec = secs['Folder' .. n] or secs[fname]
      if sec then
        local items = {}
        local k = 0
        while sec['Item' .. k] do
          local v = sec['Item' .. k]:lower()
          local it = idx_name[v] or idx_ident[v] or idx_label[v]
          if it then items[#items + 1] = it end
          k = k + 1
        end
        if #items > 0 then
          sort_items(items)
          folders[#folders + 1] = { name = fname, items = items }
        end
      end
      n = n + 1
    end
  end

  local all = {}
  for _, g in pairs(by_type) do for _, it in ipairs(g) do all[#all + 1] = it end end
  return {
    by_name = idx_name,          -- [lowercase full name] = item
    all     = all,
    variants = build_variants(all),
    folders = folders,
    devs    = sorted_groups(by_dev, false),
    types   = sorted_groups(by_type, true),
  }
end

-- the FX tree without the FX types switched off in Options > FX types
function get_view()
  if not fx_db then fx_db = build_fx_db() end
  local key = table.concat(hidden_list(), ',')
  if S.hide_over then key = key .. '|' .. LAT_LIMIT .. '|' .. LATDB.rev end
  if fx_view and fx_view_key == key then return fx_view end

  local function visible(items)
    local out = {}
    for _, it in ipairs(items) do
      if not S.hidden[it.type] and not (S.hide_over and latdb_over(latdb_get(it.name))) then
        out[#out + 1] = it
      end
    end
    return out
  end
  local v = { folders = {}, devs = {}, types = {} }
  for _, g in ipairs(fx_db.folders) do
    local items = visible(g.items)
    if #items > 0 then v.folders[#v.folders + 1] = { name = g.name, items = items } end
  end
  for _, g in ipairs(fx_db.devs) do
    local items = visible(g.items)
    if #items > 0 then v.devs[#v.devs + 1] = { name = g.name, items = items } end
  end
  for _, g in ipairs(fx_db.types) do
    if not S.hidden[g.name] then
      local items = S.hide_over and visible(g.items) or g.items
      if #items > 0 then v.types[#v.types + 1] = { name = g.name, items = items } end
    end
  end
  fx_view, fx_view_key = v, key
  return v
end

function draw_fx_items(items, on_pick)
  if #items <= LONG_LIST then
    for _, it in ipairs(items) do
      if fx_menu_item(it) then on_pick(it) end
    end
    return
  end
  -- letter submenus; when every name starts the same way (MAGC, MAnalyzer, MAutoAlign...),
  -- that shared start is skipped and the names are grouped by the next letter instead
  local p = 1
  while true do
    local c = items[1].label:sub(p, p):upper()
    if c == '' then break end
    local same = true
    for _, it in ipairs(items) do
      if it.label:sub(p, p):upper() ~= c then same = false; break end
    end
    if not same then break end
    p = p + 1
  end
  local groups, order = {}, {}
  for _, it in ipairs(items) do
    local ch = it.label:sub(p, p):upper()
    if not ch:match('%a') then ch = '#' end
    if not groups[ch] then groups[ch] = {}; order[#order + 1] = ch end
    table.insert(groups[ch], it)
  end
  table.sort(order)
  for _, ch in ipairs(order) do
    if ig.BeginMenu(ctx, ch) then
      for _, it in ipairs(groups[ch]) do
        if fx_menu_item(it) then on_pick(it) end
      end
      ig.EndMenu(ctx)
    end
  end
end

-- the FX tree; `on_pick(item)` is called with the chosen FX
function draw_add_menu(pick_now)
  -- the chosen FX is added once the frame is drawn (see rack_action)
  local function on_pick(item)
    later[#later + 1] = function() recent_add(item.name); pick_now(item); last_scan = -math.huge end
  end
  if draw_fx_search(on_pick) then return end     -- typing replaces the menu with results
  ig.Separator(ctx)
  local view = get_view()

  -- favorites (starred in FX > Plugin list...) and the last FX picked
  if ig.BeginMenu(ctx, 'Favorites') then
    local favs = fav_items()
    if #favs == 0 then ig.TextDisabled(ctx, 'No favorites yet: star FX in FX > Plugin list...') end
    draw_fx_items(favs, on_pick)
    ig.EndMenu(ctx)
  end
  if CFG.recent_n > 0 and ig.BeginMenu(ctx, 'Recently used') then
    local rec = items_for(RECENT, CFG.recent_n, S.hide_over)
    if #rec == 0 then ig.TextDisabled(ctx, 'Nothing yet') end
    for _, it in ipairs(rec) do
      if fx_menu_item(it) then on_pick(it) end
    end
    ig.EndMenu(ctx)
  end
  ig.Separator(ctx)

  for _, fld in ipairs(view.folders) do
    if ig.BeginMenu(ctx, fld.name .. '##fld') then
      draw_fx_items(fld.items, on_pick)
      ig.EndMenu(ctx)
    end
  end
  if #view.folders > 0 then ig.Separator(ctx) end

  if ig.BeginMenu(ctx, 'Developers') then
    for _, g in ipairs(view.devs) do
      if ig.BeginMenu(ctx, g.name .. '##dev') then
        draw_fx_items(g.items, on_pick)
        ig.EndMenu(ctx)
      end
    end
    ig.EndMenu(ctx)
  end
  if ig.BeginMenu(ctx, 'All FX') then
    for _, g in ipairs(view.types) do
      ig.PushStyleColor(ctx, ig.Col_Text(), type_color(g.name))
      local open = ig.BeginMenu(ctx, g.name .. '##typ')
      ig.PopStyleColor(ctx)
      if open then
        draw_fx_items(g.items, on_pick)
        ig.EndMenu(ctx)
      end
    end
    ig.EndMenu(ctx)
  end
end

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

---------------------------------------------------------------- system stats (status bar)

-- REAPER has no script function for its Performance Meter, so CPU and memory
-- come from the operating system (macOS and Linux). Latency is reported by REAPER.
-- On macOS the numbers are fetched in the background and read back from a
-- small file, so the panel never waits for them.
STATS = {
  kind = nil, pid = nil, ncpu = 1, memtotal = nil,
  cpu = nil, ram_pct = nil, ram_mb = nil,
  seq = -1, launch_n = 0, launch_t = -math.huge, sample_t = {},
  prev_cpu = nil, prev_t = nil,
  latency = nil, latency_tip = nil, lat_t = -math.huge,
}

function init_stats()
  local osn = reaper.GetOS() or ''
  if osn:find('OSX') or osn:find('mac') then
    local ok, out = pcall(reaper.ExecProcess,
      '/bin/sh -c "echo $PPID; sysctl -n hw.memsize; sysctl -n hw.ncpu"', 3000)
    if ok and out then
      local nums = {}
      for n in out:gmatch('%d+') do nums[#nums + 1] = tonumber(n) end
      if #nums >= 4 then
        STATS.kind, STATS.pid, STATS.memtotal, STATS.ncpu = 'mac', nums[2], nums[3], math.max(1, nums[4])
      end
    end
  elseif osn:find('Linux') then
    local f = io.open('/proc/meminfo', 'r')
    if f then
      local kb = f:read('*a'):match('MemTotal:%s+(%d+)')
      f:close()
      STATS.memtotal = kb and tonumber(kb) * 1024 or nil
    end
    local n = 0
    f = io.open('/proc/cpuinfo', 'r')
    if f then
      for line in f:lines() do if line:match('^processor') then n = n + 1 end end
      f:close()
    end
    STATS.ncpu = math.max(1, n)
    STATS.kind = 'linux'
  end
end

function update_stats(cpu_secs, rss_kb, t)
  if STATS.prev_t and t - STATS.prev_t > 0.2 then
    local pct = (cpu_secs - STATS.prev_cpu) / (t - STATS.prev_t) / STATS.ncpu * 100
    STATS.cpu = clamp(pct, 0, 100)
  end
  STATS.prev_cpu, STATS.prev_t = cpu_secs, t
  STATS.ram_mb = rss_kb / 1024
  if STATS.memtotal then
    STATS.ram_pct = clamp(rss_kb * 1024 / STATS.memtotal * 100, 0, 100)
  end
end

function poll_latency(now)
  if now - STATS.lat_t < STATS_EVERY then return end
  STATS.lat_t = now
  local ok, inl, outl = pcall(reaper.GetInputOutputLatency)
  local ok2, _, sr = pcall(reaper.GetAudioDeviceInfo, 'SRATE', '')
  local ok3, _, bs = pcall(reaper.GetAudioDeviceInfo, 'BSIZE', '')
  sr = ok2 and tonumber(sr) or nil
  bs = ok3 and tonumber(bs) or nil
  if ok and inl and outl and sr and sr > 0 then
    STATS.lat_in  = math.floor(inl / sr * 1000 + 0.5)
    STATS.lat_out = math.floor(outl / sr * 1000 + 0.5)
    STATS.latency_tip = ('Input / output latency reported by REAPER%s'):format(
      (bs and sr) and ('\n%d samples at %d Hz'):format(bs, sr) or '')
  else
    STATS.lat_in, STATS.lat_out, STATS.latency_tip = nil, nil, nil
  end
end

function poll_stats(now)
  poll_latency(now)
  if STATS.kind == 'mac' then
    local f = io.open(STATS_FILE, 'r')
    if f then
      local line = f:read('*l')
      f:close()
      local seq, t, rss = (line or ''):match('^(%d+)%s+(%S+)%s+(%d+)')
      seq = tonumber(seq)
      if seq and seq ~= STATS.seq then
        STATS.seq = seq
        local secs = 0
        for p in t:gmatch('[^:]+') do secs = secs * 60 + (tonumber(p) or 0) end
        update_stats(secs, tonumber(rss), STATS.sample_t[seq] or now)
        STATS.sample_t[seq] = nil
      end
    end
    if now - STATS.launch_t >= STATS_EVERY then
      STATS.launch_t = now
      STATS.launch_n = STATS.launch_n + 1
      STATS.sample_t[STATS.launch_n] = now
      STATS.sample_t[STATS.launch_n - 20] = nil
      reaper.ExecProcess(('/bin/sh -c "echo %d $(ps -o time=,rss= -p %d) > %s.tmp; mv %s.tmp %s"')
        :format(STATS.launch_n, STATS.pid, STATS_FILE, STATS_FILE, STATS_FILE), -1)
    end
  elseif STATS.kind == 'linux' then
    if now - STATS.launch_t >= STATS_EVERY then
      STATS.launch_t = now
      local f = io.open('/proc/self/stat', 'r')
      local g = io.open('/proc/self/statm', 'r')
      if f and g then
        local s = f:read('*l') or ''
        local rest = s:match('%) (.*)$') or ''
        local tk = {}
        for w in rest:gmatch('%S+') do tk[#tk + 1] = w end
        local secs = ((tonumber(tk[12]) or 0) + (tonumber(tk[13]) or 0)) / 100
        local pages = tonumber((g:read('*l') or ''):match('^%d+%s+(%d+)')) or 0
        update_stats(secs, pages * 4, now)
      end
      if f then f:close() end
      if g then g:close() end
    end
  end
end

---------------------------------------------------------------- text boxes

-- Returns the new text only when the user commits (Enter or click away).
function text_edit(key, current, width)
  local st = edit_state[key]
  if not st then st = { text = current, active = false }; edit_state[key] = st end

  -- one blank frame makes ImGui drop the active text box (used after a reset)
  if st.skip then
    st.skip = false
    st.active = false
    ig.Dummy(ctx, width, ig.GetFrameHeight(ctx))
    return nil
  end

  local shown = st.active and st.text or current
  ig.SetNextItemWidth(ctx, width)
  local rv, new = ig.InputText(ctx, '##' .. key, shown, ig.InputTextFlags_AutoSelectAll())
  if rv then st.text = new end
  local active = ig.IsItemActive(ctx)
  if active and not st.active then st.text = shown end
  local committed = nil
  if ig.IsItemDeactivatedAfterEdit(ctx) then committed = new end
  st.active = active
  return committed
end

function parse_db(s)
  s = s:lower():gsub(',', '.')
  if s:find('inf') then return -math.huge end
  return tonumber(s:match('[-+]?%d*%.?%d+'))
end

function apply_level(tr, text)
  local v = parse_db(text)
  if not v then return end
  if v <= LEVEL_MIN then
    reaper.SetMediaTrackInfo_Value(tr, 'D_VOL', 0.0)
  else
    reaper.SetMediaTrackInfo_Value(tr, 'D_VOL', 10.0 ^ (clamp(v, LEVEL_MIN, LEVEL_MAX) / 20.0))
  end
end

function rename_rack(tr, text)
  text = text:match('^%s*(.-)%s*$')
  if text == raw_name(tr) then return end
  reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', (text == '') and PREFIX or (PREFIX .. ' ' .. text), true)
end

---------------------------------------------------------------- meters

function new_meter_state()
  return {
    lv_in    = { -150, -150 }, lv_out   = { -150, -150 },
    hold_in  = { -150, -150 }, hold_out = { -150, -150 },
    clip_in  = { false, false }, clip_out = { false, false },
    cnt = -1, stale = 0,
  }
end

-- one click on any meter resets every peak hold line and clip marker
function reset_markers()
  for _, m in pairs(meters) do
    m.hold_in  = { -150, -150 }; m.hold_out = { -150, -150 }
    m.clip_in  = { false, false }; m.clip_out = { false, false }
  end
end

function mark(hold, clip, i, db)
  if db > hold[i] then hold[i] = db end
  if db >= CLIP_DB then clip[i] = true end
end

-- reads (and clears) one stage of one rack from gmem
function read_stage(base)
  local pl  = reaper.gmem_read(base)
  local pr  = reaper.gmem_read(base + 1)
  local cnt = reaper.gmem_read(base + 2)
  local sl  = reaper.gmem_read(base + 3)
  local sr  = reaper.gmem_read(base + 4)
  local n   = reaper.gmem_read(base + 5)
  reaper.gmem_write(base, 0)
  reaper.gmem_write(base + 1, 0)
  reaper.gmem_write(base + 3, 0)
  reaper.gmem_write(base + 4, 0)
  reaper.gmem_write(base + 5, 0)
  return pl, pr, cnt, sl, sr, n
end

function draw_bar(dl, x, y1, y2, w, level, hold, clipped)
  ig.DrawList_AddRectFilled(dl, x, y1, x + w, y2, T.meter_bg, 2)
  for _, z in ipairs(ZONES) do
    if level > z[1] then
      local top = math.min(level, z[2])
      local ya = y2 - meter_frac(top) * (y2 - y1)
      local yb = y2 - meter_frac(z[1]) * (y2 - y1)
      ig.DrawList_AddRectFilled(dl, x, ya, x + w, yb, z[3])
    end
  end
  if hold > METER_MIN then
    local yh = y2 - meter_frac(hold) * (y2 - y1)
    ig.DrawList_AddLine(dl, x, yh, x + w, yh, clipped and 0xFF4040FF or T.hold, 2)
  end
end

function draw_meter(dl, x, y1, y2, lv, hold, clip, id, mono)
  local by1 = y1 + CLIP_H + 2
  if mono then
    -- mono rack: one bar (both channels carry the same signal)
    ig.DrawList_AddRectFilled(dl, x, y1, x + METER_W, y1 + CLIP_H,
                              (clip[1] or clip[2]) and 0xFF2020FF or T.clip_off, 2)
    draw_bar(dl, x, by1, y2, METER_W, math.max(lv[1], lv[2]), math.max(hold[1], hold[2]), clip[1] or clip[2])
  else
    local bw = (METER_W - 2) / 2
    ig.DrawList_AddRectFilled(dl, x, y1, x + bw, y1 + CLIP_H,
                              clip[1] and 0xFF2020FF or T.clip_off, 2)
    ig.DrawList_AddRectFilled(dl, x + bw + 2, y1, x + METER_W, y1 + CLIP_H,
                              clip[2] and 0xFF2020FF or T.clip_off, 2)
    draw_bar(dl, x, by1, y2, bw, lv[1], hold[1], clip[1])
    draw_bar(dl, x + bw + 2, by1, y2, bw, lv[2], hold[2], clip[2])
  end

  ig.SetCursorScreenPos(ctx, x, y1)
  if ig.InvisibleButton(ctx, id, METER_W, y2 - y1) then reset_markers() end
  if ig.IsItemHovered(ctx) then
    ig.SetTooltip(ctx, 'Click to reset peak hold and clip markers (all racks)')
  end
end

---------------------------------------------------------------- audio device notes

-- Top of the input/output menus: which device REAPER uses and how many channels
-- it offers. Returns the channel count; when it is 0 the menu says why instead
-- of showing empty lists (device not running, closed, or channels disabled).
function audio_device_header(is_out)
  local n = is_out and reaper.GetNumAudioOutputs() or reaper.GetNumAudioInputs()
  local running = (not reaper.Audio_IsRunning) or reaper.Audio_IsRunning() ~= 0
  local ok, dev = reaper.GetAudioDeviceInfo(is_out and 'IDENT_OUT' or 'IDENT_IN')
  if not ok or not dev or dev == '' then dev = 'unknown device' end
  if running and n > 0 then
    ig.TextDisabled(ctx, ('%s  -  %d %s'):format(dev, n, is_out and 'outputs' or 'inputs'))
  else
    ig.PushStyleColor(ctx, ig.Col_Text(), ALERT_RED)
    if not running then
      ig.Text(ctx, 'The audio device is not running.')
    else
      ig.Text(ctx, ('%s reports no %s.'):format(dev, is_out and 'outputs' or 'inputs'))
    end
    ig.PopStyleColor(ctx)
    ig.TextDisabled(ctx, 'Check REAPER Preferences > Audio > Device: the device,\n'
                      .. 'its ' .. (is_out and 'output' or 'input') .. ' channel range, and that it is not in use elsewhere.')
    if ig.MenuItem(ctx, 'Open REAPER Preferences...') then reaper.Main_OnCommand(40016, 0) end
  end
  ig.Separator(ctx)
  return (running and n) or 0
end

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
        width_dots(dl, (x1 + x2) / 2, y + fh / 2, kind, true, T.dots, c.sec_bg, dot_r)
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
      ig.SetTooltip(ctx, 'Latency: ' .. samples_text(fx_lat)
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
            function() replace_fx(tr, fx_guid, item.ident) end, 'Replace')
        end)
        ig.EndMenu(ctx)
      end
      if ig.MenuItem(ctx, 'Delete FX...') then
        request_confirm(('Delete "%s" from this rack?'):format(clean_fx_name(it.name)),
          function() delete_fx(tr, fx_guid) end, 'Delete')
      end
      ig.Separator(ctx)
      local fl = lat.fx[fx_guid] or 0
      if ig.MenuItem(ctx, 'Allow latency' .. (fl > 0 and ('  (%d smp)'):format(fl) or ''), nil, lat.allowed[fx_guid] == true) then
        set_latency_allowed(tr, fx_guid, not lat.allowed[fx_guid])
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
        lines[#lines + 1] = ('  %s: %d smp%s'):format(clean_fx_name(it.name), n, tag)
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
        -- the whole rack is over its limit: its frame flashes red (drawn first, the tag goes on top)
        ig.DrawList_AddRect(dl, x0 - 1, y0 - 1, x0 + RACK_W + 1, y0 + H + 1, ALERT_RED, ROUNDING + 3, 0, 3)
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
          names[#names + 1] = ('  %s: %d smp%s'):format(clean_fx_name(it.name), n, lat.fx_over[g] and '  (over the FX limit)' or '')
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

---------------------------------------------------------------- top bar menus

function toggle_setting(label, field, key, tip, enabled)
  local clicked = ig.MenuItem(ctx, label, nil, S[field], enabled ~= false)
  if clicked then
    S[field] = not S[field]
    save_setting(key, S[field] and '1' or '0')
  end
  if tip and ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, tip) end
  return clicked
end

function open_settings_at(group)
  S.show_settings = true
  S.settings_focus = group
end

function draw_display_menu()
  toggle_setting('Daylight mode', 'daylight', 'daylight')
  ig.TextDisabled(ctx, 'Rack latency box')
  for _, o in ipairs({ { 'off', 'Off' }, { 'always', 'Always' }, { 'auto', 'Only when a rack has latency' } }) do
    if ig.MenuItem(ctx, '   ' .. o[2] .. '##latbox', nil, S.lat_box == o[1]) then
      S.lat_box = o[1]
      save_setting('latbox', o[1])
    end
  end
  ig.Separator(ctx)
  if ig.MenuItem(ctx, 'Recolor every rack', nil, false, not is_locked()) then recolor_every_rack() end
  if ig.MenuItem(ctx, 'Choose default color...') then open_picker('default') end
  if ig.MenuItem(ctx, 'New racks use automatic color', nil, S.color_mode == 'auto') then
    S.color_mode = 'auto'; save_setting('colormode', 'auto')
  end
  if ig.MenuItem(ctx, 'New racks use default color', nil, S.color_mode == 'default') then
    S.color_mode = 'default'; save_setting('colormode', 'default')
  end
  ig.Separator(ctx)
  if ig.BeginMenu(ctx, 'Dock') then
    if ig.MenuItem(ctx, 'Floating') then dock_request = 0 end
    ig.Separator(ctx)
    for n = 1, 16 do
      if ig.MenuItem(ctx, 'Docker ' .. n) then dock_request = -n end
    end
    ig.EndMenu(ctx)
  end
end

function draw_fx_menu()
  -- FX types that actually exist, with how many FX each has
  if ig.BeginMenu(ctx, 'FX types') then
    if not fx_db then fx_db = build_fx_db() end
    for _, g in ipairs(fx_db.types) do
      ig.PushStyleColor(ctx, ig.Col_Text(), type_color(g.name))
      local c = ig.MenuItem(ctx, ('%s (%d)'):format(g.name, #g.items), nil, not S.hidden[g.name])
      ig.PopStyleColor(ctx)
      if c then
        if S.hidden[g.name] then S.hidden[g.name] = nil else S.hidden[g.name] = true end
        save_hidden()
      end
    end
    ig.Separator(ctx)
    if ig.MenuItem(ctx, 'All') then
      S.hidden = {}
      save_hidden()
    end
    if ig.MenuItem(ctx, 'None') then
      S.hidden = {}
      for _, g in ipairs(fx_db.types) do S.hidden[g.name] = true end
      save_hidden()
    end
    ig.EndMenu(ctx)
  end
  if ig.MenuItem(ctx, 'FX type colors...') then open_settings_at('FX type colors') end
  ig.Separator(ctx)
  if ig.MenuItem(ctx, 'Plugin list...') then LATWIN.open = true end
  if ig.IsItemHovered(ctx) then
    ig.SetTooltip(ctx, 'Every installed FX: favorites, type, latency, scan status.\nRescan one FX or a selection.')
  end
  ig.Separator(ctx)
  toggle_setting('Hide FX over the latency limit', 'hide_over', 'hideover',
    'Leaves out of the FX menus every FX whose known latency is over the per-FX limit\n(not the ones marked "Allow latency"). Follows the limit when it changes.')
  toggle_setting('Take FX over the limit offline in Show mode', 'show_off', 'showoff',
    'Switching to Show takes offline every FX over the per-FX limit, then the FX adding\nthe most latency until each rack is under the per-rack limit.\nBack to Edit brings them back online.')
end

function draw_latency_menu()
  local la, left = alerts_state()
  toggle_setting('Latency alerts', 'lat_alerts', 'latalerts')
  if la == 'silenced' then
    if ig.MenuItem(ctx, ('Resume latency alerts (%d min left)'):format(math.ceil(left / 60))) then silence_alerts(nil) end
  elseif ig.MenuItem(ctx, ('Silence latency alerts for %d min'):format(CFG.lat_silence), nil, false, S.lat_alerts) then
    silence_alerts(CFG.lat_silence)
  end
  if ig.MenuItem(ctx, ('Latency limits...   (FX %d / rack %d smp)'):format(LAT_LIMIT, LAT_RACK_LIMIT)) then
    open_settings_at('Latency')
  end
  ig.Separator(ctx)
  local can = not SCAN.active and S.mode == 'edit'
  if ig.MenuItem(ctx, 'Scan new FX for latency...', nil, false, can) then ask_scan('new') end
  if ig.MenuItem(ctx, 'Rescan all FX for latency...', nil, false, can) then ask_scan('all') end
  if ig.MenuItem(ctx, 'Retry failed FX...', nil, false, can) then ask_scan('failed') end
  if ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, 'FX that could not load or stopped REAPER during a scan.\nRescan all leaves them out.') end
  toggle_setting('Ask to scan new FX', 'ask_scan', 'askscan')
end

function draw_options_menu()
  toggle_setting('Disconnect inputs/outputs on copy and template', 'disconnect', 'disconnect')
  -- troubleshooting: no meters, no Level match, and no meter JSFX in the racks
  if toggle_setting('Disable metering and Level match', 'no_meters', 'nometers') then
    last_scan = -math.huge          -- add or remove the meter JSFX right away
  end
  toggle_setting('Stereo pairs on odd-even channels only', 'odd_even', 'oddeven',
    'Like most consoles: stereo inputs and outputs start on an odd channel\n(1/2, 3/4, 5/6...). Also for sidechain keys.')
  ig.Separator(ctx)
  if ig.MenuItem(ctx, 'Open the FOH-Mate data folder') then open_data_folder() end
  if ig.IsItemHovered(ctx) then
    ig.SetTooltip(ctx, 'fx_latency.txt, favorites.txt, recent_fx.txt, last_scan_log.txt, last_error.txt\n' .. LATDB_DIR)
  end
  if ig.MenuItem(ctx, 'Settings...') then S.show_settings = true end
end

---------------------------------------------------------------- FX type colors

TYPE_COLOR_DEFAULTS = {
  { 'VST3', 0x5FB3F0 }, { 'VST', 0x6FD08A }, { 'CLAP', 0xF0A050 }, { 'AU', 0xC48FF0 },
  { 'JS', 0xE8D25A }, { 'LV2', 0x4FD0C8 }, { 'DX', 0xB0B0B0 }, { 'Other', 0x9A9A9A },
}

-- "VST3i" uses the VST3 color, and so on
function base_type(t)
  if not t then return 'Other' end
  if t ~= 'JS' and t:sub(-1) == 'i' then t = t:sub(1, -2) end
  for _, d in ipairs(TYPE_COLOR_DEFAULTS) do if d[1] == t then return t end end
  return 'Other'
end

function type_color(t)
  local rgb = CFG['col_' .. base_type(t)] or 0x9A9A9A
  local c = (rgb << 8) | 0xFF
  if S.daylight then c = mix(c, BLACK, 0.4) end       -- darker on the light theme
  return c
end

-- Draws text (one or more lines) with every FX type ("VST3:", "AUi:", "JS:"...) in
-- its type color. Words like "Latency:" are left alone. col: color for the rest.
function type_text(s, col)
  local function seg(txt, c, cont)
    if cont then ig.SameLine(ctx, 0, 0) end
    if c then ig.TextColored(ctx, c, txt) else ig.Text(ctx, txt) end
  end
  for line in (s .. '\n'):gmatch('(.-)\n') do
    local from, pos, cont = 1, 1, false
    while true do
      local a, b, t = line:find('%f[%w](%a%w*):', pos)
      if not a then break end
      if base_type(t) ~= 'Other' then
        if a > from then seg(line:sub(from, a - 1), col, cont); cont = true end
        seg(t .. ':', type_color(t), cont); cont = true
        from = b + 1
      end
      pos = b + 1
    end
    if from <= #line or not cont then seg(line:sub(from), col, cont) end
  end
end

---------------------------------------------------------------- windows keep their size

-- Every resizable window comes back at its last size: after being collapsed,
-- minimized, closed and reopened, or when REAPER starts again.
WINSZ = {}
FRAME = 0

function begin_window(id, title, def_w, def_h, p_open, flags)
  local st = WINSZ[id]
  if not st then
    local w, h = reaper.GetExtState(EXT_SECTION, 'win_' .. id):match('^(%d+)x(%d+)$')
    st = { w = tonumber(w) or def_w, h = tonumber(h) or def_h, last = -10 }
    WINSZ[id] = st
  end
  local back = st.last ~= FRAME - 1          -- not shown last frame: coming back
  if back then ig.SetNextWindowSize(ctx, st.w, st.h, ig.Cond_Always()) end
  local vis, open = ig.Begin(ctx, title, p_open, flags)
  if vis then
    st.last = FRAME
    if ig.IsWindowFocused(ctx, ig.FocusedFlags_RootAndChildWindows()) then st.focused = FRAME end
    if not back and not ig.IsWindowDocked(ctx) then
      local w, h = ig.GetWindowSize(ctx)
      if w >= 120 and h >= 80 and (math.abs(w - st.w) > 0.5 or math.abs(h - st.h) > 0.5) then
        st.w, st.h, st.dirty = w, h, true
      end
      if st.dirty and not ig.IsMouseDown(ctx, 0) then
        reaper.SetExtState(EXT_SECTION, 'win_' .. id, ('%dx%d'):format(st.w, st.h), true)
        st.dirty = false
      end
    end
  end
  return vis, open
end

---------------------------------------------------------------- FX menu items

-- an FX in a menu: name, its latency in red when it has some, its type in the type's color
function fx_menu_item(it)
  local e = latdb_get(it.name)
  local lat = (e and e.src ~= 'failed') and (e.lat or 0) or 0
  local lat_txt = lat > 0 and ('%d smp'):format(lat) or nil
  local label = it.label or it.name
  local pad = ''
  if lat_txt then
    -- (only the width: CalcTextSize can return more than one value)
    local sw = ig.CalcTextSize(ctx, ' ') or 4
    local lw = ig.CalcTextSize(ctx, lat_txt) or 0
    pad = string.rep(' ', math.ceil(lw / math.max(1, sw)) + 2)
  end
  local cx, cy = ig.GetCursorScreenPos(ctx)
  ig.PushStyleColor(ctx, ig.Col_TextDisabled(), type_color(it.type))
  local clicked = ig.MenuItem(ctx, label .. pad .. '##' .. (it.ident or it.name), it.type)
  ig.PopStyleColor(ctx)
  if lat_txt then
    local spx = ig.GetStyleVar(ctx, ig.StyleVar_ItemSpacing())
    local x = cx + (spx or 8) * 0.5 + (ig.CalcTextSize(ctx, label) or 0) + (ig.CalcTextSize(ctx, '  ') or 0)
    ig.DrawList_AddText(ig.GetWindowDrawList(ctx), x, cy, ALERT_RED, lat_txt)
  end
  if ig.IsItemHovered(ctx) and e and e.allowed and lat > 0 then
    ig.SetTooltip(ctx, ('Latency: %s (allowed)'):format(samples_text(lat)))
  end
  return clicked
end

---------------------------------------------------------------- FX search

SEARCH = { text = '', query = '', t = 0, cache_key = nil, results = {} }
SEARCH_MAX = 80

-- every word typed must appear in the name (any order, any case)
function search_fx(query)
  local view = get_view()
  local key = query .. '|' .. tostring(fx_view_key)
  if SEARCH.cache_key == key then return SEARCH.results end
  local words = {}
  for w in query:lower():gmatch('%S+') do words[#words + 1] = w end
  local res, seen = {}, {}
  local q = query:lower():match('^%s*(.-)%s*$')
  for _, g in ipairs(view.types) do
    for _, it in ipairs(g.items) do
      local low = it.name:lower()
      local ok = true
      for _, w in ipairs(words) do
        if not low:find(w, 1, true) then ok = false; break end
      end
      if ok and not seen[it.name] then
        seen[it.name] = true
        res[#res + 1] = { it = it, starts = (it.label or ''):lower():sub(1, #q) == q }
      end
    end
  end
  table.sort(res, function(a, b)
    if a.starts ~= b.starts then return a.starts end
    local la, lb = (a.it.label or a.it.name):lower(), (b.it.label or b.it.name):lower()
    if la ~= lb then return la < lb end
    return type_rank(a.it.type) < type_rank(b.it.type)
  end)
  local out = {}
  for i, r in ipairs(res) do out[i] = r.it end
  SEARCH.cache_key, SEARCH.results = key, out
  return out
end

-- search field at the top of every FX menu; results replace the menu 0.5 s
-- after the last keystroke (Enter picks the first result right away)
function draw_fx_search(on_pick)
  if ig.IsWindowAppearing(ctx) then
    SEARCH.text, SEARCH.query, SEARCH.cache_key = '', '', nil
    ig.SetKeyboardFocusHere(ctx)
  end
  ig.SetNextItemWidth(ctx, 280)
  local rv, t = ig.InputTextWithHint(ctx, '##fxsearch', 'Search FX...', SEARCH.text)
  if rv then SEARCH.text = t; SEARCH.t = reaper.time_precise() end
  local enter = ig.IsItemDeactivated(ctx) and (ig.IsKeyPressed(ctx, ig.Key_Enter()) or ig.IsKeyPressed(ctx, ig.Key_KeypadEnter()))
  if enter then SEARCH.query = SEARCH.text end
  if SEARCH.text ~= SEARCH.query and reaper.time_precise() - SEARCH.t >= 0.5 then SEARCH.query = SEARCH.text end
  if not SEARCH.query:match('%S') then return false end

  ig.Separator(ctx)
  local res = search_fx(SEARCH.query)
  if #res == 0 then ig.TextDisabled(ctx, 'No FX found') end
  for i = 1, math.min(#res, SEARCH_MAX) do
    if fx_menu_item(res[i]) then on_pick(res[i]) end
  end
  if #res > SEARCH_MAX then ig.TextDisabled(ctx, ('... %d more, keep typing'):format(#res - SEARCH_MAX)) end
  if enter and res[1] then
    on_pick(res[1])
    ig.CloseCurrentPopup(ctx)
  end
  return true
end

---------------------------------------------------------------- window

-- carries out the drag and drop requests collected while drawing
function apply_pending()
  if #pending_ops > 0 then
    local ops = pending_ops
    pending_ops = {}
    with_undo('Rack: move/copy FX', function()
      for _, op in ipairs(ops) do
        local g, s = op.payload:match('^(.-)|(%d+)$')
        local src_tr = g and rack_by_guid(g)
        local src = tonumber(s)
        if src_tr and src and valid(op.dst_tr) then
          local moved_guid = reaper.TrackFX_GetFXGUID(src_tr, src)
          local landed
          if src_tr == op.dst_tr then
            if has_mod(COPY_MOD) then
              reaper.TrackFX_CopyToTrack(src_tr, src, op.dst_tr, op.dst, false)
              landed = reaper.TrackFX_GetFXGUID(op.dst_tr, op.dst)
            else
              move_fx(src_tr, src, op.dst)
              landed = moved_guid
            end
          elseif has_mod(MOVE_MOD) then
            reaper.TrackFX_CopyToTrack(src_tr, src, op.dst_tr, op.dst, true)
            landed = reaper.TrackFX_GetFXGUID(op.dst_tr, op.dst)
          else
            reaper.TrackFX_CopyToTrack(src_tr, src, op.dst_tr, op.dst, false)
            landed = reaper.TrackFX_GetFXGUID(op.dst_tr, op.dst)
          end
          -- the FX takes the width of its new place (mono/stereo version)
          if landed then fit_new_fx(op.dst_tr, landed) end
        end
      end
    end)
  end

  if #pending_racks > 0 then
    local rr = pending_racks
    pending_racks = {}
    for _, r in ipairs(rr) do
      local src = rack_by_guid(r.src)
      if src and valid(r.dst) then
        if r.copy then
          -- duplicate, then put the copy where it was dropped (right after the original when dropped on itself)
          with_undo('Rack: duplicate by drag', function()
            local new = duplicate_rack(src)
            if new and r.dst ~= src then reorder_rack(new, r.dst) end
          end)
        else
          reorder_rack(src, r.dst)
        end
      end
    end
  end
end

-- the color picker and the confirmation dialog
function draw_dialogs()
  if picker.open then
    ig.OpenPopup(ctx, 'Color##picker')
    picker.open = false
  end
  if ig.BeginPopup(ctx, 'Color##picker') then
    if picker.kind == 'default' then
      ig.Text(ctx, 'Default rack color')
    elseif picker.trs and #picker.trs > 1 then
      ig.Text(ctx, ('Color for the %d selected racks'):format(#picker.trs))
    else
      ig.Text(ctx, 'Rack color')
    end
    local rv, new = ig.ColorPicker3(ctx, '##cp', picker.rgb)
    if rv then
      picker.rgb = new
      local r, g, b = (new >> 16) & 255, (new >> 8) & 255, new & 255
      if picker.kind == 'rack' then
        for _, t in ipairs(picker.trs or {}) do
          if valid(t) then set_track_rgb(t, r, g, b) end
        end
      else
        S.default_rgb = new
        save_setting('defcolor', new)
      end
    end
    if ig.Button(ctx, 'Close', 80, 0) then ig.CloseCurrentPopup(ctx) end
    ig.EndPopup(ctx)
  end

  local wx, wy = ig.GetWindowPos(ctx)
  local ww, wh = ig.GetWindowSize(ctx)
  MAIN_CENTER, MAIN_DOCKED = { wx + ww / 2, wy + wh / 2 }, ig.IsWindowDocked(ctx)
  draw_confirm('main')
end

-- the "Please confirm" box, drawn inside the window that asked for it (host)
function draw_confirm(host)
  if confirm and confirm.host == host then
    if confirm_open then
      ig.OpenPopup(ctx, 'Please confirm')
      confirm_open = false
    end
    local cx, cy
    if confirm.over_main and MAIN_CENTER then
      cx, cy = MAIN_CENTER[1], MAIN_CENTER[2]
    else
      local wx, wy = ig.GetWindowPos(ctx)
      local ww, wh = ig.GetWindowSize(ctx)
      cx, cy = wx + ww / 2, wy + wh / 2
    end
    ig.SetNextWindowPos(ctx, cx, cy, ig.Cond_Appearing(), 0.5, 0.5)
    local shown = ig.BeginPopupModal(ctx, 'Please confirm', nil, ig.WindowFlags_AlwaysAutoResize())
    if shown then
      type_text(confirm.text)
      ig.Separator(ctx)
      local yes = ig.Button(ctx, confirm.label, 110, 0)
      ig.SameLine(ctx)
      local no = ig.Button(ctx, 'Cancel', 110, 0)
      if yes then
        local f = confirm.yes
        confirm = nil
        ig.CloseCurrentPopup(ctx)
        later[#later + 1] = function() f(); last_scan = -math.huge end   -- after the frame
      elseif no then
        confirm = nil
        ig.CloseCurrentPopup(ctx)
      end
      ig.EndPopup(ctx)
    elseif not confirm_open then
      confirm = nil      -- closed some other way (Escape): treat as Cancel
    end
  end
end

-- a horizontal gauge with a label on it; frac = nil means "not available"
function draw_gauge(dl, id, x, y, w, h, frac, label, tip)
  ig.DrawList_AddRectFilled(dl, x, y, x + w, y + h, T.meter_bg, ROUNDING)
  if frac and frac > 0 then
    local col = (frac < 0.6) and 0x40C060FF or ((frac < 0.85) and 0xE0C040FF or 0xE04040FF)
    ig.DrawList_AddRectFilled(dl, x, y, x + math.max(2, w * frac), y + h, col, ROUNDING)
  end
  ig.DrawList_AddRect(dl, x, y, x + w, y + h, T.bar_border, ROUNDING, 0, 1)
  local tw = ig.CalcTextSize(ctx, label)
  local lh = ig.GetTextLineHeight(ctx)
  ig.DrawList_AddText(dl, x + (w - tw) / 2, y + (h - lh) / 2, T.gauge_text, label)
  ig.SetCursorScreenPos(ctx, x, y)
  ig.InvisibleButton(ctx, id, w, h)
  if ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, tip) end
end

-- status bar: same size, border and color as the top bar
function draw_status_bar(dl, x, y, w, h, M, nracks, nfx)
  ig.DrawList_AddRect(dl, x, y, x + w, y + h, T.bar_border, ROUNDING, 0, 1)
  local gw = 140
  local gy = y + (h - M.fh) / 2
  local gx = x + 8

  local cpu_label = STATS.cpu and ('CPU %d%%'):format(math.floor(STATS.cpu + 0.5)) or 'CPU n/a'
  draw_gauge(dl, 'g_cpu', gx, gy, gw, M.fh, STATS.cpu and STATS.cpu / 100 or nil, cpu_label,
    STATS.cpu and 'REAPER process CPU, as a share of all cores'
              or 'Not available on this system')
  gx = gx + gw + 10

  local ram_label = STATS.ram_pct and ('RAM %d%%'):format(math.floor(STATS.ram_pct + 0.5)) or 'RAM n/a'
  local ram_tip = 'Not available on this system'
  if STATS.ram_mb then
    ram_tip = ('REAPER memory: %d MB'):format(math.floor(STATS.ram_mb + 0.5))
    if STATS.memtotal then ram_tip = ram_tip .. ('\nof %.1f GB installed'):format(STATS.memtotal / 1073741824) end
  end
  draw_gauge(dl, 'g_ram', gx, gy, gw, M.fh, STATS.ram_pct and STATS.ram_pct / 100 or nil, ram_label, ram_tip)
  gx = gx + gw + 14

  -- latency: "Latency: in [33] ms  -  out [11] ms", the numbers in gauge-style boxes
  local ty = y + (h - M.tlh) / 2
  local function label(s)
    ig.SetCursorScreenPos(ctx, gx, ty)
    ig.Text(ctx, s)
    gx = gx + ig.CalcTextSize(ctx, s) + 6
  end
  if STATS.lat_in and STATS.lat_out then
    local bw = ig.CalcTextSize(ctx, '0000') + 16
    label('Latency: in')
    draw_gauge(dl, 'g_lat_in', gx, gy, bw, M.fh, nil, ('%i'):format(STATS.lat_in), STATS.latency_tip)
    gx = gx + bw + 6
    label('ms  -  out')
    draw_gauge(dl, 'g_lat_out', gx, gy, bw, M.fh, nil, ('%i'):format(STATS.lat_out), STATS.latency_tip)
    gx = gx + bw + 6
    label('ms')
  else
    label('Latency: n/a')
  end

  -- latency watchdog
  gx = gx + 10
  local la, left = alerts_state()
  local wtxt, wcol
  if la == 'on' and lat_over_racks > 0 then
    if flash_on(reaper.time_precise()) then
      wtxt, wcol = ('!! %d rack(s) over the latency limit'):format(lat_over_racks), ALERT_RED
    else
      wtxt = ''
    end
  elseif la == 'silenced' then
    wtxt = ('Latency alerts silenced (%d min)'):format(math.ceil(left / 60))
  elseif la == 'off' then
    wtxt = 'Latency alerts off'
  end
  local nowp = reaper.time_precise()
  if SCAN.last and nowp - SCAN.last_t < 8 then
    wtxt, wcol = SCAN.last, nil
  elseif SHOWOFF_MSG and nowp - SHOWOFF_MSG.t < 8 then
    wtxt, wcol = SHOWOFF_MSG.text, nil
  end
  local ww = 0
  if wtxt then
    local full = ('!! %d rack(s) over the latency limit'):format(math.max(lat_over_racks, 1))
    ww = math.max(ig.CalcTextSize(ctx, wtxt), la == 'on' and ig.CalcTextSize(ctx, full) or 0)
    if wtxt ~= '' then
      if wcol then
        ig.DrawList_AddText(dl, gx, ty, wcol, wtxt)
      else
        ig.SetCursorScreenPos(ctx, gx, ty)
        ig.TextDisabled(ctx, wtxt)
      end
    end
    if mouse_in(gx, y, gx + ww, y + h) then
      ig.SetTooltip(ctx, ('Latency limit: %d samples (Options > Settings...)\nSilence or switch alerts off in the Options menu.'):format(LAT_LIMIT))
    end
    gx = gx + ww
  end

  -- rack and FX counts, bottom right
  local counts = ('%d rack(s)  |  %d FX'):format(nracks or 0, nfx or 0)
  local cw = ig.CalcTextSize(ctx, counts)
  local cx = x + w - cw - 10
  if cx > gx + 12 then
    ig.SetCursorScreenPos(ctx, cx, ty)
    ig.TextDisabled(ctx, counts)
  end
end

-- the scrolling part: every rack, tiled
function draw_rack_area(infos, M, dt, now, avail)
  local x_left, y_top = ig.GetCursorScreenPos(ctx)
  local limit = x_left + avail                       -- the scrollbar starts here
  local wx, y = x_left + GLOW_M, y_top + GLOW_M      -- room around the racks for the selection glow
  local rects = {}
  local grid_x, last_row_y, last_row_h, grid_cols_n = wx, y, 0, 1

  if #infos == 0 then
    ig.SetCursorScreenPos(ctx, wx, y)
    ig.Text(ctx, ('No tracks named "%s ..." found. Double-click here or use + to create a rack.'):format(PREFIX))
  else
    -- each row is as tall as its tallest rack
    local cols = math.max(1, math.floor((avail - 2 * GLOW_M + RACK_SPACE) / (RACK_W + RACK_SPACE)))
    local i = 1
    while i <= #infos do
      local row_h = 0
      for c = 0, cols - 1 do
        local inf = infos[i + c]
        if inf then row_h = math.max(row_h, inf.nat) end
      end
      -- the grid is centered as a whole: every row starts at the same left edge,
      -- so a shorter last row stays aligned with the row above it
      local grid_cols = math.min(cols, #infos)
      local grid_w = grid_cols * RACK_W + (grid_cols - 1) * RACK_SPACE
      local row_x = math.max(wx, x_left + math.floor((avail - grid_w) / 2))
      grid_x, last_row_y, last_row_h, grid_cols_n = row_x, y, row_h, cols
      for c = 0, cols - 1 do
        local inf = infos[i + c]
        if inf then
          local x = row_x + c * (RACK_W + RACK_SPACE)
          draw_rack(inf, x, y, row_h, M, dt, now)
          rects[#rects + 1] = { x, y, x + RACK_W, y + row_h }
        end
      end
      y = y + row_h + RACK_SPACE
      i = i + cols
    end
    y = y - RACK_SPACE
  end

  -- empty space: a click deselects the racks, a double-click offers a new rack
  if ig.IsWindowHovered(ctx) then
    local mx, my = ig.GetMousePos(ctx)
    local over_rack = false
    for _, r in ipairs(rects) do
      if mx >= r[1] and mx <= r[3] and my >= r[2] and my <= r[4] then over_rack = true; break end
    end
    if not over_rack and mx < limit then
      if ig.IsMouseClicked(ctx, 0) then deselect_racks() end
      if ig.IsMouseDoubleClicked(ctx, 0) and not is_locked() then
        request_confirm('Create a new rack?', create_rack, 'Create')
      end
    end
  end

  -- a rack dropped in the empty space around or below the racks goes to the last position
  if drag_prev_rack and not is_locked() and #infos > 0 then
    local last = infos[#infos].tr
    local src = rack_by_guid(drag_prev_rack)
    local area_x, area_y = ig.GetWindowPos(ctx)
    local _, area_h = ig.GetWindowSize(ctx)
    local mx, my = ig.GetMousePos(ctx)
    local in_area = mx >= area_x and mx < limit and my >= area_y and my <= area_y + area_h
    local over_rack = false
    for _, r in ipairs(rects) do
      if mx >= r[1] and mx <= r[3] and my >= r[2] and my <= r[4] then over_rack = true; break end
    end
    local copying = has_mod(COPY_MOD)
    if src and (src ~= last or copying) and in_area and not over_rack then
      -- show the free cell the rack would land in
      local used = (#infos - 1) % grid_cols_n + 1
      local sx, sy
      if used < grid_cols_n then
        sx, sy = grid_x + used * (RACK_W + RACK_SPACE), last_row_y
      else
        sx, sy = grid_x, last_row_y + last_row_h + RACK_SPACE
      end
      local gdl = ig.GetWindowDrawList(ctx)
      ig.DrawList_AddRectFilled(gdl, sx, sy, sx + RACK_W, sy + last_row_h, (T.glow & 0xFFFFFF00) | 0x28, ROUNDING + 2)
      ig.DrawList_AddRect(gdl, sx, sy, sx + RACK_W, sy + last_row_h, (T.glow & 0xFFFFFF00) | 0xC0, ROUNDING + 2, 0, 3)
      if ig.IsMouseReleased(ctx, 0) then
        pending_racks[#pending_racks + 1] = { src = drag_prev_rack, dst = last, copy = copying }
      end
    end
  end

  -- extend the scrollable area to the bottom of the last row
  ig.SetCursorScreenPos(ctx, wx, y)
  ig.Dummy(ctx, 1, GLOW_M + 2)
end

-- the grey help line: what the mouse can do with what is under it, or with what is being dragged
function draw_hint(dl, x, y, w)
  local copy, move = mod_label(COPY_MOD), mod_label(MOVE_MOD)
  if drag_prev_rack then
    if has_mod(COPY_MOD) then
      HINT = ('Duplicating the rack: drop it where the copy should go  \194\183  let go of %s to move it instead'):format(copy)
    else
      HINT = ('Moving the rack: drop it on another rack, or after the last one  \194\183  hold %s to duplicate it instead'):format(copy)
    end
  elseif drag_prev_fx then
    local src = drag_prev_fx:match('^(.-)|')
    local other = hover_prev_rack ~= nil and hover_prev_rack ~= src
    if other then
      if drag_copies() then
        HINT = ('Copying the FX to this rack: drop it on an FX or on empty space  \194\183  hold %s to move it here instead'):format(move)
      else
        HINT = ('Moving the FX to this rack  \194\183  let go of %s to copy it instead'):format(move)
      end
    elseif drag_copies() then
      HINT = ('Copying the FX: drop it where the copy should go  \194\183  let go of %s to move it instead'):format(copy)
    else
      HINT = ('Moving the FX: drop it on the FX whose place it takes  \194\183  hold %s to copy it  \194\183  drop on another rack: copy (%s: move)')
             :format(copy, move)
    end
  end
  local txt = HINT
  if not txt then
    txt = is_locked() and 'Show mode: level, mute, bypass and FX on/off work; everything else is locked'
                      or 'Point at anything to see what the mouse can do with it  \194\183  double-click empty space: new rack'
  end
  ig.DrawList_AddText(dl, x, y, ig.GetStyleColor(ctx, ig.Col_TextDisabled()), fit_text(txt, w))
end

-- BeginChild takes a number (child flags) in recent ReaImGui and a boolean
-- (border) in older ones; try the number first and remember what works.
child_old_api = false
function begin_child(id, w, h)
  if not child_old_api then
    local ok, vis = pcall(ig.BeginChild, ctx, id, w, h, 0, 0)
    if ok then return vis end
    child_old_api = true
  end
  return ig.BeginChild(ctx, id, w, h, false, 0)
end

function draw(dt, now)
  drag_prev_rack, drag_prev_fx = drag_now_rack, drag_now_fx
  drag_now_rack, drag_now_fx = nil, nil
  hover_prev_rack, hover_now_rack = hover_now_rack, nil
  lat_over_racks = 0
  HINT = nil

  local M  = metrics()
  local dl = ig.GetWindowDrawList(ctx)
  local padx, pady = ig.GetStyleVar(ctx, ig.StyleVar_WindowPadding())
  local sbw = ig.GetStyleVar(ctx, ig.StyleVar_ScrollbarSize())
  local ww, wh = ig.GetWindowSize(ctx)
  local win_x, win_y = ig.GetWindowPos(ctx)
  local wx, wy = ig.GetCursorScreenPos(ctx)
  local bar_w = ww - 2 * padx

  -- gather racks
  local infos, nfx = {}, 0
  for i, tr in ipairs(racks) do
    if valid(tr) then
      local info = chain_info(tr)
      info.tr = tr
      info.slot = i - 1
      info.bypassed = is_bypassed(tr, info.list)
      info.box = latbox_on(S.lat_box == 'auto' and rack_latency(tr, reaper.GetTrackGUID(tr), info.list, now).total or 0)
      info.nat = natural_height(#info.list, M, info.box)
      nfx = nfx + #info.list
      infos[#infos + 1] = info
    end
  end

  ------------------------------------------------ top bar (stays put): Plugins Host, centered | + Options
  local tb_h = math.max(M.fh + 8, title_font and (TITLE_FONT_SIZE + 12) or 0)   -- one row

  -- Layout: cue light on the left, + and the menus on the right, the title
  -- centered in the space between. When the window is too narrow, the title
  -- keeps the first row (centered right of the cue light) and the buttons wrap
  -- onto as many rows as needed below it, right-aligned.
  local cue_w = ig.CalcTextSize(ctx, 'SHOW') + 36
  local cue_x = wx + 6
  local function menu_button(label, id, pop)
    return { w = ig.CalcTextSize(ctx, label) + 2 * M.fpx + 10, label = label .. '##' .. id, pop = pop, text = label }
  end
  local buttons = {
    { w = M.fh, plus = true },
    menu_button('Display', 'm_disp', 'disp_pop'),
    menu_button('FX', 'm_fx', 'fx_pop'),
    menu_button('Latency', 'm_lat', 'lat_pop'),
    menu_button('Options', 'm_opt', 'opts_pop'),
  }

  local tpushed = push_bold(title_font, TITLE_FONT_SIZE)
  local ttw = ig.CalcTextSize(ctx, 'Plugins Host')
  local tlh = ig.GetTextLineHeight(ctx)
  if tpushed then ig.PopFont(ctx) end
  local vtxt = 'v' .. VERSION
  local vw = ig.CalcTextSize(ctx, vtxt)
  local title_w = ttw + 6 + vw

  local left, right = cue_x + cue_w + 12, wx + bar_w - 4
  local menus_w = -M.spx
  for _, bt in ipairs(buttons) do menus_w = menus_w + bt.w + M.spx end

  local rows, title_r
  if left + title_w + 24 + menus_w <= right then
    rows = { { items = buttons, w = menus_w, row = 1 } }          -- everything on one row
    title_r = right - menus_w - 12
  else
    rows = {}
    local cur = { items = {}, w = -M.spx, row = 2 }
    local avail = right - (wx + 4)
    for _, bt in ipairs(buttons) do
      if #cur.items > 0 and cur.w + M.spx + bt.w > avail then
        rows[#rows + 1] = cur
        cur = { items = {}, w = -M.spx, row = cur.row + 1 }
      end
      cur.items[#cur.items + 1] = bt
      cur.w = cur.w + M.spx + bt.w
    end
    rows[#rows + 1] = cur
    title_r = right
  end
  local top_h = tb_h * rows[#rows].row
  ig.DrawList_AddRect(dl, wx, wy, wx + bar_w, wy + top_h, T.bar_border, ROUNDING, 0, 1)

  -- title and version, centered in the free space of the first row
  local title_x = left + math.max(0, (title_r - left - title_w) / 2)
  local title_y = wy + (tb_h - tlh) / 2
  tpushed = push_bold(title_font, TITLE_FONT_SIZE)
  ig.DrawList_AddText(dl, title_x, title_y, T.title, 'Plugins Host')
  if tpushed then ig.PopFont(ctx) end
  -- the version, small, on the title's baseline
  ig.DrawList_AddText(dl, title_x + ttw + 6, title_y + tlh - M.tlh - 2, T.dim, vtxt)

  -- mode switch, like a cue light: green = Edit, red = Show
  local editing = S.mode == 'edit'
  local cue = editing and T.cue_edit or T.cue_show
  local cue_label = editing and 'EDIT' or 'SHOW'
  local cue_y = wy + (tb_h - M.fh) / 2
  local halo = cue & 0xFFFFFF00
  for i = 1, 4 do
    local a = math.floor(130 * (1 - (i - 1) / 4) ^ 2)
    ig.DrawList_AddRect(dl, cue_x - i, cue_y - i, cue_x + cue_w + i, cue_y + M.fh + i,
                        halo | a, ROUNDING + i, 0, 1)
  end
  ig.DrawList_AddRectFilled(dl, cue_x, cue_y, cue_x + cue_w, cue_y + M.fh, cue, ROUNDING)
  ig.DrawList_AddCircleFilled(dl, cue_x + 12, cue_y + M.fh / 2, 4, mix(cue, WHITE, 0.8), 0)
  local cue_tw = ig.CalcTextSize(ctx, cue_label)
  ig.DrawList_AddText(dl, cue_x + 22 + (cue_w - 22 - cue_tw) / 2, cue_y + (M.fh - M.tlh) / 2, WHITE, cue_label)
  ig.SetCursorScreenPos(ctx, cue_x, cue_y)
  if ig.InvisibleButton(ctx, 'mode_switch', cue_w, M.fh) then
    set_mode(editing and 'show' or 'edit')
  end
  hint_hovered(editing and 'Click: switch to Show mode (racks and FX locked; level, mute, bypass and FX on/off still work)'
                        or 'Click: switch to Edit mode (everything can be changed)')
  if ig.IsItemHovered(ctx) then
    ig.SetTooltip(ctx, editing
      and 'Edit mode: everything can be changed.\nClick to switch to Show mode.'
      or  'Show mode: racks and FX are locked.\nLevel, mute, bypass and FX on/off still work.\nClick to switch to Edit mode.')
  end

  -- a JSFX problem, if any, shows next to it
  if meter_error then
    local ex = cue_x + cue_w + 12
    ig.SetCursorScreenPos(ctx, ex, wy + (tb_h - M.tlh) / 2)
    ig.TextColored(ctx, 0xFF6060FF, fit_text(meter_error, math.max(40, title_x - ex - 8)))
  end

  -- top bar buttons: + | Display | FX | Latency | Options, placed by the layout above
  local la = alerts_state()
  for _, r in ipairs(rows) do
    local x = right - r.w
    local y = wy + (r.row - 1) * tb_h + (tb_h - M.fh) / 2
    for _, bt in ipairs(r.items) do
      ig.SetCursorScreenPos(ctx, x, y)
      if bt.plus then
        -- + : new rack (edit mode only)
        lock_begin(is_locked())
        ig.PushStyleVar(ctx, ig.StyleVar_FrameRounding(), M.fh / 2)
        if ig.Button(ctx, '+##newrack', M.fh, M.fh) then create_rack() end
        ig.PopStyleVar(ctx)
        if ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, 'New empty rack') end
        hint_hovered('Click: new empty rack')
        lock_end(is_locked())
      else
        -- the Latency button turns red while alerts are silenced or off, as a reminder
        local red = bt.pop == 'lat_pop' and la ~= 'on'
        if red then ig.PushStyleColor(ctx, ig.Col_Text(), ALERT_RED) end
        if ig.Button(ctx, bt.label, bt.w, M.fh) then ig.OpenPopup(ctx, bt.pop) end
        if red then ig.PopStyleColor(ctx) end
        if red and ig.IsItemHovered(ctx) then
          ig.SetTooltip(ctx, la == 'off' and 'Latency alerts are off' or 'Latency alerts are silenced')
        end
      end
      x = x + bt.w + M.spx
    end
  end

  if ig.BeginPopup(ctx, 'disp_pop') then draw_display_menu(); ig.EndPopup(ctx) end
  if ig.BeginPopup(ctx, 'fx_pop') then draw_fx_menu(); ig.EndPopup(ctx) end
  if ig.BeginPopup(ctx, 'lat_pop') then draw_latency_menu(); ig.EndPopup(ctx) end
  if ig.BeginPopup(ctx, 'opts_pop') then draw_options_menu(); ig.EndPopup(ctx) end

  ------------------------------------------------ racks (the only part that scrolls)
  local top = wy + top_h + RACK_SPACE
  local sb_y = win_y + wh - pady - tb_h               -- status bar top
  local hint_h = M.tlh + 4                            -- the help line, right above the status bar
  local child_h = math.max(40, sb_y - RACK_SPACE - hint_h - top)

  ig.SetCursorScreenPos(ctx, wx, top)
  if begin_child('racks', bar_w, child_h) then
    draw_rack_area(infos, M, dt, now, bar_w - sbw)
    ig.EndChild(ctx)
  end

  ------------------------------------------------ help line: what the mouse can do right now
  draw_hint(dl, wx + 6, top + child_h + (sb_y - top - child_h - M.tlh) / 2, bar_w - 12)

  ------------------------------------------------ status bar (stays put)
  draw_status_bar(dl, wx, sb_y, bar_w, tb_h, M, #infos, nfx)

  apply_pending()
  draw_dialogs()
  draw_copy_badge()
end

-- the settings window: edits SCHEMA values, saved as they change
function draw_settings()
  if not S.show_settings then return end
  local vis, open = begin_window('settings', 'FOH-Mate Settings', 440, 560, true)
  if vis then
    CONFIRM_HOST = 'settings'
    local group, group_open = nil, false
    for _, e in ipairs(SCHEMA) do
      if e.group ~= group then
        group = e.group
        if S.settings_focus == group then
          ig.SetNextItemOpen(ctx, true, ig.Cond_Always())
        end
        group_open = ig.CollapsingHeader(ctx, group, nil, (group == 'Colors') and ig.TreeNodeFlags_DefaultOpen() or 0)
        if S.settings_focus == group then
          ig.SetScrollHereY(ctx, 0)
          S.settings_focus = nil
        end
      end
      if group_open then
        ig.SetNextItemWidth(ctx, 210)
        local label = e.label .. '##cfg_' .. e.key
        if e.kind == 'color' then
          local typ = e.key:match('^col_(.+)$')
          local rv, v = ig.ColorEdit3(ctx, typ and ('##cfg_' .. e.key) or label, CFG[e.key],
                                      ig.ColorEditFlags_NoInputs())
          if typ then                     -- the type name in its own color (picker stays plain)
            ig.SameLine(ctx)
            ig.TextColored(ctx, type_color(typ), e.label)
          end
          if rv then
            CFG[e.key] = v
            save_cfg_value(e)
          end
        elseif e.kind == 'mod' then
          if ig.BeginCombo(ctx, label, CFG[e.key]) then
            for _, name in ipairs({ 'ctrl', 'shift', 'alt' }) do
              if ig.Selectable(ctx, name, CFG[e.key] == name) then
                CFG[e.key] = name
                save_cfg_value(e)
              end
            end
            ig.EndCombo(ctx)
          end
        else
          local rv, v
          if e.kind == 'i' then
            rv, v = ig.SliderInt(ctx, label, CFG[e.key], e.min, e.max, e.fmt)
          else
            rv, v = ig.SliderDouble(ctx, label, CFG[e.key], e.min, e.max, e.fmt)
          end
          if rv then CFG[e.key] = v end
          if ig.IsItemDeactivatedAfterEdit(ctx) then save_cfg_value(e) end
        end
        if e.tip and ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, e.tip) end
      end
    end
    ig.Separator(ctx)
    ig.TextDisabled(ctx, (IS_MAC and 'Cmd' or 'Ctrl') .. '+click a slider to type a value.')
    if ig.Button(ctx, 'Reset to defaults', 150, 0) then
      request_confirm('Reset every setting in this window to its default?', reset_cfg, 'Reset')
    end
    draw_confirm('settings')
    CONFIRM_HOST = nil
    ig.End(ctx)
  end
  if not open then
    S.show_settings = false
    if confirm and confirm.host == 'settings' then confirm = nil end   -- closed while asking: Cancel
  end
end

---------------------------------------------------------------- main loop

-- global look: rounded corners everywhere; Daylight also swaps the colors
function push_theme()
  T = theme()
  ig.PushStyleVar(ctx, ig.StyleVar_FrameRounding(), ROUNDING)
  ig.PushStyleVar(ctx, ig.StyleVar_PopupRounding(), ROUNDING)
  local nc = 0
  if S.daylight then
    for _, e in ipairs(LIGHT_COLORS) do
      ig.PushStyleColor(ctx, ig['Col_' .. e[1]](), e[2])
      nc = nc + 1
    end
  end
  return nc
end

function pop_theme(nc)
  if nc > 0 then ig.PopStyleColor(ctx, nc) end
  ig.PopStyleVar(ctx, 2)
end

function loop()
  if not ctx_is_valid() then create_ctx() end
  FRAME = FRAME + 1
  local now = reaper.time_precise()
  local dt = now - last_time
  last_time = now

  apply_settings()
  poll_stats(now)
  scan_step()
  latdb_tick(now)
  announce_crash()
  check_new_fx(now)

  if now - last_scan > SCAN_EVERY then
    scan()
    last_scan = now
  end

  if ig.SetNextWindowSizeConstraints then
    ig.SetNextWindowSizeConstraints(ctx, MIN_W, MIN_H, 16384, 16384)
  end
  if force_size or not was_visible then
    ig.SetNextWindowSize(ctx, win_w, win_h, ig.Cond_Always())
    force_size = false
  else
    ig.SetNextWindowSize(ctx, win_w, win_h, ig.Cond_FirstUseEver())
  end
  if ig.SetNextWindowDockID then
    if dock_request ~= nil then
      ig.SetNextWindowDockID(ctx, dock_request, ig.Cond_Always())
      dock_request = nil
    elseif not dock_applied and saved_dock ~= 0 then
      ig.SetNextWindowDockID(ctx, saved_dock, ig.Cond_Once())
      dock_applied = true
    end
  end

  local nc = push_theme()
  local flags = ig.WindowFlags_NoScrollbar() | ig.WindowFlags_NoScrollWithMouse()
  local visible, open = ig.Begin(ctx, 'Plugins Host v' .. VERSION .. '###Plugins Host', true, flags)
  if visible then
    -- remember size (and detect the "minimized" shrink)
    local docked = ig.IsWindowDocked(ctx)
    if not docked then
      local w, h = ig.GetWindowSize(ctx)
      local shrunk = prev_w and (w <= MIN_W + 1 and h <= MIN_H + 1)
                     and (prev_w > MIN_W + 40 or prev_h > MIN_H + 40)
      if shrunk then
        force_size = true
      else
        win_w, win_h = w, h
      end
      prev_w, prev_h = w, h
    end

    -- remember dock state
    local did = ig.GetWindowDockID(ctx)
    if did ~= cur_dock then
      cur_dock = did
      reaper.SetExtState(EXT_SECTION, 'dock', tostring(did or 0), true)
    end

    draw(dt, now)
    ig.End(ctx)
  end
  draw_settings()
  draw_plugin_list()
  draw_scan_window()
  pop_theme(nc)
  was_visible = visible

  -- things that open a native dialog run here, after the frame is complete
  if #later > 0 then
    local l = later
    later = {}
    for _, f in ipairs(l) do f() end
  end

  if open then reaper.defer(safe_loop) end
end

-- Any error stops FOH-Mate with the exact place it happened (file, line and
-- the chain of calls), in REAPER's console and in Data/FOHMate/last_error.txt
function safe_loop()
  local ok, err = xpcall(loop, debug.traceback)
  if ok then return end
  local report = ('FOH-Mate %s stopped on an error:\n%s\n'):format(VERSION, tostring(err))
  reaper.ShowConsoleMsg(report .. '\n')
  pcall(function()
    reaper.RecursiveCreateDirectory(LATDB_DIR, 0)
    local f = io.open(LATDB_DIR .. '/last_error.txt', 'w')
    if f then f:write(os.date('%Y-%m-%d %H:%M') .. '\n' .. report); f:close() end
  end)
end

---------------------------------------------------------------- start

load_cfg()
migrate_cfg()
apply_settings()
init_stats()

if not install_jsfx() then
  reaper.MB('Could not write the meter JSFX into the Effects folder.', 'FOH-Mate', 0)
end
-- the meter JSFX files of earlier versions are no longer used (their instances are replaced automatically)
do
  local old_dir = reaper.GetResourcePath() .. '/Effects/RackPanel'
  os.remove(old_dir .. '/RackPanel_Meter')
  os.remove(old_dir .. '/RackPanel_InputMeter')
  os.remove(old_dir)                 -- only succeeds when the folder is empty
  local lr_dir = reaper.GetResourcePath() .. '/Effects/LiveRack'   -- meter of the versions called Live Rack
  os.remove(lr_dir .. '/LiveRack_Meter')
  os.remove(lr_dir)
end
migrate_data_folder()
latdb_load()
favs_load()
recent_load()
scan_recover()
reaper.gmem_attach(GMEM)
create_ctx()
reaper.defer(safe_loop)
