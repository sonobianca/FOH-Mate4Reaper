# Changelog

Changes since the last public release, grouped by minor version (revisions are folded in).

## 0.12

- The code is split into modules: `FOHMate.lua` plus a `FOHMate` folder next to it holding the rest
  (racks, sidechain, latency, menus...). Nothing changes on screen or in the sound; the code is just
  easier to read and maintain. Installing and updating now means copying the file and the folder.

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
