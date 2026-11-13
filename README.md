# FOH-Mate

Live sound tools for [REAPER](https://www.reaper.fm).

> **A note on the name.** This project was previously called *Live Rack*. It has been renamed
> **FOH-Mate** (file name `FOHMate`) to avoid confusion with an existing trademark, and is not
> affiliated with it. The rack panel is now the **Racks** module of FOH-Mate (first called Plugins Host). Your settings and
> data carry over automatically. FOH-Mate is an independent open-source project, not affiliated with or
> endorsed by Cockos Incorporated; REAPER is a trademark of Cockos.

**Racks** is the first module: a rack-based FX panel for REAPER, made for live sound.

Racks turns a handful of REAPER tracks into **racks**, each with its own input and output
routing, a chain of FX, a level, mute and bypass, and input/output meters. All racks live in one
window, away from your playback tracks, so the mixer and the track view stay clean.

> **Status: work in progress (v0.x).** It is used and tested on macOS with REAPER 7.84. Windows and
> Linux are untested. Expect rough edges and changes between versions.

<img src="docs/img/racks-window.png" width="840" alt="The Racks window: five racks in Edit mode, with the help line and the status bar">

**Contents:** [What it does](#what-it-does) · [Quick start](#quick-start) · [Requirements](#requirements) ·
[Installation on a fresh REAPER](#installation-on-a-fresh-reaper) · [Using FOH-Mate](#using-foh-mate) ·
[Good to know](#good-to-know) · [Troubleshooting](#troubleshooting) ·
[Updating and uninstalling](#updating-and-uninstalling)

---

## What it does

- **Racks are tracks.** Any track whose name starts with `RACK:` becomes a rack. FOH-Mate hides it
  from the track list and the mixer, keeps it off the master, and shows it in its own window.
- **Everything about a rack in one place:** name, input and output routing, FX chain, level (dB),
  BYPASS, MUTE, and input/output meters with peak hold and clip markers.
- **Edit and Show modes.** A cue-light switch (green = Edit, red = Show) locks the racks and their FX
  while you perform. Level, mute, bypass and FX on/off keep working.
- **Quick FX handling.** Add, insert, replace, delete, reorder, copy and move FX between racks with
  menus and drag and drop.
- **Level match.** Measures a rack's input and output (RMS) and sets its level so the output matches
  the input.
- **Sidechains without the routing maze.** A key button on every FX that has a sidechain input
  picks a hardware input or a sidechain bus; any rack can feed sidechain busses.
- **Mono, stereo and mono-to-stereo racks,** set by the rack's routing: the FX switch to their mono
  or stereo version on their own, keeping their settings.
- **Duplicate a rack** (from its menu or by dragging it), **or use it as a template** (same FX,
  default parameters).
- **Rack colors,** automatic or picked by hand, plus a **Daylight** theme for bright rooms.
- **Latency watchdog.** Racks and FX that add more latency than your limit flash **!!**; FX you
  accept can be allowed, and alerts can be silenced for a while or switched off.
- **FX list** of every installed FX, with favorites, developers, latency and scan status.
- **Favorites and recently used FX** at the top of every FX menu.
- **Status bar** with CPU and RAM gauges, REAPER's latency, latency alerts, and rack and FX counts,
  and a **help line** above it that says what the mouse can do on whatever it points at.
- **Performance mode** *(work in progress)*: every rack in one row, each with a **quick access panel**
  under it: the critical parameters of its FX as encoders, bands, pans, drop-downs and toggles, with
  limits and value curves.

---

## Quick start

Starting from a fresh REAPER? Do [Installation](#installation-on-a-fresh-reaper) first (about ten minutes,
most of it ReaPack and ReaImGui). Once FOH-Mate is loaded as an action, this is the shortest way from an
empty window to a working rack:

1. **Run it.** In **Actions > Show action list...**, select **Script: FOHMate.lua** and click **Run**.
   On a new project the window is empty.
2. **Create a rack.** Click the round **+** at the top right of the window (or double-click empty space).
   "Rack 1" appears. Behind the scenes it is a new track named `RACK: Rack 1`, hidden from REAPER's track
   list. *Already have a project?* Rename any track to `RACK: something` and it becomes a rack.
3. **Name it.** Double-click the rack's name and type.
4. **Route it.** Click **In:** to choose an input (mono, stereo or MIDI) and **Out:** to choose a hardware
   output.
5. **Add FX.** Click the round **+** in the rack's FX section and pick an FX from **Developers** or
   **All FX**. Click its button in the rack to open the FX window.
6. **Play something through it.** The input meter is on the left, the output meter on the right. Set the
   level in the dB box, or use **... > Level match**.
7. **Add more racks.** Click **+** again, or use **... > Duplicate rack** to copy a rack with everything in it.
8. **Before the show:** click the green **EDIT** switch at the top left so it turns red (**SHOW**). The racks
   are now locked against accidents. Level, mute and bypass still work.

---

## Requirements

| What | Notes |
|---|---|
| [REAPER](https://www.reaper.fm) 7.x | Developed on 7.81 to 7.84. Older versions are not tested. |
| [ReaPack](https://reapack.com) | Installs and updates ReaImGui and FOH-Mate. |
| [ReaImGui](https://github.com/cfillion/reaimgui) | The graphics library FOH-Mate is built with. |

No other extensions are needed (SWS is not required).

---

## Installation on a fresh REAPER

### 1. Install REAPER

Download it from [reaper.fm](https://www.reaper.fm/download.php), install it, and start it once so it
creates its folders. It runs in evaluation mode until you buy a license.

### 2. Install ReaPack

ReaPack is an extension that installs scripts and extensions from inside REAPER.

1. Download the ReaPack file for your system from [reapack.com](https://reapack.com).
   Pick the one that matches your REAPER (for example Apple silicon vs. Intel on a Mac, 64-bit on
   Windows).
2. In REAPER, open **Options > Show REAPER resource path in explorer/finder**. Open the
   **UserPlugins** folder inside it.
   - macOS: `~/Library/Application Support/REAPER/UserPlugins`
   - Windows: `%APPDATA%\REAPER\UserPlugins`
   - Linux: `~/.config/REAPER/UserPlugins`
3. Copy the ReaPack file into **UserPlugins** and **restart REAPER**.
4. You should now have **Extensions > ReaPack**. On the first launch it may open a settings dialog;
   you can just close it.

> If macOS blocks the extension because it was downloaded from the internet, allow it in
> **System Settings > Privacy & Security**, then restart REAPER.

### 3. Install ReaImGui

ReaImGui comes from the default **ReaTeam Extensions** repository, which ReaPack already knows.

1. **Extensions > ReaPack > Browse packages...**
2. Type `imgui` in the filter box.
3. Right-click **ReaImGui: ReaScript binding for Dear ImGui** and choose **Install**.
4. Click **Apply** (bottom right), then **restart REAPER**.

### 4. Add the FOH-Mate repository to ReaPack

1. **Extensions > ReaPack > Import repositories...**
2. Paste this address and click **OK**:

   ```
   https://github.com/sonobianca/FOH-Mate4Reaper/raw/main/index.xml
   ```

You only do this once. From then on ReaPack knows where FOH-Mate's updates come from.

### 5. Install FOH-Mate

1. **Extensions > ReaPack > Browse packages...**
2. Type `FOH-Mate` in the filter box.
3. Right-click **FOH-Mate** and choose **Install**.
4. Click **Apply** (bottom right).

ReaPack adds **Script: FOHMate.lua** to the action list by itself.

<details>
<summary>Without ReaPack (manual install)</summary>

1. Download `src/FOHMate.lua` and the `src/FOHMate` folder from this repository.
2. Copy both into REAPER's **Scripts** folder: **Options > Show REAPER resource path...** and open the
   **Scripts** folder. The `FOHMate` folder must sit right next to `FOHMate.lua`.
3. **Actions > Show action list...**, click **New action... > Load ReaScript...** and choose
   `FOHMate.lua`.

Manual installs don't update by themselves: see [Updating](#updating-and-uninstalling).
</details>

### 6. Run it

In the action list, find **Script: FOHMate.lua** and click **Run**. The Racks window opens.
It can float, or be docked (see [Docking](#docking)).

To open it automatically when REAPER starts, set it as a startup action (for example with the SWS
extension's *Global startup action*).

### 7. Optional: put it in the View menu

REAPER doesn't let an installer change its menus, so this is a one-time step by hand:

1. **Options > Customize menus/toolbars...**
2. In the drop-down at the top, choose **Main menu: View**.
3. Select the line it should go under, click **Add...**, pick **Script: FOHMate.lua** and click
   **Select/close**.
4. Optional: right-click the new line, **Rename...**, and call it `Racks`.
5. Click **Save**.

The same window adds it to a toolbar: choose that toolbar in the drop-down instead. To give it a
keyboard shortcut, select it in **Actions > Show action list...** and click **Add...** under
*Shortcuts for selected action*.

### First run: what happens

- FOH-Mate writes its small meter JSFX to
  `<REAPER resource path>/Effects/FOHMate/FOHMate_Meter`. You do not need to install it yourself.
- If the window shows no racks, click the round **+** in the top bar (or double-click empty space) to
  create your first rack.
- Existing tracks are untouched. A track only becomes a rack when its name starts with `RACK:`.

---

## Using FOH-Mate

### A rack at a glance

<img src="docs/img/rack.png" width="250" alt="One rack">

From the top: **R** (routing window), the name and **...** (Rack Option Menu), **In** and **Out**, the FX
chain (**+** adds an FX, **A/B** inverts every FX on/off), the level in dB with **SC**, **BYPASS** and **MUTE**,
and the input and output meters on each side.

- **Name:** click to select the rack, double-click to rename, drag to reorder.
- **In / Out:** pick the hardware input (mono, stereo or MIDI) and the hardware output.
- **R:** opens REAPER's own routing window for the rack, for sends and receives.
- **FX:** click a name to open or close the FX window. The dot turns one FX on or off.
- **Level box:** type a value in dB (a comma works as the decimal mark, `-inf` is allowed).
  Shift + double-click resets it to 0 dB; Alt-click (Option-click) sets 0 dB, or -inf when it is
  already at 0 dB.
- **SC** (next to the level): sends the rack to sidechain busses (see *Sidechains* below).
- **Key button** (at the end of an FX row, only on FX that have a sidechain input): picks what
  drives that FX's sidechain.
- **BYPASS** turns every FX off and restores them as they were when you click it again.
- **Meters:** input on the left, output on the right. White lines show the peak hold; the box on top
  lights red on a clip. Click any meter to reset all of them.

### Mouse and keyboard

| Action | Result |
|---|---|
| Click a rack's name | Select that rack |
| Cmd/Ctrl-click a rack's name | Add the rack to the selection, or remove it |
| Click empty space | Deselect the racks |
| Double-click empty space | Asks whether to create a new rack |
| Double-click a rack's name | Rename the rack |
| Drag a rack by its name | Reorder racks. Drop in the empty space to move it to the last position |
| Hold Cmd/Ctrl while dropping a rack | Duplicate it at the drop position |
| Drag an FX inside a rack | Reorder the FX |
| Drag an FX onto another rack | Copy it there |
| Hold Cmd/Ctrl while dropping an FX | Copy |
| Hold Alt while dropping an FX on another rack | Move |
| Right-click an FX | Insert FX, Replace FX, Delete FX..., Allow latency, Stereo from here |
| Shift + double-click the dB box | Reset the level to 0 dB |
| Alt-click (Option-click) the dB box | 0 dB, or -inf when already at 0 dB |
| Click a meter | Reset every peak hold line and clip marker |

The copy and move keys can be changed in **Options > Settings...**

### Edit and Show modes

The switch at the top left of the main bar toggles the mode (it is remembered between sessions).

| | Edit (green) | Show (red) |
|---|---|---|
| Level, mute, bypass, FX on/off, A/B | yes | yes |
| Open FX windows | yes | yes |
| Select racks | yes | yes |
| Create, rename, reorder, recolor racks | yes | locked |
| Routing (In / Out / R) | yes | locked |
| Add, insert, replace, delete, move, copy FX | yes | locked |
| Rack Option Menu | yes | locked |

<img src="docs/img/show-mode-racks.png" width="840" alt="Show mode: the switch is red, everything but the controls is locked; an FX over the latency limit is offline, its name struck through">

### Selecting racks

Click a rack's name to select it, and Cmd-click (Ctrl-click on Windows) to add or remove racks from
the selection. Selection is REAPER's own track selection, so both stay in sync. Selected racks glow.
Click empty space to deselect.

<img src="docs/img/select-racks.png" width="840" alt="Two racks selected: they glow">

### The Rack Option Menu (the `...` button)

<img src="docs/img/rack-option-menu.png" width="470" alt="The Rack Option Menu">

| Item | What it does |
|---|---|
| Level match | Listens for 3 seconds and sets the level so output matches input. Play a typical signal. |
| Duplicate rack | Copies the rack with everything: FX, parameters, routing, level. |
| Use as template | Same rack and FX, but every FX is re-added with default parameters. |
| Recolor automatically | Picks a color that contrasts with the racks before and after. |
| Choose color... | Opens a color picker. |
| Remove every FX / Remove bypassed FX | Cleans out the chain. |
| Revert to regular track | Makes it a normal track again: name prefix removed, back in the track list and mixer. |
| Delete rack... | Deletes the track, after a confirmation. |

If you open the menu on a **selected** rack, the action applies to **all selected racks**, after a
confirmation. Everything is undoable with REAPER's undo.

### Adding and changing FX

<img src="docs/img/add-fx-menu.png" width="700" alt="The + menu: search, Favorites, Recently used, by developer, all FX">
<img src="docs/img/fx-menu.png" width="300" alt="Right-click an FX">

- **+ button** (or right-click an FX > **Insert FX**): a menu of your installed FX. Every entry shows
  its type before the name (`VST3: ...`, `AU: ...`, `JS: ...`), so formats of the same FX can be
  told apart. The menu is grouped by your FX browser folders, developers, and type.
- **Right-click an FX:** *Insert FX* (before this one), *Replace FX* and *Delete FX...* (both ask first).
- **Drag an FX** to reorder it. Drop it on another rack to copy it there. Hold **Ctrl/Cmd** to copy,
  **Alt** to move. While a drop would copy, a green **+** follows the pointer and the drop target is
  outlined in green.
- **Search:** every FX menu (**+**, *Insert FX*, *Replace FX*) starts with a search field, ready to
  type in. Half a second after you stop typing, the menu shows the FX whose name contains every word
  you typed; **Enter** picks the first one.
- In the menus each FX shows its **type** (VST3, AU, CLAP, JS...) on the right in that type's color, and
  its known **latency** in red after its name. Colors are set in **FX > FX type colors...**.
- **Favorites** and **Recently used** sit right under the search field in every FX menu. Star your
  favorites in **FX > FX list...**; Recently used lists the last FX you picked, newest first
  (how many is set in **Settings > Behavior**; 0 hides it).
- **FX > FX types** limits the menus to the FX types you use, with a count for each type.

### Sidechains

<img src="docs/img/sidechain-menu.png" width="600" alt="The key button of an FX: its sidechain source">
<img src="docs/img/sc-send-menu.png" width="600" alt="The SC button: send the rack to sidechain busses">

- **Key button** on an FX row opens its sidechain menu: *None*, *Mono Input* (any hardware input),
  *Stereo Input* (any input pair; summed to mono when the FX has a mono sidechain) and *Bus* (every
  sidechain bus, plus *Create new bus...*). The button lights up when a key is set; hover it to see
  the source. One dot next to the button means a mono key, two stacked dots a stereo key.
- **The key follows the FX's width.** An FX on a mono rack, or on the mono part of a rack, gets a mono
  key, even if the FX has a stereo sidechain: a stereo source is summed to mono (two receives at
  -6 dB into one channel, visible in the routing window). When the FX turns stereo, its key does too.
- **SC button** (next to the level) lists the sidechain busses: tick one to send the rack to it and set
  the send level with its slider. *Create new sidechain bus...* makes one and sends the rack to it.
  Right-click a bus name to rename or delete it. The send is taken after the rack's FX and before its
  level, so riding the level or level matching never changes how hard a key hits.
- **Sidechain busses** are hidden tracks named `SC BUS: <name>`. They never go to the master and have
  no hardware input or output.
- **Hardware inputs** used as keys go through a hidden `SC IN: <input>` track (one per input, shared
  by every FX keyed from it). FOH-Mate creates and removes these on its own.
- Choices that would make a feedback loop (a rack keyed from a bus it feeds) are greyed out.
- Under the hood, each keyed FX gets its own pair of track channels (3/4, 5/6, ...), so FX can be
  reordered freely. Everything is regular REAPER routing, visible in the routing window.

### Dragging racks

<img src="docs/img/drag-rack.png" width="840" alt="A rack being dragged: a see-through copy follows the pointer, the rack stays faded in its place">

Drag a rack by its name. A see-through copy follows the cursor and the rack under it is outlined.
Drop it on another rack to place it there, or in the empty space around or below the racks to send it
to the last position. Racks follow your project's track order.

Hold **Ctrl/Cmd** (the copy key) when you drop to **duplicate** the rack instead: the copy lands where
you drop it, or right after the original if you drop it on itself. A green **+** follows the pointer
and the target is outlined in green while a drop would copy.

### Mono and stereo racks

<img src="docs/img/in-menu.png" width="560" alt="The In menu: mono or stereo hardware input, or MIDI">
<img src="docs/img/out-menu.png" width="620" alt="The Out menu: mono outputs or stereo pairs">

A rack's width comes from its routing, separately for each side, so a rack can be mono in and stereo
out:

- **Input side:** the hardware input (mono or stereo). With no input, the receives: mono when every
  receive is mono, stereo otherwise.
- **Output side:** the hardware outputs (mono when they are all mono). With none, the sends; with no
  outputs at all, the same as the input side.
- The **meters follow**: one bar for a mono side, two for a stereo side. Hover **In** or **Out** to
  read the width.
- **Dots between the FX** show the signal's width all along the chain: one dot for mono, two for
  stereo.
- **Options > Stereo pairs on odd-even channels only** offers only 1/2, 3/4, 5/6... as stereo inputs,
  outputs and keys, like most consoles. Off, every pair is offered.

What the FX get:

| Rack | FX |
|---|---|
| mono in, mono out | every FX mono |
| stereo in (any out) | every FX stereo; a mono output sums the two sides at the hardware output |
| mono in, stereo out | mono up to the **stereo point**, stereo from there on |

The **stereo point** is the FX where the chain turns stereo. It glows, with one dot above it and two
below. By default it is
the first FX that comes in a mono-to-stereo version (a reverb, for example). Right-click any FX >
**Stereo from here** to pick it yourself (choose it again, or **Stereo point: automatic**, to go back
to the default). With
no stereo point the whole chain stays mono and the output carries it on both sides.

How an FX changes width, best option first:

1. **The FX's bus size** (VST3 mostly; the same as **Plug-in bus size** in REAPER's pin
   connector): 1 on the mono part of a rack, 2 on the stereo part. The FX stays in place with all
   of its settings. A sidechain input nobody assigned a key to is left unconnected, so a mono FX
   never keys from its own signal.
2. **Its sibling version** when one is installed, recognised by a name that ends in *Mono*, *Stereo* or
   *Mono/Stereo* (the Waves style, e.g. `C6 Mono` / `C6 Stereo`). It is swapped in place and every
   parameter with the same name is copied over, so settings carry across; anything the other version
   does not have is left at its default. Its sidechain key, on/off state and open window follow.
3. Otherwise the FX stays as it is (a stereo-only FX on a mono rack just gets the same signal on
   both sides).

Versions are swapped when a rack's routing or stereo point changes (from FOH-Mate's menus or from
REAPER's routing window) and on FX added, copied or moved into a rack. An FX you change by hand in
REAPER afterwards is left alone until the routing changes again. The output of a mono FX feeds both
track channels, so outputs, sends and meters always agree.

### Color and Daylight

- **Display > Colors > Recolor every rack** colors all racks, starting from a random color, each contrasting
  with the previous one.
- **Display > Colors > Choose default color...** and **New racks use automatic / default color** decide the color of racks
  you create or copy.
- **Display > Daylight mode** switches the whole panel to a light theme for bright rooms. Each rack's own color
  is kept as a pale tint with a solid name label.

<img src="docs/img/daylight.png" width="840" alt="Daylight mode">

### Performance mode (work in progress)

> Performance mode is still being built: what is described here works, more is coming, and details may
> change between versions.

**Display > Performance mode** puts every rack in one row that scrolls sideways, with a column under each
rack: its **quick access panel**, the parameters of its FX you need at hand during a show. Each panel
scrolls on its own; the rows fade at the top or bottom edge while there is more, and a slim bar shows
where you are.

<img src="docs/img/performance-mode.png" width="840" alt="Performance mode, Edit mode: every rack in one row, its quick access panel under it">

- **Edit mode:** full racks. Add, remove, reorder (drag a parameter's name box), rename and recolor
  parameters.
- **Show mode:** a rack is its name, with **M** (mute) and **B** (bypass) on the right. The handle under the
  name opens its FX section (with thin meters either side of the handle). Only the controls move.
- **Widen a panel:** the band at the top of a panel (two small triangles) widens it over its neighbours;
  the parameters then flow in columns and get bigger. The band again folds it back.
- **Fold by itself:** open FX sections and widened panels fold back after a while without activity
  (**Settings > Performance mode**; in Edit mode only when you ask for it there).

<img src="docs/img/show-mode.png" width="840" alt="Performance mode, Show mode: each rack is its name with M and B">
<img src="docs/img/show-mode-fx-open.png" width="800" alt="Show mode: the handle under a rack name opens its FX section">
<img src="docs/img/performance-mode-widened.png" width="840" alt="A widened quick access panel: the parameters flow in columns, bigger">

**The controls.** FOH-Mate picks one that fits each parameter; right-click a parameter (Edit mode) >
**Control** to change it:

- **Encoder** (7:30 = minimum, 4:30 = maximum; a parameter in dB gets a fader's marks), **stepped encoder**
  (one mark per value), **width band** and **Q band** (a band at the top that widens, or narrows as Q goes
  up), **pan** (a band from the center), **drop-down**, **toggle**.
- Drag up and down (finer the farther the pointer is to the side) or around the control: **Settings >
  Controls > Rotary encoder**. The mouse wheel (or two fingers on a trackpad) turns it too; **Shift** is finer.
- The small yellow mark is the **default**: double-click the control to go back to it.
- A small box between the control and the name shows the value, turned a quarter turn.
- **Control position:** the controls sit on the right of every row, on the left, or alternating from row to
  row (**Settings > Performance mode > Control position**). A panel can have its own: its **...** menu >
  **Control position** (Default follows Settings).

<img src="docs/img/quick-access-controls.png" width="260" alt="Controls: encoders, a stepped encoder (Tone), a drop-down (Bank), a toggle (Swap L/R); a blue arc shows limits">
<img src="docs/img/quick-access-row-menu.png" width="660" alt="Right-click a parameter (Edit mode): Control, Nickname, Recolor, Inspect, the snap-back option, Copy / Paste, Remove">

<img src="docs/img/parameters-window.png" width="402" alt="The Parameters window: a rack, its FX and their parameters, with tick boxes">

**Adding parameters: the Parameters window.** Click the **+** at the end of a panel (or **Display >
Windows > Show parameter treeview**). It is a tree of every rack, its FX, their groups (an EQ's **Band 1**, **Band 2**...)
and their parameters, with a search box. Tick a parameter, a group or a whole FX to put it in (or take it
out of) the quick access panel of its rack, or select several and use **Add to the quick access panel** /
**Remove from the quick access panel**. Placeholders and MIDI CC entries are hidden (**Show hidden** lists
them; right-click a parameter > **Hide this parameter**). **Refresh** reads the FX again when it renamed its
parameters (ReaEQ does when a band changes type). Clicking a parameter in a rack selects it in the tree.

**Setting a parameter: the Inspector.** It shows the parameter selected in the tree (or double-clicked
in a rack, or **Inspect parameter...** from its right-click menu; **Display > Windows > Show parameters
inspector**), in sections that fold:

- **Control** (the kind of control, or Automatic), **Direction and default** (invert it, move or remove the
  default mark), **Preview** (the control itself, which can be turned) and **Details** (what REAPER says
  about the parameter).

  <img src="docs/img/inspector-control.png" width="392" alt="Inspector, Control">
  <img src="docs/img/inspector-direction-preview-details.png" width="392" alt="Inspector, Direction and default, Preview and Details">

- **Limit values**, the values the control may give:
  - **Range**: a Min and a Max, on a bar with an arrow at each end (drag an arrow or the round handle
    under it, or the blue part, or the handle over it, to move the whole range). The control stops at Min
    and Max; **Limit only values** lets it turn all the way while the value waits at Min or Max. Max below
    Min keeps the two outer parts.

    <img src="docs/img/inspector-limit-values.png" width="392" alt="A Range, with the snap-back option on">

  - **List of values**: only those values, in your order, as a stepped encoder or a drop-down (two values:
    a toggle).

    <img src="docs/img/inspector-list-of-values.png" width="392" alt="A List of values">

  - **List of ranges**: several ranges. **Skip the gaps** makes the control jump over the gaps between
    them; without it, the value waits at the last range while the control turns through a gap
    (**Snap to nearest limit**: it takes the nearest one instead). **Invert** keeps the gaps instead.

    <img src="docs/img/inspector-list-of-ranges.png" width="392" alt="A List of ranges">

  - **Use the full range of the control**: the whole travel covers what is allowed, for finer moves.
  - Ctrl+wheel (Cmd on a Mac) over a control moves the current range; sideways makes it wider or narrower.
  - **Bring it back inside the limits when moved from outside** (off by default): when the parameter is
    moved from the FX's own window or MIDI learn and stays outside its limits for half a second, it goes
    back to the nearest allowed value (not when it has an automation envelope). A small red lock and a red
    glow show it on the parameter (hover the lock for a reminder).

    <img src="docs/img/quick-access-lock.png" width="660" alt="The red lock and glow of the snap-back option, with its tooltip">

- **Curve**: how the value follows the control: **Linear**, **Ease in**, **Ease out**, or **Custom points**
  (click to add a point, drag it, right-click to remove it). Curves can be saved and reused.

  <img src="docs/img/inspector-curve.png" width="382" alt="A curve with custom points">

- When the value and the control can differ (a curve, Limit only values, a gap), a small pink dot on the
  control's ring shows where it is turned to; the hand shows the value.

  <img src="docs/img/position-dot.png" width="240" alt="The pink dot: where the control is turned to, while the hand shows the value">

Right-click a parameter (Edit mode, or in the tree) to **Copy** its limits and curve and **Paste** them on
another parameter or on the whole selection. **Nickname parameter...** gives it a name of your own, and
**Recolor parameters** a color (FX have a color too: right-click an FX > **Color...**). The **...** at the top
right of a panel removes the parameters whose FX is gone, or clears the panel; **Display > Hide disabled
parameters** hides those. Deleting an FX that has parameters in a panel asks first.

### Docking

Use **Display > Dock** to put the window in one of REAPER's dockers, or back to floating. You can also
drag the window onto a docker. The window remembers its dock.

In Performance mode (Edit mode), the **Parameters** window (the tree of the racks' parameters, to add them to each rack's quick access panel) and the
**Inspector** (the settings of the selected parameter) are windows of their own: **Display > Windows**
shows or hides each one. Each floats or docks on its own, with its own tab in a docker ("Racks",
"Parameters", "Inspector"), and comes back where you left it. Dropped on a docker that already holds
one, a window becomes a tab of it; to have them side by side, put them in different dockers on the same
side of REAPER's window (**Display > Windows > Dock Parameters / Dock Inspector** picks the docker).

<img src="docs/img/docked-windows.png" width="840" alt="Racks, Inspector and Parameters docked side by side">

### Menus

The top bar, right side: **+** (new rack), then four menus.

| Menu | What is in it |
|---|---|
| **Display** | Daylight mode, rack colors, Performance mode, Fold automatically, Hide disabled parameters, Rack latency box (off / always / only with latency), Windows (Parameters, Inspector), Dock |
| **FX** | FX types, FX type colors, FX list..., Hide FX over the latency limit, Take FX over the limit offline in Show mode |
| **Latency** | Latency alerts, Silence / Resume, Latency limits, Scan new / Rescan all FX, Retry failed FX, Ask to scan new FX |
| **Options** | Disconnect inputs/outputs on copy and template, Disable metering and Level match, Stereo pairs on odd-even channels only, Open the FOH-Mate data folder, Settings... |

<img src="docs/img/menu-display.png" width="400" alt="The Display menu"> <img src="docs/img/menu-fx.png" width="400" alt="The FX menu">
<img src="docs/img/menu-latency.png" width="400" alt="The Latency menu"> <img src="docs/img/menu-options.png" width="400" alt="The Options menu">

Windows (Settings, FX list) reopen at the size you left them, also after being collapsed.

### Status bar

CPU and RAM gauges, **Latency: in [..] ms - out [..] ms** as reported by REAPER, the latency alert line
(see below), and the rack and FX counts. Hover a gauge for details.

The grey **help line** just above it says what clicks and keys do on whatever the mouse points at (a
rack name, an FX, a button), and follows along while you drag a rack or an FX.

<img src="docs/img/status-bar.png" width="840" alt="The help line and the status bar">

### Latency watchdog

FOH-Mate keeps an eye on the latency each rack adds (every FX reports its own, in samples):

<img src="docs/img/latency-alert.png" width="560" alt="A rack over the latency limit: the !! RACK tag, the FX that adds it, and the tooltip">

- When a rack's FX add up to more than the **latency limit**, a red **!! x.x ms** tag flashes on the
  rack's top edge and a **!!** flashes on every FX that adds latency. Hover the tag for the list of
  culprits; hover any FX to read its latency. The status bar flashes how many racks are over.
- **Right-click an FX > Allow latency** for an FX you accept (a look-ahead limiter, say). Its latency
  is no longer counted, in this rack or any other, in every project: the mark is kept in the FX
  FX list (below), and carries over to its mono/stereo version.
- **Display > Rack latency box** adds a box across the bottom of every rack with its latency in ms
  and samples (red when over the limit): **Always**, **Only when a rack has latency**, or **Off**. Hover it for each FX's share and REAPER's own figure for the
  chain. It updates once a second, and right away when FX are added or removed.
- There are **two limits**, set in **Latency > Latency limits...**, in samples: one **per FX** and one
  **per rack** (several small latencies can add up). A rack alerts when one FX is over the per-FX limit
  or when its FX together are over the per-rack limit. Both default to 0: any added latency raises an
  alert.
- **Latency > Silence latency alerts for N min** quiets them for a while (the length is set in
  Settings and holds even if FOH-Mate is restarted); **Resume latency alerts** ends it early.
  **Latency > Latency alerts** switches them off completely. While silenced or off, the status bar says
  so and the **Latency** button turns red.
- **Latency > Count every format at its highest latency** (off by default) is for FX installed in
  several formats (AU, VST3, VST...). Some formats, often AU, report 0 where another format reports the
  real figure, so the watchdog would never see it. With this on, an FX counts with the highest
  latency any of its formats reports: in the alerts, the limits, the rack latency box, the FX menus and
  Show mode. In the FX list such figures are marked **\***, and hovering one says where it comes
  from. It is a warning only: REAPER's own compensation is not changed. The formats are matched on
  name and developer (the type, spaces, a channel count like "(4ch)" and the developer's name inside the
  FX's name are ignored). **Allow latency** stays per format: allowing one says so first.
- Alerts show in both Edit and Show mode. FX that are switched off or offline don't count: REAPER
  drops their latency from its compensation too.
- **Which limit?** When an FX is over the per-FX limit, that FX flashes **!!** and the rack tag reads
  **!! FX**. When the FX are each fine but add up to more than the per-rack limit, the rack's whole
  frame flashes red, the tag reads **!! RACK**, and only the FX adding the most latency flashes.

#### The FX list

FOH-Mate keeps one list of FX and the latency they report, shared by every project on the computer
(`Data/FOHMate/fx_latency.txt` in REAPER's resource folder; **Options > Open the FOH-Mate data
folder** shows it, with favorites, the scan log and the last error report). Every FX loaded in a rack
is added or updated as it is seen; a scan can fill it in for everything installed.

**FX > FX list...** shows every installed FX, one per row:

<img src="docs/img/fx-list.png" width="764" alt="The FX list, filtered on "Rea": latency over the limit in red">

- **Star** (click it to make the FX a favorite), **Type** in its color, **FX** name, **Developer**,
  **Latency** (last reported) and **Highest** seen, **Allowed** (tick it here too), and **Status**:
  *measured* by a scan, *seen in a rack*, *failed* to load, or *not scanned*. Names over the per-FX
  limit are red.
- **Filters:** by name (every word must match), by type, by developer (the drop-down has its own
  search field; clicking a developer in the list shows only theirs, again shows all), **Favorites**
  only, and **Latency, allowed or failed** only.
- **Sort:** click a column header, again to reverse. Latency and Highest start biggest first.
- **Select** FX with click, Cmd/Ctrl-click and Shift-click, or **Select all shown**, then **Rescan
  selected...** (Edit mode). Right-click a row to rescan it or the selection, or to add or remove
  favorites. This is also how a *failed* FX can be tried again on its own.

- **Latency > Scan new FX for latency...** measures the effects not measured yet; **Rescan all FX
  for latency...** measures them all again (the only way an FX is measured twice), leaving out FX that
  failed before; **Retry failed FX...** tries those again. Each result is saved the moment it is
  measured, and if a scan doesn't finish (a crash, or REAPER closed), the next start offers to
  **continue it** where it stopped. Each effect is loaded once on a temporary hidden track,
  read and removed, with a progress window and a **Stop** button. Instruments are skipped. Scans run in
  Edit mode only.
- Two settings in **Settings > Latency** tune the scan: a **pause between FX** (raise it if scans crash
  REAPER often) and an **extra wait for AUs** that report no latency at first.
- **Do it when nothing is live** (audio may glitch while FX load) and **save first**: an FX
  that crashes on load can take REAPER down. If that happens, the next time FOH-Mate opens it tells
  you which FX it was, marks it *failed* and skips it in later scans. The scan window always
  shows the FX being loaded, and every scan is logged, in order, in
  `Data/FOHMate/last_scan_log.txt` in REAPER's resource folder.
- Most effects really have no latency, so a scan showing mostly zeros is normal; look-ahead limiters,
  linear-phase EQs and oversampling are the usual exceptions. Each FX is measured with its
  default settings.
- **New FX:** when you start FOH-Mate (and once a minute after), it looks for effects that are
  not in the list and offers to scan them. **Latency > Ask to scan new FX** turns the question off.
- A few FX only settle their latency once audio runs through them or once a setting changes
  (look-ahead, oversampling): the number seen in a rack then updates the list.
- **FX > Hide FX over the latency limit** leaves FX whose known latency is over the per-FX limit (and
  that are not allowed) out of the **+**, *Insert FX* and *Replace FX* menus. It follows the limit
  when you change it.
- **FX > Take FX over the limit offline in Show mode:** switching to Show takes offline every FX over
  the per-FX limit, then, rack by rack, the FX adding the most latency until each rack is back under
  the per-rack limit.
  Offline means unloaded, so their latency is really gone; audio passes through them untouched. Their
  name is struck through. Switching back to Edit brings them back online (it can take a moment for
  big FX to reload).

### Settings

<img src="docs/img/settings.png" width="444" alt="Settings, with the Performance mode section open">

**Options > Settings...** opens a window with the values you can change: automatic color ranges, meter
range and fall speed, Level match time and gate, latency limits and silence time, FX type colors,
copy and move keys, how many recently used FX to show, corner rounding, and the
dimensions of the racks (grouped under *Layout*). Changes apply immediately and are saved. Ctrl+click
a slider to type a value. **Reset to defaults** restores everything.

Most confirmation boxes (creating a rack by double-click, replacing or deleting one FX, an action on
several selected racks, and some notes) have a **Don't show this again** checkbox; once ticked, the
question is answered "yes" without asking. **Reset warning popups**, next to Reset to defaults, brings
them all back. Boxes that delete a rack or a sidechain bus, reset the settings or start a latency scan
always show.

---

## Good to know

- **Racks never go through the master.** FOH-Mate keeps the master send off on every rack, and on
  the sidechain tracks (`SC BUS:` and `SC IN:`).
- **Hidden tracks.** Racks are hidden from the track list and mixer on purpose. To bring one back, use
  **Revert to regular track**.
- **Meter JSFX.** Each rack gets two small meters, one first and one last in its chain. They
  never show in FOH-Mate's FX list. If you open a rack's FX chain in REAPER you will see them.
- **Opening a project on another computer** without FOH-Mate: the meters show up as missing FX.
  This does not affect the audio.
- **CPU and RAM** come from the operating system (REAPER does not expose its Performance Meter to
  scripts). On macOS and Linux they show REAPER's share of the machine. On Windows the gauges show
  `n/a`. REAPER does not report processing time to scripts, so the status bar shows latency instead.
- **Saved settings** live in REAPER's own settings file. Each rack's bypass state is saved in the
  project. On macOS and Linux a tiny file (`/tmp/FOHMate_stats.txt`) is used for the CPU and RAM
  numbers.

---

## Troubleshooting

| Problem | What to try |
|---|---|
| "ReaImGui is not installed" | Follow [step 3](#3-install-reaimgui), then restart REAPER. |
| Any other error after a ReaImGui update | Update the script too, or report it with the file, line number and message. |
| In / Out menus show no channels (red note at the top) | REAPER reports no inputs or outputs: the audio device is not running, failed to open (in use elsewhere, sample rate refused), or its channel range is off. Check **Preferences > Audio > Device**; the note names the device REAPER is using. |
| "Could not add the meter JSFX" | Restart REAPER, or refresh the FX list (**Options > Preferences > Plug-ins > VST**, then re-scan). |
| Meters do not move | Check that audio is flowing through the rack. The output meter shows the level after the fader. |
| Something odd with racks or sound | **Options > Disable metering and Level match.** This also removes the meter FX from the racks, to rule them out. Turn it off to bring them back. |
| CPU / RAM show `n/a` | They need macOS or Linux. See *Good to know*. |
| The window opens tiny or in the wrong place | Resize or dock it again. REAPER remembers windows by name. |
| A rack disappeared | It is hidden on purpose, but still a track named `RACK: ...`. Check the track list with *show hidden tracks* or the Track Manager. |

If you hit an error, the ReaScript error dialog shows the file, the line number and the message.
Please include all three in a bug report.

---

## Updating and uninstalling

- **Update with ReaPack:** ReaPack checks for updates when REAPER starts; to check right away use
  **Extensions > ReaPack > Synchronize packages**. Close and re-run FOH-Mate to use the new version.
  The action, toolbar buttons and shortcuts keep working.
- **Moving from a manual install to ReaPack** (versions before 0.12 could only be installed by hand):
  install with ReaPack as above, point your toolbar buttons and shortcuts to the new
  **Script: FOHMate.lua** action, then remove the old action and delete the old `FOHMate.lua` (and
  `FOHMate` folder) from **Scripts**. Settings, favorites, the latency list and your racks' data carry
  over: they aren't stored in the script.
- **Update a manual install:** replace `FOHMate.lua` and the `FOHMate` folder with the new ones and
  re-run it. The file name doesn't change between versions, so the action, toolbar buttons and
  shortcuts keep working. Versions before 0.12 were a single file: add the `FOHMate` folder next to
  it. If you used an older file with the version in its name (`FOHMate_v...lua`), load `FOHMate.lua`
  once and remove the old action.
- **Coming from Live Rack:** load `FOHMate.lua` in the action list and remove the old `LiveRack_v...lua`
  action. Your settings, favorites and latency list are copied over the first time FOH-Mate starts, and
  your racks keep their saved data. Once everything checks out you can delete the old
  `<REAPER resource path>/Data/LiveRack/` folder.
- **Uninstall:** use **Revert to regular track** on racks you want to keep as normal tracks. Then, with
  ReaPack: **Browse packages**, right-click **FOH-Mate**, **Uninstall**, **Apply**. Manual install:
  remove the script action and delete `FOHMate.lua` and the `FOHMate` folder. Optionally delete
  `<REAPER resource path>/Effects/FOHMate/`.

---

## Contributing

**Version numbers** are *major.minor.revision*: the revision goes up for small fixes and adjustments,
the minor number for new features or bigger changes. The current version is shown in the window's
title bar (next to the Racks title); it is not part of the file name.

Issues and pull requests are welcome. When reporting a bug, please include the FOH-Mate version
(shown next to the Racks title), your REAPER version, operating system, ReaImGui version, and the
exact error message.

By contributing you agree that your contribution is licensed under the same terms as the project
(see below).

## License

FOH-Mate is free software under the **MIT License**. See the [LICENSE](LICENSE) file.

You are free to use, copy, modify and share it, also as part of other work, as long as the copyright
and license notice stay with it. It comes with no warranty.
