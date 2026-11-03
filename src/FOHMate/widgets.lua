-- FOHMate/widgets.lua: system stats, text boxes, meters, audio device notes.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- system stats (status bar)

-- REAPER has no script function for its Performance Meter, so CPU and memory
-- come from the operating system (macOS and Linux). Latency is reported by REAPER.
-- On macOS the numbers are fetched in the background and read back from a
-- small file, so the panel never waits for them.
STATS = {
  kind = nil, pid = nil, ncpu = 1, memtotal = nil,
  cpu = nil, ram_pct = nil, ram_mb = nil,
  seq = -1, launch_n = 0, launch_t = -math.huge, sample_t = {},
  prev_cpu = nil, prev_t = nil,
  latency = nil, latency_tip = nil, lat_t = -math.huge,
}

function init_stats()
  local osn = reaper.GetOS() or ''
  if osn:find('OSX') or osn:find('mac') then
    local ok, out = pcall(reaper.ExecProcess,
      '/bin/sh -c "echo $PPID; sysctl -n hw.memsize; sysctl -n hw.ncpu"', 3000)
    if ok and out then
      local nums = {}
      for n in out:gmatch('%d+') do nums[#nums + 1] = tonumber(n) end
      if #nums >= 4 then
        STATS.kind, STATS.pid, STATS.memtotal, STATS.ncpu = 'mac', nums[2], nums[3], math.max(1, nums[4])
      end
    end
  elseif osn:find('Linux') then
    local f = io.open('/proc/meminfo', 'r')
    if f then
      local kb = f:read('*a'):match('MemTotal:%s+(%d+)')
      f:close()
      STATS.memtotal = kb and tonumber(kb) * 1024 or nil
    end
    local n = 0
    f = io.open('/proc/cpuinfo', 'r')
    if f then
      for line in f:lines() do if line:match('^processor') then n = n + 1 end end
      f:close()
    end
    STATS.ncpu = math.max(1, n)
    STATS.kind = 'linux'
  end
end

function update_stats(cpu_secs, rss_kb, t)
  if STATS.prev_t and t - STATS.prev_t > 0.2 then
    local pct = (cpu_secs - STATS.prev_cpu) / (t - STATS.prev_t) / STATS.ncpu * 100
    STATS.cpu = clamp(pct, 0, 100)
  end
  STATS.prev_cpu, STATS.prev_t = cpu_secs, t
  STATS.ram_mb = rss_kb / 1024
  if STATS.memtotal then
    STATS.ram_pct = clamp(rss_kb * 1024 / STATS.memtotal * 100, 0, 100)
  end
end

function poll_latency(now)
  if now - STATS.lat_t < STATS_EVERY then return end
  STATS.lat_t = now
  local ok, inl, outl = pcall(reaper.GetInputOutputLatency)
  local ok2, _, sr = pcall(reaper.GetAudioDeviceInfo, 'SRATE', '')
  local ok3, _, bs = pcall(reaper.GetAudioDeviceInfo, 'BSIZE', '')
  sr = ok2 and tonumber(sr) or nil
  bs = ok3 and tonumber(bs) or nil
  if ok and inl and outl and sr and sr > 0 then
    STATS.lat_in  = math.floor(inl / sr * 1000 + 0.5)
    STATS.lat_out = math.floor(outl / sr * 1000 + 0.5)
    STATS.latency_tip = ('Input / output latency reported by REAPER%s'):format(
      (bs and sr) and ('\n%d samples at %d Hz'):format(bs, sr) or '')
  else
    STATS.lat_in, STATS.lat_out, STATS.latency_tip = nil, nil, nil
  end
end

function poll_stats(now)
  poll_latency(now)
  if STATS.kind == 'mac' then
    local f = io.open(STATS_FILE, 'r')
    if f then
      local line = f:read('*l')
      f:close()
      local seq, t, rss = (line or ''):match('^(%d+)%s+(%S+)%s+(%d+)')
      seq = tonumber(seq)
      if seq and seq ~= STATS.seq then
        STATS.seq = seq
        local secs = 0
        for p in t:gmatch('[^:]+') do secs = secs * 60 + (tonumber(p) or 0) end
        update_stats(secs, tonumber(rss), STATS.sample_t[seq] or now)
        STATS.sample_t[seq] = nil
      end
    end
    if now - STATS.launch_t >= STATS_EVERY then
      STATS.launch_t = now
      STATS.launch_n = STATS.launch_n + 1
      STATS.sample_t[STATS.launch_n] = now
      STATS.sample_t[STATS.launch_n - 20] = nil
      reaper.ExecProcess(('/bin/sh -c "echo %d $(ps -o time=,rss= -p %d) > %s.tmp; mv %s.tmp %s"')
        :format(STATS.launch_n, STATS.pid, STATS_FILE, STATS_FILE, STATS_FILE), -1)
    end
  elseif STATS.kind == 'linux' then
    if now - STATS.launch_t >= STATS_EVERY then
      STATS.launch_t = now
      local f = io.open('/proc/self/stat', 'r')
      local g = io.open('/proc/self/statm', 'r')
      if f and g then
        local s = f:read('*l') or ''
        local rest = s:match('%) (.*)$') or ''
        local tk = {}
        for w in rest:gmatch('%S+') do tk[#tk + 1] = w end
        local secs = ((tonumber(tk[12]) or 0) + (tonumber(tk[13]) or 0)) / 100
        local pages = tonumber((g:read('*l') or ''):match('^%d+%s+(%d+)')) or 0
        update_stats(secs, pages * 4, now)
      end
      if f then f:close() end
      if g then g:close() end
    end
  end
end

---------------------------------------------------------------- text boxes

-- Returns the new text only when the user commits (Enter or click away).
function text_edit(key, current, width)
  local st = edit_state[key]
  if not st then st = { text = current, active = false }; edit_state[key] = st end

  -- one blank frame makes ImGui drop the active text box (used after a reset)
  if st.skip then
    st.skip = false
    st.active = false
    ig.Dummy(ctx, width, ig.GetFrameHeight(ctx))
    return nil
  end

  local shown = st.active and st.text or current
  ig.SetNextItemWidth(ctx, width)
  local rv, new = ig.InputText(ctx, '##' .. key, shown, ig.InputTextFlags_AutoSelectAll())
  if rv then st.text = new end
  local active = ig.IsItemActive(ctx)
  if active and not st.active then st.text = shown end
  local committed = nil
  if ig.IsItemDeactivatedAfterEdit(ctx) then committed = new end
  st.active = active
  return committed
end

function parse_db(s)
  s = s:lower():gsub(',', '.')
  if s:find('inf') then return -math.huge end
  return tonumber(s:match('[-+]?%d*%.?%d+'))
end

function apply_level(tr, text)
  local v = parse_db(text)
  if not v then return end
  if v <= LEVEL_MIN then
    reaper.SetMediaTrackInfo_Value(tr, 'D_VOL', 0.0)
  else
    reaper.SetMediaTrackInfo_Value(tr, 'D_VOL', 10.0 ^ (clamp(v, LEVEL_MIN, LEVEL_MAX) / 20.0))
  end
end

function rename_rack(tr, text)
  text = text:match('^%s*(.-)%s*$')
  if text == raw_name(tr) then return end
  reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', (text == '') and PREFIX or (PREFIX .. ' ' .. text), true)
end

---------------------------------------------------------------- meters

function new_meter_state()
  return {
    lv_in    = { -150, -150 }, lv_out   = { -150, -150 },
    hold_in  = { -150, -150 }, hold_out = { -150, -150 },
    clip_in  = { false, false }, clip_out = { false, false },
    cnt = -1, stale = 0,
  }
end

-- one click on any meter resets every peak hold line and clip marker
function reset_markers()
  for _, m in pairs(meters) do
    m.hold_in  = { -150, -150 }; m.hold_out = { -150, -150 }
    m.clip_in  = { false, false }; m.clip_out = { false, false }
  end
end

function mark(hold, clip, i, db)
  if db > hold[i] then hold[i] = db end
  if db >= CLIP_DB then clip[i] = true end
end

-- reads (and clears) one stage of one rack from gmem
function read_stage(base)
  local pl  = reaper.gmem_read(base)
  local pr  = reaper.gmem_read(base + 1)
  local cnt = reaper.gmem_read(base + 2)
  local sl  = reaper.gmem_read(base + 3)
  local sr  = reaper.gmem_read(base + 4)
  local n   = reaper.gmem_read(base + 5)
  reaper.gmem_write(base, 0)
  reaper.gmem_write(base + 1, 0)
  reaper.gmem_write(base + 3, 0)
  reaper.gmem_write(base + 4, 0)
  reaper.gmem_write(base + 5, 0)
  return pl, pr, cnt, sl, sr, n
end

function draw_bar(dl, x, y1, y2, w, level, hold, clipped)
  ig.DrawList_AddRectFilled(dl, x, y1, x + w, y2, T.meter_bg, 2)
  for _, z in ipairs(ZONES) do
    if level > z[1] then
      local top = math.min(level, z[2])
      local ya = y2 - meter_frac(top) * (y2 - y1)
      local yb = y2 - meter_frac(z[1]) * (y2 - y1)
      ig.DrawList_AddRectFilled(dl, x, ya, x + w, yb, z[3])
    end
  end
  if hold > METER_MIN then
    local yh = y2 - meter_frac(hold) * (y2 - y1)
    ig.DrawList_AddLine(dl, x, yh, x + w, yh, clipped and 0xFF4040FF or T.hold, 2)
  end
end

-- a thin horizontal meter (Performance mode, Show mode): one bar for a mono rack, two for a
-- stereo one, with the clip marker at one end. Normal: fills left to right, marker at the right
-- end. flip: mirrored (fills right to left, marker at the left end). a = 0..1 fades it out.
function draw_hbar(dl, x1, x2, yc, lv, hold, clip, mono, a, flip)
  local function fade(col) return (col & 0xFFFFFF00) | math.floor((col & 0xFF) * a) end
  local cw = 4
  local b1, b2, c1, c2                         -- the bar's two ends, the clip marker's two ends
  if flip then b1, b2, c1, c2 = x2, x1 + cw + 2, x1, x1 + cw
  else b1, b2, c1, c2 = x1, x2 - cw - 2, x2 - cw, x2 end
  local w = b2 - b1                            -- negative when flipped: fractions run from b1 toward b2
  local function rect(xa, xb, y, bh, col, r)
    ig.DrawList_AddRectFilled(dl, math.min(xa, xb), y, math.max(xa, xb), y + bh, col, r)
  end
  local bars
  if mono then
    bars = { { math.max(lv[1], lv[2]), math.max(hold[1], hold[2]), clip[1] or clip[2] } }
  else
    bars = { { lv[1], hold[1], clip[1] }, { lv[2], hold[2], clip[2] } }
  end
  local bh = mono and 5 or 3
  local y = math.floor(yc - (#bars * bh + (#bars - 1)) / 2)
  for _, b in ipairs(bars) do
    rect(b1, b2, y, bh, fade(T.meter_bg), 1)
    for _, z in ipairs(ZONES) do
      if b[1] > z[1] then
        rect(b1 + meter_frac(z[1]) * w, b1 + meter_frac(math.min(b[1], z[2])) * w, y, bh, fade(z[3]))
      end
    end
    if b[2] > METER_MIN then
      local xh = b1 + meter_frac(b[2]) * w
      ig.DrawList_AddLine(dl, xh, y, xh, y + bh, fade(b[3] and 0xFF4040FF or T.hold), 2)
    end
    rect(c1, c2, y, bh, fade(b[3] and 0xFF2020FF or T.clip_off), 1)
    y = y + bh + 1
  end
end

function draw_meter(dl, x, y1, y2, lv, hold, clip, id, mono)
  local by1 = y1 + CLIP_H + 2
  if mono then
    -- mono rack: one bar (both channels carry the same signal)
    ig.DrawList_AddRectFilled(dl, x, y1, x + METER_W, y1 + CLIP_H,
                              (clip[1] or clip[2]) and 0xFF2020FF or T.clip_off, 2)
    draw_bar(dl, x, by1, y2, METER_W, math.max(lv[1], lv[2]), math.max(hold[1], hold[2]), clip[1] or clip[2])
  else
    local bw = (METER_W - 2) / 2
    ig.DrawList_AddRectFilled(dl, x, y1, x + bw, y1 + CLIP_H,
                              clip[1] and 0xFF2020FF or T.clip_off, 2)
    ig.DrawList_AddRectFilled(dl, x + bw + 2, y1, x + METER_W, y1 + CLIP_H,
                              clip[2] and 0xFF2020FF or T.clip_off, 2)
    draw_bar(dl, x, by1, y2, bw, lv[1], hold[1], clip[1])
    draw_bar(dl, x + bw + 2, by1, y2, bw, lv[2], hold[2], clip[2])
  end

  ig.SetCursorScreenPos(ctx, x, y1)
  if ig.InvisibleButton(ctx, id, METER_W, y2 - y1) then reset_markers() end
  if ig.IsItemHovered(ctx) then
    ig.SetTooltip(ctx, 'Click to reset peak hold and clip markers (all racks)')
  end
end

---------------------------------------------------------------- audio device notes

-- Top of the input/output menus: which device REAPER uses and how many channels
-- it offers. Returns the channel count; when it is 0 the menu says why instead
-- of showing empty lists (device not running, closed, or channels disabled).
function audio_device_header(is_out)
  local n = is_out and reaper.GetNumAudioOutputs() or reaper.GetNumAudioInputs()
  local running = (not reaper.Audio_IsRunning) or reaper.Audio_IsRunning() ~= 0
  local ok, dev = reaper.GetAudioDeviceInfo(is_out and 'IDENT_OUT' or 'IDENT_IN')
  if not ok or not dev or dev == '' then dev = 'unknown device' end
  if running and n > 0 then
    ig.TextDisabled(ctx, ('%s  -  %d %s'):format(dev, n, is_out and 'outputs' or 'inputs'))
  else
    ig.PushStyleColor(ctx, ig.Col_Text(), ALERT_RED)
    if not running then
      ig.Text(ctx, 'The audio device is not running.')
    else
      ig.Text(ctx, ('%s reports no %s.'):format(dev, is_out and 'outputs' or 'inputs'))
    end
    ig.PopStyleColor(ctx)
    ig.TextDisabled(ctx, 'Check REAPER Preferences > Audio > Device: the device,\n'
                      .. 'its ' .. (is_out and 'output' or 'input') .. ' channel range, and that it is not in use elsewhere.')
    if ig.MenuItem(ctx, 'Open REAPER Preferences...') then reaper.Main_OnCommand(40016, 0) end
  end
  ig.Separator(ctx)
  return (running and n) or 0
end


---------------------------------------------------------------- vertical text

-- ReaImGui can't rotate text, so the values of Performance mode rows are drawn with a small
-- stroke font (cell 5 x 8 units, y down): only the characters a value needs.
VFONT = {
  -- digits
  ['0'] = { { 1,0, 4,0, 5,1, 5,7, 4,8, 1,8, 0,7, 0,1, 1,0 } },
  ['1'] = { { 1,1.5, 3,0, 3,8 }, { 1,8, 5,8 } },
  ['2'] = { { 0,1, 1,0, 4,0, 5,1, 5,3, 0,8, 5,8 } },
  ['3'] = { { 0,0, 5,0, 2.5,3.5, 4,3.5, 5,4.5, 5,7, 4,8, 1,8, 0,7 } },
  ['4'] = { { 4,8, 4,0, 0,5.5, 5.5,5.5 } },
  ['5'] = { { 5,0, 0,0, 0,3.5, 4,3.5, 5,4.5, 5,7, 4,8, 1,8, 0,7 } },
  ['6'] = { { 5,1, 4,0, 1,0, 0,1, 0,7, 1,8, 4,8, 5,7, 5,4.5, 4,3.5, 0,3.5 } },
  ['7'] = { { 0,0, 5,0, 2,8 } },
  ['8'] = { { 1,0, 4,0, 5,1, 5,3, 4,4, 1,4, 0,3, 0,1, 1,0 }, { 1,4, 4,4, 5,5, 5,7, 4,8, 1,8, 0,7, 0,5, 1,4 } },
  ['9'] = { { 0,7, 1,8, 4,8, 5,7, 5,1, 4,0, 1,0, 0,1, 0,3.5, 1,4.5, 5,4.5 } },
  -- capitals
  ['A'] = { { 0,8, 2.5,0, 5,8 }, { 1,5.5, 4,5.5 } },
  ['B'] = { { 0,8, 0,0, 3.5,0, 5,1, 5,3, 3.5,4, 0,4 }, { 3.5,4, 5,5, 5,7, 3.5,8, 0,8 } },
  ['C'] = { { 5,1.5, 4,0, 1,0, 0,1, 0,7, 1,8, 4,8, 5,6.5 } },
  ['D'] = { { 0,0, 0,8, 3,8, 5,6, 5,2, 3,0, 0,0 } },
  ['E'] = { { 5,0, 0,0, 0,8, 5,8 }, { 0,4, 3.5,4 } },
  ['F'] = { { 5,0, 0,0, 0,8 }, { 0,4, 3.5,4 } },
  ['G'] = { { 5,1.5, 4,0, 1,0, 0,1, 0,7, 1,8, 4,8, 5,7, 5,4, 3,4 } },
  ['H'] = { { 0,0, 0,8 }, { 5,0, 5,8 }, { 0,4, 5,4 } },
  ['I'] = { { 0,0, 3,0 }, { 1.5,0, 1.5,8 }, { 0,8, 3,8 } },
  ['J'] = { { 5,0, 5,7, 4,8, 1,8, 0,7 } },
  ['K'] = { { 0,0, 0,8 }, { 5,0, 0,4.5 }, { 1.8,3.2, 5,8 } },
  ['L'] = { { 0,0, 0,8, 5,8 } },
  ['M'] = { { 0,8, 0,0, 3.5,5, 7,0, 7,8 } },
  ['N'] = { { 0,8, 0,0, 5,8, 5,0 } },
  ['O'] = { { 1,0, 4,0, 5,1, 5,7, 4,8, 1,8, 0,7, 0,1, 1,0 } },
  ['P'] = { { 0,8, 0,0, 4,0, 5,1, 5,3, 4,4, 0,4 } },
  ['Q'] = { { 1,0, 4,0, 5,1, 5,7, 4,8, 1,8, 0,7, 0,1, 1,0 }, { 3.2,5.8, 5.2,8.6 } },
  ['R'] = { { 0,8, 0,0, 4,0, 5,1, 5,3, 4,4, 0,4 }, { 2.5,4, 5,8 } },
  ['S'] = { { 5,1, 4,0, 1,0, 0,1, 0,3, 1,4, 4,4, 5,5, 5,7, 4,8, 1,8, 0,7 } },
  ['T'] = { { 0,0, 5,0 }, { 2.5,0, 2.5,8 } },
  ['U'] = { { 0,0, 0,7, 1,8, 4,8, 5,7, 5,0 } },
  ['V'] = { { 0,0, 2.5,8, 5,0 } },
  ['W'] = { { 0,0, 1.8,8, 3.5,2.5, 5.2,8, 7,0 } },
  ['X'] = { { 0,0, 5,8 }, { 5,0, 0,8 } },
  ['Y'] = { { 0,0, 2.5,4 }, { 5,0, 2.5,4, 2.5,8 } },
  ['Z'] = { { 0,0, 5,0, 0,8, 5,8 } },
  -- small letters (x-height 5, from y = 3 to the baseline at 8; ascenders reach 0, descenders 10)
  ['a'] = { { 5,3, 5,8 }, { 5,4, 4,3, 1,3, 0,4, 0,7, 1,8, 4,8, 5,7 } },
  ['b'] = { { 0,0, 0,8 }, { 0,4, 1,3, 4,3, 5,4, 5,7, 4,8, 1,8, 0,7 } },
  ['c'] = { { 5,4, 4,3, 1,3, 0,4, 0,7, 1,8, 4,8, 5,7 } },
  ['d'] = { { 5,0, 5,8 }, { 5,4, 4,3, 1,3, 0,4, 0,7, 1,8, 4,8, 5,7 } },
  ['e'] = { { 0,5.5, 5,5.5, 5,4, 4,3, 1,3, 0,4, 0,7, 1,8, 4,8, 5,7 } },
  ['f'] = { { 4,0.5, 3.5,0, 2,0, 1,1, 1,8 }, { 0,3.5, 3.5,3.5 } },
  ['g'] = { { 5,3, 5,9, 4,10, 1,10, 0,9 }, { 5,4, 4,3, 1,3, 0,4, 0,7, 1,8, 4,8, 5,7 } },
  ['h'] = { { 0,0, 0,8 }, { 0,4, 1,3, 4,3, 5,4, 5,8 } },
  ['i'] = { { 1,0.2, 1,1 }, { 1,3, 1,8 } },
  ['j'] = { { 2,0.2, 2,1 }, { 2,3, 2,9, 1,10, 0,9.5 } },
  ['k'] = { { 0,0, 0,8 }, { 4.5,3, 0,6 }, { 1.8,5, 4.5,8 } },
  ['l'] = { { 1,0, 1,8 } },
  ['m'] = { { 0,3, 0,8 }, { 0,4, 1,3, 3,3, 3.5,4, 3.5,8 }, { 3.5,4, 4.5,3, 6,3, 7,4, 7,8 } },
  ['n'] = { { 0,3, 0,8 }, { 0,4, 1,3, 4,3, 5,4, 5,8 } },
  ['o'] = { { 1,3, 4,3, 5,4, 5,7, 4,8, 1,8, 0,7, 0,4, 1,3 } },
  ['p'] = { { 0,3, 0,10 }, { 0,4, 1,3, 4,3, 5,4, 5,7, 4,8, 1,8, 0,7 } },
  ['q'] = { { 5,3, 5,10 }, { 5,4, 4,3, 1,3, 0,4, 0,7, 1,8, 4,8, 5,7 } },
  ['r'] = { { 0,3, 0,8 }, { 0,5, 1,3.5, 2.5,3, 4,3 } },
  ['s'] = { { 5,3.8, 4,3, 1,3, 0,4, 1,5.2, 4,5.8, 5,7, 4,8, 1,8, 0,7.2 } },
  ['t'] = { { 1.5,1, 1.5,7, 2.5,8, 4,8 }, { 0,3, 4,3 } },
  ['u'] = { { 0,3, 0,7, 1,8, 4,8, 5,7 }, { 5,3, 5,8 } },
  ['v'] = { { 0,3, 2.5,8, 5,3 } },
  ['w'] = { { 0,3, 1.8,8, 3.5,4, 5.2,8, 7,3 } },
  ['x'] = { { 0,3, 5,8 }, { 5,3, 0,8 } },
  ['y'] = { { 0,3, 2.5,8 }, { 5,3, 2.5,8, 1.5,10, 0.5,10 } },
  ['z'] = { { 0,3, 5,3, 0,8, 5,8 } },
  -- punctuation and signs
  ['.'] = { { 1,7, 1,8 } },
  [','] = { { 1,7, 1,8, 0.2,9.5 } },
  [':'] = { { 1,3, 1,4 }, { 1,7, 1,8 } },
  [';'] = { { 1,3, 1,4 }, { 1,7, 1,8, 0.2,9.5 } },
  ['!'] = { { 1,0, 1,5.5 }, { 1,7.3, 1,8 } },
  ['?'] = { { 0,1.5, 1,0, 4,0, 5,1, 5,3, 2.5,4.5, 2.5,5.5 }, { 2.5,7.2, 2.5,8 } },
  ['('] = { { 3,0, 1,2, 1,6, 3,8 } },
  [')'] = { { 0,0, 2,2, 2,6, 0,8 } },
  ['['] = { { 3,0, 0,0, 0,8, 3,8 } },
  [']'] = { { 0,0, 3,0, 3,8, 0,8 } },
  ['-'] = { { 0.5,4, 4.5,4 } },
  ['+'] = { { 0.5,4, 4.5,4 }, { 2.5,2, 2.5,6 } },
  ['='] = { { 0,3, 5,3 }, { 0,5.5, 5,5.5 } },
  ['*'] = { { 2.5,1, 2.5,5 }, { 0.6,2, 4.4,4 }, { 4.4,2, 0.6,4 } },
  ['/'] = { { 0,8, 4,0 } },
  ['\\'] = { { 0,0, 4,8 } },
  ['_'] = { { 0,9, 5,9 } },
  ["'"] = { { 1,0, 1,2.5 } },
  ['"'] = { { 0.5,0, 0.5,2.5 }, { 3,0, 3,2.5 } },
  ['<'] = { { 4.5,1, 0.5,4.5, 4.5,8 } },
  ['>'] = { { 0.5,1, 4.5,4.5, 0.5,8 } },
  ['#'] = { { 1.5,0, 1,8 }, { 4,0, 3.5,8 }, { 0,2.5, 5,2.5 }, { 0,5.5, 5,5.5 } },
  ['%'] = { { 0,0, 1.5,0, 1.5,1.5, 0,1.5, 0,0 }, { 3.5,6.5, 5,6.5, 5,8, 3.5,8, 3.5,6.5 }, { 0.3,8, 4.7,0 } },
  ['&'] = { { 5,8, 1.5,3.5, 1.5,1, 2.5,0, 3.5,1, 3.5,2.5, 0,5.5, 0,7, 1,8, 3,8, 5,5.5 } },
  ['$'] = { { 5,1, 4,0, 1,0, 0,1, 0,3, 1,4, 4,4, 5,5, 5,7, 4,8, 1,8, 0,7 }, { 2.5,-1, 2.5,9 } },
  ['@'] = { { 3.5,5.5, 2,5.5, 2,3.5, 3.5,3.5, 3.5,6, 4.5,6, 4.5,2, 3.7,1, 1.2,1, 0,2.5, 0,6.5, 1,8, 4,8 } },
  ['~'] = { { 0,5, 1.2,3.8, 2.5,5, 3.8,6.2, 5,5 } },
  ['^'] = { { 0,3, 2.5,0, 5,3 } },
  ['|'] = { { 1,0, 1,9 } },
}

-- the width of a character's cell where it is not 5 (the next character starts 2 units after it)
VWIDTH = { ['I'] = 3, ['M'] = 7, ['W'] = 7, ['m'] = 7, ['w'] = 7, ['f'] = 4, ['r'] = 4, ['t'] = 4, ['i'] = 2, ['j'] = 2,
           ['l'] = 2, ['.'] = 2, [','] = 2, [':'] = 2, [';'] = 2, ['!'] = 2, ['('] = 3, [')'] = 3, ['['] = 3, [']'] = 3,
           ['/'] = 4, ['\\'] = 4, ["'"] = 2, ['"'] = 4, ['|'] = 2 }

function vfont_advance(ch)
  if ch == ' ' then return 3 end
  return (VWIDTH[ch] or 5) + 2
end

-- A character's strokes as runs that can each be drawn in one call (a polyline): a stroke is cut
-- where it turns sharply (more than 100 degrees, the tips of V, W, M...), where a joined line would
-- grow a spike, so those corners look as before. Found once per character.
VRUNS = {}
function vfont_runs(ch)
  local runs = VRUNS[ch]
  if runs then return runs end
  runs = {}
  for _, st in ipairs(VFONT[ch] or {}) do
    local run = { st[1], st[2] }
    for j = 3, #st, 2 do
      run[#run + 1], run[#run + 2] = st[j], st[j + 1]
      if j + 3 <= #st then
        local ax, ay = st[j] - st[j - 2], st[j + 1] - st[j - 1]
        local bx, by = st[j + 2] - st[j], st[j + 3] - st[j + 1]
        local cos = (ax * bx + ay * by) / math.sqrt((ax * ax + ay * ay) * (bx * bx + by * by))
        if cos < math.cos(math.rad(100)) then
          runs[#runs + 1] = run
          run = { st[j], st[j + 1] }
        end
      end
    end
    runs[#runs + 1] = run
  end
  VRUNS[ch] = runs
  return runs
end

-- the runs of `text` placed in the box, as point arrays for DrawList_AddPolyline
function vtext_paths(text, bx, by, bw, bh, ccw, zoom)
  local paths = {}
  local units = 0
  for i = 1, #text do units = units + vfont_advance(text:sub(i, i)) end
  units = units - 2
  local s = math.min(1.15 * zoom, (bh - 12) / units, (bw - 6) / 8)      -- a bit smaller than the box allows
  if s <= 0 then return paths end
  local len, thick = units * s, 8 * s
  local cx, cy = bx + bw / 2, by + bh / 2
  local ox, oy, dux, duy, dvx, dvy
  if ccw then
    ox, oy, dux, duy, dvx, dvy = cx - thick / 2, cy + len / 2, 0, -1, 1, 0
  else
    ox, oy, dux, duy, dvx, dvy = cx + thick / 2, cy - len / 2, 0, 1, -1, 0
  end
  local u = 0
  for i = 1, #text do
    local ch = text:sub(i, i)
    if VFONT[ch] then
      for _, run in ipairs(vfont_runs(ch)) do
        local arr = reaper.new_array(#run)
        for j = 1, #run, 2 do
          local gu, gv = u + run[j] * s, run[j + 1] * s
          arr[j], arr[j + 1] = ox + dux * gu + dvx * gv, oy + duy * gu + dvy * gv
        end
        paths[#paths + 1] = arr
      end
    end
    u = u + vfont_advance(ch) * s
  end
  return paths
end

-- Draws `text` rotated a quarter turn inside the box (bx, by, bw, bh), centered, as big as fits.
-- ccw: reads from bottom to top (a control on the left); otherwise top to bottom (control on the right).
-- memo (a table kept by the caller, optional): the placed strokes are kept there and drawn again as
-- they are while the text and the box don't change.
function draw_vtext(dl, text, bx, by, bw, bh, col, ccw, zoom, memo)
  zoom = zoom or 1
  local paths
  if memo then
    local key = text .. '|' .. bx .. '|' .. by .. '|' .. bw .. '|' .. bh .. '|' .. (ccw and 1 or 0) .. '|' .. zoom
    if memo.vkey ~= key then memo.vkey, memo.vpaths = key, vtext_paths(text, bx, by, bw, bh, ccw, zoom) end
    paths = memo.vpaths
  else
    paths = vtext_paths(text, bx, by, bw, bh, ccw, zoom)
  end
  for i = 1, #paths do ig.DrawList_AddPolyline(dl, paths[i], col, 0, 1.5 * zoom) end
end

---------------------------------------------------------------- rotary encoder, drop-down

-- Controls for the parameter rows of Performance mode, drawn by hand (ReaImGui has none). They know
-- nothing about REAPER, so another module can use them. The encoder turns from the 7:30 mark
-- (minimum) clockwise to the 4:30 mark (maximum), 270 degrees, and stops there.

ENC = {}                    -- per encoder: what the current drag started from
ENC_DEFAULT_COL = 0xFFD21EFF   -- the default value's mark: yellow
ENC_A0, ENC_A1 = math.rad(135), math.rad(405)   -- screen angles of 7:30 and 4:30 (y points down)

-- a tiny arrow just outside the circle, pointing at it (perpendicular to the circumference)
function enc_mark(dl, cx, cy, r, ang, col, s)
  local ux, uy = math.cos(ang), math.sin(ang)
  local px, py = -uy, ux
  local tip, base, hw = r + 2 * s, r + 6.5 * s, 2.6 * s
  ig.DrawList_AddTriangleFilled(dl, cx + ux * tip, cy + uy * tip,
    cx + ux * base + px * hw, cy + uy * base + py * hw,
    cx + ux * base - px * hw, cy + uy * base - py * hw, col)
end

-- How far a band reaches on each side of the top, for a width w (0..1): from nothing at the minimum to a
-- half circle (9 to 3 o'clock) in the middle of the range, a normal stereo width (100% of a 0-200%
-- width, the center of an M-S one), then on to the min and max marks (7:30 to 4:30) at the maximum.
function band_half(w)
  local half, full = math.rad(90), (ENC_A1 - ENC_A0) / 2
  local h = w <= 0.5 and half * w / 0.5 or half + (full - half) * (w - 0.5) / 0.5
  return math.max(math.rad(1.5), h)
end

-- a short line just outside the circle, perpendicular to the circumference (min, max and value marks)
function enc_tick(dl, cx, cy, r, ang, col, s)
  local ux, uy = math.cos(ang), math.sin(ang)
  ig.DrawList_AddLine(dl, cx + ux * (r + 2.5 * s), cy + uy * (r + 2.5 * s),
                      cx + ux * (r + 6.5 * s), cy + uy * (r + 6.5 * s), col, 2 * s)
end

-- o: body (fill), col (ring and min/max marks, the encoder's color), ptr (pointer or arc color),
--    s (scale), style ('line' pointer, or 'pan' for a pan or balance, or 'band' for a width: a band centered at the top, wider with the value),
--    steps (n values: stepped, with a mark per value), marks (positions 0..1 of extra marks, like a fader's), def (default position 0..1, yellow mark),
--    static (draw only, no mouse).
-- Returns the new position 0..1 when the user changed it.
function draw_encoder(id, cx, cy, r, norm, o)
  local s = o.s or 1
  local dl = ig.GetWindowDrawList(ctx)
  local changed
  local hover = false
  if not o.static then
    local R = r + 6 * s
    ig.SetCursorScreenPos(ctx, cx - R, cy - R)
    ig.InvisibleButton(ctx, id, 2 * R, 2 * R)
    hover = ig.IsItemHovered(ctx)
    local st = ENC[id]
    if not st then st = {}; ENC[id] = st end
    if ig.IsItemActivated(ctx) then st.raw, st.a = norm, nil end
    if hover and ig.IsMouseDoubleClicked(ctx, 0) and o.def then
      changed, st.raw = o.def, o.def
    elseif ig.IsItemActive(ctx) then
      local mx, my = ig.GetMousePos(ctx)
      local raw = st.raw or norm
      if CFG.enc_mode == 'circle' then
        local a = math.atan(my - cy, mx - cx)
        if st.a then
          local d = a - st.a
          if d > math.pi then d = d - 2 * math.pi elseif d < -math.pi then d = d + 2 * math.pi end
          raw = raw + d / (ENC_A1 - ENC_A0)
        end
        st.a = a
      else
        local _, dy = ig.GetMouseDelta(ctx)
        local k = 0.006 / (1 + math.abs(mx - cx) / (40 * s))   -- farther to the side = finer
        if has_mod('shift') then k = k * 0.25 end
        raw = raw - dy * k
      end
      raw = math.max(0, math.min(1, raw))
      st.raw = raw
      local v = raw
      if o.steps and o.steps > 1 then v = math.floor(raw * (o.steps - 1) + 0.5) / (o.steps - 1) end
      if v ~= norm then changed = v end
    end
  end
  local v = changed or norm
  ig.DrawList_AddCircleFilled(dl, cx, cy, r, o.body, 0)
  ig.DrawList_AddCircle(dl, cx, cy, r, hover and mix(o.col, WHITE, 0.3) or o.col, 0, 2 * s)
  enc_tick(dl, cx, cy, r, ENC_A0, o.col, s)
  enc_tick(dl, cx, cy, r, ENC_A1, o.col, s)
  if o.steps and o.steps > 2 then
    for i = 1, o.steps - 2 do enc_tick(dl, cx, cy, r, ENC_A0 + (ENC_A1 - ENC_A0) * i / (o.steps - 1), o.col, 0.6 * s) end
  end
  if o.marks then
    for _, m in ipairs(o.marks) do enc_tick(dl, cx, cy, r, ENC_A0 + (ENC_A1 - ENC_A0) * m, o.col, 0.75 * s) end
  end
  if o.def or o.style == 'pan' then
    if o.style == 'band' then
      -- a band: the default is a range, so two short lines at the edges of the band it would have
      local mid = (ENC_A0 + ENC_A1) / 2
      local half = band_half(o.narrow and 1 - o.def or o.def)
      enc_tick(dl, cx, cy, r, mid - half, ENC_DEFAULT_COL, s)
      enc_tick(dl, cx, cy, r, mid + half, ENC_DEFAULT_COL, s)
    else
      enc_mark(dl, cx, cy, r, ENC_A0 + (ENC_A1 - ENC_A0) * (o.style == 'pan' and 0.5 or o.def), ENC_DEFAULT_COL, s)
    end
  end
  local ang = ENC_A0 + (ENC_A1 - ENC_A0) * v
  if o.style == 'pan' then
    -- a pan: the default mark is the center; a band runs from the top to the position, left or right
    -- (7:30 = all the way left, 4:30 = all the way right); centered, a small vertical line under the mark
    local mid = (ENC_A0 + ENC_A1) / 2
    if math.abs(v - 0.5) < 0.0025 then
      -- centered: a small vertical line where the arrow's back would be
      local py = cy - (r - 4 * s)
      ig.DrawList_AddRectFilled(dl, cx - 0.75 * s, py - 2.5 * s, cx + 0.75 * s, py + 2.5 * s, o.ptr)
    elseif math.abs(v - 0.5) < 0.05 then        -- up to 9% either side (9L to 9R on a 100L-100R pan)
      -- off center by too little for a band to show: a tiny arrow pointing left or right, smaller than
      -- the default mark, its back on the center line
      local d = ang < mid and -1 or 1
      local px, py = cx, cy - (r - 4 * s)
      -- (the points go round the same way for both directions, or the left one's soft edge falls inside it)
      ig.DrawList_AddTriangleFilled(dl, px + d * 3.5 * s, py, px, py - 2 * d * s, px, py + 2 * d * s, o.ptr)
    else
      -- from 10% on: the band, never shorter than the arrow so the switch doesn't jump
      local rb = r - 4 * s
      local a = mid + (ang < mid and -1 or 1) * math.max(math.abs(ang - mid), 3.5 * s / rb)
      ig.DrawList_PathArcTo(dl, cx, cy, rb, math.min(mid, a), math.max(mid, a))
      ig.DrawList_PathStroke(dl, o.ptr, 0, 3.5 * s)
    end
  elseif o.style == 'band' then
    -- a width: a band centered at the top, as thin as it can be at the minimum, a half circle in the
    -- middle and reaching from the minimum mark to the maximum mark at the maximum (see band_half)
    local mid, half = (ENC_A0 + ENC_A1) / 2, band_half(o.narrow and 1 - v or v)
    ig.DrawList_PathArcTo(dl, cx, cy, r - 4 * s, mid - half, mid + half)
    ig.DrawList_PathStroke(dl, o.ptr, 0, 3.5 * s)
  else
    ig.DrawList_AddLine(dl, cx + math.cos(ang) * r * 0.3, cy + math.sin(ang) * r * 0.3,
                        cx + math.cos(ang) * r * 0.85, cy + math.sin(ang) * r * 0.85, o.ptr, 3 * s)
  end
  return changed
end

-- a circle with a small arrow pointing down; a click opens a menu of the values.
-- items: { { label, norm }, ... }. Returns the norm of the one picked.
function draw_dropdown(id, cx, cy, r, norm, items, o)
  local s = o.s or 1
  local dl = ig.GetWindowDrawList(ctx)
  ig.SetCursorScreenPos(ctx, cx - r, cy - r)
  if ig.InvisibleButton(ctx, id, 2 * r, 2 * r) then ig.OpenPopup(ctx, id .. '_dd') end
  local hover = ig.IsItemHovered(ctx)
  ig.DrawList_AddCircleFilled(dl, cx, cy, r, o.body, 0)
  ig.DrawList_AddCircle(dl, cx, cy, r, hover and mix(o.col, WHITE, 0.3) or o.col, 0, 2 * s)
  local w, h = 5.5 * s, 3.5 * s
  ig.DrawList_AddTriangleFilled(dl, cx - w, cy - h, cx + w, cy - h, cx, cy + h, o.ptr)
  local picked
  if ig.BeginPopup(ctx, id .. '_dd') then
    for _, it in ipairs(items) do
      if ig.Selectable(ctx, it.label .. '##' .. it.norm, math.abs(it.norm - norm) < 1e-4) then picked = it.norm end
    end
    ig.EndPopup(ctx)
  end
  return picked
end
