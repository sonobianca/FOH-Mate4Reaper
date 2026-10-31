# FOH-Mate: Performance mode

Design agreed with Bianca, and the order to build it in. Nothing is built yet. The short version of
the idea is in `docs/ROADMAP.md`; this file is the detail. Built in the 0.14 versions.

## What it is

An optional view, switched on and off with a toggle. Edit and Show keep working inside it.

```
 ┌ top bar (as today) ──────────────────────────────────────────────────────────┐
 │ RACK 1 (full, or slim)   │ RACK 2                   │ RACK 3        │ ... →   │   one row,
 │ name, In/Out, FX boxes   │                          │               │         │   scrolls sideways
 │ level, BYPASS, MUTE      │                          │               │         │
 │ meters stay              │                          │               │         │
 ├──────────────────────────┼──────────────────────────┼───────────────┼─────────┤
 │ Threshold        (o)     │ Ratio            (o)     │      (+)      │         │   one column per
 │ (o)        Attack        │ (o)        Mix           │               │         │   rack, its own
 │ Gain             [==|=]  │ HPF freq   [ 80 Hz v]    │               │         │   vertical scroll
 │ (+)                      │ [   XY pad   ]           │               │         │   (fades at the
 └──────────────────────────┴──────────────────────────┴───────────────┴─────────┘   edges + position bar)
```

- **The toggle** switches the whole window; the choice is saved per project like the other view settings.
- **Full or slim rack** is a second toggle. Slim keeps the name, the FX boxes, BYPASS, MUTE **and the
  meters**; routing and level are hidden.
- **A column belongs to its rack.** Each row is one parameter of an FX of that rack. (Later: rows
  controlling an FX of another rack. The storage must not forbid it.)
- **Rows alternate sides:** name left / control right, then control left / name right.
- **Controls:** rotary knob by default (switchable to a slider per row; the default may change after
  trying it), a toggle for on/off, a drop-down for a few fixed values. Plugins that don't say what
  their parameter is get the knob/slider.
- **Name** defaults to what the plugin reports and can be renamed. **Color** is the rack's, changeable
  per row from a drop-down.
- **Always one empty row** at the end with a + in a circle: it opens a dialog to pick a parameter.
- **Edit mode only:** add, remove, reorder, rename, recolor, combine. Show mode only moves the controls.
- **Deleting an FX** deletes its rows; the delete confirmation says so.
- **Scroll position** (per column): the rows fade to transparent at the top or bottom edge while there
  is more beyond, plus a slim position bar.
- **Selecting rows (Edit mode):** click a row to select it, Cmd/Ctrl-click to add more. With exactly two
  selected, the context menu offers **Combine as XY pad**.
- **XY pad:** one control for two parameters, with X and Y labels, drag to move both, double-click to
  reset. From its context menu: **reverse X**, **reverse Y**, **swap axes**, **split back into two
  rows**. Reverse is on every control, not only the pad: knobs and sliders get **Reverse** too.

## Things to know before building

- ReaImGui has no knob or XY pad: both are drawn by hand (mouse drag, fine adjust with a modifier key,
  double-click to reset).
- REAPER gives the value of a parameter as text ("-6.0 dB") and whether it is a toggle or has steps,
  but not the names of the steps. A drop-down's entries are found by trying each step and reading the
  text, then putting the value back. Plugins that don't expose steps get a knob.
- A parameter is stored as the FX's GUID plus its index (and its name, to notice when a plugin update
  changed it). A row whose FX or parameter is gone is shown greyed out, not silently dropped.
- Cost: only the rows that are visible are read each frame, and a value is only written while the
  control is being moved. Nothing here may add latency or noticeable CPU.
- Rows are saved on the rack (its track), like the other per-rack data, so a duplicated rack copies them.

## Build order

Each step is a version (0.14.x), ends with something to test in REAPER, and is committed on its own.

1. **The view.** The toggle, racks in one row, an empty column under each, full/slim rack, per-column
   scroll with the fade and the position bar. No parameters yet.
   *Test:* switch the view on and off, scroll sideways, slim and full, docked and floating, many racks.
2. **Parameter rows, basics.** The + dialog (list an FX's parameters, with a search), rows stored and
   restored, a knob/slider/toggle/drop-down that moves the real parameter, names and colors, side
   alternation, rows greyed out when missing.
   *Test:* add rows from a few different plugins, move them, rename, recolor, save and reopen.
3. **Edit-mode handling.** Select, reorder, remove, reverse; delete FX removes its rows (with the
   warning); duplicating a rack copies its rows; Show mode locks everything but the controls.
   *Test:* each action, undo, and Show mode.
4. **XY pad.** Select two rows, combine, reverse each axis, swap axes, split.
   *Test:* combine two parameters, drag, reverse, swap, split, save and reopen.
5. **Polish.** What testing turns up: sizes, feel of the controls, docs (README, screenshots).

## Not in this feature

MIDI mapping of the controls (roadmap, later); rows controlling another rack's FX (later, see above).
