# FOH-Mate: roadmap

Accepted ideas. Nothing here is started unless noted. New ideas get added as they come up.

## 0.13 plan
0.12 was released with the modular code and ReaPack install only; these two follow.
- **Latency mismatch safety option.** Opt-in setting: a plugin installed in several formats (AU, VST3)
  counts with the highest latency reported by any of its formats, for alerts, limits and display
  only. Estimated values marked in the Plugin list. REAPER's own compensation is not touched. Needs
  name + developer matching across formats. See the AU vs VST3 open question below.
- **Performance mode.** Bianca's description:
  - Racks in a single row, scrolling left to right. The FX part of each rack (the boxes we already
    have) lines up at the top of the screen.
  - Below each rack, a parameter section in the same visual style. Each row is one parameter of any
    FX, with its control, usable in both Show and Edit mode.
  - There is always one empty row at the end of the list, with a + in a circle; clicking it opens a
    dialog to pick an FX parameter.
  - The control fits the parameter when REAPER can tell: on/off, a drop-down for a few fixed
    values, a rotary knob for continuous values (lighter on screen; switchable to a slider per row,
    and the default may be swapped to slider after trying it). Plugins that report nothing about
    their steps get the continuous control.
  - Rows are removed and reordered in Edit mode only, never in Show mode.
  - Deleting an FX deletes its parameter rows too; the delete confirmation says so.
  - Rows are saved with the project, on the rack.
  - The name defaults to what the plugin reports, and can be renamed by the user.
  - Color: the rack's color by default, changeable from a drop-down.
  - Rows alternate sides (row 1 name left, control right; row 2 control left, name right), so a
    control is harder to hit by mistake.
  - Replaces the "Performance Panel" idea under Advanced view mode below; MIDI mapping stays a
    later step.
- Translations: dropped for now.

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
