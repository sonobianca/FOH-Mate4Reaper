-- FOHMate/state.lua: state.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

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

