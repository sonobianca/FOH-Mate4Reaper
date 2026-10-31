# FOH-Mate

Live-sound toolkit for REAPER, written in Lua (ReaImGui). Main script: `src/FOHMate.lua`, which loads
the modules in `src/FOHMate/` (list and order in its `MODULES` table). Docs in
`docs/`, `CHANGELOG.md` and `README.md` at the root.

**At the start of any work session, read `docs/TESTING.md` and `docs/ROADMAP.md`.**

Bianca (owner) is a live sound engineer, not a full-time programmer: explain changes in plain
language and keep them small.

## Project state
- Name: **FOH-Mate** (formerly "Live Rack", renamed because of a trademark conflict). Never write
  "Live Rack", "LiveRack" or "RackPanel" in new code, text or file names. Only exception: the
  one-time migration code that reads the old settings and data names.
- First module: the rack. Its window is titled **Plugins Host**. In code and UI, "FX" is the word
  for what is inside a rack (not "insert" or "plugin"), and "rack" is used, never "strip".
- Version: the `VERSION` constant in the script. Last public release: v0.11.9. Tag
  `v0.11.14-pre-reorg` marks the state before the repo reorganization.
- Racks are REAPER tracks with the `RACK:` prefix (constant `PREFIX`). Sidechain busses are hidden
  `SC BUS:` tracks. Racks must never be routed to the master.
- License: GPL-3.0-or-later (LICENSE, script header, README). Bianca holds the copyright.

## Hard constraints
1. Never use too much CPU or RAM, never add audio latency.
2. Code is split into modules (`src/FOHMate/*.lua`) for readability, as long as it costs no
   performance. Every module is loaded once at start into the script's private environment, so all
   top-level names are shared; new top-level names go there, not into Lua `local`s. A new module must
   be added to `MODULES` in `src/FOHMate.lua` (the ReaPack index is built from that list, see
   `docs/RELEASING.md`).
3. Versioning is major.minor.revision: revision for minor adjustments, minor for new features or big
   changes. The major version is Bianca's decision only. The version lives in the one `VERSION`
   constant and shows in the window title bar, not in the file name.
4. `CHANGELOG.md` is grouped by minor version only (revisions folded in). Every change needs an entry.
5. Bianca tests in REAPER; the script can't be run here. After a change, say exactly what to check
   and add it to `docs/TESTING.md` as a numbered open item. When Bianca reports results by number,
   tick the item, move it to Done and note what was found.
6. Never run git push, merge, rebase or delete branches. Work on a branch, commit in small steps,
   and say when it is ready to push.
