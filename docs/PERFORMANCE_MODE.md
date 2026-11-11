# FOH-Mate: Performance mode

How Performance mode is built (a work in progress, in the 0.14 versions). How to use it is in the README
(section "Performance mode"); ideas for later are in `docs/ROADMAP.md`.

## What it is

An optional view, switched on and off with **Display > Performance mode** (saved for REAPER, not per
project). Edit and Show keep working inside it.

```
 ┌ top bar ─────────────────────────────────────────────────────────────────────┐
 │ RACK 1                   │ RACK 2                   │ RACK 3        │ ... →   │   one row,
 │ name, In/Out, FX boxes   │                          │               │         │   scrolls sideways
 │ level, BYPASS, MUTE      │                          │               │         │
 ├──────────────────────────┼──────────────────────────┼───────────────┼─────────┤
 │ Threshold        (o)     │ Ratio            (o)     │      (+)      │         │   a quick access
 │ (o)        Attack        │ (o)        Mix           │               │         │   panel per rack,
 │ Gain             (o)     │ HPF freq       (v)       │               │         │   its own scroll
 │ (+)                      │ (+)                      │               │         │
 └──────────────────────────┴──────────────────────────┴───────────────┴─────────┘
```

- **Edit mode:** full racks. **Show mode:** a rack is its name with **M** and **B**; the handle under it
  unfolds the FX section (with thin horizontal meters either side of the handle), pushing only that
  rack's panel down. Open sections fold back after a time without activity (Settings, default 15 s;
  in Edit mode only when asked for).
- **The quick access panel** is the column under a rack: the critical parameters of its FX, at hand. A
  panel belongs to its rack (rows are saved on the rack's track, so a duplicated rack takes them along).
  Each row is one parameter: the FX's GUID, the parameter's index and the name the FX reported (to
  notice a changed FX); a row whose FX or parameter is gone is greyed out, never dropped silently.
- **Rows alternate sides** (name left / control right, then the other way). The name is bold in its own
  box (two lines), a small vertical box between name and control shows the value. The whole row glows
  under the pointer; pointing at an FX in a rack makes its rows glow in its color, and the other way.
- **Each panel scrolls on its own** (the rows fade at an edge while there is more, plus a slim bar). A
  band at its top widens it over the neighbours (rows flow in columns, bigger); one at a time.
- **The Parameters window** (a tree of every rack, FX, group and parameter, with tick boxes) adds and
  removes parameters; **the Inspector** sets the one selected. Both are windows of their own that dock
  separately; Show mode closes them, Edit mode brings them back.

## The parts, and what other modules can reuse

Every piece below is a file of its own in `src/FOHMate/`, with a header that says how to use it. None of
them knows about racks or rows: a module gives them its data and gets back what changed.

| File | What it is | How a module uses it |
|---|---|---|
| `controls.lua` | The controls, drawn by hand (ReaImGui has none): encoder, stepped encoder, width band, Q band, pan, drop-down, toggle, round on/off box; and `draw_control`, which turns one through limits, a list of values and a curve, with the mouse and the wheel | `draw_control(id, value, { kind, limits, memo, cx, cy, r, ... })` returns the new value (0..1) when it was changed |
| `limit_map.lua` | The maths of limits and curves: where the control is for a value, what value a position gives, gaps, the dot | `param_map(limits, kind, curve)` then `param_map_val` / `param_ctl_pos`; the limits are a plain table (the same fields as a quick access row) |
| `range_bar.lua` | The range selector: two value boxes, a bar, an arrow per end (tip on the value) with a round handle, a handle over the covered part | `draw_range_bar(id, lo, hi, { text, find, steps, inv, right })` returns the new lo, hi |
| `curve_graph.lua` | The curve editor: kind of curve, a square 1:1 graph with its points, saved curves | `draw_curve_graph(id, curve, pos, steps)` returns the new curve |
| `param_tree.lua` | The tree of the project's racks, FX, groups and parameters, with search, selection and tick boxes | `draw_tree(state, data, { have, apply, in_label, add_label, remove_label, leaf_menu })` inside the module's own window |

What belongs to the quick access panel stays in `params.lua` (its rows and how they are saved, the
Inspector, copy and paste of limits, the snap back from outside) and `window.lua` (drawing the panels).

## Rules the controls follow

- **A control** turns from 7:30 (minimum) clockwise to 4:30 (maximum). Small lines mark the minimum and
  maximum, a yellow mark the default (double-click goes back to it). Drag up and down (finer the farther
  the pointer is to the side) or around it (Settings > Controls); the wheel turns it too (Shift: finer;
  a stepped control or a list: one step at a time).
- **Limits** (Range, List of values, List of ranges), the **full range** option, **Limit only values**,
  **Skip the gaps** and **Snap to nearest limit** decide how the control turns and what value it gives
  (the details are at the top of `limit_map.lua`). An arc around the control shows what is allowed.
- **A curve** covers the stretch the control turns through. Where the value and the control's position
  can differ, the hand shows the value and a small pink dot on the ring shows where the control is.
- **A stepped control** sits on its steps, and so do its limits and its curve's dots.
- **From outside** (the FX's own window, MIDI learn): the hand shows the real value, past the arc. Per
  parameter and off by default, the value can be brought back inside the limits after half a second of
  no movement (not with an automation envelope); a red lock and a red glow show the option is on.

## Things to know

- REAPER gives a parameter's value as text ("-6.0 dB") and whether it is a toggle or has steps, but not
  the names of the steps: a drop-down's entries are found by trying each step and reading the text, then
  putting the value back. FX that don't expose steps get an encoder.
- An FX may rename its parameters (ReaEQ when a band changes type): the tree reads them again with
  Refresh, or when a rack puts something in focus in it.
- Cost: only the rows in view are drawn, each row keeps what the FX last told it and asks again only when
  the value moved, and a value is only written while a control is being moved. The snap back from
  outside reads only the parameters that have it on, ten times a second. Nothing here may add latency or
  noticeable CPU.
