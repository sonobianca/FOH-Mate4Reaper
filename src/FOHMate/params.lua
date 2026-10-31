-- FOHMate/params.lua: Performance mode parameter rows.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- parameter rows
--
-- The rows of a rack's column are saved on the rack (its track), so a duplicated rack takes them
-- along. Each row is one parameter of one FX of that rack: the FX's GUID and the parameter's
-- index, plus the name the plug-in reported when the row was made (to notice a changed plug-in)
-- and a name of the user's own (nil = the reported one). A row whose FX or parameter is gone is
-- kept and drawn greyed out, never silently dropped.

PARAM_CACHE = {}   -- per rack: the saved text and the rows parsed from it
PARAM_PICK  = nil  -- the parameter window (Edit mode): { tr, filter, sel, anchor, order, fx }
PARAM_KIND  = {}   -- what kind of control a parameter gets, found once per parameter

function param_esc(s)
  return (s:gsub('[%%|;\n\r]', function(ch) return ('%%%02X'):format(ch:byte()) end))
end

function param_unesc(s)
  return (s:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end))
end

-- The rows of a rack. The saved text is only read again every 20 frames (a third of a second), so
-- an undo still shows up; our own writes drop the copy at once.
function params_read(tr)
  local guid = reaper.GetTrackGUID(tr)
  local c = PARAM_CACHE[guid]
  if c and FRAME - c.frame < 20 then return c.rows end
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, EXT_PARAMS, '', false)
  if not ok then s = '' end
  if c and c.raw == s then c.frame = FRAME; return c.rows end
  local rows = {}
  for rec in s:gmatch('[^;]+') do
    local g, i, pn, nm, df, iv = rec:match('^([^|]*)|(%d+)|([^|]*)|([^|]*)|?([^|]*)|?([^|]*)$')
    if g then
      rows[#rows + 1] = { guid = g, idx = tonumber(i), pname = param_unesc(pn),
                          name = nm ~= '' and param_unesc(nm) or nil, def = tonumber(df), inv = (iv == '1') }
    end
  end
  PARAM_CACHE[guid] = { raw = s, rows = rows, frame = FRAME }
  return rows
end

function params_write(tr, rows)
  local t = {}
  for _, r in ipairs(rows) do
    t[#t + 1] = ('%s|%d|%s|%s|%s|%s'):format(r.guid, r.idx, param_esc(r.pname or ''), param_esc(r.name or ''),
                                             r.def and ('%.6f'):format(r.def) or '', r.inv and '1' or '')
  end
  reaper.GetSetMediaTrackInfo_String(tr, EXT_PARAMS, table.concat(t, ';'), true)
  PARAM_CACHE[reaper.GetTrackGUID(tr)] = nil
end

