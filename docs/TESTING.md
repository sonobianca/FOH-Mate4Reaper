# FOH-Mate: testing to do

Open items to check in REAPER, newest version first. Report by number (e.g. "3 ok, 7 fails: ...").
Done items are kept at the bottom, with what was found.
New items get the next free number (next: 82).

## Open

- [ ] 81. (0.13.2) A rack over its latency limit (rack limit, so the whole frame flashes): the red
  frame is thicker and hides the rack's own colored frame completely, corners included, with the rack
  selected and not selected.

- [ ] 80. (0.13.1) The flashing "!! RACK ... ms" / "!! FX" tag on a rack of the first row shows whole
  (nothing cut off at the top). The racks sit a few pixels lower than before; selection glow and
  dragging racks unchanged.

- [ ] 79. (0.13.0) Show mode re-check. Checked by Claude in REAPER: with an FX over the limit, in Show
  mode, ticking FX > **Take FX over the limit offline in Show mode** takes it offline right away
  (strike-through, "1 FX taken offline for latency"); back to Edit brings it online; Edit -> Show with
  the option on takes it offline too. Left for Bianca: in Show, raise the per-FX limit above the FX's
  latency, then lower it again: the FX goes offline; and turning **Count every format...** on in Show
  with an AU that really stays at 0 (not bx_limiter: see the note below). A re-check that finds
  nothing leaves no extra step in Edit > Undo.
  Note: the AU of bx_limiter reports its real 304 samples once it has been loaded for a moment; the 0
  in the latency list comes from the scan reading it too early (like Spec Craft, items 16-19).

- [ ] 78. (0.13.0) Latency > **Count every format at its highest latency** (off at first). Turn it on.
  Plugin list, AU of bx_limiter: Latency shows `304*`, hover says the VST3 reports 304; with a per-FX
  limit under 304 its name turns red. A rack with the AU bx_limiter: rack latency box and FX hover show
  304 "(estimated from VST3)", the watchdog alerts. Turn the option off: back to 0, no alert. Plugin
  list Allowed on the AU: a note says only the AU is allowed and lists the VST3 (has "Don't show this
  again"); Allow ticks it, Cancel doesn't. With the option off, no note.

- [ ] 77. (0.13.0) "Don't show this again". Double-click empty space: the "Create a new rack?" box has
  the checkbox (tooltip explains it); tick it and Create; double-click again: a rack is created with no
  box. Same idea with Delete FX... and Replace FX on one FX. **Delete rack**, **Reset to defaults** and
  **Scan... for latency** still show with no checkbox. Settings: **Reset warning popups** (next to Reset
  to defaults) says how many come back; double-click asks again. Hidden popups stay hidden after
  restarting FOH-Mate.

## Done

- [x] 76. (0.12.0) ReaPack install from the repository's index (first release through ReaPack): the
  repository imports, FOH-Mate installs, and the installed copy runs v0.12.0 with racks and settings:
  ok.
- [x] 75. (0.12.0) Modular code: v0.12.0 runs from the existing action and everything works as in
  0.11.21; with the `FOHMate` folder renamed, the missing-file message shows: ok.
- [x] 74. (0.11.21) Key dots show the key source's width: mono input into a stereo FX is one dot,
  stereo pair or bus two dots, stereo into a mono FX one: ok.
- [x] 73. (0.11.20) Mono-in/stereo-out rack with a keyed FX switched to stereo: key no longer comes
  out the right channel (Main R back on channel 2): ok.
- [x] 72. (0.11.19) Settings: one Latency section with all five settings, values kept, no error on
  hover, Latency > Latency limits... opens it: ok.
- [x] 56. Favorites and Recently used under the search field (+, Insert FX, Replace FX); last 5
  different FX, newest first; Settings > Behavior > Recently used FX count, 0 hides it: ok.
- [x] 52. Help line: every hovered control, rack and FX drags with Cmd/Opt, Edit and Show hints: ok.
- [x] 51. (0.11.10) Open the FOH-Mate data folder in Options, gone from Latency: ok.
- [x] 66. Closed, not needed: the 0.11.9 file is replaced by 0.11.18 once merged into main.
- [x] 63. (0.11.14) Mono key follows the FX's width: soothe3 on a mono rack gets a mono key (bus size
  1, one key pin on channel 3); the sum is two -6 dB receives into that channel; turns stereo with the
  rack and back: ok.
- [x] 62. (0.11.13) Key dots in the gap between name and key button; name button width unchanged: ok.
- [x] 58. Key dots: one for a mono key, two stacked for stereo, none without a key: ok.
- [x] 57. Dots on mono, stereo and mono-in/stereo-out racks, glowing stereo point, centering, Daylight: ok.
- [x] 59. Options > Stereo pairs on odd-even channels only, on and off: ok.
- [x] 67. Fresh install on a new Mac (0.11.14): starts clean, no error, everything looks good.
- [x] 65. Migration on the Live Rack machine: settings, mode, dock, window sizes, favorites, recent FX,
  latency list, racks' saved data and meters all carried over; nothing copied twice: ok.
- [x] 64. Rename: no "Live Rack" anywhere on screen; Plugins Host titles, FOH-Mate Settings, Open the
  FOH-Mate data folder: ok.
- [x] 71. (0.11.18) Docked Plugins Host: Rescan all box in front with the Plugin list, Settings, or
  both open (follows the one clicked last); floating Plugins Host normal; Plugin list's own box ok.
- [x] 70. (0.11.17) Confirmations over the window that asks: Plugin list Rescan (button and
  right-click), Settings Reset, closing the list while asking, Delete FX: ok. Latency > Rescan all was
  hidden behind the Plugin list with Plugins Host docked: fixed in 0.11.18, see 71.
- [x] 69. (0.11.16) Plugin list: clicking a developer again shows all developers; Stereo from here
  picked again on the stereo point goes back to automatic: ok.
- [x] 68. (0.11.15) Script runs as FOHMate.lua from the action, toolbar and shortcut; meters ok.
- [x] 55. Plugin list selection (click, Cmd-click, Shift-click, Select all, Clear) and Rescan selected:
  ok. The rescan first froze every FOH-Mate window: its confirmation box opened late or hidden behind
  the Plugin list. Fixed in 0.11.17 (see 70); the rescan then works perfectly.
- [x] 54. Plugin list stars: gold on click, off again, Favorites checkbox, favorites in the + menu,
  kept after a REAPER restart: ok.
- [x] 61. (0.11.12) Plugin list: click a column header to sort, again to reverse, arrow shows column
  and direction; Latency/Highest biggest first, star puts favorites first; Sort drop-down gone: ok.
- [x] 53. FX > Plugin list: every FX listed, type colors, latency/Highest/Status, red names over the
  limit, Allowed box, name/type/developer filters, latency checkbox, sort: ok.
- [x] 60. (0.11.11) Plugin list Developer column, developer drop-down with its own search field,
  click a developer to filter: ok. Clicking it again didn't show all developers: fixed in 0.11.16, ok.

- [x] 20-23, 44-46. **Clicking glitch** (mouse couldn't click in plug-in windows or FOH-Mate menus):
  never happened again after extensive use since; considered fixed. Cause never found. What was known:
  soothe3 windows and the Plugins Host window both stopped taking clicks, no sidechain involved, no
  confirmation box open, seen in Show mode with only 3 soothe3 instances open; closing and reopening
  FOH-Mate did not seem to fix it. If it comes back: check for an invisible window over the dead areas
  (Cmd+Shift+4 then Space), a hidden REAPER dialog (Cmd+` or Mission Control), and whether other
  plug-in windows and Edit mode are affected too.

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
