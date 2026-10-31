-- FOHMate/fx_list.lua: FX latency list, favorite and recently used FX, new FX detection.
-- Part of FOH-Mate, loaded by FOHMate.lua (see the note there).
--
-- Copyright (C) 2026 Bianca and the FOH-Mate contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

---------------------------------------------------------------- FX latency list
--
-- One list for the whole computer, shared by every project:
--   <REAPER resource folder>/Data/FOHMate/fx_latency.txt
-- one line per FX (by its full name, e.g. "VST3: Pro-L 2 (FabFilter)"):
--   name <tab> latency <tab> highest seen <tab> allowed (0/1) <tab> source <tab> sample rate
-- source: "scan" (measured by the scan), "seen" (reported while in a rack),
-- "failed" (could not be loaded, or REAPER stopped while loading it).
-- FX marked "Allow latency" are flagged here, so they stay allowed everywhere.

LATDB_DIR  = reaper.GetResourcePath() .. '/Data/FOHMate'
LATDB_FILE = LATDB_DIR .. '/fx_latency.txt'
LATDB      = { by = {}, rev = 0, dirty = false, save_t = 0 }
SCAN_MARK  = LATDB_DIR .. '/scan_loading.txt'   -- the FX being loaded right now (survives a crash)
SCAN_LOG   = LATDB_DIR .. '/last_scan_log.txt'  -- every FX of the last scan, in order, with its result
SCAN_TODO  = LATDB_DIR .. '/scan_pending.txt'   -- the FX of a scan in progress, to continue it after a crash
SCAN_POS   = LATDB_DIR .. '/scan_position.txt'  -- how far that scan got

-- The latency list, favorites and recently used FX saved in Data/LiveRack (before the rename to
-- FOH-Mate) are copied once to Data/FOHMate. The old folder is left as it is.
function migrate_data_folder()
  if reaper.GetExtState(EXT_SECTION, 'migrated_data') == '1' then return end
  local old_dir = reaper.GetResourcePath() .. '/Data/LiveRack'
  for _, name in ipairs({ 'fx_latency.txt', 'favorites.txt', 'recent_fx.txt' }) do
    local from = io.open(old_dir .. '/' .. name, 'rb')
    if from then
      local data = from:read('*a')
      from:close()
      local to_path = LATDB_DIR .. '/' .. name
      local probe = io.open(to_path, 'rb')
      if probe then
        probe:close()
      else
        reaper.RecursiveCreateDirectory(LATDB_DIR, 0)
        local to = io.open(to_path, 'wb')
        if to then to:write(data); to:close() end
      end
    end
  end
  reaper.SetExtState(EXT_SECTION, 'migrated_data', '1', true)
end

function latdb_key(name) return (name or ''):lower() end

-- shows the data folder in Finder / Explorer
function open_data_folder()
  reaper.RecursiveCreateDirectory(LATDB_DIR, 0)
  local osn = reaper.GetOS() or ''
  if osn:find('Win') then
    reaper.ExecProcess('cmd.exe /C start "" "' .. LATDB_DIR:gsub('/', '\\') .. '"', -1)
  elseif osn:find('OSX') or osn:find('mac') then
    reaper.ExecProcess('/usr/bin/open "' .. LATDB_DIR .. '"', -1)
  else
    reaper.ExecProcess('xdg-open "' .. LATDB_DIR .. '"', -1)
  end
end

function latdb_load()
  LATDB.by = {}
  local f = io.open(LATDB_FILE, 'r')
  if not f then return end
  for line in f:lines() do
    local name, lat, mx, ok, src, sr = line:match('^([^\t]+)\t(%-?%d+)\t(%-?%d+)\t([01])\t([^\t]*)\t?(%d*)')
    if name then
      LATDB.by[latdb_key(name)] = { name = name, lat = tonumber(lat), max = tonumber(mx),
                                    allowed = ok == '1', src = src, sr = tonumber(sr) }
    end
  end
  f:close()
  LATDB.rev = LATDB.rev + 1
end

