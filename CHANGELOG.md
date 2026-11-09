# Changelog

Changes since the last public release, grouped by minor version (revisions are folded in).

## 0.14

- Changes from outside FOH-Mate (the FX's own window, MIDI learn): a parameter with a Range or a List of ranges that stays outside them for half a second goes back to the nearest allowed value, on every rack, shown or not (not while the Racks window is closed, and not when the parameter has an automation envelope). Until then the hand shows the real value, past the arc, and the dot where the control is.

- List of ranges with Skip the gaps off: new option "Snap to nearest limit" (off by default). Off, the value waits at the last allowed value while the control turns through a gap, until it reaches the next range; on, it takes the nearest allowed value (as before). Greyed out while Skip the gaps is on.

- A stepped encoder's limits sit on its steps: the Range and List of ranges handles move a step at a time, limits set before move to the nearest step by themselves (the arc then starts and ends on a step mark), and the curve graph shows a dot for each step.

- A List of ranges is shown from low to high, each range with only its remove button (moving them up and down did nothing useful); with the full range and the gaps skipped, the ranges follow one another from low to high.

- Limits, new rules (encoders, width and Q bands, pans). A Range: the control stops at Min and Max again; new option "Limit only values": the control turns all the way while the value stays in the range. A List of ranges (and a Range with Max below Min, which loses its notch): the control turns between the lowest and the highest limit; new option "Skip the gaps" (on by default; lists made before keep what they did): the control jumps over the gaps, or, off, turns through them while the value waits at the nearest allowed value. Full range: one range covers the whole travel; several cover it from the lowest to the highest limit, gaps included, or one after the other when the gaps are skipped. A curve now covers the stretch the control turns through (the whole travel with Limit only values). The pink dot shows wherever the value and the control can differ: with a curve, Limit only values, or gaps that are not skipped. The Curve section warns when a curve meets Skip the gaps (the control may jump several times) or Limit only values.

- A width or Q band with limits but no curve: its dots reach both ends of the travel, like with a curve (the control keeps where it is turned to).

- A width or Q band with limits shows the position dots also without a curve.

- A parameter named with BW (bandwidth), such as "BW" or "Band 2 BW", gets a width control.

- The position dot reaches both ends of the travel also with limits: a value the FX rounds (a stepped encoder, a limit between two of its steps) no longer pulls the control back.

- The position dot also shows with "Use the full range of the control" on.

- An encoder with a curve and limits shows a small pink dot on its ring where the control itself is turned to, next to the hand that shows the value (a width or Q band: a dot at each edge).

- An encoder with a list of ranges (or an inverted range) and a curve: its hand no longer shows values in the gaps, while dragging or scrolling; it jumps straight across them.

- An encoder with a curve and limits (without the full range): the mouse wheel keeps the position it was turned to, so it can now cross a stretch that is not allowed instead of sticking at its edge; the control no longer jumps back after a drag. The Curve section says how a curve behaves with limits and offers a button to use the full range of the control.

- Stepped encoders turn slower with the wheel (about 2.5 notches per step; lists and drop-downs still one value per notch). Show mode closes the Parameters and Inspector windows and Edit mode brings them back (Settings > Reopen the Parameters and Inspector windows). Each Inspector edit (limits, list values, ranges, curve, nickname...) now gets its own undo point, "Rack: edit parameter settings", once it has been still for half a second (one point per drag, not per frame).

- Inspect FX... opens both the Parameters tree and the Inspector (it only opened the Inspector). Changing the control type of several parameters at once asks first ("Change the control of N parameters to ...?"), with a "Don't show this again" check box (Settings > Reset warning popups brings the question back).

- Wheel: Cmd/Ctrl and Shift are seen over a control even when the Racks window has no keyboard focus (with js_ReaScriptAPI installed); smooth controls turn slower (0.6% of the travel per notch), stepped ones and lists one step at a time, so no value is skipped; Shift+wheel on a Mac (sent sideways) turns finer. Inspector: every section starts folded; the "Add the value it has now?" question opens in the Inspector; with two listed values, Show as reads Toggle. Parameters whose every value is "Reserved" (Kirchhoff-EQ Speakers Type) are hidden like placeholders; a "%" an FX leaves after a unit ("12.0dB/oct %") is dropped. Daylight: frames have a thin outline (empty check boxes and radio buttons stay visible). Cmd/Ctrl+Z and Cmd/Ctrl+Shift+Z in a FOH-Mate window go to REAPER's Undo / Redo (not while typing in a box).

- Controls: a parameter with many named values (Kirchhoff-EQ band Type: 72, a few starting with a number) is a drop-down of all of them again; a Drop-down or Stepped encoder chosen by hand lists the FX's own values (it showed 11 positions along it, Bell missing). A slope in dB/oct no longer gets the marks of a fader.

- Parameters tree: Paste goes on the whole selection also when the parameter right-clicked is selected through its group, its FX or its rack (it said "Paste" instead of "Paste on the N selected"). Curves: Reset the curve (and any custom curve of two points) is a straight line again, not an S.

- Parameters tree: clicking a rack's name selects the rack in the Racks window too (Cmd/Ctrl or Shift: adds it to the selection).

- Parameters window: right-click a rack's name to select it in the tree (Shift+right-click: and unfold it, with its FX and groups); a rack can be selected in the tree like an FX (click its name; the arrow folds it), which selects all its parameters. FX right-click > Inspect FX... selects the FX in the tree and opens the Inspector.

- Parameters: right-click a parameter (a rack's row in Edit mode, or the Parameters tree) > Copy its limits, its curve or both, and Paste them on another parameter, or on the whole selection in the tree. Pasting puts the parameter in the Performance if needed, and gives it the copied one's control when its own can't take what is pasted.

- Performance mode: the help line of a parameter section's handle says whether it folds back by itself in this mode (in Edit mode, only with Settings > Also fold them by themselves in Edit mode).

- Performance mode: **the mouse wheel (or two fingers on a trackpad) turns the controls**, in the racks and in the Inspector's Preview: an encoder, band or pan moves smoothly (Shift: finer), a stepped encoder, a list or a drop-down moves a step at a time, a toggle goes on (up) or off (down); the column (or the Inspector) doesn't scroll while the pointer is on a control. With **Cmd (Ctrl on Windows) + wheel**, the **current range** (the one the value is in, Range or List of ranges) changes: up / down moves it, stopping when one of its ends reaches the value or the gap before another range; sideways makes it wider or narrower (the value stays inside). The help line at the bottom of the window says so when the pointer is on a control.

- Inspector, Preview: the control has its **value box** on its right, like in the rack (the value written the same way, updated as it moves).

- Limit values: switching to **List of values** asks whether to add the value it has now; **Cancel** now leaves the limits as they were (the mode you came from, or no limits), instead of switching to the list like Don't add.

- Inspector: the curve's **Type** is above the graph; Strength (or Smooth) and Save / Delete a curve are under it (Delete only when you have saved curves of your own). The **Preview** can be **turned**: it is the same control as in the rack (limits, list, curve, drop-down, toggle), and moving it moves the parameter. **A list of values with only two values is a toggle**: off is the lower value, on the higher one (in the rack and in the Preview).

- List of ranges: a range dragged as a whole (by its blue part) can now **go past another range**: it goes to the nearest place where it fits, on either side of the others (the gap away from them), instead of stopping at its neighbour.

- Range control: each handle now sits **inside its range** (its flat side on the value, its tip pointing into the range), so the space seen between two ranges of a list is the real gap; before, the handles stuck out of their ranges and neighbouring ranges looked like they overlapped. The blue part's ends hide under the handles' flat sides.

- Limit values: the kind of limits (**Range**, **List of values**, **List of ranges**) is a **menu right of Use limits** (choosing one also turns the limits on). An inverted Range always has the **notch** (the option is gone). The range control: the blue part goes on a little under each handle (no visible end), and **dragging the blue part moves the whole range**. **List of ranges**: ranges never overlap, and stay at least a gap apart (Settings > Performance mode > **Gap between ranges in a list**, 2% of the travel at first); **Add a range** makes a small one as close to the value it has now as it can, outside the others, and is gone when there is no room left; **Invert: the gaps between the ranges are the ranges** (the value moves to the nearest allowed one only when a control is next turned).

- Limit values: **Min / Max is now called Range**, set on a new **range control**: a thin bar with a handle for Min (pointing right) and one for Max (pointing left), the covered part in the link color, a value box on each side (type a number; the unit after the box), and Set to the value now: Min / Max. **Inverted range**: Max below Min allows the values up to Max and from Min up (two ranges, shown on the bar outside the handles and by two arcs on the control); a **Notch between the two ranges** check box then appears: going from one range to the other takes a step of the control (the value holds, then jumps). With **Use the full range of the control**, the two ranges follow each other over the control's whole travel, with a mark where they meet. New mode **List of ranges**: any number of ranges (Min below Max), each on a range control, reordered and removed like the list of values (arrows, red x), **Add a range** adds a small one around the value it has now; with the full range they follow each other in the list's order, a mark at each junction; without it the control keeps to the nearest range. The range control can also be drawn read only (small handles, plain values) for later uses.

- Inspector, Curve: the graph is **square** (a 1:1 scale), as wide as the Inspector allows (from 120 to 260 px); the options under it keep its width.

- Performance mode: **every control sits in the middle of its area** (encoders, width / Q bands, pans, stepped encoders, drop-downs, toggles), on left and right rows alike; the area is a little wider than the control, so its marks (the default arrow, the min / max ticks) and the arc of its limits stay inside the row and its glow. The gap to the value box is back to what it was.

- Performance mode, parameter columns: the rows reach closer to the position bar (a 2 px gap instead of the padding), and take the **whole width of the column when everything fits** (no bar). The gap between a control and its value box is 2 px wider, and a control with the arc of its limits sits a little further in, so the arc stays inside the row and its glow on both sides of a column.

- Inspector: the top (the parameter's name, its nickname box, the FX) stays at the top; the sections under it (Control, Direction and default, Limit values, Curve, Preview, Details) scroll under it, with a line between the two.

- Fix: FOH-Mate stopped on an error ("attempt to compare number with nil", curves.lua) when the Inspector showed a curve, and could do the same in Limit values > Min / Max and in Settings: a text width was compared with a missing second value.

- Fields read **caption first, then the field, then its unit**, everywhere it wasn't the case: the Inspector's curve (**Type**, **Strength**), its **Min** / **Max** (caption, the value, its unit, then Now), the value slider of a list of values (value, unit, then Add), and the whole **Settings** window: captions in a column on the left, the fields lined up after them, the units after the fields ("px", "s", "dB"...), the colored type names before their color swatch. The tooltips also show over the captions. Check boxes keep their box before the label.

- Daylight mode: the **+** at the end of a parameter column, its hover glow, the band over a parameter column (its triangles), the "..." of the parameters and the handle under a rack in Show mode were drawn in the color of the rack names, nearly invisible on the light background. They now take a color that stands out from the rack's background: dark in Daylight mode, light otherwise.

- The **Parameters** and **Inspector** windows left open when FOH-Mate closes **open again** when it starts, where they were (floating or docked). Settings > Performance mode > **Reopen the Parameters and Inspector windows** (on at first) turns it off. Only when it starts in Edit mode; the windows closed by switching to Show mode count as left open.

- **Display > Windows** has **Dock Parameters** and **Dock Inspector**: Floating, or Docker 1 to 16 (the window opens if it is closed). Dropped on a docker that holds one already, a window becomes a tab of it (REAPER's dockers hold tabs); to have them side by side, put them in different dockers on the same side of REAPER's window.

- Naming cleanup: the FX list module, its code identifiers, its menu label and the ReaPack About source now use the current names consistently. The FX list keeps its saved window ID, and parameter nicknames and hidden-parameter data keep their existing keys.

- The window of the racks is now called **Racks** (it was Plugins Host). The **Parameters** window (the tree, until now "Performance parameters") and the **Inspector** each have a context of their own, so when they are docked, REAPER's docker tab shows their name: **Racks**, **Parameters**, **Inspector** (it said "FOH-Mate" for all of them). Parameters and Inspector come back where you left them, floating or in their docker. They only exist while open (Edit mode), so they cost nothing in Show mode. Settings and the FX list stay floating windows. (Tag v0.14.106-rollback marks the version before this change.)

- The parameters are now **two windows that don't depend on each other**: the **tree** ("Performance parameters": the racks, FX, groups and parameters with their check boxes, search, Add to / Remove from Performance) and the **inspector** ("Parameters inspector": the settings of what is selected). Each one opens, closes, floats and docks on its own (drag it into a docker, or to another screen); closing one leaves the other open. **Display > Windows** has **Show parameter treeview** and **Show parameters inspector**. The **+** opens both; **Inspect parameter...** and a double-click on a parameter open the inspector (and leave the tree as it is). The selection is shared: picking in the tree fills the inspector, clicking a parameter in a rack selects it in both; the glow and the scrolling in the racks work with either window open.

- Performance parameters window, inspector: what is selected in its tree and is a parameter of a rack **glows in the rack's column** (the same white glow as the row under the pointer). A single parameter picked in the tree is also **scrolled to**, once: the Plugins Host window scrolls sideways to bring its rack into view, and the rack's column scrolls (up and down, or sideways when widened) to show the row. A parameter clicked in the rack itself doesn't scroll anything.

- Fold by itself, redone around the handles. **Edit mode, the configuration mode, no longer folds by itself by default** (Settings > Performance mode, **Also fold them by themselves in Edit mode**, turns it on). **Show mode**: clicking a handle (under a rack's FX section, or the band over a parameter section) opens or folds it, and an open one folds back after a while as set in **Display > Fold automatically**. **Right-click a handle**: it becomes a **push pin** in a contrasting color and the section stays open until you click the handle (which folds it); a second right-click takes the pin off and the section folds back by itself again as set. The hints at the bottom of the window explain each state. The per-rack and per-section "Fold by itself" menus are gone.

- Parameter window, list of values: the **Add the value it has now** button is gone. Choosing the list (Use limits, or the List of values choice) asks instead whether to add the value it has now, when it isn't in the list yet (once the list is on, the parameter only takes the values of the list). The value field and its Add button are together as wide as the list, like the menu of the plug-in's own values, and the **Show as** caption is right above its menu. The general fold-by-itself setting is now also in the **Display** menu (**Fold automatically**, under Performance mode) as well as in Settings. **Settings** has a search field at the top: it lists the settings whose name (or group) has the text, with their groups open.

- Performance mode, Edit mode: **double-click a parameter's name or value box** opens the parameter window on it (selected in the tree, as when it is already open). On the control, a double-click still goes back to the default mark.

- Performance parameters window works as an **inspector**: with it open, click (or start turning) a parameter in a rack's column and the window selects it in its tree: its rack, FX and groups open, the tree scrolls to it, and a search that would hide it is cleared. The settings on the right show that parameter.

- Parameter window, list of values: a unit the plug-in prints twice ("1000 Hz Hz") shows once. Each value of the list is in a **box in the parameter's color** (the color of its name in the tree), with its **unit outside the box**, to the right. A number can be typed in the box (Enter or click away): the parameter is asked for the position that prints it, with that unit, and the value of the list becomes that one (nothing happens when no position prints it). Text values ("Low Pass") are shown in a box that can't be typed in. The same single unit shows in the Min / Max sliders, the "Add one of its values..." menu and the drop-down.

- Performance mode: **FX have a color**. Right-click an FX in the rack (or in the parameter window's tree) > **Color...**; **Automatic** gives back the rack's color, which is what every FX has at first. The parameters of an FX take its color (still shifted for a group, still changeable one by one with Recolor parameters). An FX with its own color shows it as a small tab on its button; the colors are saved with the rack and go along when it is duplicated. In the parameter window's tree, rack names are in the rack's color, FX and their groups in the FX's, made lighter or darker to stay readable. **The hover link follows the colors**: point at a parameter and its FX glows in the parameter's color; point at an FX and its parameters glow in the FX's color. The glow is made vivid whatever the color (lighter on a dark window, darker in Daylight mode), strong, and pulses a little, so it stays visible.

- Performance parameters window, tree: the thin dotted outline is now on the **branches**, not around the area: a dotted line runs down each open branch (rack, FX, group), from under its arrow to its last line. FX are indented one more step under their rack (their arrow sits under the first letter of the rack's name).

- Performance parameters window, the tree is redrawn: **every rack** of the project is a branch (the one you opened it from is open; the others open with their arrow), with its name in a **bigger bold font**; FX and groups ("Band 1"...) have a smaller bold name, still bigger than the parameters. The check boxes are all the same size and line up in columns whatever the font: what is inside a branch is one step in, so its check boxes start where the branch's name starts, and a group's check box lines up with its sibling parameters' (its arrow is left of it). The names of parameters in a group no longer repeat the group ("Band1 Type" shows as "Type"; hover for the full name). **Subgroups**: in a group, parameters that start with the same word ("Dyn. Threshold", "Dyn. Ratio"...) get a branch of their own: Rack > FX > Band 1 > Dyn. > Threshold. Parameter names are drawn in their color in the rack (their own, or the rack's shifted for their group), made lighter or darker to stay readable. A thin dotted outline surrounds the tree. Right-click > Inspect parameter opens the branches down to the parameter.

- Settings: the sections have the same bold, slightly bigger titles as the parameter window (every folding section in FOH-Mate now looks this way). Parameter window: the tree is indented the right way: an FX's parameters sit one step further in than the FX, like its groups (REAPER, Band 1...), and a group's parameters one step further in than the group. The kind and value column lines up on every line, however deep.

- Parameter window, Curve: right-click the graph of a custom curve (not on a point) > **Reset the curve (a straight line)** starts it again from its two ends. Right-clicking a point still removes it.

- Parameter window: the right side is in sections that fold, each with a clear title a little bigger than the text: **Control**, **Direction and default**, **Limit values**, **Curve**, **Preview** and **Details** (what REAPER says about the parameter, folded at first). The parameter's name at the top is bigger and bold; right under it, a box for its **nickname** (set when you leave the box, or press Enter; empty gives back its own name; only for a parameter in the Performance). The Limit values check box is now called **Use limits**.

- Parameter window, Curve: the graph is 10% bigger; under it come **Save this curve...** and **Delete a curve...** side by side, then **Type** (the kind of curve) and its **Strength** or **Smooth**, none wider than the graph, captions included. The examples are all different from Ease in / Ease out: S curve, Fine in the middle, **Rising wave**, **Parabola**, **Valley**, **Staircase**, Wave, Zigzag (a row that used the old "Ease in" or "Ease out" example keeps its curve).

- Racks: the **Out** menu lists **mono** outputs before stereo pairs, like everywhere else.

- Performance mode: a parameter whose values are all words (no numbers) gets a **drop-down** automatically, also when it has many values: a band type with 72 values, most of them "Reserved" (Kirchhoff-EQ), was a smooth encoder. Placeholder values no longer count when telling numbers from words.

- Performance mode, Edit mode: a **"..."** in the top right corner of the parameters, above the position bar, has what the right-click menu of the **+** had (remove the parameters not linked any more, Clear all). The **+** only opens the parameter window. Right-click a parameter > **Inspect parameter...** opens the parameter window on it (it replaces "Limit values...").

- Performance parameters window: parameters that aren't meant for the user are hidden: placeholders ("Reserved", "Unused", "-", nameless, "Param 12") and the MIDI CC entries many VST3 plug-ins add by the hundred. Right-click a parameter > **Hide this parameter** hides one by hand, for that plug-in in every project (Data/FOHMate/param_hidden.txt). **Show hidden**, next to the search, lists them all again, dimmed and marked "(hidden)", where a hand-hidden one can be shown again. REAPER's own **Bypass**, **Wet** and **Delta** are in a **REAPER** branch at the end of each FX. Placeholder values (a band type's "Reserved" choices) are left out of drop-downs, of stepped encoders (which then go through the other values only) and of the list of values.

- Performance mode: **value curves** for encoders (smooth and stepped) and width / Q bands, in the parameter window (section "This parameter", under Limit values). Dragging moves evenly along the curve, and the encoder shows the value it gives, so it rises and falls with the curve while you drag one way: **Linear**, **Ease in**, **Ease out** (with a Strength), or **Custom points** (click the graph to add a point, drag to move, right-click to remove; **Smooth** joins them with a curve, otherwise straight lines). A curve can go up and down, so one turn of the control can make the value rise and fall. The graph shows where the control is now. **Save this curve...** keeps a curve for any parameter and project (Data/FOHMate/param_curves.txt); examples are provided (S curve, Fine in the middle, Up and down, Wave, Zigzag...). With Min / Max and the full range the curve fits between Min and Max; not with a list of values. The dB marks, the default mark and the limits arc stay where the values are. When the value jumps far in one go (a steep curve dragged quickly, or a change from the plug-in or automation), the encoder's pointer sweeps over the top to its new place, quickly, so it never seems to pass under the encoder.

- Performance mode: **Limit values** has a second way, a **List of values**: the parameter only takes the values of a list, in the order you choose (any order, not necessarily consecutive). Add the value it has now, one of the plug-in's own values, or one picked with a slider; move values up and down, or remove them (the arrows, none up on the first and none down on the last, and a red x on the right of each value). The control becomes a stepped encoder with one step per value, or a drop-down of them: automatically (a drop-down for a plug-in's named values, a single value or more than 12 values) or as you choose under **Show as**. Not for a toggle. Switching between Min / Max and the list, or unticking Limit values, keeps the settings of both for later.

- Performance mode: a parameter's values can be **limited** to a Min and a Max (the parameter window, section "This parameter", or right-click a parameter > **Limit values...**), for encoders, stepped encoders, width/Q bands and pans. The sliders show the plug-in's own values, and **Now** takes the current one. With **Use the full range of the control**, the control turns all the way from Min to Max, for finer moves; without it, the control stops at Min and Max, shown by a thin arc in the link color outside the marks, with a handle from each end to the encoder (drawn as one line, so the corners join cleanly). On a width or Q band, two mirrored arcs show where the band's edges can go. That encoder sits a little more toward the middle of the row, so the arc isn't cut off at the edge of the column. The value box of every row sits a little closer to the name, leaving more room for the control. Setting the limits moves a value that is outside them inside at once. Saved with the parameter in the project (also when duplicating a rack).

- The **Display** menu is in three groups between lines: **Daylight mode** and a **Colors** submenu (Recolor every rack, Choose default color..., New racks use automatic / default color); **Performance mode** and **Hide disabled parameters**; a **Rack latency box** submenu (Off, Always, Only when a rack has latency) and **Dock**.

- Performance parameters window: parameters with the same prefix (an EQ's **Band 1**, **Band 2**...) are gathered in a branch of their own under their FX, with its own check box to add or remove them all.

- Performance mode: parameters of the same group (an EQ band: "Band 1...", "Gain-Band 2"...) get the rack's color slightly shifted, one way for odd bands and the other way for even ones, so neighbouring bands stand apart.

- Performance mode: the right-click menu of a parameter has a **Control** submenu, then **Nickname parameter...** and **Recolor parameters** (this parameter, its band, or every parameter of its FX; "Automatic" goes back to the rack's color). With **Settings > Performance mode > Remember parameters nicknames** on, a nickname is remembered for that plug-in and given to the parameter whenever it is added again.

- Performance mode: right-click the **+** at the end of a column to remove the parameters that aren't linked any more (their FX removed or changed).

- Performance mode: the **Width band** and **Q band** have a new scale. The middle of the range (a normal stereo width, the center of an M-S width) is a half circle, from 9 to 3 o'clock; the maximum still reaches the min and max marks, the minimum is still the thinnest line.

- Performance mode, Edit mode: parameters can be **reordered by dragging** their name box, with the same look as dragging an FX (a bar follows the pointer, the parameter stays behind faded, the target is outlined). Drop on a parameter to take its place, or on the + to put it at the end.

- Performance mode: pointing at an FX name in a rack makes that FX's parameters glow in their own color (sky blue, orange in Daylight), and pointing at a parameter makes its FX glow.

- Performance mode: deleting an FX (**Delete FX...**, **Remove every FX**, **Remove bypassed FX**) that has parameters in the Performance always asks first, saying how many it has: **Delete FX and parameters**, **Delete FX, keep parameters** (they stay, greyed out), or Cancel. Ctrl+Z brings everything back.

- Performance mode: a new FX on a rack (added from the menus, dropped from another rack, or Replace FX) takes back the kept parameters of a deleted FX of the same plug-in: every one of them must be found, with the same name, at the same place in the new FX. One deleted FX per new FX, and only for an FX that has no parameters in the Performance yet.

- Performance mode: **Display > Hide disabled parameters** leaves the parameters that aren't linked any more (greyed out) out of the columns. They are still there, and show again when the option is switched off or when a new FX takes them back.

- Performance mode: the menus, confirmations and hints call the rows of a column **parameters** (Remove this parameter, Delete FX and parameters...).

- Performance mode: the right-click menu of the **+** has **Clear all**, which removes every parameter of that rack (after a confirmation; Ctrl+Z brings them back).

- Performance mode: a rack made with **Duplicate rack** (menu or Cmd-drag) or **Use as template** keeps its parameters working: they now control the copy's own FX. Before, they still pointed at the original's FX and showed as removed.

- For editing only: a `.luarc.json` settings file tells VS Code's Lua checker about the names REAPER and FOHMate.lua provide, so it no longer marks them as errors. Nothing changes in REAPER.

- Test versions only: the status bar shows a **debug timer** after the latency: how many milliseconds FOH-Mate's script takes per frame, and how much of it the racks area takes (Performance parameters included). Its tooltip adds the slowest frame of the last 2 seconds. Public versions have it switched off.

- Performance mode uses less CPU: each parameter row keeps what the plug-in last told it (its value's text, whether the parameter is still there, a Pan/Width's stereo placement, how the name wraps) and only asks again when the value moves or after a short while, instead of on every frame. The vertical values are drawn with a few joined lines per character instead of one call per line (sharp corners such as the tips of V and W stay as they were), and redrawn as they are while the value and the row don't move.

- Performance mode: the **Pan** control shows a tiny arrow (smaller than the default mark, its back on the center line, the same size both ways), left or right, when the value is less than 10% off center (up to 9L / 9R), and the band from 10% on, starting as long as the arrow so the switch is smooth; a small vertical line (where the arrow's back is) marks the exact center. A combined **Pan/Width** parameter of an EQ band (the Kirchhoff EQ, for example) follows the band's stereo placement parameter, found by its name: a pan for Stereo, a width for MS (its value then reads M / S, e.g. 100M to 100S, even when the plug-in prints L / R, however it writes them: 100L, L100, Left 30...), and greyed out for Left, Right, Mid, Side and Mono. Placement texts it doesn't know are noted in Data/FOHMate/param_text_rejects.txt.

- Performance mode: a pan or balance gets its own control, the **Pan**: the yellow default mark is always at the top (the center), a band runs from the top to the left or to the right following the value (7:30 = all the way left, 4:30 = all the way right), and when centered a small vertical line sits under the mark. Also selectable by hand for any parameter.

- Performance mode: the value box tidies the plug-in's text before writing it (drops µ, ° and other unusual characters, adds "Hz" to a bare number on a frequency parameter, squeezes out spaces when it is too long) so an EQ's frequencies show as frequencies and not percentages. What still can't be written is noted in Data/FOHMate/param_text_rejects.txt, to improve the rules.

- Performance mode: on a width or Q band the default mark is two short yellow lines, at the edges of the band the default value would have (a range, not a point).

- Performance mode: a **Q** (or "Quality") parameter gets a new control, the **Q band**: like the width band but it gets narrower as the value goes up, since a higher Q is tighter (also selectable by hand). A pan added to the Performance gets its default mark at the center, a stereo width at the minimum (mono).

- Settings, Plugin list and the Performance parameters window open next to the Plugins Host window (a remembered position could leave them off the screen) and can no longer be folded.

- **Performance mode** (first step, the view): **Display > Performance mode** puts every rack in one
  row that scrolls sideways, with a column under each rack. Each column scrolls on its own: the rows
  fade out at the top or bottom edge while there is more beyond, and a slim bar on the right shows
  where you are. In **Edit mode** the racks are full racks. In **Show mode** a rack is just its name
  with **M** (mute) and **B** (bypass) buttons on the right; the handle at the bottom of the rack opens
  its FX section (with the meters beside it) and pushes that rack's column down, and clicking it again
  folds it back, both animated. **Settings > Performance mode** has a checkbox to turn the automatic folding
  off, and the time to wait (**Fold them after**, 15 s by default): open FX sections and widened
  parameter sections then fold back after that long without activity in the Plugins Host window (the mouse moving over it, a click, a drag, scrolling or a key). In Show mode the meters are thin horizontal bars either side of the chevron (input left, output right, mirrored so the tops and the clip lights are both next to the chevron), always visible, and the FX section uses the full width of the rack. **Parameter rows**: in Edit mode the **+** at the end of a column (it is not there in Show mode) opens
  the **Performance parameters** window: a tree of the rack, its FX (name and type in its color) and
  every parameter (kind of value and current value), foldable, with groups selectable (click,
  Cmd/Ctrl-click, Shift-click); **Add to Performance** and **Remove from Performance** work on the
  selection, and selecting an FX means all of its parameters. Every parameter and every FX has a check box: click it to put it in or take it out of the Performance (the buttons stay for working on a selection). The section on the right of the window shows the control of what is selected: pick another one (or Automatic), with a preview and what REAPER says about the parameter; the choice is added to the training data (below). A row shows the plug-in's name for it, its real value in the vertical box and a
  control that fits the parameter: a **rotary encoder** (7:30 = minimum, 4:30 = maximum, with small
  short lines for the minimum and maximum and a small arrow for the default, which is yellow; a band centered at the top for a width (as thin as possible at the minimum, reaching from the minimum mark to the maximum mark at the maximum: bandwidth, stereo width, knee); marks for each value
  when there are only a few; a parameter in dB gets a fader's marks instead: -60, -30, -10, -5, 0 and +5 dB where they fall), a **toggle** (a circle) or a **drop-down** (a circle with an arrow). The default
  is the value the parameter had when it was added; double-click an encoder to go back to it. In the window's section on the right, a parameter that is in the Performance can be inverted (the control turns the other way) and its default mark can be switched off or put at the current value, the minimum, the middle or the maximum. **Settings > Controls >
  Rotary encoder** picks how it turns: up and down (finer the farther the pointer is to the side) or around the
  encoder. FOH-Mate guesses which control a parameter gets; in Edit mode, right-click a row to correct it (encoder, width band, stepped, toggle, drop-down, or automatic). Corrections are kept for every project in Data/FOHMate/param_controls.txt, with what REAPER said about the parameter, so the guesses can be improved from them. Rows are saved on the rack; one whose FX is gone is greyed out. In Performance mode the
  status bar also shows how many parameters the selected rack has. The vertical value now has a stroke font for every letter (capitals and small), digit and the usual punctuation, so "Mono" or "Stereo" can be written (it falls back to a percentage only for an unusual character). A parameter with two values that are words (Mono / Stereo) is a drop-down, not a toggle. Parameters a plug-in calls "Reserved" are left out of the window. The placeholder rows are gone. Rows look like this (names in bold, controls outside the name box, alternating sides, the whole row
  glows under the pointer). Each row shows its value in a small vertical box between the control and
  the name, turned a quarter turn. A band at the top of every column
  (two small triangles) **widens the column** over the neighbouring ones: the rows then flow in
  columns that scroll sideways, and every row grows to 1.5 times its width and height, with bigger
  text and controls and room around it, and a thin divider between the columns. Clicking the band again, or a pause in your activity (same setting
  as the FX sections), folds it back to one column showing the row you touched last. Open FX
  sections fold first; all animated.

- Fixed: **BYPASS** (and the new B) did nothing in Show mode on a rack with an FX that Show mode had
  taken offline for latency: the offline FX counted as "switched on again by hand" and cancelled the
  bypass.

## 0.13

- **Latency > Count every format at its highest latency** (off by default). A plugin installed in
  several formats (AU, VST3, VST...) counts with the highest latency any of its formats reports: some
  formats, often AU, report 0 where another reports the real figure. Alerts, limits, the rack latency
  box, the FX menus and Show mode's offline step use it; REAPER's own compensation is not changed. The
  Plugin list marks estimated figures with * (hover for where they come from). Formats are matched on
  name and developer, ignoring the type, spaces, a channel count like "(4ch)" and the developer's name
  inside the plugin's name.
- **Take FX over the limit offline in Show mode** now also acts while already in Show mode: turning on
  Count every format..., changing a latency limit, or turning this option on checks the racks again.
  The FX it adds come back online with the others when you go back to Edit.
- The latency alert tag on the first row of racks is no longer cut off at the top.
- The flashing red frame of a rack over its latency limit covers the rack's own frame completely
  (thicker, same corners), so the rack's color no longer shows through.
- One gap everywhere: between racks (sideways and down) it is now the same as between the top bar and
  the first row (the room the latency tag needs plus the setting, 8 px by default: about 17 px
  instead of 8). The setting is now called **Extra space between racks**.
- ReaPack now shows an About overview of FOH-Mate (what it does, requirements, status), for the
  repository and for the package. The text lives in `tools/reapack_about.txt`.
- **Allow latency** stays per format. With the option on, allowing an FX that has other formats
  installed first says that only this format is allowed (that note can be hidden).
- **"Don't show this again"** on popups that are not critical: creating a rack by double-click,
  replacing or deleting one FX, an action on several selected racks, and the scan notes. Once hidden, a
  question is answered yes without asking. On "new effects were found, scan now?" the checkbox turns
  off **Latency > Ask to scan new FX**. Popups that delete a rack or a sidechain bus, reset the
  settings or start a latency scan always show.
- **Settings > Reset warning popups** shows every hidden popup again.

## 0.12

- The code is split into modules: `FOHMate.lua` plus a `FOHMate` folder next to it holding the rest
  (racks, sidechain, latency, menus...). Nothing changes on screen or in the sound; the code is just
  easier to read and maintain.
- FOH-Mate can be installed and updated with ReaPack (see the README). A manual install now means
  copying the file and the folder.

## 0.11

- Key dots show the width of the key's source: a mono sidechain into a stereo FX is one dot, not two.
- Sidechain fix: switching a mono rack to stereo no longer leaves the FX's Main R input listening to
  the sidechain key (which made the key come out of the rack's right channel).
- **New name: FOH-Mate.** The project was called Live Rack; it is now FOH-Mate (live sound tools for
  REAPER). The rack is its first module and its window is titled **Plugins Host**. Every "Live Rack" /
  "LiveRack" label, menu item, file name and text is gone.
- The script is now `FOHMate.lua` (in `src/` in the repository). The version is shown in the window's
  title bar only, not in the file name, so updating means replacing the file: the action, toolbar
  buttons and shortcuts keep working.
- Nothing is lost by the rename: the first time FOH-Mate starts it copies your settings, window sizes
  and dock position, and the latency list from the old names, and moves the saved data of your racks
  (bypass, sidechain keys, routing, stereo point...) to the new names the first time each rack is seen.
  The meters of the old name are replaced automatically. The old data folder (`Data/LiveRack`) is left
  in place and can be deleted once everything checks out.
- New top bar menus: **Display**, **FX**, **Latency** and **Options** (replacing the single Options
  menu). The Latency button turns red while alerts are silenced or off. The title is centered in the
  free space; in a narrow window the buttons wrap onto extra rows.
- Search field at the top of every FX menu: results replace the menu half a second after typing;
  Enter picks the first one.
- FX menus: when every name in a long list starts the same way (e.g. MeldaProduction's M...), the
  letter submenus skip that shared start (A, B, C... instead of a single M).
- FX types are shown in their own color everywhere (FX menus and type submenus, FX latency list,
  scan window, confirmations; set in **FX > FX type colors...**). FX menus also show known latency in
  red.
- Two latency limits: per FX and per rack. Alerts, hiding FX and Show-mode offline follow both. A rack
  over its own limit flashes its whole frame and reads **!! RACK**; only its biggest FX flashes.
- Mono racks: the plug-in bus size is now set on every FX that has the setting (some plug-ins, e.g.
  Plugin Alliance consoles, accept it without saying so), back to 2 on stereo parts. Unassigned
  sidechain inputs are left unconnected.
- FX that are switched off no longer count toward latency (REAPER drops them from compensation).
- Rack latency box: always, only when a rack has latency, or off.
- **Options > Open the FOH-Mate data folder** (latency list, scan log, error report).
- Latency scan: Audio Units that report 0 get a second, later look; a short pause between FX (both set
  in Settings); no FX or FX chain window is left open; the log keeps earlier runs. A scan that doesn't
  finish (crash, REAPER closed) can be continued where it stopped. **Rescan all** leaves out FX that
  failed before; **Latency > Retry failed FX...** tries them again.
- Alt-click the level box: 0 dB, or -inf when already at 0 dB.
- Windows reopen at their last size, also after being collapsed or minimized.
- FX latency list: Allowed checkboxes centered.
- Fixed: error after **Remove every FX** (and other actions that change a rack's FX from its menus).
- Fixed: choosing **Stereo from here** again on the FX that is already the stereo point now goes
  back to the automatic stereo point (it did nothing).
- Fixed: a confirmation asked from the Plugin list or the Settings window opens over that window. It
  could open hidden behind it, and every FOH-Mate window then waited for an answer you couldn't see.
  The same for confirmations from a docked Plugins Host while the Plugin list or Settings is open.
- Fixed: **Settings** showed a second **Latency** section (the two scan settings), with an error
  when hovered. Everything is now in one Latency section.
- If FOH-Mate stops on an error, the exact place (line and chain of calls) goes to REAPER's console
  and to `Data/FOHMate/last_error.txt`.
- **FX > Plugin list...** replaces the FX latency list: every installed FX with its type (in color),
  developer, latency (last and highest), Allowed and scan status. Filter by name, type or developer
  (the developer drop-down has its own search field; click a developer in the list to show only
  theirs, again to show all), and show only favorites or only FX with latency. Click a column header
  to sort by it, again to reverse.
- Plugin list selection: click, Cmd/Ctrl-click, Shift-click for a range, or **Select all shown**, then
  **Rescan selected...** (Edit mode). Right-click for Rescan and Add to / Remove from favorites. A
  failed FX can be retried this way.
- **Favorites**: click the star in the Plugin list. Every FX menu (**+**, Insert FX, Replace FX) shows
  **Favorites** and **Recently used** under the search field. **Settings > Behavior > Recently used
  FX** sets how many (0 hides it).
- Dots between the FX show the signal's width: one dot for mono, two for stereo. On a mono-in,
  stereo-out rack the stereo point glows. An FX with a key shows one or two dots next to its key button.
- Sidechain keys follow the FX's width: on a mono rack (or the mono part of a rack), an FX with a
  stereo key input gets a mono key, and a stereo key again when the FX turns stereo.
- **Options > Stereo pairs on odd-even channels only**, like most consoles: stereo inputs, outputs and
  keys start on an odd channel (1/2, 3/4...).
- A grey help line above the status bar says what clicks and keys do on whatever is under the pointer.

## 0.10

- FX latency list, shared by every project: every FX loaded in a rack is recorded with the latency it
  reports (last and highest seen). Viewable in **Options > FX latency list...**.
- **Allow latency** is now remembered per FX, in every rack and every project.
- Latency scan: **Options > Scan new FX / Rescan all FX for latency...** measures every installed
  effect in one go, showing the plug-in being loaded and keeping a log. A plug-in that crashes REAPER
  during a scan is named when FOH-Mate opens again, and skipped by later scans. Results are saved as
  they are measured: a scan picks up where it stopped, and an FX is measured again only on request.
- FOH-Mate offers to scan newly installed effects.
- **Options > Hide FX over the latency limit** leaves them out of the FX menus; follows the limit.
- **Options > Take FX over the limit offline in Show mode**, back online in Edit mode.
- **Options > Show rack latency**: a box under every rack with its latency in ms and samples.
- Version number shown next to the Plugins Host title.
- Background upkeep (mono/stereo requests, sidechain and output pin mappings) sends each change to a
  plug-in only once, instead of repeating it when a plug-in does not take it.

## 0.9

- Latency watchdog: racks over a user-set latency limit flash **!!** on the rack and on the FX
  responsible, with a status bar summary. Limit and silence time in **Settings > Latency**.
- Right-click an FX > **Allow latency** to leave it out of the count.
- Alerts can be silenced for a while or switched off from the Options menu.
- In and Out menus show the audio device in use and explain when it offers no channels.

## 0.8

- Sidechain management:
  - a key button on FX that have a sidechain input picks a hardware input (mono or stereo) or a
    sidechain bus as the key;
  - an **SC** button next to the level sends a rack to sidechain busses, with a send level;
  - busses are hidden `SC BUS:` tracks, never routed to the master or to hardware;
  - feedback loops are prevented.
- Mono, stereo and mono-to-stereo racks, set by each rack's input and output routing. FX switch to
  their mono or stereo version automatically and keep their settings. Meters follow each side's width.
- Right-click an FX > **Stereo from here** sets where a mono-in, stereo-out rack turns stereo.
- Drag a rack with the copy key held to duplicate it.
- A green **+** follows the pointer, and the drop target turns green, when a drag will copy.
- Version numbers are now *major.minor.revision*, shown in the window title.
- Fixed: error when running FOH-Mate a second time ("expected a valid ImGui_Context").
- Fixed: the **R** button could open the routing window of the wrong track.
