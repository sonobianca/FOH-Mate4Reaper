# FOH-Mate: roadmap

Accepted ideas. Nothing here is started unless noted. New ideas get added as they come up.

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
