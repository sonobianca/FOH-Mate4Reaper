-- FOHMate/helpers.lua: helpers.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

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

