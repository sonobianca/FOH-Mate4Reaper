-- FOHMate/colors.lua: theme and colors.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

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

