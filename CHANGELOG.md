# Changelog

Changes since the last public release, grouped by minor version (revisions are folded in).

## 0.14

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
  selection, and selecting an FX means all of its parameters. A parameter in the Performance has a
  check mark. A row shows the plug-in's name for it, its real value in the vertical box and a
  control that fits the parameter: a **rotary encoder** (7:30 = minimum, 4:30 = maximum, with small
  arrows for min, max and the default, which is yellow; a band centered at the top for a width (as thin as possible at the minimum, reaching from the minimum mark to the maximum mark at the maximum: bandwidth, stereo width, knee); marks for each value
  when there are only a few), a **toggle** (a circle) or a **drop-down** (a circle with an arrow). The default
  is the value the parameter had when it was added; double-click an encoder to go back to it. **Settings > Controls >
  Rotary encoder** picks how it turns: up and down (finer the farther the pointer is to the side) or around the
  encoder. FOH-Mate guesses which control a parameter gets; in Edit mode, right-click a row to correct it (encoder, width band, stepped, toggle, drop-down, or automatic). Corrections are kept for every project in Data/FOHMate/param_controls.txt, with what REAPER said about the parameter, so the guesses can be improved from them. Rows are saved on the rack; one whose FX is gone is greyed out. In Performance mode the
  status bar also shows how many parameters the selected rack has. The placeholder rows are gone. Rows look like this (names in bold, controls outside the name box, alternating sides, the whole row
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
