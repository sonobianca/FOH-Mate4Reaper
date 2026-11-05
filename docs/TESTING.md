# FOH-Mate: testing to do

Open items to check in REAPER, newest version first. Report by number (e.g. "3 ok, 7 fails: ...").
Done items are kept at the bottom, with what was found.
New items get the next free number (next: 147).

## Open

- [ ] 146. (0.14.99) Double-click to inspect. With the parameter window closed (Edit mode), double-click a parameter's name box, then its value box: the window opens with that parameter selected, its FX and group open in the tree. With the window already open: the same selects it. Double-click the control (an encoder with a default mark): it still goes back to the default mark and does not open anything. Show mode: nothing opens.
- [ ] 145. (0.14.98) Inspector behaviour. Open the parameter window (+ or right-click a parameter > Inspect parameter...), leave it open. (a) Click a parameter in a rack's column (the name box, or the control): it is the only one selected in the tree, with its FX and band group opened and the tree scrolled to show it; the right side shows its settings (nickname, limits, curve...). (b) Do it with a parameter of another rack (open or folded in the tree): that rack opens in the tree. (c) Type something in the search that hides the parameter, then click it in the rack: the search is cleared and it is shown. (d) Click one that is far down a long list (Kirchhoff, a band at the end): the tree scrolls to it. (e) With the window closed, clicking a parameter does nothing new; turning a control with the window open still works normally.
- [ ] 144. (0.14.97) List of values, boxes. (a) A parameter in Hz (a frequency) with a list of values: each value is a box with the number ("1000") and the unit (Hz) right of it, once, never "Hz Hz"; same for dB, %, ms. (b) The box and its text are in the parameter's color (change the FX's color, or Recolor the parameter: they follow), readable on dark and in Daylight mode. (c) Click a box, type 440, Enter: the value becomes 440 Hz (as close as the plug-in prints), the row's control follows. Type 2 with a kHz plug-in: 2 kHz. Type something the plug-in never prints (a unit it doesn't use): nothing changes. (d) A text value (a Kirchhoff band type) is in a box you can't type in. (e) The arrows and the red x still work and stay lined up on the right.
- [ ] 143. (0.14.95) FX colors. (a) Right-click an FX in a rack (Edit mode) > Color...: a picker; the parameters of that FX in the Performance take the color at once (an EQ's odd and even bands still differ slightly; a parameter you recolored by hand keeps its own). A small tab in the color shows on the FX button. **Automatic**: the rack's color again, no tab. (b) The same in the parameter window: right-click an FX line > Color...; its name and its parameters' names in the tree follow. Rack names are in the rack's color. (c) Duplicate the rack: the copy's FX have the same colors. Save and reopen the project: colors are kept. (d) Hover a parameter in the Performance: the FX in the rack glows in that parameter's color; hover the FX's name: its parameters glow in the FX's color. Try a very dark color, a very light one, grey, and the same color as the rack: the glow is always easy to see and pulses a little. Daylight mode too. (e) The row you point at still glows in the usual blue.

- [ ] 142. (0.14.94) Tree outline and indentation. (a) No dotted frame around the tree any more; instead a thin dotted vertical line under the arrow of every open rack, FX and group, from below its row down to its last line (also when scrolled: only the part in view). (b) An FX's arrow is under the first letter of its rack's name, its check box one step further: clearly indented from the rack. (c) Check boxes of parameters and groups still line up as in 141.

- [ ] 141. (0.14.93) The parameter tree. (a) Every rack of the project is in the tree, names bigger and bold; only the rack you opened the window from is open at first. Open another rack: its FX are listed; select and add parameters of two racks at once, **Add to Performance** puts each in its own rack. Fold a rack: what was selected inside it is deselected. (b) Check boxes: the same size on every line, and lined up: the check box of an FX starts where its rack's name starts, a parameter's where its FX's name starts, a group's lines up with the parameters beside it, with its arrow to the left. (c) Kirchhoff-EQ > Band 1: names without "Band1" ("Type", "Used"...), hover shows the full name; a **Dyn.** branch holds the dynamics parameters ("Threshold", "Ratio"...), with its own check box and count; check it: all of them are added or removed. Other plug-ins with groups still work; the REAPER branch (Bypass, Wet, Delta) too. (d) Names are in the rack's color: change the rack's color (or Recolor a parameter) and reopen the window; a dark rack color is lightened (Daylight mode: darkened) to be readable; parameters of odd and even bands differ a little. (e) (changed in 142: guide lines on the branches). (f) Search: opens every branch that has a match, in the racks that are open. (g) Right-click a parameter in a rack > Inspect parameter...: the window opens with its FX and groups unfolded and the parameter selected. (h) Selecting with Shift-click (range) and Ctrl-click still works, also across the unfolded racks. (i) Show hidden and right-click > Hide this parameter still work.

- [ ] 140. (0.14.92) Indentation and section titles. (a) Settings window: section titles (Colors...) bold and a little bigger than the text, the same as the parameter window's sections; they fold and unfold as before, Colors open at first, and a link that opens Settings on a section still does. (b) Parameter window tree: under an FX, its parameters' check boxes are one step to the right of the FX's check box, lined up with the check boxes of its groups (REAPER, Band 1...); a group's parameters one more step to the right. (c) The "Toggle: Mono" / "Encoder: -6.0" column is at the same place on every line, in groups too. (d) Clicking a parameter's check box still adds or removes it; clicking its name still selects it.

- [ ] 139. (0.14.91) Curve reset. On a Custom points curve, right-click the graph away from the points (or on an end point): a menu with "Reset the curve (a straight line)"; choose it: only the two end points are left, in a straight line, Smooth as it was. Right-click a middle point: it is still removed, no menu. The tooltip mentions the reset.

- [ ] 138. (0.14.90) The parameter window's layout. (a) At the top: the parameter's name, big and bold (bigger than the section titles); under it the nickname box, then the FX name, dimmed. (b) Type a nickname, press Enter or click elsewhere: the row in the Performance shows it, Ctrl+Z undoes it; empty the box: its own name is back. Type one and click another parameter in the list without pressing Enter: the first one still gets it. Not in the Performance: the box is greyed out. (c) Sections Control, Direction and default, Limit values (Use limits inside), Curve, Preview, Details: each title bold, a bit bigger than the text; click a title to fold or unfold it; Details starts folded. (d) Several parameters selected: the title says how many, only Control is shown.

- [ ] 137. (0.14.89) The curve section. (a) The graph is a little bigger (10%). (b) Under it: Save this curve... and Delete a curve... side by side (Delete only when you saved a curve), then Type and Strength (or Smooth): their right edges, captions included, line up with the right edge of the graph; their left edges with its left edge. (c) Type > Saved curves: S curve, Fine in the middle, Rising wave (climbs while waving), Parabola (up then down), Valley (down then up), Staircase (4 flat steps), Wave, Zigzag. No Ease in / Ease out among them.

- [ ] 136. (0.14.88) Click a rack's **Out**: "Hardware out: mono" comes before "Hardware out: stereo pair", and both still set the output.

- [ ] 135. (0.14.87) Drop-down for word values. Remove the hand-made correction first (right-click Kirchhoff Band 1 Type > Control > Automatic). (a) Kirchhoff-EQ: every band's Type is a drop-down without the "Reserved" values. (b) A stepped numeric parameter (a ratio 1:1, 2:1... or an oversampling 1x, 2x...) is still a stepped encoder. (c) Mono / Stereo-style two-word parameters are still drop-downs, on/off still toggles.

- [ ] 134. (0.14.86) The "..." menu of the parameters (Edit mode). (a) Top right of each parameter column, above the position bar: three dots that light up on hover; click: "Remove the N parameters not linked any more" and "Clear all" (with its confirmation). Not shown in Show mode. (b) The widen band still widens / folds when clicked anywhere else. (c) The **+** opens the parameter window; right-click on it does nothing now. (d) Right-click a parameter > **Inspect parameter...**: the parameter window opens with that parameter selected.

- [ ] 133. (0.14.85) Hidden parameters and values. (a) The parameter window: no "Reserved", "Unused", "-", nameless or "Param 12" parameters; a JUCE VST3 plug-in (most of them: try one with lots of parameters) has no "MIDI CC 0|1"... entries. The "n of m" counts leave them out. (b) Each FX ends with a **REAPER** branch: Bypass, Wet, Delta (Delta only on REAPER versions that have it), with its check box. (c) Right-click a parameter > **Hide this parameter**: it goes, for that plug-in, on every rack and after a restart. **Show hidden** (next to the search): every hidden one is back, dimmed, "(hidden)"; right-click a hand-hidden one > **Show this parameter again**; an automatic one says why it's hidden. A hidden parameter already in the Performance stays there. (d) Kirchhoff band type (and any drop-down with "Reserved" values): the drop-down no longer lists them; as a stepped encoder it only steps through the real types, and the value box follows. The list of values' "Add one of its values..." leaves them out too. (e) A plug-in that names every parameter "Param 1, Param 2..." would show nothing: tick Show hidden. Tell me if you meet one.

## Done

- [x] 132. (0.14.84; 0.14.83 stopped on an error: GetID is not in ReaImGui) The pointer never seems to go under the encoder: with a steep curve (like the one in your screenshot), drag fast across the steep part: the pointer sweeps over the top, quickly. Also: move the parameter from minimum to maximum in the plug-in, or with automation: a quick sweep over the top. Does the short lag (about a sixth of a second for the whole range) bother you while dragging normally? Width / Q bands and pans too. CPU unchanged. Found: runs again (0.14.84), Bianca: "great!".

- [x] 131. (0.14.82) The encoder follows the curve: with Wave or Up and down, drag one way only: the pointer (or the band, for a width / Q band) swings up and down with the value, smoothly, and the value box agrees. Let go and drag again: it carries on from where it was along the curve, no jump. Move the parameter in the plug-in: the encoder shows the new value. dB marks and the default mark are back on curved encoders, where those values are; double-click goes to the default. Min / Max without full range: the arc is back, and the pointer never goes past it. Stepped encoder with a curve: the pointer jumps from value to value as the curve says. Found (Bianca): ok.

- [x] 130. (0.14.81) Value curves. In the parameter window, select a parameter in the Performance (an encoder): under Limit values, a **Curve** menu and a graph. (a) Linear: a straight diagonal, the blue dot follows the encoder as you turn it (and when moved in the plug-in). (b) Ease in / Ease out + Strength: the curve bends; turning the encoder, the value changes slowly then fast (or the other way); the value box and the plug-in agree. (c) Custom points: starts from the current curve; click to add a point, drag points (the ends only move up and down, the others stay between their neighbours), right-click removes one; Smooth on/off. (d) Saved curves in the Curve menu: the examples (S curve, Fine in the middle, Up and down, Wave, Zigzag, Ease in/out). With **Wave**, one turn of the encoder makes the value go up and down twice; turn back and forth: the encoder doesn't jump around. Move the parameter in the plug-in: the encoder goes to a sensible place. (e) **Save this curve...** asks a name; it appears in the menu, also for other parameters, and after restarting FOH-Mate. Same name: replaced. **Delete a saved curve...**: asks, then it's gone. (f) A stepped encoder with a curve: still on steps, values follow the curve. A width band and a Q band with a curve. A pan, toggle or drop-down: no Curve section. A list of values: "not with a list of values". (g) With Min / Max + full range: the curve fits between Min and Max. Without full range: no arc, the value still stays inside. With Invert. (h) Default mark and double-click with a curve. (i) Save, reopen, duplicate the rack: the curve is kept. CPU with several rows with curves. Found (Bianca): ok.

- [x] 129. (0.14.80) List of values: the first value has no up arrow, the last no down arrow (an empty space in their place, so the buttons of every line stay lined up). A single value: only the red x. After moving a value to the top or bottom, the arrows follow. Found: works.

- [x] 128. (0.14.79) The list of values reads better: no numbers, each value's text on the left, and on the right of the same line, lined up for every value: up, down and a red x (lighter red under the pointer). The text sits level with the buttons. Do the buttons still work, and stay on the right when the window is resized? Found: works, reads well.

- [x] 127. (0.14.78) Min / Max on a width band and a Q band, full range off: instead of one arc, two mirrored arcs (each with its two handles), left and right of the top, covering only where the band's edges can go: the band at Min ends at their inner handles, at Max at their outer handles. Try Min at the minimum (the arcs almost meet at the top) and Max at the maximum (they reach the min/max marks). With Invert. With full range on: no arcs. An encoder and a pan keep the single arc. Found: works.

- [x] 126. (0.14.77) Limit values, list. (a) Right-click a parameter > Limit values..., tick Limit values: for an encoder there are two choices, Min / Max and List of values; for a drop-down parameter only the list (no Min / Max); not offered for a toggle. (b) List of values: "No values yet"; add with **Add the value it has now** (turn it in the plug-in first), with the slider + **Add** (shows the plug-in's values), and for a stepped or drop-down parameter with **Add one of its values...**. The same value can't be added twice. Values show with the plug-in's text, numbered. Up/down arrows reorder, x removes. (c) Make a list out of order, like 1 kHz, 250 Hz, 4 kHz, 632 Hz: the row becomes a **stepped encoder** with 4 steps, which go through the values in that order; the plug-in and the value box follow. (d) Show as: Automatic (says what it chose), Stepped encoder, Drop-down: the drop-down lists the values in the list's order with the current one highlighted. More than 12 values, or a drop-down parameter: Automatic picks Drop-down. One value: always a drop-down. (e) When the list changes or you switch to it, a value that's not in the list jumps to the nearest one. (f) Default mark on a stepped list: on the nearest step; double-click goes there. (g) Switch to Min / Max and back, untick and tick again: the list and the Min / Max are both kept. (h) The preview in the window shows the stepped encoder or the drop-down. (i) Save, close, reopen; duplicate the rack: kept. Rows saved by 0.14.72 to 0.14.76 with a Min / Max still have it. Found: works; the list was hard to read (numbers, buttons on the left): see 128.

- [x] 125. (0.14.76) The limits arc and its two handles are one line now: both corners (Min and Max) join cleanly, no pixel off at either end, at normal size and widened. Found: works, both corners join cleanly (Bianca: "it's great!").

- [x] 124. (0.14.75) The value box sits a little closer to the name (gap 2.5 px instead of 4) and farther from the control (5.5 px), on every row, both sides, normal size and widened. A control with the limits arc has room now? The name boxes keep their width. Found: right, the arc has room.

- [x] 123. (0.14.74) A control with the limits arc is no longer cropped at the column's edge: it moves to the middle of its space (a little toward the value box), on both sides (rows with the name left and right), at normal size and widened. The arc doesn't touch the value box. Controls without the arc stay where they were. Found: no longer cropped, clear of the value box.

- [x] 122. (0.14.73) Limits without the full range: instead of two marks, a thin sky-blue arc (orange in Daylight) runs outside the encoder from Min to Max, with a short handle at each end down to the ring. The min/max, dB and default marks sit between the arc and the ring, drawn over it. Easy to see with the default mark right next to a limit? Not cut off at the top or bottom of the row, at normal size and widened? Also in the parameter window's preview. Found: the arc is easy to see next to the default mark (seen in Bianca's screenshots).

- [x] 121. (0.14.72) Limit values. (Bianca: the sliders (b) and the full range (d) work; the rest still to check.) (a) Right-click a parameter (an encoder, e.g. a Kirchhoff gain) > **Limit values...**: the parameter window opens with it selected; "Limit values (Min / Max)" is under Invert and Default mark. Not offered for a toggle or a drop-down. (b) Tick it: Min and Max sliders appear, showing the plug-in's values (Hz, dB...; a percentage when the plug-in can't say). Move them, and try **Now** on each: Min can't go above Max. A value outside the new limits jumps inside. (c) Full range off: two marks in sky blue (orange in Daylight) on the encoder show Min and Max, and the encoder stops there, in both drag modes (up/down and around). No dead zone when you drag past a limit and come back. (d) Full range on: the encoder turns from its minimum to its maximum mark for Min to Max, finer than before; the value box and the plug-in agree; dB marks outside the limits are gone, the default mark only shows when it's inside. (e) With Invert on too, in both modes. (f) A width band, a Q band and a pan (both modes; with full range, does a pan's center still make sense?). A stepped encoder: stops at the limits, no full-range option. (g) Double-click to the default mark. (h) Untick Limit values: back to normal. (i) Save, close, reopen: kept; duplicate the rack: the copy has them too. (Like Invert, changing the limits is not an undo step.) Found (Bianca): it all works.

- [x] 120. (0.14.71) The Display menu: Daylight mode, Colors > (Recolor every rack, Choose default color..., a line, New racks use automatic color / default color, with the check mark on the one in use); a line; Performance mode, Hide disabled parameters; a line; Rack latency box > (Off / Always / Only when a rack has latency, check mark on the one in use), Dock >. Each item still does what it did. Recolor every rack is greyed out in Show mode. Found (Bianca): all good.

- [x] 119. (0.14.70) The word "row" is gone from what you see in Performance mode: the row menu (Recolor parameters > This parameter... / Every "Band 1" parameter / Every parameter of <FX>; Remove this parameter), the + menu (Remove the N parameters not linked any more, Clear all box), the delete boxes, the help line at the bottom (hover a name box, the +, and while dragging), the parameter window's "This parameter" section, the Settings tooltips (Remember parameters nicknames, Rotary encoder), Display > Hide disabled parameters tooltip, and the undo names (Reorder / Clear Performance parameters). Does anything still say "row"? Found (Bianca): all good.

- [x] 118. (0.14.69) Right-click the + of a column > **Clear all**: a confirmation with the number of rows; Clear all removes every row of that rack (only that rack), Cancel keeps them; Ctrl+Z brings them back. Greyed out when the rack has no rows. Found (Bianca): all good.

- [x] 117. (0.14.69) **Display > Hide disabled parameters** (a check mark, remembered after a restart): the greyed-out rows (FX deleted, or changed) disappear from the columns, and the rows under them move up (odd/even sides still alternate). Switch it off: they are back, in their place. With it on: drag a row to reorder, right-click a row, the + menu ("Remove the N parameters not linked any more" still counts the hidden ones). Widened column too. Found (Bianca): all good.

- [x] 116. (0.14.69) A new FX takes back kept rows. Delete a Kirchhoff with parameters, **keep parameters**, then add a Kirchhoff to the same rack (a) from the + / FX menu, (b) by dragging one from another rack (and Cmd-drag a copy within the rack), (c) with Replace FX on another FX: the rows come back to life, with their nicknames, colors, controls, invert and default. (d) Add a different plug-in: the rows stay greyed out. (e) Two Kirchhoffs deleted with kept rows, then one added: only the first one's rows come back; add a second: the others come back. (f) An FX that already has rows (moved within the rack) never takes other rows. (g) Ctrl+Z after adding: FX and relink go back together. (Not covered: FX added from REAPER's own FX window.) Found (Bianca): all good.

