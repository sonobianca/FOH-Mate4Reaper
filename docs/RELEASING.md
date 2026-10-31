# FOH-Mate: releasing a version

Users install and update FOH-Mate with ReaPack. ReaPack reads `index.xml` at the root of the
repository on `main`. Every file in it points at a release tag (`v0.12.0`...), so a version only
reaches users once its tag is pushed. Merging to `main` alone publishes nothing new.

## Steps

1. On the release branch (Claude):
   - check `VERSION` in `src/FOHMate.lua`, the `CHANGELOG.md` section for this minor version, and that
     `docs/TESTING.md` has nothing open (except the ReaPack install check, added for after the tag);
   - run `tools/make_reapack_index.sh`. It writes `index.xml` for that version (its changelog is the
     CHANGELOG section) and stops if `MODULES` and the files in `src/FOHMate/` don't match;
   - commit `index.xml`.
2. Bianca: merge the branch into `main`.
3. Bianca: create the tag on `main`, named `v` + the version (e.g. `v0.12.0`), and push `main` and the
   tag. In GitHub Desktop: History, right-click the merge commit, **Create Tag...**, then **Push**.
   Or create a GitHub Release with that tag name.
4. In REAPER: **Extensions > ReaPack > Synchronize packages**: the new version shows up.

Between steps 2 and 3 the list points at a tag that doesn't exist yet: do them together.

## The About text in ReaPack

`tools/reapack_about.txt` is the overview ReaPack shows in the repository's and the package's About
window. Plain ASCII, with `# ` and `## ` headings, `- ` bullets and `**bold**`; the script turns it
into RTF (what ReaPack reads) and refuses non-ASCII characters. Edit it, run
`tools/make_reapack_index.sh`, commit `index.xml`, and merge to `main`: About text changes need no
new version or tag (ReaPack reads `index.xml` from `main`). Rebuilding the same version keeps its
release time.

## Where ReaPack installs it

`<REAPER resource path>/Scripts/FOH-Mate/Live sound/FOHMate.lua`, with the `FOHMate` folder next to
it. That is a different place than a manual copy in `Scripts/`, so the first ReaPack install gives a
new action: point toolbar buttons and shortcuts to it once and remove the old manual copy. Settings,
favorites, the latency list and the racks' data are not tied to the file and carry over.

## How users find it

Users add the repository once (README, Installation steps 4 and 5) with this address:
`https://github.com/sonobianca/FOH-Mate4Reaper/raw/main/index.xml`

To be found without the README (once, after the first ReaPack release):
- **reapack.com's list of repositories** (https://reapack.com/repos): its "Edit this list" link opens
  `config/repos.yml` in the `cfillion/reapack.com` GitHub project. Add this entry at the end and send
  it as a pull request:
  ```yaml
    -
      link: 'https://github.com/sonobianca/FOH-Mate4Reaper'
      index: 'https://github.com/sonobianca/FOH-Mate4Reaper/raw/main/index.xml'
  ```
- **A thread on the Cockos REAPER forum** (and other live-sound places) with the address above.

Later option, not used for now: submitting FOH-Mate to ReaTeam's repository, which every ReaPack user
has by default (https://reapack.com/upload/reascript). Their review then decides when updates go out.
Use one source only, never both.
