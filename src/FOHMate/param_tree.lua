-- FOHMate/param_tree.lua: the tree of the project's racks, their FX, groups and parameters, with tick boxes,
-- to pick parameters for a module (the quick access panel's Parameters window uses it).
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- parameter tree

-- the racks of the project, in track order
function param_racks()
  local out = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local name = track_name(tr)
    if is_rack_name(name) then out[#out + 1] = { tr = tr, guid = reaper.GetTrackGUID(tr), name = name } end
  end
  return out
end

-- a rack folded: what was selected in its FX is not selected any more (it can't be seen)
function param_pick_forget(P, tr)
  local guids = {}
  for i = 0, reaper.TrackFX_GetCount(tr) - 1 do guids[reaper.TrackFX_GetFXGUID(tr, i)] = true end
  for k in pairs(P.sel) do
    local g = k:match('^%a:({[^}]+})')
    if g and guids[g] then P.sel[k] = nil end
  end
end

-- The tree of an FX: parameters of the same group (param_group: "Band 1"...) go in a branch of their
-- own, where the first of them is; the others stay as they are. In a group, parameters that start
-- with the same word ("Dyn. Threshold", "Dyn. Ratio"...) go in a branch of their own too, and so on
-- (3 levels at most). A branch is { label, path, ps = { every index in it }, pset, children }, a
-- parameter is { p = index, label = its name without the groups }. fx.items is the list, in the
-- FX order; fx.gps has the indexes of each branch by its key (for the selection).
function param_split(fx, node, mem, depth)
  node.children, node.pset = {}, {}
  for _, m in ipairs(mem) do node.pset[m.p] = true end
  fx.gps['G:' .. fx.guid .. ':' .. node.path] = node.ps
  local first, cnt = {}, {}
  if depth <= 2 then
    for i, m in ipairs(mem) do
      local w = m.rest:match('^(%S+)%s+%S')
      first[i] = w
      if w then cnt[w] = (cnt[w] or 0) + 1 end
    end
  end
  local sub, subs = {}, {}
  for i, m in ipairs(mem) do
    local w = first[i]
    local c = w and cnt[w] or 0
    -- a word shared by 3 or more (2 when it ends with a dot or a colon: "Dyn."), but not by all
    if w and c < #mem and (c >= 3 or (c >= 2 and w:find('[%.:]$'))) then
      local sg = sub[w]
      if not sg then
        sg = { label = w, path = node.path .. '/' .. w, ps = {}, mem = {} }
        sub[w] = sg
        subs[#subs + 1] = sg
        node.children[#node.children + 1] = sg
      end
      sg.ps[#sg.ps + 1] = m.p
      sg.mem[#sg.mem + 1] = { p = m.p, rest = m.rest:match('^%S+%s+(.*)$') }
    else
      node.children[#node.children + 1] = { p = m.p, label = m.rest ~= '' and m.rest or fx.names[m.p + 1] }
    end
  end
  for _, sg in ipairs(subs) do param_split(fx, sg, sg.mem, depth + 1) end
end

function param_pick_groups(fx)
  local count = {}
  for p = 0, #fx.names - 1 do
    if not fx.hide[p] and not fx.reaper[p] then
      local _, lbl = param_group(fx.names[p + 1])
      if lbl then count[lbl] = (count[lbl] or 0) + 1 end
    end
  end
  local items, at, rp = {}, {}, nil
  fx.gps = {}
  for p = 0, #fx.names - 1 do
    if fx.reaper[p] then
      -- REAPER's own (Bypass, Wet, Delta): their branch, at the end
      if not fx.hide[p] then
        rp = rp or { label = 'REAPER', path = 'REAPER', ps = {}, mem = {} }
        rp.ps[#rp.ps + 1] = p
        rp.mem[#rp.mem + 1] = { p = p, rest = '' }          -- (rest empty: the parameter's own name)
      end
    elseif not fx.hide[p] then
      local nm = fx.names[p + 1]
      local _, lbl = param_group(nm)
      if lbl and count[lbl] > 1 then
        if not at[lbl] then at[lbl] = { label = lbl, path = lbl, ps = {}, mem = {} }; items[#items + 1] = at[lbl] end
        local g = at[lbl]
        g.ps[#g.ps + 1] = p
        g.mem[#g.mem + 1] = { p = p, rest = param_group_rest(nm) }
      else
        items[#items + 1] = { p = p, label = nm }
      end
    end
  end
  for _, it in ipairs(items) do if it.mem then param_split(fx, it, it.mem, 1) end end
  if rp then param_split(fx, rp, rp.mem, 9); items[#items + 1] = rp end     -- (depth 9: no sub-branches)
  fx.items = items
end

-- the parameters of an FX node or of one parameter, as { guid, idx, name }
function param_pick_targets(P, fxs)
  local out, seen = {}, {}
  local function add(fx, p)
    local key = fx.guid .. ':' .. p
    if not seen[key] then seen[key] = true; out[#out + 1] = { guid = fx.guid, idx = p, name = fx.names[p + 1], tr = fx.tr } end
  end
  for _, fx in ipairs(fxs) do
    if P.sel['P:' .. fx.guid] or (fx.tr and P.sel['R:' .. reaper.GetTrackGUID(fx.tr)]) then   -- the FX, or its rack
      for p = 0, #fx.names - 1 do if not fx.hide[p] then add(fx, p) end end
    end
    for key, ps in pairs(fx.gps or {}) do
      if P.sel[key] then for _, p in ipairs(ps) do add(fx, p) end end
    end
    for p = 0, #fx.names - 1 do
      if P.sel['p:' .. fx.guid .. ':' .. p] then add(fx, p) end
    end
  end
  return out
end

-- the selection may be in several racks: each gets its own call of apply(tr, targets, adding)
function param_pick_apply(P, fxs, adding, apply)
  local by, order = {}, {}
  for _, t in ipairs(param_pick_targets(P, fxs)) do
    if not by[t.tr] then by[t.tr] = {}; order[#order + 1] = t.tr end
    table.insert(by[t.tr], t)
  end
  for _, tr in ipairs(order) do apply(tr, by[tr], adding) end
end

function param_pick_data(P)
  -- every rack of the project is a branch; the FX of the racks that are open, and the names of their
  -- parameters, are read once per FX
  local racks = param_racks()
  P.open = P.open or {}
  local fxs, gm = {}, {}
  for _, rk in ipairs(racks) do
    rk.fxs = {}
    if P.open['R:' .. rk.guid] then
      for _, it in ipairs(chain_info(rk.tr).list) do
        local g = reaper.TrackFX_GetFXGUID(rk.tr, it.fx)
        local f = P.cache and P.cache[g]
        if not f or f.fx ~= it.fx or f.name ~= it.name then
          -- hidden: by the rules above (auto) or by hand (uhid); shown anyway with Show hidden
          local names, hide, auto, uhid, nvis = {}, {}, {}, {}, 0
          local fx_key = param_fx_name_key(it.name)
          for p = 0, reaper.TrackFX_GetNumParams(rk.tr, it.fx) - 1 do
            local _, nm = reaper.TrackFX_GetParamName(rk.tr, it.fx, p, '')
            names[p + 1] = nm
            auto[p], uhid[p] = param_hidden(nm) or param_dead_values(rk.tr, it.fx, p), param_uhidden(fx_key, nm)
            if (auto[p] or uhid[p]) and not P.show_hidden then hide[p] = true else nvis = nvis + 1 end
          end
          f = { guid = g, fx = it.fx, name = it.name, names = names, hide = hide, auto = auto, uhid = uhid,
                fx_key = fx_key, nvis = nvis, reaper = param_reaper_set(names) }
          param_pick_groups(f)
          P.cache = P.cache or {}
          P.cache[g] = f
        end
        f.tr = rk.tr
        gm[g] = it.fx
        rk.fxs[#rk.fxs + 1] = f
        fxs[#fxs + 1] = f
      end
    end
  end

  -- what is selected glows in the rack's column (window.lua); a single parameter picked here is also
  -- scrolled to, once (the rack into view, then the column to the row)
  local targets = param_pick_targets(P, fxs)
  P.hl = {}
  local sig = #targets .. ':' .. (targets[1] and (targets[1].guid .. ':' .. targets[1].idx) or '')
  for _, t in ipairs(targets) do P.hl[t.guid .. ':' .. t.idx] = true end
  if P.sel_sig ~= sig then
    P.sel_sig = sig
    P.focus = (#targets == 1 and not P.no_focus) and { guid = targets[1].guid, idx = targets[1].idx, t = reaper.time_precise() } or nil
    P.no_focus = false
  end
  if P.focus and reaper.time_precise() - P.focus.t > 1 then P.focus = nil end   -- not in any column: forget it

  P.data = { racks = racks, fxs = fxs, gm = gm, targets = targets }
  return P.data
end

-- draw_tree(P, D, o): the tree, inside the window the module opened: a search box, Show hidden, the racks
-- (folding), their FX, groups and parameters, each with a tick box, then the module's two buttons. P: the
-- tree's state (filter, sel, open, order...: a table the module keeps); D: param_pick_data(P). o, what the
-- module says:
--   have(racks, P) -> { ['fxguid:idx'] = what it keeps for that parameter (a table may hold col) }
--   apply(tr, targets, adding): add or remove parameters ({ guid, idx, name } each) of a rack
--   in_label: after the counts ("3 of 12 " .. in_label)
--   add_label, remove_label (+ add_tip, remove_tip): the buttons
--   leaf_menu(P, D, fx, p, name): more items in a parameter's right-click menu (optional)
function draw_tree(P, D, o)
  local racks, fxs, gm = D.racks, D.fxs, D.gm
  do
    local spx = select(1, ig.GetStyleVar(ctx, ig.StyleVar_ItemSpacing()))
    local refw = ig.CalcTextSize(ctx, 'Refresh') + 2 * select(1, ig.GetStyleVar(ctx, ig.StyleVar_FramePadding()))
    ig.SetNextItemWidth(ctx, -ig.CalcTextSize(ctx, 'Show hidden') - ig.GetFrameHeight(ctx) - 16 - refw - spx)
    local rv, ftxt = ig.InputTextWithHint(ctx, '##pf', 'Search parameters', P.filter)
    if rv then P.filter = ftxt end
    -- the names of the parameters are read once per FX: Refresh reads them again (an FX may rename its
    -- parameters, ReaEQ when a band changes type); also done when a rack puts something in focus here
    ig.SameLine(ctx)
    if ig.Button(ctx, 'Refresh') then P.cache = nil end
    if ig.IsItemHovered(ctx) then
      ig.SetTooltip(ctx, 'Read the FX\'s parameters again (an FX may change them: ReaEQ when a band changes type).')
    end
    ig.SameLine(ctx)
    local rvh, vh = ig.Checkbox(ctx, 'Show hidden', P.show_hidden == true)
    if rvh then P.show_hidden, P.cache = vh, nil end
    if ig.IsItemHovered(ctx) then
      ig.SetTooltip(ctx, 'Also list the parameters that are hidden: placeholders ("Reserved"...), MIDI CC\n'
                      .. 'entries, and those you hid (right-click a parameter > Hide this parameter).')
    end
    local low = P.filter:lower()

    local have = o.have(racks, P)              -- guid:idx -> what the module keeps for it (in its list)
    local lh = ig.GetTextLineHeightWithSpacing(ctx)
    local TXT = ig.GetStyleColor(ctx, ig.Col_Text())
    local bgc = ig.GetStyleColor(ctx, ig.Col_WindowBg())
    local dark = ((bgc >> 24) & 255) * 0.3 + ((bgc >> 16) & 255) * 0.59 + ((bgc >> 8) & 255) * 0.11 < 128
    local order = {}
    local box = lh - 6                                   -- the check boxes: this size whatever the text
    local function click(key, shift, ctrl)
      if shift and P.anchor then
        local a, b
        for i, k in ipairs(P.order) do
          if k == P.anchor then a = i end
          if k == key then b = i end
        end
        if a and b then
          if a > b then a, b = b, a end
          for i = a, b do P.sel[P.order[i]] = true end
          return
        end
      end
      if not ctrl then P.sel = {} end
      if ctrl and P.sel[key] then P.sel[key] = nil else P.sel[key] = true end
      P.anchor = key
    end
    local mx = ig.GetMousePos(ctx)

    -- the height of a line by what it holds: a rack (big name), an FX or a group (a smaller one), a parameter
    local function line_h(font, size)
      local pushed = push_bold(font, size)
      local h = ig.GetTextLineHeight(ctx)
      if pushed then ig.PopFont(ctx) end
      return math.floor(h)
    end
    local th0 = ig.GetTextLineHeight(ctx)
    local h_rack, h_grp, h_par = line_h(head_font, HEAD_FONT_SIZE) + 8, line_h(sect_font, SECT_FONT_SIZE) + 6, lh - 2

    local avail_w, avail_h = ig.GetContentRegionAvail(ctx)
    local foot = ig.GetFrameHeightWithSpacing(ctx) + 4
    if ig.BeginChild(ctx, 'pptree', avail_w, avail_h - foot) then
      -- Every line is drawn here, not by ImGui's tree: a branch has its arrow, then (FX, groups,
      -- parameters) a check box, then its name. What a branch holds is one step in, and the step is
      -- the width of a check box and its gap: the check boxes of what is in a branch start where the
      -- name of the branch starts, and a branch inside a branch has its check box with its siblings'
      -- (its arrow is left of it).
      local L = ig.GetCursorScreenPos(ctx) + 6
      local aw = 10                                       -- the arrow
      -- an FX is one more step in than its rack's name, so its arrow sits under the name's first letter
      local function cxof(depth) return L + aw + 6 + (aw + 4) + depth * (box + 8) end
      -- a thin dotted line down a branch, from under its row to its last line (only what is in view)
      local wx, wy = ig.GetWindowPos(ctx)
      local ww, wh = ig.GetWindowSize(ctx)
      local lastbot = 0                                   -- where the last line drawn ends
      local guide_col = (T.dim & 0xFFFFFF00) | 0xB0
      local function guide(x, y1, y2)
        for y = math.max(y1, wy), math.min(y2, wy + wh), 4 do
          ig.DrawList_AddRectFilled(ig.GetWindowDrawList(ctx), x - 0.5, y, x + 1, y + 1.5, guide_col)
        end
      end

      -- sp: id, sel (the key it selects by), depth, h, font + size (of the name), arrow + open + okey (the
      -- branches), check + on + part (the check box), name, col, type, count, right, tip, on_check, menu
      local function draw_row(sp)
        if sp.sel then order[#order + 1] = sp.sel end
        local scroll = sp.sel ~= nil and sp.sel == P.scroll_key        -- a parameter picked in the rack: brought into view
        if not scroll and not ig.IsRectVisible(ctx, 1, sp.h) then
          ig.Dummy(ctx, 1, sp.h)
          lastbot = select(2, ig.GetItemRectMax(ctx))
          return
        end
        local clicked = ig.Selectable(ctx, '##' .. sp.id, sp.sel ~= nil and P.sel[sp.sel] == true, 0, 0, sp.h)
        local ix, iy = ig.GetItemRectMin(ctx)
        local iw = ig.GetItemRectSize(ctx)
        lastbot = iy + sp.h
        if scroll then ig.SetScrollHereY(ctx, 0.35); P.scroll_key = nil end
        local midy = iy + sp.h / 2
        local cx = sp.check and cxof(sp.depth) or nil
        local ax = cx and (cx - aw - 4) or L
        local tx = cx and (cx + box + 8) or (L + aw + 6)
        if sp.tip and ig.IsItemHovered(ctx) then ig.SetTooltip(ctx, sp.tip) end
        if sp.menu and ig.BeginPopupContextItem(ctx, 'pph' .. sp.id) then sp.menu(); ig.EndPopup(ctx) end
        if clicked then
          local toggle = sp.arrow and mx >= ax - 3 and mx <= ax + aw + 3
          if toggle or (sp.arrow and not sp.sel) then
            sp.on_toggle()
          elseif cx and mx >= cx - 3 and mx <= cx + box + 3 then
            sp.on_check()
          elseif sp.sel then
            click(sp.sel, has_mod('shift'), has_mod('ctrl'))
            if sp.on_select then sp.on_select() end
          end
        end
        local dl = ig.GetWindowDrawList(ctx)
        if sp.arrow then
          if sp.open then
            ig.DrawList_AddTriangleFilled(dl, ax, midy - 2.5, ax + aw, midy - 2.5, ax + aw / 2, midy + 3.5, TXT)
          else
            ig.DrawList_AddTriangleFilled(dl, ax + 2, midy - 4.5, ax + 2, midy + 4.5, ax + aw, midy, TXT)
          end
        end
        if cx then draw_check(dl, cx, midy - box / 2, box, TXT, sp.on, sp.part) end
        local rcol = sp.right and (ix + iw * 0.5)           -- the kind and value column: the same place on every line
        local pushed = sp.font and push_bold(sp.font, sp.size)
        local th = ig.GetTextLineHeight(ctx)
        local name = sp.name
        if rcol then name = fit_text(name, rcol - tx - 10) end
        ig.DrawList_AddText(dl, tx, midy - th / 2, sp.col or TXT, name)
        local nx = tx + ig.CalcTextSize(ctx, name) + 8
        if pushed then ig.PopFont(ctx) end
        local ty = midy - th0 / 2
        if sp.type then
          local ttxt = '(' .. sp.type .. ')'
          ig.DrawList_AddText(dl, nx, ty, type_color(sp.type), ttxt)
          nx = nx + ig.CalcTextSize(ctx, ttxt) + 8
        end
        if sp.count then ig.DrawList_AddText(dl, nx, ty, T.dim, sp.count) end
        if rcol then ig.DrawList_AddText(dl, rcol, ty, T.dim, fit_text(sp.right(), ix + iw - rcol - 6)) end
      end

      local function matches(fx, p) return low == '' or fx.names[p + 1]:lower():find(low, 1, true) end
      local function targets_of(fx, ps)
        local t = {}
        for _, p in ipairs(ps) do t[#t + 1] = { guid = fx.guid, idx = p, name = fx.names[p + 1] } end
        return t
      end
      local function count_have(fx, ps)
        local n = 0
        for _, p in ipairs(ps) do if have[fx.guid .. ':' .. p] then n = n + 1 end end
        return n
      end

      local function draw_leaf(fx, p, label, depth, rack_col)
        local nm = fx.names[p + 1]
        local key = 'p:' .. fx.guid .. ':' .. p
        local inn = have[fx.guid .. ':' .. p] ~= nil
        local hid = fx.auto[p] or fx.uhid[p]
        local col = TXT
        if ig.IsRectVisible(ctx, 1, h_par) then
          -- the name in the color it has in the rack (its own, or the group's shift of the rack's), made readable
          local kept = have[fx.guid .. ':' .. p]
          col = hid and T.dim or param_name_color(
            param_row_color(rack_col, { col = type(kept) == 'table' and kept.col or nil, pname = nm }), dark)
          -- (rack_col here is the color of the FX the parameter is in)
        end
        draw_row({ id = key, sel = key, depth = depth, h = h_par, check = true, on = inn, col = col,
          name = label .. (hid and '  (hidden)' or ''),
          tip = label ~= nm and nm or nil,
          right = function()
            -- the kind of value and its value now
            local kind = param_kind(fx.tr, gm[fx.guid], { guid = fx.guid, idx = p, pname = nm })
            local _, txt = reaper.TrackFX_GetFormattedParamValue(fx.tr, gm[fx.guid], p)
            return ('%s:  %s'):format(kind.label, txt or '')
          end,
          on_check = function() o.apply(fx.tr, { { guid = fx.guid, idx = p, name = nm } }, not inn) end,
          -- right-click: hide it (for this FX, everywhere), or show it again
          menu = function()
            if fx.uhid[p] then
              if ig.MenuItem(ctx, 'Show this parameter again') then param_set_uhidden(fx.fx_key, nm, false) end
            elseif fx.auto[p] then
              ig.TextDisabled(ctx, 'Hidden by FOH-Mate (a placeholder, a MIDI CC entry, or every value "Reserved")')
            elseif ig.MenuItem(ctx, 'Hide this parameter') then
              param_set_uhidden(fx.fx_key, nm, true)
            end
            if o.leaf_menu and gm[fx.guid] then o.leaf_menu(P, D, fx, p, nm) end
          end })
      end

      local draw_nodes
      -- a group ("Band 1"), or a branch of one ("Dyn."): folded at first, open while searching when something in it matches
      local function draw_group(fx, nd, depth, rack_col)
        if low ~= '' then
          local any = false
          for _, p in ipairs(nd.ps) do if matches(fx, p) then any = true; break end end
          if not any then return end
        end
        local gkey = 'G:' .. fx.guid .. ':' .. nd.path
        if P.reveal and P.reveal.guid == fx.guid and nd.pset[P.reveal.idx] then P.open[gkey] = true end
        if P.unfold and P.unfold[fx.guid] then P.open[gkey] = true end   -- Shift+right-click on the rack's name
        local opened = low ~= '' or P.open[gkey] == true
        local g_have = count_have(fx, nd.ps)
        draw_row({ id = gkey, sel = gkey, depth = depth, h = h_grp, font = sect_font, size = SECT_FONT_SIZE,
          col = param_name_color(param_row_color(rack_col, { pname = nd.label }), dark),
          arrow = true, open = opened, check = true, on = g_have == #nd.ps, part = g_have > 0, name = nd.label,
          count = ('%d of %d '):format(g_have, #nd.ps) .. o.in_label,
          on_toggle = function() P.open[gkey] = not opened end,
          -- the check box: every parameter of the branch in or out
          on_check = function() o.apply(fx.tr, targets_of(fx, nd.ps), g_have < #nd.ps) end })
        if opened then
          local y1 = lastbot
          draw_nodes(fx, nd.children, depth + 1, rack_col)
          guide(cxof(depth) - aw / 2 - 4, y1, lastbot - 5)
        end
      end
      draw_nodes = function(fx, nodes, depth, rack_col)
        for _, nd in ipairs(nodes) do
          if nd.p then
            if matches(fx, nd.p) then draw_leaf(fx, nd.p, nd.label, depth, rack_col) end
          else
            draw_group(fx, nd, depth, rack_col)
          end
        end
      end

      for _, rk in ipairs(racks) do
        local rkey = 'R:' .. rk.guid
        local ropen = P.open[rkey] == true
        draw_row({ id = rkey, sel = rkey, h = h_rack, font = head_font, size = HEAD_FONT_SIZE, arrow = true, open = ropen,
          name = rk.name, col = param_name_color(track_color(rk.tr), dark),
          -- clicked: the rack is selected in the Racks window too (Cmd/Ctrl or Shift: added to the selection)
          on_select = function() select_rack(rk.tr, has_mod('ctrl') or has_mod('shift')) end,
          on_toggle = function()
            P.open[rkey] = not ropen
            if ropen then param_pick_forget(P, rk.tr) end
          end })
        if ropen then
          local rk_y1 = lastbot
          local rack_col = track_color(rk.tr)
          if #rk.fxs == 0 then ig.Indent(ctx, cxof(0) - L); ig.TextDisabled(ctx, 'This rack has no FX yet.'); ig.Unindent(ctx, cxof(0) - L) end
          for _, fx in ipairs(rk.fxs) do
            local pname, ptype = fx_name_type(fx.name)
            local pkey = 'P:' .. fx.guid
            local fkey = 'F:' .. fx.guid
            if P.reveal and P.reveal.guid == fx.guid then P.open[fkey] = true end
            local n_have = 0
            for p = 0, #fx.names - 1 do if not fx.hide[p] and have[fx.guid .. ':' .. p] then n_have = n_have + 1 end end
            local opened = low ~= '' or P.open[fkey] == true
            local fcol = fx_color(fx.tr, fx.guid, rack_col)           -- the FX's color: its own, or the rack's
            draw_row({ id = pkey, sel = pkey, depth = 0, h = h_grp, font = sect_font, size = SECT_FONT_SIZE,
              col = param_name_color(fcol, dark),
              menu = function() if ig.MenuItem(ctx, 'Color...') then fx_open_picker(fx.tr, fx.guid, fx.name) end end,
              arrow = true, open = opened, check = true, on = n_have == fx.nvis and n_have > 0, part = n_have > 0,
              name = pname, type = ptype, count = ('%d of %d '):format(n_have, fx.nvis) .. o.in_label,
              on_toggle = function() P.open[fkey] = not opened end,
              -- the check box: every parameter of the FX in or out
              on_check = function()
                local all = {}
                for p = 0, #fx.names - 1 do if not fx.hide[p] then all[#all + 1] = p end end
                o.apply(fx.tr, targets_of(fx, all), n_have < fx.nvis)
              end })
            if opened then
              local y1 = lastbot
              draw_nodes(fx, fx.items or {}, 1, fcol)
              guide(cxof(0) - aw / 2 - 4, y1, lastbot - 5)
            end
          end
          guide(L + aw / 2, rk_y1, lastbot - 5)
        end
      end
      P.reveal, P.scroll_key, P.unfold = nil, nil, nil
      ig.EndChild(ctx)
    end
    P.order = order

    local any = next(P.sel) ~= nil
    if not any and ig.BeginDisabled then ig.BeginDisabled(ctx, true) end
    if ig.Button(ctx, o.add_label) then param_pick_apply(P, fxs, true, o.apply) end
    if o.add_tip and ig.IsItemHovered(ctx, ig.HoveredFlags_AllowWhenDisabled()) then ig.SetTooltip(ctx, o.add_tip) end
    ig.SameLine(ctx)
    if ig.Button(ctx, o.remove_label) then param_pick_apply(P, fxs, false, o.apply) end
    if o.remove_tip and ig.IsItemHovered(ctx, ig.HoveredFlags_AllowWhenDisabled()) then ig.SetTooltip(ctx, o.remove_tip) end
    if not any and ig.EndDisabled then ig.EndDisabled(ctx) end
    ig.SameLine(ctx)
    ig.TextDisabled(ctx, ('%d selected'):format((function() local c = 0 for _ in pairs(P.sel) do c = c + 1 end return c end)()))
  end
end
