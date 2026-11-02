# FOH-Mate: testing to do

Open items to check in REAPER, newest version first. Report by number (e.g. "3 ok, 7 fails: ...").
Done items are kept at the bottom, with what was found.
New items get the next free number (next: 92).

## Open

- [ ] 95. (0.14.46) Pan / balance parameters get the **Pan** control (name rules: Pan, Balance; or pick it by hand): the default mark is a yellow arrow at 12 o'clock, a band starts at the top and goes left or right with the value (7:30 = fully left, 4:30 = fully right, the band reaching that mark), and at the center a white X shows on the line of the mark instead of a band. Check it with a real pan, a balance, inverted (the band goes the other way), and that rows added before still show the mark at the top. The control name is "Pan" in the menus and the inspector.

- [ ] 94. (0.14.45) Rack 2's EQ: frequency parameters show as frequencies ("1000 Hz", "1.2kHz"), not percentages. If some are still percentages, send Data/FOHMate/param_text_rejects.txt (plug-in, parameter, the text the plug-in gave) so the rules can be fixed from it.

- [ ] 93. (0.14.44) A width band or Q band shows its yellow default mark as two short lines (like the min/max marks, but yellow) at the two edges of the band the default value would give (not one arrow). A pan or width whose default is mono (minimum): the two lines are close together at the top, as thin as the thinnest band. Q band: the lines follow the narrower-with-higher-Q rule. Inverted rows and the "Default mark" choices in the inspector still move the marks. Plain encoders keep a single arrow.

- [ ] 92. (0.14.0) Q and pan/width. (a) A parameter named "Q", "Quality", "Band 1 Q" gets the **Q band** (Automatic, or right-click > Control): at the minimum the band is as wide as it can be (minimum mark to maximum mark), at the maximum it is the thinnest line, so a higher Q = tighter. Check it with a real EQ's Q, and that "Width band" (bandwidth, knee, stereo width) still gets wider with the value. (b) Add a pan and a stereo width to the Performance (re-add them: existing rows keep the mark they had, or change it in the section on the right): the pan's yellow mark is at the center (12 o'clock), the width's is at the minimum end (7:30, mono); a width turned all the way to mono sits on its mark. Double-click returns to it. (c) Edit mode: right-click a row > Remove this row: the row goes (it crashed before: the function was missing); the check box in the Performance parameters window is empty again; Cmd-Z brings it back.

- [ ] 91. (0.14.0) Settings (Options > Settings...), Plugin list and Performance parameters: each opens next to the
  Plugins Host window every time (also with REAPER on a second screen, or after moving the windows),
  and none of them has a fold arrow any more.

- [ ] 90. (0.14.0) Parameter rows (Performance mode). (a) Edit mode: the + at the end of a column
  opens "Performance parameters": rack > FX (name, (TYPE) in its color, "n of m in the Performance")
  > parameters (kind of value and current value). Folding works; click / Cmd-click / Shift-click
  select; Add / Remove to Performance work on the selection; an FX selected = all its parameters (a
  plug-in with several hundred: lag?); the check marks follow. Search narrows the tree. The window
  closes when you switch to Show mode, and the + is gone in Show mode. (b) Controls: a continuous
  parameter gets an encoder (7:30 to 4:30, stops at the ends, clockwise = up; yellow default mark;
  min/max marks in the encoder's color); a width or Q gets an arc; a few numeric values get a stepped
  encoder with a mark per value (an 1176 ratio?); on/off gets a circle toggle; named values get a
  drop-down circle with a menu. Each moves the real parameter, and follows it when it is moved in the
  FX window. (b1) A parameter in dB (a gain, a threshold, Noise (dB)): a smooth encoder with small marks where -60, -30, -10, -5, 0 and +5 dB fall (only those inside its range), not one per step. Right? (b5) Values with words: the vertical box writes them ("Mono", "Stereo", "Peak", "-6.0 dB", with capitals, small letters, digits, . , : ; ! ? ( ) ...). Are all the letters clear and evenly spaced at the row's size and widened? JS Pink Noise Generator > Mode (Mono/Stereo) is now a Drop-down. (b4) The section on the right, for a parameter in the Performance: Invert (the encoder, toggle and marks turn the other way; the real parameter follows), Default mark on/off and where (now, minimum, middle, maximum). Min, max and the dB or step marks are short lines; only the default is an arrow. The control names are the same everywhere (Encoder, Width band, Stepped encoder, Toggle, Drop-down). A Drop-down is a circle with an arrow that opens a menu of the values, for any parameter (11 positions when the plug-in doesn't list its values). The check boxes are empty for parameters that are not in the Performance, ticked for those that are, and a second click takes it out again. (b3) In the Performance parameters window: the check boxes put a parameter (or all of an FX) in or out with one click; the buttons below still work on the selection. Select a parameter: the section on the right shows its control choices, a preview and REAPER's facts; picking one changes the row at once; with several selected the choice applies to all. (b2) Edit mode: right-click a row > Control for this parameter: pick another one (the row changes at once); "Automatic" goes back to the guess. The corrections go to Data/FOHMate/param_controls.txt (plugin, parameter, your choice, the guess, REAPER's min/max/step/toggle and the text at 0 and 1): send it to Claude to improve the guesses. A width/Q/knee shows a band centered at the top. (c) Settings > Controls > Rotary encoder: up and down (finer the farther to the side)
  and around the encoder; Shift = finer; double-click = back to the default mark. (d) Save, close
  and reopen the project: rows are back. (e) Remove an FX: its rows grey out. (f) Performance mode
  status bar: "n parameter(s) in the selected rack". (g) CPU with several racks of 20+ rows, and
  with a plug-in whose rows were all added. (Rollback point before this: tag `perf-checkpoint-3`.)

