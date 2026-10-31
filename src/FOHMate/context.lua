-- FOHMate/context.lua: fonts and the ImGui context.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

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

