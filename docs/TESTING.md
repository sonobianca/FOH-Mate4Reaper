# FOH-Mate: testing to do

Open items to check in REAPER, newest version first. Report by number (e.g. "3 ok, 7 fails: ...").
Done items are kept at the bottom, with what was found.
New items get the next free number (next: 69). Priorities: 64-67, then 63.

## Open

- [ ] 68. (0.11.15) The script file is now **FOHMate.lua** (no version in the name). Load it as an action
  (or point your toolbar button / shortcut to it): it runs, and the title bar shows **0.11.15**. Meters
  still move on existing racks (the meter file on disk is rewritten once at this start).
- [ ] 64. (0.11.14) **Rename**: no "Live Rack" / "LiveRack" anywhere (window titles, menus, Settings,
  alerts, tooltips, script file name). The rack window and the big title in its top bar read
  **Plugins Host** (does the longer title still fit next to the buttons?); Settings reads
  **FOH-Mate Settings**; the data folder item reads **Open the FOH-Mate data folder**.
- [ ] 65. (0.11.14) **Migration**, on the machine that ran Live Rack: start src/FOHMate.lua (0.11.14 or
  later). Colors, mode, dock position, window sizes and all Settings are as before; favorites, recently
  used FX and the latency list are there (copied to Data/FOHMate; Data/LiveRack is left untouched). On existing racks:
  bypass state, sidechain keys, stereo point and "allowed latency" FX are kept, and the old LiveRack
  meters are replaced by FOHMate ones (Effects/FOHMate). Quit and restart: nothing is copied twice.
- [ ] 66. (0.11.9) Same checks as 64 and 65 on **FOHMate_v0.11.9.lua** (the rename-only build for the
  repository; it has no favorites or recently used FX).
- [ ] 67. A fresh install (no old settings, no Data/LiveRack, no old meters) starts clean with no error.
- [ ] 51. (0.11.10) **Options > Open the FOH-Mate data folder** is there (and gone from Latency).
- [ ] 52. Help line (grey, above the status bar): hover a rack name, an FX, the on/off circle, the key
  button, In/Out, the level box, SC, BYPASS, MUTE, A/B, +: each says what clicks and keys do. Drag a
  rack, then an FX (same rack, then over another rack), pressing and releasing Cmd and Opt: the line
  follows. Nothing hovered: a general hint (Edit) or what still works (Show).
- [ ] 53. **FX > Plugin list...**: every installed FX; type column in color; latency, Allowed and
  status still right; name filter, type drop-down, Favorites and latency checkboxes, sort.
- [ ] 63. (0.11.14) On a **mono** rack (or the mono part of a mono-to-stereo rack), a plug-in with a
  stereo key input gets a **mono** key: its key menu reads *Stereo Input (summed to mono)*, a single dot
  shows next to the key button, and in REAPER's pin connector both key pins listen to the same channel.
  Make the rack stereo: the key turns stereo (two stacked dots, two channels) on its own, and back.
- [ ] 62. (0.11.13) Key dots sit in the gap between the FX name and the key button; the name button
  keeps the same width whether a key is connected or not.
- [ ] 61. (0.11.12) Plugin list: click each column header to sort by it, click again to reverse; the
  arrow shows the column and direction. Latency and Highest start biggest first; the star column puts
  favorites first. The Sort drop-down is gone.
- [ ] 60. (0.11.11) Plugin list: **Developer** column (names no longer end in "(Developer)"); developer
  drop-down with its own search field; clicking a developer in the list filters to it, again shows
  all; Sort: developer.
- [ ] 54. Plugin list: click the star to make a favorite (gold), click again to remove. Favorites stay
  after restarting REAPER.
- [ ] 55. Plugin list selection: click, Cmd-click, Shift-click (range), Select all shown, Clear.
  **Rescan selected...** and right-click > Rescan / Add to / Remove from favorites. A failed FX can be
  rescanned this way.
- [ ] 56. **+** menu (and Insert / Replace FX): **Favorites** and **Recently used** under the search
  field. Recently used lists the last 5 different FX picked, newest first; Settings > Behavior >
  Recently used FX changes the count (0 hides the menu).
