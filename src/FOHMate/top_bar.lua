-- FOHMate/top_bar.lua: top bar menus, FX type colors, window sizes, FX menu items, FX search.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

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
  if toggle_setting('Take FX over the limit offline in Show mode', 'show_off', 'showoff',
       'Switching to Show takes offline every FX over the per-FX limit, then the FX adding\nthe most latency until each rack is under the per-rack limit.\nBack to Edit brings them back online.') then
    recheck_show_offline()
  end
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
  if toggle_setting('Count every format at its highest latency', 'lat_formats', 'latformats',
       'A plugin installed in several formats (AU, VST3, VST...) counts with the highest\n'
       .. 'latency any of its formats reports: some formats (often AU) report 0 where\n'
       .. 'another reports the real figure. Estimated figures are marked * in the Plugin list.\n'
       .. 'Only alerts, limits and figures use it: REAPER\'s compensation is not changed.') then
    LAT = {}                          -- every rack is counted again right away
    recheck_show_offline()
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
  local lat = (e and e.src ~= 'failed') and (latency_counted(e.name, e.lat or 0)) or 0
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

