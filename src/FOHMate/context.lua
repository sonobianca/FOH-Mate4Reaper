-- FOHMate/context.lua: fonts and the ImGui context.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: MIT

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

name_font, title_font, head_font, sect_font = nil, nil, nil, nil

-- Each window that docks has a context of its own: REAPER names a docker tab after the context's label
-- (the text before "##"), not after the window, so the Racks window, the Parameters (the tree) and the
-- Inspector each get their own tab. The label after "##" keeps them apart from other scripts' contexts.
-- Every drawing call uses `ctx`, the context being drawn; use_ctx() switches it, with its fonts.
CTX_LABEL_MAIN = 'Racks##FOH-Mate'
CTX_MAIN       = nil
CTX_FONTS      = {}   -- context -> its fonts (a font belongs to one context)
SUB_CTX        = {}   -- key ('tree', 'insp') -> its context, while its window is open

-- the bold fonts of the context being created (fonts are attached before its first frame)
function create_fonts()
  local f = { name = make_bold_font(NAME_FONT_SIZE) }
  f.title = new_font_api and f.name or make_bold_font(TITLE_FONT_SIZE)
  f.head  = new_font_api and f.name or make_bold_font(HEAD_FONT_SIZE)
  f.sect  = new_font_api and f.name or make_bold_font(SECT_FONT_SIZE)
  CTX_FONTS[ctx] = f
end

function use_ctx(c)
  ctx = c
  local f = CTX_FONTS[c] or {}
  name_font, title_font, head_font, sect_font = f.name, f.title, f.head, f.sect
end

function ctx_valid(c)
  if not c then return false end
  if not reaper.ImGui_ValidatePtr then return true end
  return reaper.ImGui_ValidatePtr(c, 'ImGui_Context*')
end

-- ReaImGui discards a context that does not run a frame soon after creation,
-- so the context (and its fonts) is created right before the first frame,
-- and re-created if it ever turns out to be invalid.
function create_ctx()
  if CTX_MAIN then CTX_FONTS[CTX_MAIN] = nil end
  ctx = reaper.ImGui_CreateContext(CTX_LABEL_MAIN, cfg_flags)
  CTX_MAIN = ctx
  create_fonts()
  use_ctx(ctx)
end

function ctx_is_valid()
  return ctx_valid(CTX_MAIN)
end

-- Draws fn() in the context of a docking window (key, label): made when it is first needed, made again if
-- ReaImGui dropped it (it does so a moment after its window stops being drawn: a closed window costs
-- nothing). The theme is pushed in it like in the Racks window.
function in_sub_ctx(key, label, fn)
  local c = SUB_CTX[key]
  if not ctx_valid(c) then
    if c then CTX_FONTS[c] = nil end
    local was = ctx
    ctx = reaper.ImGui_CreateContext(label, cfg_flags)
    c = ctx
    create_fonts()
    ctx = was
    SUB_CTX[key] = c
  end
  local main = ctx
  use_ctx(c)
  local nc, nv = push_theme()
  fn()
  pass_undo_keys()
  pop_theme(nc, nv)
  use_ctx(main)
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