function latdb_save()
  reaper.RecursiveCreateDirectory(LATDB_DIR, 0)
  local f = io.open(LATDB_FILE, 'w')
  if not f then return end
  local keys = {}
  for k in pairs(LATDB.by) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do f:write(latdb_line(LATDB.by[k])) end
  f:close()
  LATDB.dirty = false
end

function latdb_line(e)
  local nm = e.name:gsub('[\t\r\n]', ' ')
  return ('%s\t%d\t%d\t%s\t%s\t%d\n'):format(nm, e.lat or 0, e.max or e.lat or 0,
         e.allowed and '1' or '0', e.src or 'seen', math.floor(e.sr or 0))
end

-- one entry added at the end of the file right away (the scan uses this, so a
-- crash never loses what was already measured). When the file is read, the
-- last line for an FX wins; the next full save tidies the file up.
function latdb_append(name)
  local e = LATDB.by[latdb_key(name)]
  if not e then return end
  reaper.RecursiveCreateDirectory(LATDB_DIR, 0)
  local f = io.open(LATDB_FILE, 'a')
  if f then f:write(latdb_line(e)); f:close() end
end

-- written at most a few seconds after the first unsaved change
function latdb_touch()
  if not LATDB.dirty then LATDB.save_t = reaper.time_precise() + 3 end
  LATDB.dirty = true
  LATDB.rev = LATDB.rev + 1
end

function latdb_tick(now)
  if LATDB.dirty and now >= LATDB.save_t then latdb_save() end
end

function latdb_get(name) return LATDB.by[latdb_key(name)] end

-- records what an FX reports (scan, or while it sits in a rack)
function latdb_record(name, lat, src)
  if not name or name == '' then return end
  local k = latdb_key(name)
  local e = LATDB.by[k]
  local sr = sample_rate()
  if not e then
    e = { name = name, lat = lat, max = lat, allowed = false, src = src, sr = sr }
    LATDB.by[k] = e
    latdb_touch()
    return
  end
  if e.lat ~= lat or (lat > (e.max or 0)) or (src == 'scan' and e.src ~= 'scan') or e.src == 'failed' then
    e.lat = lat
    e.max = math.max(e.max or 0, lat)
    if src == 'scan' or e.src ~= 'scan' then e.src = src end
    e.sr = sr
    latdb_touch()
  end
end

function latdb_allowed(name)
  local e = latdb_get(name)
  return e ~= nil and e.allowed
end

function latdb_set_allowed(name, on)
  local k = latdb_key(name)
  local e = LATDB.by[k]
  if not e then
    e = { name = name, lat = 0, max = 0, src = 'seen', sr = sample_rate() }
    LATDB.by[k] = e
  end
  e.allowed = on and true or false
  latdb_touch()
end

-- an FX is "over" on its own when its known latency is above the limit
function latdb_over(e)
  return e and not e.allowed and e.src ~= 'failed' and (latency_counted(e.name, e.lat or 0)) > LAT_LIMIT
end

---------------------------------------- one plugin in several formats
--
-- Some formats report 0 latency where another format of the same plugin reports
-- the real figure (often AU vs VST3). With Latency > Count every format at its
-- highest latency, an FX counts with the highest figure any of its formats
-- reports. Only FOH-Mate's alerts, limits and figures use it: REAPER's own
-- compensation is untouched.
--
-- Formats are matched on name and developer, leaving out the type ("VST3: "), a
-- channel count at the end ("(4ch)", "(4->8ch)", "(2 out)"), spaces, and the
-- developer's name inside the plugin's name:
--   "VST3: FabFilter Pro-Q 3 (FabFilter) (4ch)" and "AU: Pro-Q 3 (FabFilter)"
--   both give "pro-q3|fabfilter". JSFX exist in one format only and are left out.