## Done

- [x] 87. (0.14.0) Performance mode rows show their value: a small vertical box between the control and
  the name, with placeholder values that fit the parameter ("-18 dB", "4:1", "12 ms", "250 Hz",
  "+3 dB", "50%", "8 kHz", "80 Hz"). With the control on the right the value reads top to bottom
  (clockwise quarter turn), with the control on the left it reads bottom to top (counterclockwise).
  Legible at a glance? Right size, thickness and distance from the name? Also in Daylight mode and
  with many rows (CPU gauge while scrolling 40 placeholder rows in two or three columns).

- [x] 88. (0.14.0) Widening a parameter column (turn on Performance mode, Settings > Placeholder rows, e.g.
  20). The band at the top of a column has two small triangles back to back. (a) Click it: the
  column widens over the neighbouring columns to the full window width and the rows flow in columns
  (top to bottom, then the next column) that scroll sideways (trackpad, or the mouse wheel); the
  triangles now face each other; edges fade and a slim bar at the bottom shows where you are.
  (b) Click again: it folds back to one column, scrolled so the last row you clicked is visible.
  (c) In Show mode with an FX section open: widening folds the FX section first, then widens;
  opening an FX section while widened folds the columns back. (d) Widening another rack's column
  folds the first. (e) Settings > Performance mode: a widened column and an open FX section fold back by
  themselves after the pause (the pause counts from the last mouse movement, click, drag, scroll or key in the
  Plugins Host window; working elsewhere in REAPER doesn't restart it); with the checkbox "Fold ... by themselves" off they stay open (and
  the time setting does nothing). (f) Smooth and snappy? Band the same size and look as the chevron under the FX section?
  (h) Widening: every row grows to 1.5 times its width and height, with room around it and a divider between the columns, while the column widens, with a
  bigger control, value and name; back to normal when folded. Smooth? Readable? Rows reflow per
  column as designed? (Experiment: roll back with the tag `perf-widen-checkpoint`.)
  (g) Both triangles the same size; the same gap between rows widened and folded; placeholder rows
  now carry a number to see how they spread. Also Edit mode, a bypassed rack, Daylight mode, a
  narrow window, CPU while scrolling sideways.

- [x] 89. (0.14.0) Performance mode, Show mode: the only meters are thin horizontal bars either side
  of the chevron (input left, output right, mirrored: tops and clip lights both next to the chevron; one bar for a mono rack, two for stereo; clip marker at
  the right end, peak hold tick), visible folded and unfolded. No vertical meters; the FX section
  uses the full width of the rack when open (FX names, the + button, drop zones, drag and drop
  of FX all still right?). Edit mode keeps the full racks with vertical meters. Readable but not
  noisy? Also with "no meters" on (nothing drawn), a bypassed or muted rack, Daylight mode, CPU.
  (Rollback point before this: tag `perf-checkpoint-2`.)
  All three (87, 88, 89): ok.

- [x] 86. (0.14.0) Performance mode in Show mode: racks fold to the name with M and B, the handle
  (centered, whole-width click zone) opens and folds the FX section with the animation and moves only
  that rack's column, auto-fold after 15 s idle, Edit/Show switching, latency alert frame: ok. Found
  while testing: B (and BYPASS) did nothing on a rack with an FX that Show mode had taken offline;
  fixed in 0.14.0 (the offline FX counted as switched on again).
- [x] 85. (0.14.0) Performance mode, the view: toggle, one row, columns with their own scroll, fade and
  position bar, row design (bold name box, control outside, staggered sides, hover glow, + circle),
  Edit mode full racks, docked/floating, Daylight: ok.

- [x] 84. ReaPack About text (repository and package) shows the FOH-Mate overview with headings and
  bullets, and no new version is offered: ok.
- [x] 83. (0.13.3) Update through ReaPack: after the tag was pushed (the first sync failed with a 404
  until then), Synchronize packages offered 0.13.3 and the ReaPack copy works: ok.
- [x] 82. (0.13.3) Same gap everywhere (between racks, between rows, under the top bar, about 17 px):
  works.
- [x] 81. (0.13.2) A rack over its rack latency limit: the thicker red frame hides the rack's own
  frame completely, selected or not: ok.
- [x] 80. (0.13.1) The latency alert tag on a first-row rack shows whole, selection glow and rack
  dragging unchanged: ok.
- [x] 79. (0.13.0) Show mode re-check: with an FX over the limit, turning on Take FX over the limit
  offline in Show mode (or Count every format..., or changing a limit) takes it offline right away; Edit
  brings it back: ok. Found while testing: the AU of bx_limiter reports its real 304 samples once it
  has been loaded a moment; the 0 in the latency list comes from the scan reading it too early (like
  Spec Craft, items 16-19).
- [x] 78. (0.13.0) Latency > Count every format at its highest latency: Plugin list marks estimated
  figures with *, racks and FX hover show "(estimated from VST3)", the watchdog alerts; off puts it
  back; Allow stays per format with the note (and its "Don't show this again"): ok.
- [x] 77. (0.13.0) "Don't show this again" on the non-critical popups and Settings > Reset warning
  popups; critical popups (delete rack, reset, scans) still always show: ok.

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
