-- FOHMate/plugin_list.lua: the Plugin list window, Show mode taking FX over the limit offline.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

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
  lat     = function(r) return (r.e and r.e.src ~= 'failed') and (latency_counted(r.e.name, r.e.lat or 0)) or -1 end,
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
                             LATDB.rev, FAVS.rev, LAT_LIMIT, tostring(S.lat_formats), tostring(fx_db) }, '|')
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
          local n, from = latency_counted(e.name, e.lat or 0)
          local txt = ('%d%s (%.2f ms)'):format(n, from and '*' or '', n * 1000 / sample_rate())
          if over then ig.TextColored(ctx, ALERT_RED, txt) else ig.Text(ctx, txt) end
          if from and ig.IsItemHovered(ctx) then
            ig.SetTooltip(ctx, ('Estimated: this format reports %d samples,\n%s reports %d.\n'
                               .. '(Latency > Count every format at its highest latency)'):format(e.lat or 0, from, n))
          end
        end
        ig.TableNextColumn(ctx)
        if e and e.src ~= 'failed' then ig.Text(ctx, tostring(e.max or 0)) else ig.TextDisabled(ctx, '-') end
        -- allowed
        ig.TableNextColumn(ctx)
        local cw = ig.GetContentRegionAvail(ctx)
        ig.SetCursorPosX(ctx, ig.GetCursorPosX(ctx) + math.max(0, (cw - fh) / 2))
        local c, nv = ig.Checkbox(ctx, '##al', e ~= nil and e.allowed)
        if c then
          local name = it.name
          local function go() latdb_set_allowed(name, nv); LAT = {} end
          if nv then confirm_allowed_one_format(name, go) else go() end
        end
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
-- their latency is really gone) until the rack is back under the limit. FX
-- already offline are left as they are, so this can run again while in Show
-- mode: the ones it adds join the list that Edit brings back.
function offline_for_show()
  -- first what goes offline (nothing changes yet, so no empty undo point)
  local plan = {}
  for _, tr in ipairs(racks) do
    if valid(tr) then
      local items, total = {}, 0
      for _, it in ipairs(chain_info(tr).list) do
        local nm = fx_orig_name(tr, it.fx)
        local lat = (latency_counted(nm, fx_latency(tr, it.fx)))
        if lat > 0 and not latdb_allowed(nm) and not reaper.TrackFX_GetOffline(tr, it.fx)
           and reaper.TrackFX_GetEnabled(tr, it.fx) then
          items[#items + 1] = { guid = reaper.TrackFX_GetFXGUID(tr, it.fx), lat = lat }
          total = total + lat
        end
      end
      table.sort(items, function(a, b) return a.lat > b.lat end)
      local off = {}
      for _, x in ipairs(items) do
        if total <= LAT_RACK_LIMIT and x.lat <= LAT_LIMIT then break end
        off[#off + 1] = x.guid
        total = total - x.lat
      end
      if #off > 0 then plan[#plan + 1] = { tr = tr, off = off } end
    end
  end
  if #plan == 0 then return 0 end
  local n = 0
  with_undo('Rack: FX offline for Show mode', function()
    for _, p in ipairs(plan) do
      local done = {}
      for _, g in ipairs(p.off) do
        local fx = fx_index_by_guid(p.tr, g)
        if fx then
          reaper.TrackFX_SetOffline(p.tr, fx, true)
          done[#done + 1] = g
          n = n + 1
        end
      end
      if #done > 0 then
        local ok, s = reaper.GetSetMediaTrackInfo_String(p.tr, EXT_SHOWOFF, '', false)
        if ok and s ~= '' then table.insert(done, 1, s) end
        reaper.GetSetMediaTrackInfo_String(p.tr, EXT_SHOWOFF, table.concat(done, ';'), true)
      end
      LAT[reaper.GetTrackGUID(p.tr)] = nil
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

