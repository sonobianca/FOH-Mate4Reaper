-- FOHMate/scan.lua: the latency scan.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------- the scan

SCAN = { active = false }

function write_file(path, text, mode)
  local f = io.open(path, mode or 'w')
  if f then f:write(text); f:close() end
end

function scan_log(line)
  write_file(SCAN_LOG, line .. '\n', 'a')
end

function start_scan(list)
  if SCAN.active or #list == 0 then return end
  if S.mode ~= 'edit' then
    request_confirm('Switch to Edit mode to scan FX for latency.', function() end, 'OK', 'scan_edit_mode')
    return
  end
  reaper.RecursiveCreateDirectory(LATDB_DIR, 0)
  -- each scan adds to the log, so a scan resumed after a crash keeps the first part
  write_file(SCAN_LOG, ('\nFOH-Mate %s latency scan, %s, %d FX\n'):format(VERSION, os.date('%Y-%m-%d %H:%M'), #list), 'a')
  local n = reaper.CountTracks(0)
  reaper.PreventUIRefresh(1)
  reaper.InsertTrackAtIndex(n, false)
  local tr = reaper.GetTrack(0, n)
  reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', 'FOHMate latency scan (temporary)', true)
  -- silent without being muted (no master send, no outputs), so the FX really run
  reaper.SetMediaTrackInfo_Value(tr, 'B_MAINSEND', 0)
  reaper.SetMediaTrackInfo_Value(tr, 'B_SHOWINTCP', 0)
  reaper.SetMediaTrackInfo_Value(tr, 'B_SHOWINMIXER', 0)
  reaper.PreventUIRefresh(-1)
  SCAN = { active = true, list = list, i = 0, tr = tr, phase = 'next', cur = nil,
           found = 0, failed = 0, measured = 0 }
  -- the list and the position are kept on disk, so a crash or a quit can be continued
  local lines = {}
  for _, it in ipairs(list) do lines[#lines + 1] = it.name .. '\t' .. (it.ident or '') end
  write_file(SCAN_TODO, table.concat(lines, '\n') .. '\n')
  write_file(SCAN_POS, '0')
  RESUME = nil
end

function finish_scan(cancelled)
  if SCAN.tr and valid(SCAN.tr) then reaper.DeleteTrack(SCAN.tr) end
  os.remove(SCAN_MARK)
  os.remove(SCAN_TODO)                 -- done, or stopped on purpose: nothing to continue
  os.remove(SCAN_POS)
  latdb_save()
  local msg = cancelled and 'Latency scan stopped' or 'Latency scan done'
  local summary = ('%s: %d measured, %d with latency, %d could not load.')
                  :format(msg, SCAN.measured, SCAN.found, SCAN.failed)
  scan_log(summary)
  SCAN = { active = false, last = summary, last_t = reaper.time_precise() }
end

function scan_failed(item, why)
  local k = latdb_key(item.name)
  local e = LATDB.by[k] or { name = item.name, lat = 0, max = 0, allowed = false }
  e.src = 'failed'
  LATDB.by[k] = e
  latdb_touch()
  latdb_append(item.name)
  SCAN.failed = SCAN.failed + 1
  scan_log(item.name .. '\t' .. why)
end

-- One FX at a time, in three steps, one per frame or more:
--   next : show its name (so the window says which FX is loading, even if it hangs)
--   load : load it (with a marker file on disk while it loads)
--   wait : give it a moment to settle, read its latency, remove it
function scan_step()
  if not SCAN.active then return end
  if not valid(SCAN.tr) then finish_scan(true) return end
  local now = reaper.time_precise()

  if SCAN.phase == 'next' then
    if SCAN.rest_until and now < SCAN.rest_until then return end
    SCAN.i = SCAN.i + 1
    SCAN.cur = SCAN.list[SCAN.i]
    if not SCAN.cur then finish_scan(false) return end
    SCAN.phase = 'load'
    return

  elseif SCAN.phase == 'load' then
    local item = SCAN.cur
    write_file(SCAN_MARK, SCAN.i .. '\t' .. item.name)
    local idx = reaper.TrackFX_AddByName(SCAN.tr, item.ident or item.name, false, -1)
    if idx < 0 and item.ident then idx = reaper.TrackFX_AddByName(SCAN.tr, item.name, false, -1) end
    os.remove(SCAN_MARK)
    if idx < 0 then
      scan_failed(item, 'could not load')
      SCAN.rest_until = now + CFG.scan_pause
      SCAN.phase = 'next'
      write_file(SCAN_POS, tostring(SCAN.i))
    else
      reaper.TrackFX_Show(SCAN.tr, idx, 2)       -- never leave a window open: no floating window,
      reaper.TrackFX_Show(SCAN.tr, idx, 0)       -- no FX chain window
      -- Audio Units can take longer to report their latency once loaded
      SCAN.wait_until = now + (item.name:match('^AUi?:') and 0.8 or 0.25)
      SCAN.phase = 'wait'
    end
    return

  elseif SCAN.phase == 'wait' then
    if now < SCAN.wait_until then return end
    local item = SCAN.cur
    local n = reaper.TrackFX_GetCount(SCAN.tr)
    if n > 0 then
      local ok, s = reaper.TrackFX_GetNamedConfigParm(SCAN.tr, 0, 'pdc')
      local lat = (ok and tonumber(s)) or 0
      local ok2, c = reaper.TrackFX_GetNamedConfigParm(SCAN.tr, 0, 'chain_pdc_reporting')
      lat = math.max(lat, (ok2 and tonumber(c)) or 0)
      -- Audio Units can be slow to report: one that says 0 gets a second, later look
      if lat == 0 and item.name:match('^AUi?:') and not SCAN.second_look then
        SCAN.second_look = true
        SCAN.wait_until = now + CFG.scan_au_wait
        return
      end
      SCAN.second_look = nil
      latdb_record(item.name, lat, 'scan')
      latdb_append(item.name)
      SCAN.measured = SCAN.measured + 1
      if lat > 0 then SCAN.found = SCAN.found + 1 end
      scan_log(('%s\t%d samples'):format(item.name, lat))
      for fx = n - 1, 0, -1 do reaper.TrackFX_Delete(SCAN.tr, fx) end
    end
    -- a short pause before the next one: some plug-ins don't like being loaded right
    -- after another one was removed
    SCAN.rest_until = now + CFG.scan_pause
    SCAN.phase = 'next'
    write_file(SCAN_POS, tostring(SCAN.i))
  end
end

-- REAPER stopped during the last scan: the FX that was loading is marked
-- failed (never loaded by a scan again) and named on the next start
CRASH_FX = nil

function read_file(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local t = f:read('a')
  f:close()
  return t
end

RESUME = nil     -- the rest of a scan that did not finish: { list, crashed }

function scan_recover()
  local mark = read_file(SCAN_MARK) or ''
  local at, name = mark:match('^(%d+)\t(.*)$')
  if not at then name = mark end                     -- marker written by 0.10.2 - 0.11.5
  at = tonumber(at)
  if name == '' then
    -- marker kept by 0.10.0/0.10.1 in REAPER's settings
    name = reaper.GetExtState(EXT_SECTION, 'scan_current')
  end
  reaper.DeleteExtState(EXT_SECTION, 'scan_current', true)
  os.remove(SCAN_MARK)
  if name ~= '' then
    local e = LATDB.by[latdb_key(name)] or { name = name, lat = 0, max = 0, allowed = false }
    e.src = 'failed'
    LATDB.by[latdb_key(name)] = e
    latdb_save()
    scan_log(name .. '\tREAPER stopped while loading it')
    CRASH_FX = name
  end
  -- an interrupted scan: what is left after the crash, or after where it got to
  local todo = read_file(SCAN_TODO)
  if todo then
    local list = {}
    for line in todo:gmatch('[^\n]+') do
      local n, id = line:match('^(.-)\t(.*)$')
      if n then list[#list + 1] = { name = n, ident = (id ~= '' and id or nil) } end
    end
    local from = (at or tonumber(read_file(SCAN_POS) or '') or 0) + 1
    local rest = {}
    for i = from, #list do
      local e = LATDB.by[latdb_key(list[i].name)]
      if not (e and e.src == 'failed') then rest[#rest + 1] = list[i] end
    end
    if #rest > 0 then RESUME = { list = rest, crashed = CRASH_FX ~= nil } end
    os.remove(SCAN_TODO)
    os.remove(SCAN_POS)
  end
  -- a scan track left behind by a crash
  for i = reaper.CountTracks(0) - 1, 0, -1 do
    local t = reaper.GetTrack(0, i)
    local tn = track_name(t)
    if tn == 'FOHMate latency scan (temporary)' or tn == 'LiveRack latency scan (temporary)' then reaper.DeleteTrack(t) end
  end
end

-- shown once, on the first frame after a crash during a scan
function announce_crash()
  if confirm or not (CRASH_FX or RESUME) then return end
  local name, resume = CRASH_FX, RESUME
  CRASH_FX, RESUME = nil, nil        -- asked once
  NEWFX.asked = true          -- no scan offer on top of this
  local text
  if name then
    text = ('REAPER stopped during the last latency scan, while loading:\n\n    %s\n\n'
      .. 'It is marked "failed" in FX > Plugin list... Scans leave it out\n'
      .. '(Latency > Retry failed FX... tries again). The scan, in order, is in:\n%s\n\n'):format(name, SCAN_LOG)
  else
    text = 'The last latency scan did not finish.\n\n'
  end
  if resume then
    request_confirm(text .. ('Continue that scan where it stopped (%d FX left)?'):format(#resume.list),
      function() start_scan(resume.list) end, 'Continue')
  else
    request_confirm(text .. 'Scan the FX that are not measured yet?', function() ask_scan('new') end, 'Scan the rest')
  end
end

-- which: 'new' (not measured yet), 'all' (everything but failed FX), 'failed' (only those)
function ask_scan(which)
  local list
  if which == 'all' then list = all_effects(false)
  elseif which == 'failed' then list = all_effects(true)
  else list = unscanned_fx() end
  if #list == 0 then
    request_confirm(which == 'failed' and 'No FX is marked as failed.'
                    or 'Every installed effect is already in the latency list.', function() end, 'OK',
                    'scan_nothing')
    return
  end
  local what = (which == 'all' and 'Rescan all %d effects (failed ones left out)')
            or (which == 'failed' and 'Retry the %d effects that failed before (some may crash REAPER again)')
            or 'Scan %d effects'
  request_confirm((what .. ' for latency?\n\nEach one is loaded once on a hidden track and removed. Audio may glitch\n'
    .. 'while it runs, so do it when nothing is live. Save your project first: a plug-in\n'
    .. 'that crashes on load can take REAPER down (it is skipped next time, and the scan\n'
    .. 'can be continued where it stopped).'):format(#list), function() start_scan(list) end, 'Scan')
end

-- progress window
function draw_scan_window()
  if not SCAN.active then return end
  ig.SetNextWindowSize(ctx, 420, 0, ig.Cond_Always())
  local vis = ig.Begin(ctx, 'FX latency scan###lr_scan', nil, ig.WindowFlags_NoCollapse())
  if vis then
    local n = #SCAN.list
    ig.Text(ctx, ('Measuring %d of %d'):format(math.min(SCAN.i, n), n))
    local cur = SCAN.cur
    type_text(cur and ((SCAN.phase == 'wait' and 'Reading: ' or 'Loading: ') .. fit_text(cur.name, 330)) or '')
    ig.ProgressBar(ctx, n > 0 and (SCAN.i - 1) / n or 0, -1, 0)
    ig.TextDisabled(ctx, ('%d with latency so far, %d could not load'):format(SCAN.found, SCAN.failed))
    if ig.Button(ctx, 'Stop', 100, 0) then finish_scan(true) end
    ig.End(ctx)
  end
end

