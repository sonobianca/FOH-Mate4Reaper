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