- [ ] 57. Dots, on a **mono** rack: one dot above the first FX, one between each FX, one below the
  last. **Stereo** rack: two dots everywhere. **Mono in, stereo out**: one dot until the stereo point,
  which glows (color opposite to the rack's) with one dot above and two below, then two dots. Dots are
  centered on the narrower FX when one has a key button. Do they look connected, and readable in
  Daylight mode?
- [ ] 58. FX with a key connected: one dot (mono key) or two stacked dots (stereo key) between the name
  and the key button; nothing when no key is set.
- [ ] 59. **Options > Stereo pairs on odd-even channels only**: In > Stereo input, Out > Hardware out:
  stereo pair, and the key menu's Stereo Input list only 1/2, 3/4...; off again: every pair.

Clicking glitch (mouse can't click in plug-in windows or FOH-Mate menus), seen again:

- [ ] 20. Does it stop when you close the Plugins Host window? (First impression: closing Plugins Host
  and reopening everything did **not** fix it. Confirm next time.)
- [x] 21. Both the soothe3 windows and the Plugins Host window stopped taking clicks.
- [x] 22. No sidechain involved. (Mono / mono-to-stereo rack: not known.)
- [ ] 46. It felt like only **some areas of the screen** didn't take clicks: probably an invisible
  window on top. When it happens: Cmd+Shift+4 then Space, and move over a dead area: a highlighted
  frame where nothing is visible is the blocker (Esc to cancel). Mission Control (F3) shows all
  windows too. Do the dead areas match where a FOH-Mate menu or tooltip appeared earlier?
- [ ] 45. Next time, also try: can you click REAPER's own main window and its menus? If not, look for
  a hidden dialog (Cmd+\` to cycle REAPER's windows, or Mission Control): a plug-in's license /
  update window or a REAPER prompt hidden behind other windows blocks every REAPER window.
- [x] 23. No confirmation box open. Happened again in **Show mode**, with only 3 soothe3 instances
  open (no other windows).
- [ ] 44. Next time: does it affect only the soothe3 windows, or other plug-in windows too? Does it
  also happen in Edit mode? Does it go away if you switch Plugins Host to Edit and back, or click once
  inside the Plugins Host window?

## Done

- [x] 50. FX types in their own color everywhere (All FX submenus, latency list, scan window,
  confirmations, Settings).
- [x] 49. Developers > MeldaProduction: letter submenus A, B, C... (no single M).

- [x] 40. The scan log keeps the part before a crash.
- [x] 41. Rescan all leaves out FX marked failed.
- [x] 42. An interrupted scan is offered to be continued, from the right place.
- [x] 48. bx_console AMEK 9099 (VST3) goes mono on its own on mono racks (bus size 1), back to stereo
  on stereo racks; stereo point respected.
- [x] 24. Mono racks: VST3 and AU plug-ins that accept the bus size switch to mono.

- [x] 47. bx_console AMEK 9099: setting **Plug-in bus size** to 1 by hand makes it mono ("2 in 1 out"):
  FOH-Mate's request wasn't sent because the plug-in doesn't list it as supported (fixed in 0.11.7).

- [x] 43. **Retry failed FX** scanned the 3 failed FX with no crash, Cenozoix AU included: it only
  crashed when loaded in the middle of a long scan, not on its own.

- [x] 39. Pause between FX: only one crash in a full rescan (TBTECH Cenozoix Compressor AU, again; its
  VST3 loads fine and reports 4 samples). The rescan stopped there, about a third of the way through:
  fixed in 0.11.6 (see 41-42).

- [x] 37. **!! RACK** tag on top of the red frame.
- [x] 38. FX hover shows latency (also 0) when the box is on Always.
- [x] 25. Not applicable: no plug-ins with separate Mono / Stereo versions installed (no Waves).

- [x] 28-29. Rack limit / FX limit alerts work (tag position fixed in 0.11.5, see 37).
- [x] 30. FX switched off are not counted.
- [x] 31. Rack latency box modes work (FX hover for Always added in 0.11.5, see 38).
- [x] 32. Data folder opens in Finder.
- [x] 33. More AUs report latency with the extra wait (Spec Craft AU: 2048, same as VST3). One crash
  instead of four (TBTECH Cenozoix Compressor AU).
- [x] 34. No windows opened during the scan.
- [x] 35. Cmd+click on macOS.
- [x] 36. Remove every FX and other FX-changing actions: no error.
- [x] 4. FX search: no shortcut or menu problems so far.
- [x] AU vs VST3, full scan of 826 FX: 249 plug-ins installed as both; 85 pairs differ, always AU 0 vs
  VST3 > 0. Almost all Plugin Alliance (e.g. ADPTR StreamLiner 15000, bx_limiter 304, Lindell channels
  52, Acme Opticom 32), plus sonible smartgate, Denise Perfect Plate XL, LEWITT Space Replicator.
  MeldaProduction, TBTECH and Black Salt report the same in both. For those vendors, prefer VST3 live.
- [x] Failed to load: TBTECH Cenozoix Compressor (AU, crashed REAPER), Cut Classic High Flyer (VST3),
  fiedler audio splat (VST3).

- [x] 1. Top bar layout, title centered, buttons wrap.
- [x] 2. Search "de" with FX that have latency: no error.
- [x] 3. Search field ready to type, results after 0.5 s, Enter picks the first.
- [x] 5. FX menus: colored type, red latency.
- [x] 6. FX type colors follow the settings.
- [x] 8. Alt-click on the level box.
- [x] 9. Windows keep their size.
- [x] 10. "Scan the rest" only scans plug-ins not measured yet.
- [x] 11. Crashed plug-in shows as failed in the list. (The file couldn't be found: 0.11.3 adds a menu
  item that opens the folder, see 32.)
- [x] 12-13. AU vs VST3: Acme Opticom XLA-3 (Plugin Alliance): VST3 reports 32 samples (REAPER
  applies 64, rounded to the buffer), AU reports 0. Turning the VST3 off drops the chain to 0/0. The AU
  doesn't report its latency, so REAPER can't compensate it and the watchdog can't see it.
- [x] 14. One JSFX window opened during the scan (fixed in 0.11.3, see 34).
- [x] 15. Scan window shows the plug-in being loaded.
- [x] 16-19. Spec Craft (Three-Body Technology), AU: always has latency, but reports it only after a
  while (or once oversampling is switched on). REAPER's figures match once reported. No playback.
- [x] 26. Meters: one bar for a mono side, two for a stereo side.
- [x] 27. Key button on every plug-in with a sidechain input.
- [x] Full scan: about 10-15 min for ~700 plug-ins, including 4 crashes/restarts.
- [x] A plug-in that crashes REAPER during a scan is named on the next start and marked failed.