function fx_family_key(name)
  local s = (name or ''):lower()
  if s:find('^js:') then return nil end
  s = s:gsub('^[^:]*:%s*', '')
  s = s:gsub('%s*%(%d+%->%d+ch%)$', '')
  s = s:gsub('%s*%(%d+ch%)$', '')
  s = s:gsub('%s*%(%d+ out%)$', '')
  local base, dev = s:match('^(.-)%s*%(([^()]*)%)$')
  if not base then base, dev = s, '' end
  base = base:gsub('%s', '')
  dev = dev:gsub('%s', '')
  if dev ~= '' then
    local short = base:gsub(dev:gsub('%p', '%%%0'), '')
    if short ~= '' then base = short end     -- a plugin named just like its developer keeps its name
  end
  return base .. '|' .. dev
end

FAMILY = { rev = -1, by = {} }   -- [family key] = { n = formats measured, lat = highest, from = its name }

-- rebuilt only when the latency list changed
function fx_families()
  if FAMILY.rev ~= LATDB.rev then
    local by = {}
    for _, e in pairs(LATDB.by) do
      local k = e.src ~= 'failed' and fx_family_key(e.name)
      if k then
        local f = by[k]
        if not f then f = { n = 0, lat = -1 }; by[k] = f end
        f.n = f.n + 1
        if (e.lat or 0) > f.lat then f.lat, f.from = e.lat or 0, e.name end
      end
    end
    FAMILY.by, FAMILY.rev = by, LATDB.rev
  end
  return FAMILY.by
end