-- FX guid -> index, for the FX of a rack
-- changes fields of one row (inv, def...): changes = { inv = true, def = 0.5 }; a field set to false is cleared
function params_update(tr, guid, idx, changes)
  local rows = {}
  for _, r in ipairs(params_read(tr)) do
    local n = {}
    for k, v in pairs(r) do n[k] = v end
    if r.guid == guid and r.idx == idx then
      for k, v in pairs(changes) do n[k] = (v ~= false) and v or nil end
    end
    rows[#rows + 1] = n
  end
  params_write(tr, rows)
end

-- the row of a parameter in the Performance, if it is there
function params_find(tr, guid, idx)
  for _, r in ipairs(params_read(tr)) do
    if r.guid == guid and r.idx == idx then return r end
  end
end

function fx_guid_map(tr)
  local m = {}
  for i = 0, reaper.TrackFX_GetCount(tr) - 1 do m[reaper.TrackFX_GetFXGUID(tr, i)] = i end
  return m
end

-- how many parameters of the rack are in the Performance
function params_count(tr)
  return #params_read(tr)
end

-- the value as the vertical box can write it: what the plug-in says when the little stroke font
-- has every character of it, otherwise the position as a percentage
function param_vtext(txt, norm)
  if txt and txt ~= '' and #txt <= 12 then
    local ok = true
    for i = 1, #txt do
      local ch = txt:sub(i, i)
      if ch ~= ' ' and not VFONT[ch] then ok = false; break end
    end
    if ok then return txt end
  end
  return ('%d%%'):format(math.floor(norm * 100 + 0.5))
end

-- What control a parameter gets. REAPER says little about a parameter (its range, its step, whether
-- it is a toggle, how it prints a value), so FOH-Mate guesses from that and from the name, and the
-- guess can be corrected by hand: right-click a row in Edit mode. The corrections are kept in
-- Data/FOHMate/param_controls.txt (for every project), together with what REAPER said about the
-- parameter, so the guesses can be improved from them.
--   toggle: on/off, or two values   list: a few named values (a drop-down)   steps: a few numeric
--   values (a stepped encoder)      band: a width or a range (a band centered at the top of the encoder)
--   knob: a smooth encoder
PARAM_OVR      = nil
PARAM_OVR_FILE = LATDB_DIR .. '/param_controls.txt'
-- the names of the controls, used everywhere (the tree, the menus, the section on the right)
PARAM_KIND_LABEL = { knob = 'Encoder', band = 'Width band', steps = 'Stepped encoder', toggle = 'Toggle', list = 'Drop-down' }
PARAM_CONTROL_OPTS = { { nil, 'Automatic' } }
for _, k in ipairs({ 'knob', 'band', 'steps', 'toggle', 'list' }) do
  PARAM_CONTROL_OPTS[#PARAM_CONTROL_OPTS + 1] = { k, PARAM_KIND_LABEL[k] }
end

-- the plug-in's name without its type, the way the corrections are filed
function param_plugin_key(fxname)
  return (fx_name_type(fxname))
end

-- the key of an FX of a rack
function param_fx_key(tr, fxi)
  local _, name = reaper.TrackFX_GetFXName(tr, fxi, '')
  return param_plugin_key(name or '')
end

function param_ovr_load()
  PARAM_OVR = {}
  for _, ln in ipairs(read_lines(PARAM_OVR_FILE)) do
    local f = {}
    for x in (ln .. '\t'):gmatch('([^\t]*)\t') do f[#f + 1] = x end
    if f[1] and f[2] and f[3] and f[3] ~= '' then PARAM_OVR[f[1] .. '\t' .. f[2]] = { kind = f[3], line = ln } end
  end
end

function param_ovr_save()
  local t = {}
  for _, o in pairs(PARAM_OVR) do t[#t + 1] = o.line end
  table.sort(t)
  write_lines(PARAM_OVR_FILE, t)
end

-- what REAPER says about a parameter
function param_facts(tr, fxi, idx)
  local ok, step, _, _, istoggle = reaper.TrackFX_GetParameterStepSizes(tr, fxi, idx)
  local _, mn, mx = reaper.TrackFX_GetParamEx(tr, fxi, idx)
  local _, t0 = reaper.TrackFX_FormatParamValueNormalized(tr, fxi, idx, 0, '')
  local _, t1 = reaper.TrackFX_FormatParamValueNormalized(tr, fxi, idx, 1, '')
  return { ok = ok, step = step, toggle = ok and istoggle, min = mn, max = mx, t0 = t0, t1 = t1 }
end

-- A parameter that is in dB gets the marks of a fader instead of one per step: where -60, -30, -10,
-- -5, 0 and +5 dB lie on it. REAPER can only say what text a position prints, so the parameter is
-- sampled at 41 positions (once) and the positions of those dB values are worked out from that.
-- Returns a list of positions 0..1, or nil when the parameter is not in dB.
FADER_DB = { -60, -30, -10, -5, 0, 5 }

function param_db_marks(tr, fxi, idx)
  local pts, is_db = {}, false
  for i = 0, 40 do
    local v = i / 40
    local _, txt = reaper.TrackFX_FormatParamValueNormalized(tr, fxi, idx, v, '')
    if txt:lower():find('db', 1, true) then is_db = true end
    local num = tonumber((txt:match('^%s*([%-%+]?%d+%.?%d*)')))
    if num then pts[#pts + 1] = { v, num } end
  end
  if not is_db or #pts < 2 then return nil end
  local marks = {}
  for _, target in ipairs(FADER_DB) do
    for i = 1, #pts - 1 do
      local a, b = pts[i], pts[i + 1]
      if (a[2] - target) * (b[2] - target) <= 0 and a[2] ~= b[2] then
        local v = a[1] + (b[1] - a[1]) * (target - a[2]) / (b[2] - a[2])
        if v > 0.02 and v < 0.98 then marks[#marks + 1] = v end
        break
      end
    end
  end
  return marks
end

function param_kind(tr, fxi, r)
  local key = r.guid .. ':' .. r.idx .. ':' .. (r.pname or '')
  local k = PARAM_KIND[key]
  if k then return k end
  if not PARAM_OVR then param_ovr_load() end

  -- how many values there are, when there are few (the step is in the parameter's own units)
  local ok, step, _, _, istoggle = reaper.TrackFX_GetParameterStepSizes(tr, fxi, r.idx)
  local _, mn, mx = reaper.TrackFX_GetParamEx(tr, fxi, r.idx)
  local n
  if ok and step and step > 0 and mn and mx and mx > mn then
    local cnt = (mx - mn) / step
    if cnt <= 31.5 then n = math.floor(cnt + 0.5) + 1 end
  end
  local items, numeric
  if n and n >= 2 then
    items, numeric = {}, true
    for i = 0, n - 1 do
      local v = i / (n - 1)
      local _, txt = reaper.TrackFX_FormatParamValueNormalized(tr, fxi, r.idx, v, '')
      if txt == '' then txt = ('%d%%'):format(math.floor(v * 100 + 0.5)) end
      items[#items + 1] = { label = txt, norm = v }
      if not tonumber((txt:match('^%s*([%-%+]?[%d%.]+)'))) then numeric = false end
    end
  end

  -- the guess
  local low = (r.pname or ''):lower()
  -- two values: a toggle when they read on/off or numbers, a drop-down when they are words (Mono / Stereo)
  local two_words = false
  if n == 2 and items and not (ok and istoggle) then
    local function plain(t)
      t = t:lower()
      return t:find('^on') or t:find('^off') or t:find('^yes') or t:find('^no') or t:find('^enable') or t:find('^disable')
             or t:find('^active') or t:find('^bypass') or tonumber((t:match('^%s*([%-%+]?[%d%.]+)')))
    end
    two_words = not (plain(items[1].label) and plain(items[2].label))
  end
  local guess = 'knob'
  if two_words then
    guess = 'list'
  elseif (ok and istoggle) or n == 2 or low:find('bypass', 1, true) or low:find('^enable') or low:find('on/off', 1, true)
     or low:find('^mute') or low == 'on' or low:find('^power') then
    guess = 'toggle'
  elseif n and n >= 3 then
    guess = numeric and 'steps' or 'list'
  elseif low:find('width', 1, true) or low:find('range', 1, true) or low:find('spread', 1, true)
         or low:find('knee', 1, true) or low == 'q' or low:find('^q[%s%-_]') or low:find('[%s%-_]q$') then
    guess = 'band'
  end

  -- in dB: a smooth encoder with the marks of a fader, never one mark per step
  local marks
  if guess == 'steps' or guess == 'knob' or guess == 'band' then
    marks = param_db_marks(tr, fxi, r.idx)
    if marks and guess == 'steps' then guess = 'knob' end
  end

  -- a correction made by hand wins (a list or steps needs the values to be known)
  local kind, overridden = guess, false
  local ovr = PARAM_OVR[param_fx_key(tr, fxi) .. '\t' .. (r.pname or '')]
  if ovr and PARAM_KIND_LABEL[ovr.kind] then
    kind, overridden = ovr.kind, true
    if (kind == 'steps' or kind == 'list') and not items then
      -- the plug-in doesn't say what its values are: take 11 positions along it
      n, items = 11, {}
      for i = 0, 10 do
        local v = i / 10
        local _, txt = reaper.TrackFX_FormatParamValueNormalized(tr, fxi, r.idx, v, '')
        if txt == '' then txt = ('%d%%'):format(i * 10) end
        items[#items + 1] = { label = txt, norm = v }
      end
    end
  end
  k = { kind = kind, guess = guess, overridden = overridden, label = PARAM_KIND_LABEL[kind], marks = marks }
  if (kind == 'steps' or kind == 'list') and items then
    k.steps, k.items = n, items
    k.label = ('%s (%d)'):format(PARAM_KIND_LABEL[kind], n)
  end
  PARAM_KIND[key] = k
  return k
end

-- Sets (or, with kind = nil, clears) the correction for a parameter and files what REAPER said about it.
function param_set_override(tr, fxi, r, kind)
  if not PARAM_OVR then param_ovr_load() end
  local plug = param_fx_key(tr, fxi)
  local key = plug .. '\t' .. (r.pname or '')
  if kind then
    local guess = param_kind(tr, fxi, r).guess
    local f = param_facts(tr, fxi, r.idx)
    PARAM_OVR[key] = { kind = kind, line = table.concat({
      plug, r.pname or '', kind, guess, tostring(f.min), tostring(f.max), tostring(f.step),
      tostring(f.toggle), f.t0 or '', f.t1 or '' }, '\t') }
  else
    PARAM_OVR[key] = nil
  end
  PARAM_KIND[r.guid .. ':' .. r.idx .. ':' .. (r.pname or '')] = nil
  param_ovr_save()
end

---------------------------------------------------------------- the parameter window (Edit mode)
--
-- A tree of the rack: the rack, its FX, and under each FX every parameter. Click selects, Cmd/Ctrl-click
-- adds to the selection, Shift-click selects a stretch. "Add to Performance" and "Remove from
-- Performance" work on the selection; selecting an FX means all of its parameters.

function param_picker_open(tr)
  PARAM_PICK = { tr = tr, filter = '', sel = {}, anchor = nil, order = {} }
end

-- the parameters of an FX node or of one parameter, as { guid, idx, name }
function param_pick_targets(P, fxs)
  local out, seen = {}, {}
  local function add(fx, p)
    local key = fx.guid .. ':' .. p
    if not seen[key] then seen[key] = true; out[#out + 1] = { guid = fx.guid, idx = p, name = fx.names[p + 1] } end
  end
  for _, fx in ipairs(fxs) do
    if P.sel['P:' .. fx.guid] then
      for p = 0, #fx.names - 1 do add(fx, p) end
    end
    for p = 0, #fx.names - 1 do
      if P.sel['p:' .. fx.guid .. ':' .. p] then add(fx, p) end
    end
  end
  return out
end

function param_pick_apply(P, fxs, adding)
  params_apply(P.tr, param_pick_targets(P, fxs), adding)
end

-- adds (or removes) parameters, { guid, idx, name } each, to the rack's Performance
function params_apply(tr, targets, adding)
  if #targets == 0 then return end
  local gm = fx_guid_map(tr)
  local rows, have = {}, {}
  for _, r in ipairs(params_read(tr)) do
    rows[#rows + 1] = r
    have[r.guid .. ':' .. r.idx] = #rows
  end
  if adding then
    for _, t in ipairs(targets) do
      if not have[t.guid .. ':' .. t.idx] and gm[t.guid] then
        -- the value it has now is remembered as its default (REAPER doesn't say what the plug-in's own is)
        local def = reaper.TrackFX_GetParamNormalized(tr, gm[t.guid], t.idx)
        rows[#rows + 1] = { guid = t.guid, idx = t.idx, pname = t.name, def = def }
      end
    end
  else
    local drop = {}
    for _, t in ipairs(targets) do drop[t.guid .. ':' .. t.idx] = true end
    local kept = {}
    for _, r in ipairs(rows) do
      if not drop[r.guid .. ':' .. r.idx] then kept[#kept + 1] = r end
    end
    rows = kept
  end
  with_undo(adding and 'Add parameters to Performance' or 'Remove parameters from Performance',
            function() params_write(tr, rows) end)
end

-- a check box, drawn (the font may not have a check mark): x, y = top left, h = its size; on = ticked,
-- part = some but not all (a dash)
function draw_check(dl, x, y, h, col, on, part)
  ig.DrawList_AddRect(dl, x, y, x + h, y + h, col, 3, 0, 1.5)
  if on then
    ig.DrawList_AddLine(dl, x + h * 0.22, y + h * 0.52, x + h * 0.42, y + h * 0.74, col, 2)
    ig.DrawList_AddLine(dl, x + h * 0.42, y + h * 0.74, x + h * 0.8, y + h * 0.26, col, 2)
  elseif part then
    ig.DrawList_AddLine(dl, x + h * 0.25, y + h * 0.5, x + h * 0.75, y + h * 0.5, col, 2)
  end
end

-- the plug-in's name without its type ("VST3: Foo (Dev)" -> "Foo (Dev)") and the type
function fx_name_type(name)
  local t, rest = name:match('^(%w+):%s*(.*)$')
  if t then return rest, t end
  return name, nil
end

-- the right-hand section: pick and set up the control of the selected parameter(s)
function draw_param_control_panel(P, fxs, gm, targets)
  local tr = P.tr
  if #targets == 0 then
    ig.TextDisabled(ctx, 'Select a parameter to choose\nits control.')
    return
  end
  local first = targets[1]
  local fxi = gm[first.guid]
  local fxname = ''
  for _, fx in ipairs(fxs) do if fx.guid == first.guid then fxname = fx.name end end
  if #targets == 1 then
    ig.Text(ctx, first.name)
    ig.TextDisabled(ctx, (fx_name_type(fxname)))
  else
    ig.Text(ctx, ('%d parameters selected'):format(#targets))
    ig.TextDisabled(ctx, 'The choice applies to all of them.')
  end
  if not fxi then return end
  local r1 = { guid = first.guid, idx = first.idx, pname = first.name }
  local k = param_kind(tr, fxi, r1)
  ig.Separator(ctx)
  ig.Text(ctx, 'Control')
  for _, o in ipairs(PARAM_CONTROL_OPTS) do
    local on = #targets == 1 and ((o[1] == nil and not k.overridden) or (o[1] ~= nil and k.overridden and k.kind == o[1]))
    local label = o[2] .. ((o[1] == nil and #targets == 1) and (' (now: ' .. PARAM_KIND_LABEL[k.guess] .. ')') or '')
    if ig.RadioButton(ctx, label .. '##ctl' .. tostring(o[1]), on) then
      for _, t in ipairs(targets) do
        local f = gm[t.guid]
        if f then param_set_override(tr, f, { guid = t.guid, idx = t.idx, pname = t.name }, o[1]) end
      end
    end
  end
  ig.TextDisabled(ctx, 'Your choice is added to the training data.')
  if #targets ~= 1 then return end

  -- how this row behaves (saved with the project: only for a parameter that is in the Performance)
  local row = params_find(tr, first.guid, first.idx)
  ig.Separator(ctx)
  ig.Text(ctx, 'This row')
  if not row then
    ig.TextDisabled(ctx, 'Put the parameter in the Performance\nto set these.')
  else
    local inv = row.inv == true
    local rv, v = ig.Checkbox(ctx, 'Invert (turns the other way)', inv)
    if rv then params_update(tr, first.guid, first.idx, { inv = v }) end
    local has_def = row.def ~= nil
    local rv2, v2 = ig.Checkbox(ctx, 'Default mark', has_def)
    if rv2 then
      params_update(tr, first.guid, first.idx, { def = v2 and reaper.TrackFX_GetParamNormalized(tr, fxi, first.idx) or false })
    end
    if has_def then
      ig.TextDisabled(ctx, 'Put it at:')
      local at = { { 'Now', nil }, { 'Minimum', 0 }, { 'Middle', 0.5 }, { 'Maximum', 1 } }
      for i, a_ in ipairs(at) do
        if i > 1 then ig.SameLine(ctx) end
        if ig.SmallButton(ctx, a_[1] .. '##defat' .. i) then
          params_update(tr, first.guid, first.idx,
                        { def = a_[2] or reaper.TrackFX_GetParamNormalized(tr, fxi, first.idx) })
        end
      end
    end
  end

  -- a preview of the control, and what REAPER says about the parameter
  ig.Separator(ctx)
  local norm = reaper.TrackFX_GetParamNormalized(tr, fxi, first.idx)
  local px, py = ig.GetCursorScreenPos(ctx)
  local dl = ig.GetWindowDrawList(ctx)
  local body = ig.GetStyleColor(ctx, ig.Col_FrameBg())
  local ring = ig.GetStyleColor(ctx, ig.Col_Text())
  local cx, cy, r = px + 36, py + 34, 20
  if k.kind == 'toggle' then
    ig.DrawList_AddCircleFilled(dl, cx, cy, r, body, 0)
    ig.DrawList_AddCircle(dl, cx, cy, r, ring, 0, 2)
    if norm > 0.5 then ig.DrawList_AddCircleFilled(dl, cx, cy, r - 6, T.chk_dot, 0) end
  elseif k.kind == 'list' then
    ig.DrawList_AddCircleFilled(dl, cx, cy, r, body, 0)
    ig.DrawList_AddCircle(dl, cx, cy, r, ring, 0, 2)
    ig.DrawList_AddTriangleFilled(dl, cx - 6, cy - 3.5, cx + 6, cy - 3.5, cx, cy + 4, ring)
  else
    local inv = row and row.inv
    local pm = nil
    if k.marks then pm = {}; for i, m in ipairs(k.marks) do pm[i] = inv and 1 - m or m end end
    local pd = row and row.def and (inv and 1 - row.def or row.def)
    draw_encoder('pv', cx, cy, r, inv and 1 - norm or norm, { body = body, col = ring, ptr = T.dots, s = 1, static = true,
                 style = k.kind == 'band' and 'band' or 'line', steps = k.steps, marks = pm, def = pd })
  end
  ig.Dummy(ctx, 1, 76)
  local f = param_facts(tr, fxi, first.idx)
  local _, now = reaper.TrackFX_GetFormattedParamValue(tr, fxi, first.idx)
  ig.TextDisabled(ctx, ('Now: %s'):format(now or ''))
  ig.TextDisabled(ctx, ('At the minimum: %s'):format(f.t0 or ''))
  ig.TextDisabled(ctx, ('At the maximum: %s'):format(f.t1 or ''))
  ig.TextDisabled(ctx, ('Range: %s to %s, step %s'):format(tostring(f.min), tostring(f.max), tostring(f.step)))
  ig.TextDisabled(ctx, ('REAPER says toggle: %s'):format(f.toggle and 'yes' or 'no'))
end

function draw_param_picker()
  local P = PARAM_PICK
  if not P then return end
  if not valid(P.tr) or is_locked() then PARAM_PICK = nil; return end
  local tr = P.tr
  local vis, open = begin_window('parampick', 'Performance parameters###parampick', 760, 560, true)
  if vis then
    -- the rack's FX and the names of their parameters, read once per FX
    local fxs = {}
    for _, it in ipairs(chain_info(tr).list) do
      local g = reaper.TrackFX_GetFXGUID(tr, it.fx)
      local f = P.cache and P.cache[g]
      if not f or f.fx ~= it.fx or f.name ~= it.name then
        local names = {}
        for p = 0, reaper.TrackFX_GetNumParams(tr, it.fx) - 1 do
          local _, nm = reaper.TrackFX_GetParamName(tr, it.fx, p, '')
          names[p + 1] = nm
        end
        f = { guid = g, fx = it.fx, name = it.name, names = names }
        P.cache = P.cache or {}
        P.cache[g] = f
      end
      fxs[#fxs + 1] = f
    end

    ig.SetNextItemWidth(ctx, -1)
    local rv, ftxt = ig.InputTextWithHint(ctx, '##pf', 'Search parameters', P.filter)
    if rv then P.filter = ftxt end
    local low = P.filter:lower()

    local have = {}
    for _, r in ipairs(params_read(tr)) do have[r.guid .. ':' .. r.idx] = true end
    local gm = fx_guid_map(tr)
    local lh = ig.GetTextLineHeightWithSpacing(ctx)
    local TXT = ig.GetStyleColor(ctx, ig.Col_Text())
    local order = {}
    local box = lh - 6                                   -- the check boxes
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

    local avail_w, avail_h = ig.GetContentRegionAvail(ctx)
    local foot = ig.GetFrameHeightWithSpacing(ctx) + 4
    if ig.BeginChild(ctx, 'pptree', avail_w * 0.62, avail_h - foot) then
      local rname = track_name(tr)
      ig.SetNextItemOpen(ctx, true, ig.Cond_Once())
      if ig.TreeNode(ctx, rname .. '##rack') then
        if #fxs == 0 then ig.TextDisabled(ctx, 'This rack has no FX yet.') end
        for _, fx in ipairs(fxs) do
          local pname, ptype = fx_name_type(fx.name)
          local pkey = 'P:' .. fx.guid
          local n_have = 0
          for p = 0, #fx.names - 1 do if have[fx.guid .. ':' .. p] then n_have = n_have + 1 end end
          if low ~= '' then ig.SetNextItemOpen(ctx, true, ig.Cond_Always()) end
          local flags = ig.TreeNodeFlags_OpenOnArrow() | ig.TreeNodeFlags_SpanAvailWidth()
          if P.sel[pkey] then flags = flags | ig.TreeNodeFlags_Selected() end
          order[#order + 1] = pkey
          local opened = ig.TreeNodeEx(ctx, pkey, '', flags)
          local x1, y1 = ig.GetItemRectMin(ctx)
          local lx = x1 + ig.GetTreeNodeToLabelSpacing(ctx)
          if ig.IsItemClicked(ctx, 0) and not ig.IsItemToggledOpen(ctx) then
            if mx >= lx and mx <= lx + box + 4 then
              -- the check box: every parameter of the FX in or out
              local all = {}
              for p = 0, #fx.names - 1 do all[#all + 1] = { guid = fx.guid, idx = p, name = fx.names[p + 1] } end
              params_apply(tr, all, n_have < #fx.names)
            else
              click(pkey, has_mod('shift'), has_mod('ctrl'))
            end
          end
          -- the label, drawn over the node: a check box, the name, then (TYPE) in its color
          local dl = ig.GetWindowDrawList(ctx)
          draw_check(dl, lx, y1 + 2, box, TXT, n_have == #fx.names and n_have > 0, n_have > 0)
          local tx = lx + box + 8
          ig.DrawList_AddText(dl, tx, y1, TXT, pname)
          local nx = tx + ig.CalcTextSize(ctx, pname) + 6
          if ptype then
            local ttxt = '(' .. ptype .. ')'
            ig.DrawList_AddText(dl, nx, y1, type_color(ptype), ttxt)
            nx = nx + ig.CalcTextSize(ctx, ttxt) + 8
          end
          ig.DrawList_AddText(dl, nx, y1, T.dim, ('%d of %d in the Performance'):format(n_have, #fx.names))
          if opened then
            local fxi = gm[fx.guid]
            for p = 0, #fx.names - 1 do
              local nm = fx.names[p + 1]
              if low == '' or nm:lower():find(low, 1, true) then
                local key = 'p:' .. fx.guid .. ':' .. p
                order[#order + 1] = key
                if ig.IsRectVisible(ctx, 1, lh) then
                  local selected = P.sel[key] == true
                  local clicked = ig.Selectable(ctx, '##' .. key, selected, 0, 0, lh - 2)
                  local ix, iy = ig.GetItemRectMin(ctx)
                  local iw = ig.GetItemRectSize(ctx)
                  local inn = have[fx.guid .. ':' .. p]
                  if clicked then
                    if mx >= ix and mx <= ix + box + 8 then   -- the check box: this parameter in or out
                      params_apply(tr, { { guid = fx.guid, idx = p, name = nm } }, not inn)
                    else
                      click(key, has_mod('shift'), has_mod('ctrl'))
                    end
                  end
                  local dl2 = ig.GetWindowDrawList(ctx)
                  draw_check(dl2, ix + 4, iy + 2, box, TXT, inn)
                  ig.DrawList_AddText(dl2, ix + box + 12, iy, TXT, fit_text(nm, iw * 0.45 - box))
                  -- the kind of value and its value now
                  local kind = param_kind(tr, fxi, { guid = fx.guid, idx = p, pname = nm })
                  local _, txt = reaper.TrackFX_GetFormattedParamValue(tr, fxi, p)
                  local right = ('%s:  %s'):format(kind.label, txt or '')
                  ig.DrawList_AddText(dl2, ix + iw * 0.5, iy, T.dim, fit_text(right, iw * 0.5 - 6))
                else
                  ig.Dummy(ctx, 1, lh)
                end
              end
            end
            ig.TreePop(ctx)
          end
        end
        ig.TreePop(ctx)
      end
      ig.EndChild(ctx)
    end
    P.order = order

    -- the right-hand section: the control of what is selected
    ig.SameLine(ctx)
    if ig.BeginChild(ctx, 'ppctl', 0, avail_h - foot) then
      draw_param_control_panel(P, fxs, gm, param_pick_targets(P, fxs))
      ig.EndChild(ctx)
    end

    local any = next(P.sel) ~= nil
    if not any and ig.BeginDisabled then ig.BeginDisabled(ctx, true) end
    if ig.Button(ctx, 'Add to Performance') then param_pick_apply(P, fxs, true) end
    ig.SameLine(ctx)
    if ig.Button(ctx, 'Remove from Performance') then param_pick_apply(P, fxs, false) end
    if not any and ig.EndDisabled then ig.EndDisabled(ctx) end
    ig.SameLine(ctx)
    ig.TextDisabled(ctx, ('%d selected'):format((function() local c = 0 for _ in pairs(P.sel) do c = c + 1 end return c end)()))
    ig.End(ctx)
  end
  if not open then PARAM_PICK = nil end
end
