#!/usr/bin/env bash
# Unit tests for convert.sh's pure routing/helper functions (no backends needed).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"

# Source convert.sh: BASH_SOURCE guard means main() will NOT run.
source "$HERE/../scripts/convert.sh"

echo "detect_backend: Amiga formats -> uade"
assert_eq uade "$(detect_backend song.mod)"      ".mod by suffix"
assert_eq uade "$(detect_backend SONG.MOD)"      "uppercase suffix"
assert_eq uade "$(detect_backend track.ahx)"     ".ahx (AHX)"
assert_eq uade "$(detect_backend tune.med)"      ".med (OctaMED)"
assert_eq uade "$(detect_backend mod.amiga)"     "mod. prefix form"
assert_eq uade "$(detect_backend tfmx.boss)"     "tfmx. prefix form"
assert_eq uade "$(detect_backend mdat.intro)"    "mdat. prefix form"
assert_eq uade "$(detect_backend hip.song)"      "hip. prefix form"
assert_eq uade "$(detect_backend fc.tune)"       "fc. prefix form"

echo "detect_backend: PC tracker formats -> openmpt"
assert_eq openmpt "$(detect_backend track.xm)"   ".xm"
assert_eq openmpt "$(detect_backend cool.it)"    ".it"
assert_eq openmpt "$(detect_backend foo.s3m)"    ".s3m"
assert_eq openmpt "$(detect_backend FOO.S3M)"    ".s3m uppercase"
assert_eq openmpt "$(detect_backend x.669)"      ".669 (numeric ext)"

echo "detect_backend: AdLib/OPL formats -> adplay"
assert_eq adplay "$(detect_backend tune.rad)"    ".rad (Reality AdLib)"
assert_eq adplay "$(detect_backend song.d00)"    ".d00 (EdLib)"
assert_eq adplay "$(detect_backend x.hsc)"       ".hsc (HSC AdLib)"
assert_eq adplay "$(detect_backend y.a2m)"       ".a2m (AdLib Tracker 2)"

echo "detect_backend: C64 SID -> sid"
assert_eq sid "$(detect_backend tune.sid)"       ".sid"
assert_eq sid "$(detect_backend X.SID)"          ".sid uppercase"
assert_eq sid "$(detect_backend chip.psid)"      ".psid"

echo "detect_backend: IT_ENGINE=schism reroutes IT/S3M/MOD"
assert_eq schism "$(IT_ENGINE=schism detect_backend song.it)"   "IT_ENGINE=schism: .it -> schism"
assert_eq schism "$(IT_ENGINE=schism detect_backend song.s3m)"  "IT_ENGINE=schism: .s3m -> schism"
assert_eq schism "$(IT_ENGINE=schism detect_backend song.mod)"  "IT_ENGINE=schism: .mod -> schism"
assert_eq uade   "$(IT_ENGINE=schism detect_backend song.ahx)"  "IT_ENGINE=schism: .ahx stays uade"
assert_eq openmpt "$(detect_backend song.it)"                   "default: .it stays openmpt"

echo "detect_backend: unknown -> empty"
assert_eq "" "$(detect_backend random.bin)"      "unknown extension"
assert_eq "" "$(detect_backend noextension)"     "no extension at all"
assert_eq "" "$(detect_backend archive.zip)"     ".zip is not a module"

echo "detect_backend: precedence — UADE wins shared/ambiguous names"
# A bare 'mod' file (no dot) should match the uade prefix table.
assert_eq uade "$(detect_backend mod)"           "bare 'mod' (prefix-only match)"

echo "word_in_list helper"
assert_true  "member present"  -- word_in_list mod  a mod b
assert_false "member absent"   -- word_in_list zzz  a mod b
assert_false "no partial match" -- word_in_list mo  a mod b

echo "lc helper"
assert_eq "abc.mod" "$(lc ABC.MOD)" "lowercases"

finish
