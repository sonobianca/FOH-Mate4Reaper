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

VERSION         = '0.12.0'   -- major.minor.revision, shown in the window's title bar
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

---------------------------------------------------------------- modules

-- The rest of the code is in the FOHMate folder next to this file. Each module
-- is loaded into the same private environment, in this order, so every name
-- is shared exactly as if it were all one file.
MODULES = {
  'settings', 'context', 'jsfx', 'state', 'helpers', 'modes', 'colors', 'chain', 'tracks',
  'sidechain', 'stereo', 'latency', 'fx_list', 'scan', 'plugin_list', 'add_fx_menu', 'setup',
  'widgets', 'sidechain_ui', 'racks', 'top_bar', 'window'
}

MODULE_DIR = (debug.getinfo(1, 'S').source:match('^@?(.*[/\\])') or '') .. 'FOHMate/'
for _, name in ipairs(MODULES) do
  local chunk, err = loadfile(MODULE_DIR .. name .. '.lua', 't', _ENV)
  if not chunk then
    reaper.MB('FOH-Mate could not load one of its files:\n' .. tostring(err) ..
              '\n\nThe FOHMate folder must sit next to FOHMate.lua. Reinstall FOH-Mate.',
              'FOH-Mate', 0)
    return
  end
  chunk()
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
