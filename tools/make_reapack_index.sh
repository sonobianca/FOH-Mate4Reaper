#!/bin/zsh
# Writes index.xml, the list ReaPack reads, for the version in src/FOHMate.lua, plus the About text
# of the repository and the package (tools/reapack_about.txt, turned into RTF, which ReaPack needs).
# Every file points at the release tag (v<VERSION>), so nothing reaches users until that tag is
# pushed. Run from anywhere: tools/make_reapack_index.sh   (see docs/RELEASING.md)
set -e
cd "${0:A:h}/.."

REPO_URL=https://github.com/sonobianca/FOH-Mate4Reaper
MAIN=src/FOHMate.lua

VERSION=$(sed -nE "s/^VERSION *= *'([0-9.]+)'.*/\1/p" $MAIN)
[[ -n $VERSION ]] || { print -u2 "VERSION not found in $MAIN"; exit 1 }
RAW=$REPO_URL/raw/v$VERSION

# module names, in load order, from the MODULES table
MODULES=(${(f)"$(sed -n '/^MODULES = {/,/^}/p' $MAIN | grep -oE "'[a-z_]+'" | tr -d "'")"})

# every module file must be listed in MODULES, and the other way round
LISTED=$(print -l $MODULES | sort)
FOUND=$(ls src/FOHMate/*.lua | xargs -n1 basename | sed 's/\.lua$//' | sort)
if [[ $LISTED != $FOUND ]]; then
  print -u2 "MODULES in $MAIN and the files in src/FOHMate/ don't match:"
  diff <(print -r -- $LISTED) <(print -r -- $FOUND) | grep '^[<>]' | sed 's/^</  only in MODULES:/; s/^>/  only a file:/' >&2
  exit 1
fi

# this minor version's CHANGELOG section (e.g. "## 0.12")
MINOR=${VERSION%.*}
CHANGES=$(awk -v h="## $MINOR" '$0 == h {on = 1; next} /^## / {on = 0} on' CHANGELOG.md | sed '/./,$!d')

# the About text: a few simple lines ("# " and "## " headings, "- " bullets, **bold**) become RTF
ABOUT=$(awk '
  function esc(t) { gsub(/\\/, "\\\\", t); gsub(/\{/, "\\{", t); gsub(/\}/, "\\}", t); return t }
  function bold(t,   out, a, b) {
    out = ""
    while (match(t, /\*\*[^*]+\*\*/)) {
      out = out substr(t, 1, RSTART - 1) "{\\b " substr(t, RSTART + 2, RLENGTH - 4) "}"
      t = substr(t, RSTART + RLENGTH)
    }
    return out t
  }
  BEGIN { printf "{\\rtf1\\ansi\\deff0 {\\fonttbl {\\f0 Helvetica;}}\\f0\\fs24 " }
  /^$/ { next }
  /^## / { printf "\\pard\\sb240\\sa80{\\b\\fs28 %s}\\par ", bold(esc(substr($0, 4))); next }
  /^# /  { printf "\\pard\\sa120{\\b\\fs40 %s}\\par ", bold(esc(substr($0, 3))); next }
  /^- /  { printf "\\pard\\li360\\fi-240\\sa80 \\\047" "95  %s\\par ", bold(esc(substr($0, 3))); next }
  { printf "\\pard\\sa120 %s\\par ", bold(esc($0)) }
  END { printf "}" }
' tools/reapack_about.txt)
if [[ -n $(LC_ALL=C tr -d '\000-\177' < tools/reapack_about.txt) ]]; then
  print -u2 "tools/reapack_about.txt must be plain ASCII (RTF)"; exit 1
fi

# a metadata-only rebuild of the same version keeps that version's release time
VTIME=$(sed -nE "s/.*<version name=\"$VERSION\" author=\"Bianca\" time=\"([^\"]+)\".*/\1/p" index.xml 2>/dev/null | head -1)
VTIME=${VTIME:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}

{
  print '<?xml version="1.0" encoding="utf-8"?>'
  print '<index version="1" name="FOH-Mate">'
  print '  <metadata>'
  print "    <link rel=\"website\">$REPO_URL</link>"
  print -r -- "    <description><![CDATA[$ABOUT]]></description>"
  print '  </metadata>'
  print '  <category name="Live sound">'
  print '    <reapack name="FOHMate.lua" type="script" desc="FOH-Mate">'
  print '      <metadata>'
  print "        <link rel=\"website\">$REPO_URL</link>"
  print -r -- "        <description><![CDATA[$ABOUT]]></description>"
  print '      </metadata>'
  print "      <version name=\"$VERSION\" author=\"Bianca\" time=\"$VTIME\">"
  print -r -- "        <changelog><![CDATA[$CHANGES]]></changelog>"
  print "        <source main=\"main\">$RAW/$MAIN</source>"
  for m in $MODULES; do
    print "        <source file=\"FOHMate/$m.lua\">$RAW/src/FOHMate/$m.lua</source>"
  done
  print '      </version>'
  print '    </reapack>'
  print '  </category>'
  print '</index>'
} > index.xml

print "index.xml written for v$VERSION (${#MODULES} modules)"