- [x] 115. (0.14.69) Delete an FX that has rows (**Delete FX...**): the box says how many rows it has, with three buttons: **Delete FX and parameters** (both go), **Delete FX, keep parameters** (the FX goes, the parameters stay greyed out), Cancel (nothing). The same for **Remove every FX** and **Remove bypassed FX** (Remove FX and parameters / Remove FX, keep parameters), with several racks selected too. An FX with no rows: the old simple box (Don't show this again still works). Ctrl+Z after each. Found (Bianca): all good.

- [x] 114. (0.14.68) Performance parameters window (the + of a column): under an FX, parameters with the same prefix are in a branch of their own (Kirchhoff: Band 1, Band 2...; ReaEQ: Band 1...), folded at first, where the first of them was in the plug-in's list. The other parameters stay where they were. (a) A branch shows a check box (all / some / none, like an FX) and "n of m in the Performance"; its check box puts all of them in or out at once. (b) Clicking a branch selects it: Add / Remove to Performance and the control section on the right work on all of its parameters; Shift-click and Cmd-click work across branches and parameters. (c) Search: branches with a match open and show only the matching parameters. (d) A plug-in with many bands: no lag when opening the window. Found (Bianca): all good.

- [x] 113. (0.14.67: stronger shift than 0.14.66, which was too subtle) Group colors. In a Kirchhoff (or any EQ), add rows of band 1 and band 2 (and a parameter without a band number, like Output). The band 1 rows are a slightly different shade from the band 2 rows (band 3 like band 1, band 4 like band 2...), the rows without a band keep the rack's color. Subtle but visible? In Daylight too. Also ReaEQ ("Freq-Band 1"...). Changing the rack's color: the shades follow. Found (Bianca): all good.

- [x] 112. (0.14.66) Right-click a row > Recolor parameters: (a) This row...: the color picker; the row changes as you drag (name box, value box, control ring). Automatic: back to the rack's color (or its band shade). (b) Every "Band 1" row (n)...: only the rows of that band of that FX. Only offered when there are several and not all the FX's rows. (c) Every row of <FX> (n)...: all of them. (d) Save and reopen the project: the colors stay. Cmd-Z after a recolor: tell Claude what it does (the color isn't an undo step yet, like the rack color). Found (Bianca): all good.

- [x] 111. (0.14.66) Right-click a row > Nickname parameter...: a box asks for the name (empty = the plug-in's own name). The row shows the nickname at once, also wrapped on two lines. Cmd-Z undoes it. (a) Settings > Performance mode > Remember parameters nicknames, on (default): add the same parameter of the same plug-in on another rack, or in another project: it gets the nickname. Nicknames are in Data/FOHMate/param_nicknames.txt. (b) Off: a new nickname stays on its row only, and new rows get the plug-in's name. (c) A greyed-out row can be nicknamed too. Found (Bianca): all good.

- [x] 110. (0.14.66) Right-click a row (Edit mode): the menu reads Control > (the control choices, as before), a line, Nickname parameter..., Recolor parameters >, a line, Remove this row. The Control choices work as before (tick on the current one, "Automatic (now: ...)"). Found (Bianca): all good.

- [x] 109. (0.14.65) The other way round from 105: point at a parameter row, and its FX in the rack above glows sky blue (orange in Daylight), with the same soft glow as the rows. Only that FX; nothing while dragging a row. Show mode with the FX section folded: nothing to see, nothing breaks. Found (Bianca): all good.

- [x] 108. (0.14.64) Right-click the + at the end of a column (Edit mode). (a) With greyed-out rows (delete an FX from REAPER's own FX window, or replace one): the menu says "Remove the N rows not linked any more"; clicking it removes exactly those, the working rows stay in their order. Cmd-Z brings them back. (b) With every row working: the menu item is greyed out ("Every row is linked: nothing to remove"). (c) A left click still opens the Performance parameters window. (d) The grey help line mentions the right-click. Found (Bianca): all good.

- [x] 107. (0.14.63) New scale for the width band (Width band and Q band controls). (a) Kirchhoff Pan/Width in MS: at C (normal stereo) the band is a half circle, flat from 9 to 3 o'clock; at 100S it reaches the min and max marks (7:30 to 4:30, as before); towards 100M it shrinks to the thinnest line. (b) A stereo width (0-200%): 100% = the half circle. (c) The yellow default marks follow the same scale (a width whose default is 100% has its two marks at 9 and 3 o'clock). (d) Q band: the middle of the Q range is the half circle too. Does it read well, or should Q keep the old scale? Found (Bianca): all good.

- [x] 106. (0.14.61) Reordering rows by drag (Edit mode, Performance mode). (a) Drag a row by its name box: a bar with its name follows the pointer (like an FX drag), the row stays behind faded, and the row under the pointer gets the outline. Drop: the row takes that place, the rows in between shift by one (and switch sides, since odd rows have the name on the left). (b) Drop on the + at the end: the row goes last. (c) Dropped outside the column, or on another rack's column: nothing changes. (d) Cmd-Z undoes the move. (e) Widened column (rows in several columns): the same. (f) Turning a control still works as before, and the right-click menu still opens on the name box. (g) Show mode: rows can't be dragged. (h) The grey help line says what to do while dragging. Found (Bianca): all good.

- [x] 105. (0.14.60) Point at an FX name in a rack (Performance mode, Edit and Show): that FX's rows in the column underneath glow sky blue (orange in Daylight), the other rows don't. The normal white (blue in Daylight) glow when pointing at a row is unchanged. Is the color clear enough, and different enough from the normal glow? Also: no flicker while moving along the FX names. Found (Bianca): all good.

- [x] 104. (0.14.59) Deleting an FX takes its Performance rows along. (a) Right-click an FX that has rows > Delete FX...: the box says how many rows go too, and shows even if you ticked "Don't show this again" for Delete FX before. Delete: the FX and its rows are gone, the other FX's rows stay. Cmd-Z: both come back, rows working. (b) An FX without rows: the usual box (or none, if you hid it). (c) Rack menu > Remove every FX, and Remove bypassed FX (also with the rack bypassed): when rows would go, a box first with the count; then only the rows of the removed FX go. With several racks selected: one box, the count for all of them. (d) Not changed: an FX deleted from REAPER's own FX window, or replaced (Replace FX), still leaves its rows greyed out. Tell Claude if those should go too. Found (Bianca): all good.

- [x] 103. (0.14.58) Duplicated racks keep working rows. (a) A rack with a few Performance rows: right-click > Duplicate rack. The copy's rows are not greyed out, and turning one moves the copy's FX, not the original's (check in both FX windows). (b) The same with Cmd-drag of the rack (duplicate by drag). (c) Use as template: the copy's rows work too, on its fresh FX. (d) Cmd-Z after each: the copy goes, the original's rows are untouched. (e) Not covered yet: REAPER's own Track > Duplicate (Cmd-D) still gives greyed rows on the copy. Tell Claude if you use that one too. Found (Bianca): all good.

- [x] 102. (0.14.62; 0.14.57 didn't show it: the value was drawn before the swap) Kirchhoff band in MS (follow-up to 97). Band 1 of the screenshots should now read 24M, band 2 (Stereo) still 43R: the Pan/Width row's value box reads M / S, whatever way the plug-in writes L / R ("100L", "L100", "-50 L", "Left 30"). Back in Stereo it reads L / R again. If it still shows L / R: (a) does the encoder show the width band (centered at the top) or the pan? (b) what exactly does the value box say, and what does the plug-in's own window say for that value? Found (Bianca): all good.

- [x] 101. (0.14.56) In VS Code (not REAPER): open a few files in src/FOHMate/ (widgets.lua, racks.lua, FOHMate.lua). The Problems panel shows no "Undefined global" or "lowercase initial" lines any more. If they're still there, reload the window (Cmd-Shift-P > Developer: Reload Window). Also: the script still starts in REAPER as before. Found (Bianca): all good.

- [x] 100. (0.14.55) Vertical values drawn as joined lines. (a) Same setup as 98 and 99: is the "racks" number lower again? (b) Look closely at the values: same letters, same thickness, same spacing as before? Check the sharp ones (V, W, M, A, N, K, 4, 7) for spikes at the tips, and the rounded ones (0, 8, S, O) for clean corners. Also widened (bigger rows) and in Daylight mode. (c) Scroll a column and turn a control: the values follow without lag or leftovers. Found (Bianca): all good.

- [x] 99. (0.14.54) Performance rows remember what the plug-in said. (a) Same setup as 98: is the "racks" number lower than before? (b) Turn a control, and move the same parameter in the plug-in's own window: the value box follows at once both ways. (c) A Kirchhoff Pan/Width: change the stereo placement in the plug-in, the row switches within half a second. (d) Replace or remove an FX that has rows: they grey out within half a second; Cmd-Z brings them back. (e) Rename a row, widen and fold a column: the names wrap as before. Found (Bianca): all good.

- [x] 98. (0.14.53) Debug timer: the status bar shows "Script [x.x] ms  -  racks [x.x] ms" right after the latency boxes, and the tooltip gives the average, the racks part and the slowest frame of the last 2 seconds. Write down the numbers for one fixed setup (same project, Performance mode, same racks and rows visible, nothing playing or the same thing playing), so the next two versions can be compared to it. Also with a narrow window: nothing on the status bar overlaps. Found (Bianca): all good.

- [x] 97. (0.14.52) Kirchhoff band in MS: the Pan/Width row's value box reads M / S ("100M" fully one way, "100S" the other, "C" in the middle), not L / R; back in Stereo it reads L / R again. Also after changing the control by hand and setting it back to Automatic. If it doesn't, check the plug-in's own text (Param > the parameter list in its FX window) for that value in MS mode, and tell Claude what it says. Found (Bianca): all good.

- [x] 96. (0.14.51) (a) Pan control: 1L to 9L and 1R to 9R show a tiny arrow, the same size pointing left as pointing right; from 10L / 10R the band, starting about as long as the arrow, so the switch looks smooth. The tiny arrow pointing left or right, smaller than the yellow default mark, its back exactly under the mark; exactly at the center a small vertical line (no X any more) sits under the mark, where the arrow's back is; a bigger offset shows the band; the vertical line shows only at exactly the center. (b) Kirchhoff EQ (Threebody, Plugin Alliance), a band's Pan/Width with its Stereo Placement in the Performance: Stereo = Pan control (band from the center), MS = Width band, Left / Right / Mid / Side = greyed out ("Not used with this stereo placement") and it doesn't react; change the placement in the plug-in and the row follows within a moment. The value box keeps showing the plug-in's text. If it never changes, or the row picks the wrong one, send Data/FOHMate/param_text_rejects.txt (the placement texts it didn't know) and the names of the two parameters. Pro-Q 3: the same, if its names match (the band's number, then a name with placement / stereo / channel / mode); otherwise a manual "controlled by" link is the next step. Found (Bianca): all good.

- [x] 95. (0.14.46) Pan / balance parameters get the **Pan** control (name rules: Pan, Balance; or pick it by hand): the default mark is a yellow arrow at 12 o'clock, a band starts at the top and goes left or right with the value (7:30 = fully left, 4:30 = fully right, the band reaching that mark), and at the center a white X shows on the line of the mark instead of a band. Check it with a real pan, a balance, inverted (the band goes the other way), and that rows added before still show the mark at the top. The control name is "Pan" in the menus and the inspector. Found (Bianca): all good.

- [x] 94. (0.14.45) Rack 2's EQ: frequency parameters show as frequencies ("1000 Hz", "1.2kHz"), not percentages. If some are still percentages, send Data/FOHMate/param_text_rejects.txt (plug-in, parameter, the text the plug-in gave) so the rules can be fixed from it. Found (Bianca): all good.

- [x] 93. (0.14.44) A width band or Q band shows its yellow default mark as two short lines (like the min/max marks, but yellow) at the two edges of the band the default value would give (not one arrow). A pan or width whose default is mono (minimum): the two lines are close together at the top, as thin as the thinnest band. Q band: the lines follow the narrower-with-higher-Q rule. Inverted rows and the "Default mark" choices in the inspector still move the marks. Plain encoders keep a single arrow. Found (Bianca): all good.

- [x] 92. (0.14.0) Q and pan/width. (a) A parameter named "Q", "Quality", "Band 1 Q" gets the **Q band** (Automatic, or right-click > Control): at the minimum the band is as wide as it can be (minimum mark to maximum mark), at the maximum it is the thinnest line, so a higher Q = tighter. Check it with a real EQ's Q, and that "Width band" (bandwidth, knee, stereo width) still gets wider with the value. (b) Add a pan and a stereo width to the Performance (re-add them: existing rows keep the mark they had, or change it in the section on the right): the pan's yellow mark is at the center (12 o'clock), the width's is at the minimum end (7:30, mono); a width turned all the way to mono sits on its mark. Double-click returns to it. (c) Edit mode: right-click a row > Remove this row: the row goes (it crashed before: the function was missing); the check box in the Performance parameters window is empty again; Cmd-Z brings it back. Found (Bianca): all good.

- [x] 91. (0.14.0) Settings (Options > Settings...), Plugin list and Performance parameters: each opens next to the
  Plugins Host window every time (also with REAPER on a second screen, or after moving the windows),
  and none of them has a fold arrow any more. Found (Bianca): all good.

- [x] 90. (0.14.0) Parameter rows (Performance mode). (a) Edit mode: the + at the end of a column
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
  with a plug-in whose rows were all added. (Rollback point before this: tag `perf-checkpoint-3`.) Found (Bianca): all good.

- [x] 89. (0.14.0) Performance mode, Show mode: the only meters are thin horizontal bars either side
  of the chevron (input left, output right, mirrored: tops and clip lights both next to the chevron; one bar for a mono rack, two for stereo; clip marker at
  the right end, peak hold tick), visible folded and unfolded. No vertical meters; the FX section
  uses the full width of the rack when open (FX names, the + button, drop zones, drag and drop
  of FX all still right?). Edit mode keeps the full racks with vertical meters. Readable but not
  noisy? Also with "no meters" on (nothing drawn), a bypassed or muted rack, Daylight mode, CPU.
  (Rollback point before this: tag `perf-checkpoint-2`.)
  All three (87, 88, 89): ok.

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

- [x] 87. (0.14.0) Performance mode rows show their value: a small vertical box between the control and
  the name, with placeholder values that fit the parameter ("-18 dB", "4:1", "12 ms", "250 Hz",
  "+3 dB", "50%", "8 kHz", "80 Hz"). With the control on the right the value reads top to bottom
  (clockwise quarter turn), with the control on the left it reads bottom to top (counterclockwise).
  Legible at a glance? Right size, thickness and distance from the name? Also in Daylight mode and
  with many rows (CPU gauge while scrolling 40 placeholder rows in two or three columns).

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

- [x] 71. (0.11.18) Docked Plugins Host: Rescan all box in front with the Plugin list, Settings, or
  both open (follows the one clicked last); floating Plugins Host normal; Plugin list's own box ok.

- [x] 70. (0.11.17) Confirmations over the window that asks: Plugin list Rescan (button and
  right-click), Settings Reset, closing the list while asking, Delete FX: ok. Latency > Rescan all was
  hidden behind the Plugin list with Plugins Host docked: fixed in 0.11.18, see 71.

- [x] 69. (0.11.16) Plugin list: clicking a developer again shows all developers; Stereo from here
  picked again on the stereo point goes back to automatic: ok.

- [x] 68. (0.11.15) Script runs as FOHMate.lua from the action, toolbar and shortcut; meters ok.

- [x] 67. Fresh install on a new Mac (0.11.14): starts clean, no error, everything looks good.

- [x] 66. Closed, not needed: the 0.11.9 file is replaced by 0.11.18 once merged into main.

- [x] 65. Migration on the Live Rack machine: settings, mode, dock, window sizes, favorites, recent FX,
  latency list, racks' saved data and meters all carried over; nothing copied twice: ok.

- [x] 64. Rename: no "Live Rack" anywhere on screen; Plugins Host titles, FOH-Mate Settings, Open the
  FOH-Mate data folder: ok.

- [x] 63. (0.11.14) Mono key follows the FX's width: soothe3 on a mono rack gets a mono key (bus size
  1, one key pin on channel 3); the sum is two -6 dB receives into that channel; turns stereo with the
  rack and back: ok.

- [x] 62. (0.11.13) Key dots in the gap between name and key button; name button width unchanged: ok.

- [x] 61. (0.11.12) Plugin list: click a column header to sort, again to reverse, arrow shows column
  and direction; Latency/Highest biggest first, star puts favorites first; Sort drop-down gone: ok.

- [x] 60. (0.11.11) Plugin list Developer column, developer drop-down with its own search field,
  click a developer to filter: ok. Clicking it again didn't show all developers: fixed in 0.11.16, ok.

- [x] 20-23, 44-46. **Clicking glitch** (mouse couldn't click in plug-in windows or FOH-Mate menus):
  never happened again after extensive use since; considered fixed. Cause never found. What was known:
  soothe3 windows and the Plugins Host window both stopped taking clicks, no sidechain involved, no
  confirmation box open, seen in Show mode with only 3 soothe3 instances open; closing and reopening
  FOH-Mate did not seem to fix it. If it comes back: check for an invisible window over the dead areas
  (Cmd+Shift+4 then Space), a hidden REAPER dialog (Cmd+` or Mission Control), and whether other
  plug-in windows and Edit mode are affected too.

- [x] 59. Options > Stereo pairs on odd-even channels only, on and off: ok.

- [x] 58. Key dots: one for a mono key, two stacked for stereo, none without a key: ok.

- [x] 57. Dots on mono, stereo and mono-in/stereo-out racks, glowing stereo point, centering, Daylight: ok.

- [x] 56. Favorites and Recently used under the search field (+, Insert FX, Replace FX); last 5
  different FX, newest first; Settings > Behavior > Recently used FX count, 0 hides it: ok.

- [x] 55. Plugin list selection (click, Cmd-click, Shift-click, Select all, Clear) and Rescan selected:
  ok. The rescan first froze every FOH-Mate window: its confirmation box opened late or hidden behind
  the Plugin list. Fixed in 0.11.17 (see 70); the rescan then works perfectly.

- [x] 54. Plugin list stars: gold on click, off again, Favorites checkbox, favorites in the + menu,
  kept after a REAPER restart: ok.

- [x] 53. FX > Plugin list: every FX listed, type colors, latency/Highest/Status, red names over the
  limit, Allowed box, name/type/developer filters, latency checkbox, sort: ok.

- [x] 52. Help line: every hovered control, rack and FX drags with Cmd/Opt, Edit and Show hints: ok.

- [x] 51. (0.11.10) Open the FOH-Mate data folder in Options, gone from Latency: ok.

- [x] 50. FX types in their own color everywhere (All FX submenus, latency list, scan window,
  confirmations, Settings).

- [x] 49. Developers > MeldaProduction: letter submenus A, B, C... (no single M).

- [x] 48. bx_console AMEK 9099 (VST3) goes mono on its own on mono racks (bus size 1), back to stereo
  on stereo racks; stereo point respected.

- [x] 47. bx_console AMEK 9099: setting **Plug-in bus size** to 1 by hand makes it mono ("2 in 1 out"):
  FOH-Mate's request wasn't sent because the plug-in doesn't list it as supported (fixed in 0.11.7).

- [x] 43. **Retry failed FX** scanned the 3 failed FX with no crash, Cenozoix AU included: it only
  crashed when loaded in the middle of a long scan, not on its own.

- [x] 42. An interrupted scan is offered to be continued, from the right place.

- [x] 41. Rescan all leaves out FX marked failed.

- [x] 40. The scan log keeps the part before a crash.

- [x] 39. Pause between FX: only one crash in a full rescan (TBTECH Cenozoix Compressor AU, again; its
  VST3 loads fine and reports 4 samples). The rescan stopped there, about a third of the way through:
  fixed in 0.11.6 (see 41-42).

- [x] 38. FX hover shows latency (also 0) when the box is on Always.

- [x] 37. **!! RACK** tag on top of the red frame.

- [x] 36. Remove every FX and other FX-changing actions: no error.

- [x] 35. Cmd+click on macOS.

- [x] 34. No windows opened during the scan.

- [x] 33. More AUs report latency with the extra wait (Spec Craft AU: 2048, same as VST3). One crash
  instead of four (TBTECH Cenozoix Compressor AU).

- [x] 32. Data folder opens in Finder.

- [x] 31. Rack latency box modes work (FX hover for Always added in 0.11.5, see 38).

- [x] 30. FX switched off are not counted.

- [x] 27. Key button on every plug-in with a sidechain input.
- [x] Full scan: about 10-15 min for ~700 plug-ins, including 4 crashes/restarts.
- [x] A plug-in that crashes REAPER during a scan is named on the next start and marked failed.

- [x] 26. Meters: one bar for a mono side, two for a stereo side.

- [x] 25. Not applicable: no plug-ins with separate Mono / Stereo versions installed (no Waves).

- [x] 28-29. Rack limit / FX limit alerts work (tag position fixed in 0.11.5, see 37).

- [x] 24. Mono racks: VST3 and AU plug-ins that accept the bus size switch to mono.

- [x] 15. Scan window shows the plug-in being loaded.
- [x] 16-19. Spec Craft (Three-Body Technology), AU: always has latency, but reports it only after a
  while (or once oversampling is switched on). REAPER's figures match once reported. No playback.

- [x] 14. One JSFX window opened during the scan (fixed in 0.11.3, see 34).

- [x] 11. Crashed plug-in shows as failed in the list. (The file couldn't be found: 0.11.3 adds a menu
  item that opens the folder, see 32.)
- [x] 12-13. AU vs VST3: Acme Opticom XLA-3 (Plugin Alliance): VST3 reports 32 samples (REAPER
  applies 64, rounded to the buffer), AU reports 0. Turning the VST3 off drops the chain to 0/0. The AU
  doesn't report its latency, so REAPER can't compensate it and the watchdog can't see it.

- [x] 10. "Scan the rest" only scans plug-ins not measured yet.

- [x] 9. Windows keep their size.

- [x] 8. Alt-click on the level box.

- [x] 6. FX type colors follow the settings.

- [x] 5. FX menus: colored type, red latency.

- [x] 4. FX search: no shortcut or menu problems so far.
- [x] AU vs VST3, full scan of 826 FX: 249 plug-ins installed as both; 85 pairs differ, always AU 0 vs
  VST3 > 0. Almost all Plugin Alliance (e.g. ADPTR StreamLiner 15000, bx_limiter 304, Lindell channels
  52, Acme Opticom 32), plus sonible smartgate, Denise Perfect Plate XL, LEWITT Space Replicator.
  MeldaProduction, TBTECH and Black Salt report the same in both. For those vendors, prefer VST3 live.
- [x] Failed to load: TBTECH Cenozoix Compressor (AU, crashed REAPER), Cut Classic High Flyer (VST3),
  fiedler audio splat (VST3).

- [x] 3. Search field ready to type, results after 0.5 s, Enter picks the first.

- [x] 2. Search "de" with FX that have latency: no error.

- [x] 1. Top bar layout, title centered, buttons wrap.
