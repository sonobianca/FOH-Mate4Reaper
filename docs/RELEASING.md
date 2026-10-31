# FOH-Mate: releasing a version

Users install and update FOH-Mate with ReaPack. ReaPack reads `index.xml` at the root of the
repository on `main`. Every file in it points at a release tag (`v0.12.0`...), so a version only
reaches users once its tag is pushed. Merging to `main` alone publishes nothing new.

## Steps

1. On the release branch (Claude):
   - check `VERSION` in `src/FOHMate.lua`, the `CHANGELOG.md` section for this minor version, and that
     `docs/TESTING.md` has nothing open;
   - run `tools/make_reapack_index.sh`. It writes `index.xml` for that version (its changelog is the
     CHANGELOG section) and stops if `MODULES` and the files in `src/FOHMate/` don't match;
   - first ReaPack release only (0.12.0): add the ReaPack install steps below to the README, as the
     main way to install;
   - commit `index.xml`.
2. Bianca: merge the branch into `main`.
3. Bianca: create the tag on `main`, named `v` + the version (e.g. `v0.12.0`), and push `main` and the
   tag. In GitHub Desktop: History, right-click the merge commit, **Create Tag...**, then **Push**.
   Or create a GitHub Release with that tag name.
4. In REAPER: **Extensions > ReaPack > Synchronize packages**: the new version shows up.

Between steps 2 and 3 the list points at a tag that doesn't exist yet: do them together.

## Where ReaPack installs it

`<REAPER resource path>/Scripts/FOH-Mate/Live sound/FOHMate.lua`, with the `FOHMate` folder next to
it. That is a different place than a manual copy in `Scripts/`, so the first ReaPack install gives a
new action: point toolbar buttons and shortcuts to it once and remove the old manual copy. Settings,
favorites, the latency list and the racks' data are not tied to the file and carry over.

## Adding users to the repository (README)

**Extensions > ReaPack > Import repositories...** and paste
`https://github.com/sonobianca/FOH-Mate4Reaper/raw/main/index.xml`, then **Browse packages**, find
**FOH-Mate**, install, apply.
