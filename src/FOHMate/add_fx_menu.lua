-- FOHMate/add_fx_menu.lua: add FX menu.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

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

