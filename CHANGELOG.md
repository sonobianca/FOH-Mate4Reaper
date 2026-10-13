# Changelog

Changes since the last public release, grouped by minor version (revisions are folded in).

## 0.11

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
- **Latency > Open the Live Rack data folder** (latency list, scan log, error report).
- Latency scan: Audio Units that report 0 get a second, later look; a short pause between FX (both set
  in Settings); no FX or FX chain window is left open; the log keeps earlier runs. A scan that doesn't
  finish (crash, REAPER closed) can be continued where it stopped. **Rescan all** leaves out FX that
  failed before; **Latency > Retry failed FX...** tries them again.
- Alt-click the level box: 0 dB, or -inf when already at 0 dB.
- Windows reopen at their last size, also after being collapsed or minimized.
- FX latency list: Allowed checkboxes centered.
- Fixed: error after **Remove every FX** (and other actions that change a rack's FX from its menus).
- If Live Rack stops on an error, the exact place (line and chain of calls) goes to REAPER's console
  and to `Data/LiveRack/last_error.txt`.

## 0.10

- FX latency list, shared by every project: every FX loaded in a rack is recorded with the latency it
  reports (last and highest seen). Viewable in **Options > FX latency list...**.
- **Allow latency** is now remembered per FX, in every rack and every project.
- Latency scan: **Options > Scan new FX / Rescan all FX for latency...** measures every installed
  effect in one go, showing the plug-in being loaded and keeping a log. A plug-in that crashes REAPER
  during a scan is named when Live Rack opens again, and skipped by later scans. Results are saved as
  they are measured: a scan picks up where it stopped, and an FX is measured again only on request.
- Live Rack offers to scan newly installed effects.
- **Options > Hide FX over the latency limit** leaves them out of the FX menus; follows the limit.
- **Options > Take FX over the limit offline in Show mode**, back online in Edit mode.
- **Options > Show rack latency**: a box under every rack with its latency in ms and samples.
- Version number shown next to the Live Rack title.
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
- Fixed: error when running Live Rack a second time ("expected a valid ImGui_Context").
- Fixed: the **R** button could open the routing window of the wrong track.
