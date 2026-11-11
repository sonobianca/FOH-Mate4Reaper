# FOH-Mate: roadmap

Accepted ideas. Nothing here is started unless noted. New ideas get added as they come up.

Shipped in 0.13 and no longer listed here: the latency mismatch option. Translations: dropped for now.

## Performance mode
Being built in the 0.14 versions (a work in progress): every rack in one row, each with its **quick
access panel** of critical parameters (encoders, bands, pans, drop-downs, toggles, with limits and
value curves), a Parameters window to pick them and an Inspector to set them. How it is built:
`docs/PERFORMANCE_MODE.md`; how to use it: the README.

Ideas for it, not started:
- **XY controller (Edit mode):** any two selected parameters combined into one XY pad; axes reversed or
  swapped from a context menu.
- **MIDI mapping** of the controls (the reason the position dot exists: a hardware control's position
  can differ from the value).
- **A parameter controlling an FX of another rack** (the storage doesn't forbid it).
- Other modules reusing the controls, the range selector, the curve editor and the parameter tree.

## Advanced view mode
- Basic stays the default; the mode is saved per project.
- Overview row of racks with small controls for exposed parameters.
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

## If we get there and have the motivation
- **A FOH-Mate font.** Bianca likes the look of the stroke font that draws the vertical values in
  Performance mode (light, technical, even spacing) and would like it, or something built on that
  look, across the whole interface. The idea is to design a custom font in that style, so no
  third-party font license is involved, rather than pick an existing one. Things to check first: the
  stroke font only has the digits and a few letters and costs a drawing call per line, so it can't
  simply be used everywhere; a real font file would be loaded through ReaImGui's font functions
  (does the installed ReaImGui version load a font from a file, or only an installed system font?),
  and the font would ship with the script through ReaPack. A cheaper stop on the way: try a few
  existing fonts with a similar feel.

## Open questions
- **AU vs VST3 reliability.** Some AU versions report 0 latency where the VST3 reports real latency,
  mostly Plugin Alliance (about 700 FX installed). Full scan result: 85 of 249 AU/VST3 pairs
  differ, always AU 0 vs VST3 > 0 (see the Done section of TESTING.md).