-- the latency FOH-Mate counts for an FX whose own figure is "own". With the
-- option on and another format reporting more, that figure, plus the name of
-- the format it comes from (nil when it is the FX's own figure).
function latency_counted(name, own)
  if not S.lat_formats then return own end
  local k = fx_family_key(name)
  local f = k and fx_families()[k]
  if f and f.n > 1 and f.lat > own then return f.lat, f.from end
  return own
end

-- "  (estimated from VST3)"
function estimate_note(from)
  return from and ('  (estimated from %s)'):format(from:match('^([^:]+):') or from) or ''
end

-- the other installed formats of an FX ("AU: ...", "VST: ..."), for the Allowed warning
function other_formats(name)
  if not fx_db then fx_db = build_fx_db() end
  local k, out = fx_family_key(name), {}
  if not k then return out end
  for _, it in ipairs(fx_db.all) do
    if it.name ~= name and fx_family_key(it.name) == k then out[#out + 1] = it.name end
  end
  return out
end

-- "Allowed" belongs to one format only: with the option on and other formats
-- installed, say so first (that note can be hidden)
function confirm_allowed_one_format(name, go)
  local others = S.lat_formats and other_formats(name) or {}
  if #others == 0 then go(); return end
  request_confirm(('Allow latency for this format only:\n  %s\n\nIts other formats still count their latency:\n  %s')
                  :format(name, table.concat(others, '\n  ')), go, 'Allow', 'allowed_one_format')
end

---------------------------------------- favorite and recently used FX
--
-- Both are plain lists of full FX names, one per line, in the data folder:
--   favorites.txt   FX starred in FX > Plugin list...
--   recent_fx.txt   FX picked from an FX menu, newest first

FAV_FILE    = LATDB_DIR .. '/favorites.txt'
RECENT_FILE = LATDB_DIR .. '/recent_fx.txt'
RECENT_KEEP = 30           -- how many are remembered (Settings decides how many are shown)
FAVS   = { by = {}, rev = 0 }   -- [lowercase name] = name
RECENT = {}                     -- names, newest first

function read_lines(path)
  local out = {}
  local f = io.open(path, 'r')
  if not f then return out end
  for line in f:lines() do
    line = line:gsub('\r$', '')
    if line ~= '' then out[#out + 1] = line end
  end
  f:close()
  return out
end

function write_lines(path, lines)
  reaper.RecursiveCreateDirectory(LATDB_DIR, 0)
  local f = io.open(path, 'w')
  if not f then return end
  for _, l in ipairs(lines) do f:write(l, '\n') end
  f:close()
end

function favs_load()
  FAVS.by = {}
  for _, n in ipairs(read_lines(FAV_FILE)) do FAVS.by[n:lower()] = n end
  FAVS.rev = FAVS.rev + 1
end

function is_fav(name) return FAVS.by[(name or ''):lower()] ~= nil end

function set_fav(name, on)
  FAVS.by[name:lower()] = on and name or nil
  FAVS.rev = FAVS.rev + 1
  local t = {}
  for _, n in pairs(FAVS.by) do t[#t + 1] = n end
  table.sort(t, function(a, b) return a:lower() < b:lower() end)
  write_lines(FAV_FILE, t)
end

function recent_load()
  RECENT = read_lines(RECENT_FILE)
end

function recent_add(name)
  if not name or name == '' then return end
  local t = { name }
  for _, n in ipairs(RECENT) do
    if n:lower() ~= name:lower() and #t < RECENT_KEEP then t[#t + 1] = n end
  end
  RECENT = t
  write_lines(RECENT_FILE, RECENT)
end

-- installed FX for a list of names (FX no longer installed are skipped)
function items_for(names, max, hide_over)
  if not fx_db then fx_db = build_fx_db() end
  local out = {}
  for _, n in ipairs(names) do
    local it = fx_db.by_name[n:lower()]
    if it and not (hide_over and latdb_over(latdb_get(it.name))) then
      out[#out + 1] = it
      if max and #out >= max then break end
    end
  end
  return out
end

function fav_items()
  local names = {}
  for _, n in pairs(FAVS.by) do names[#names + 1] = n end
  local items = items_for(names, nil, S.hide_over)
  sort_items(items)
  return items
end

---------------------------------------- new FX detection

function is_instrument_type(t)
  return t ~= nil and t:sub(-1) == 'i' and t ~= 'JS'
end

-- installed effects (instruments left out) that are not in the list yet
function unscanned_fx()
  local out = {}
  local i = 0
  while true do
    local ok, name, ident = reaper.EnumInstalledFX(i)
    if not ok then break end
    i = i + 1
    local t = name:match('^([%w_]+):')
    if not is_instrument_type(t) and not name:find(METER_NAME, 1, true) then
      local e = LATDB.by[latdb_key(name)]
      if not e or (e.src ~= 'scan' and e.src ~= 'failed') then
        out[#out + 1] = { name = name, ident = ident }
      end
    end
  end
  return out
end

-- every installed effect, for a full rescan
-- every installed effect, for a full rescan; FX that failed (could not load, or
-- stopped REAPER) are left out unless only_failed asks for exactly those
function all_effects(only_failed)
  local out = {}
  local i = 0
  while true do
    local ok, name, ident = reaper.EnumInstalledFX(i)
    if not ok then break end
    i = i + 1
    local t = name:match('^([%w_]+):')
    if not is_instrument_type(t) and not name:find(METER_NAME, 1, true) then
      local e = LATDB.by[latdb_key(name)]
      local failed = e ~= nil and e.src == 'failed'
      if failed == (only_failed == true) then out[#out + 1] = { name = name, ident = ident } end
    end
  end
  return out
end

NEWFX = { t = -math.huge, asked = false }

-- at start and once a minute: offer to scan FX that appeared since the last scan
function check_new_fx(now)
  if RESUME then return end          -- an interrupted scan is offered first
  if not S.ask_scan or SCAN.active or NEWFX.asked or S.mode ~= 'edit' then return end
  if now - NEWFX.t < 300 then return end
  NEWFX.t = now
  local list = unscanned_fx()
  if #list == 0 then return end
  NEWFX.asked = true            -- once per session; Options > Scan new FX is always there
  local first = next(LATDB.by) == nil
  local text = (first
      and 'FOH-Mate can measure the latency of your %d installed effects, so the\nlatency watchdog knows them before you load them.\n\n'
      or  '%d new effects were found since the last latency scan.\n\n')
      .. 'Each one is loaded once on a hidden track and removed. Audio may glitch while\n'
      .. 'it runs, so do it when nothing is live. Save your project first: a plug-in that\n'
      .. 'crashes on load can take REAPER down (it is skipped next time).\n\nScan now?'
  request_confirm(text:format(#list), function() start_scan(list) end, 'Scan', 'new_fx')
end

