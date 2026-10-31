-- FOHMate/jsfx.lua: the meter JSFX.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- JSFX

JSFX_SRC = [==[
desc:FOHMate Meter
// Part of FOH-Mate (FOHMate.lua) - do not remove. Audio passes through untouched.
// Copyright (C) 2026 Bianca and the FOH-Mate contributors. GPL-3.0-or-later (see LICENSE).
// Stage 0 = chain input, stage 1 = chain output (before the track fader).
// Publishes peak and RMS data to the panel through gmem.
options:gmem=FOHMateMeters

slider1:0<0,255,1>-Slot (managed by FOH-Mate)
slider2:0<0,1,1>-Stage (0 input, 1 output)

in_pin:Left
in_pin:Right
out_pin:Left
out_pin:Right

@init
bpl = 0;
bpr = 0;
ssl = 0;
ssr = 0;
cnt = 0;
base = 0;

@slider
base = floor(slider1) * 16 + floor(slider2) * 8;

@block
gmem[base + 0] = max(gmem[base + 0], bpl);
gmem[base + 1] = max(gmem[base + 1], bpr);
gmem[base + 2] += 1;
gmem[base + 3] += ssl;
gmem[base + 4] += ssr;
gmem[base + 5] += cnt;
bpl = 0;
bpr = 0;
ssl = 0;
ssr = 0;
cnt = 0;

@sample
a = abs(spl0);
a > bpl ? bpl = a;
b = abs(spl1);
b > bpr ? bpr = b;
ssl += spl0 * spl0;
ssr += spl1 * spl1;
cnt += 1;
]==]

function install_jsfx()
  local dir  = reaper.GetResourcePath() .. '/Effects/FOHMate'
  local path = dir .. '/FOHMate_Meter'
  local f = io.open(path, 'r')
  if f then
    local cur = f:read('*a')
    f:close()
    if cur == JSFX_SRC then return true end
  end
  reaper.RecursiveCreateDirectory(dir, 0)
  f = io.open(path, 'w')
  if not f then return false end
  f:write(JSFX_SRC)
  f:close()
  return true
end

