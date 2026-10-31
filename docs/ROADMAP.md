# FOH-Mate: roadmap

Accepted ideas. Nothing here is started unless noted. New ideas get added as they come up.

## Performance mode (next: 0.14)
Shipped in 0.13 and no longer listed here: the latency mismatch option. Translations: dropped for now.

Bianca's design (planning stage, nothing built yet):
- **A toggle**, not a third mode: an optional, different workflow. Edit and Show keep working inside it.
- Racks in a single row, scrolling left to right. The FX part of each rack (the boxes we already
  have) lines up at the top. The full rack or a slimmer one: **a toggle, the user chooses**.
- **Under each rack, its own column of parameter rows,** in the same visual style. A column belongs to
  its rack. (Later: a row controlling an FX of another rack. Not now, but don't close the door.)
- Each row is one parameter of an FX of that rack. There is always one empty row at the end with a +
  in a circle; clicking it opens a dialog to pick an FX parameter.
- The control fits the parameter when REAPER can tell: on/off, a drop-down for a few fixed values, a
  rotary knob for continuous values (switchable to a slider per row; the default may be swapped to
  slider after trying it). Plugins that report nothing about their steps get the continuous control.
- Name: what the plugin reports by default, renamable. Color: the rack's color by default, changeable
  from a drop-down.
- Rows alternate sides (row 1 name left, control right; row 2 control left, name right), so a control
  is harder to hit by mistake.
- Usable in Show and Edit mode. Rows are added, removed and reordered in Edit mode only.
- Deleting an FX deletes its parameter rows too; the delete confirmation says so.
- Rows are saved with the project, on the rack.
- **Scrolling is per column,** and where you are must be clear at a glance: the content fades to
  transparent at the top and bottom edge while there is more beyond, plus a slim position indicator.
- **XY controller (Edit mode):** rows are selectable; any two selected parameters can be combined into
  one XY pad. Axes can be reversed or swapped from a context menu (reverse is on every control).
- The meters stay in the slim rack.
- Detail and build order: `docs/PERFORMANCE_MODE.md`.
- Replaces the "Performance Panel" idea under Advanced view mode below. MIDI mapping stays a later step.

## Advanced view mode
- Basic stays the default; the mode is saved per project.
- Overview row of racks with small controls for exposed parameters.
- **Performance Panel**: the exposed parameters of the selected racks.
- Each parameter has a **Map MIDI control** button.

## Latency watchdog and CPU
- Flashing **!!** on racks and FX, user-set sample limit, FX allowed latency, alerts that can be
  silenced. *The base of this exists (0.9-0.11).*
- CPU headroom alarm.

## Song snapshots (high priority, not first)
- Whole-chain recall: several tracks per rack, switched rather than rebuilt, with a crossfade time.
- Take unused racks offline per song.

## Racks
- Rack templates, recalled from a menu.
- Rack groups: bulk color, one-click bypass, relative level, phase analysis at soundcheck (with
  confirmation).
- Shared analyzer.

## Console integration
Modular, one module per console (Behringer Wing first). Principle: use REAPER's audio engine to give
consoles functions they don't have.
- External-insert detection, patch management, selection sync.
- Console automation tracks.
- Tempo-detector driven FX sync.
- Ideas: line check assistant, gain staging suggestions, ring-out assistant, virtual soundcheck switch.

## Multitrack playback management

## Longer term
- Possible hybrid licensing model: core and basic modules free, advanced modules licensed.

## Open questions
- **AU vs VST3 reliability.** Some AU versions report 0 latency where the VST3 reports real latency,
  mostly Plugin Alliance (about 700 plug-ins installed). Full scan result: 85 of 249 AU/VST3 pairs
  differ, always AU 0 vs VST3 > 0 (see the Done section of TESTING.md).
