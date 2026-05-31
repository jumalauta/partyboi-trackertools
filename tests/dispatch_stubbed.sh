#!/usr/bin/env bash
# End-to-end tests of convert.sh with STUBBED backends on PATH.
# Exercises argument parsing, output naming, routing, and the fallback chain
# without needing the real tools or Docker.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"

CONVERT="$HERE/../scripts/convert.sh"

WORKROOT="$(mktemp -d)"
trap 'rm -rf "$WORKROOT"' EXIT

BIN="$WORKROOT/bin"
make_stub_backends "$BIN"
export PATH="$BIN:$PATH"
export STUB_LOG="$WORKROOT/stublog"

# run_convert <args...> : run convert.sh fresh, capturing which backend was used.
run_convert() {
  : > "$STUB_LOG"
  bash "$CONVERT" "$@"
}
backend_used() { tail -n1 "$STUB_LOG" 2>/dev/null; }

echo "single file: default output name + routing"
W="$WORKROOT/case1"; mkdir -p "$W"; make_mod "$W/song.mod"
assert_true "convert song.mod exits 0" -- run_convert "$W/song.mod"
assert_file "$W/song.wav" "song.wav produced next to input"
assert_eq uade "$(backend_used)" "  .mod routed to uade"

echo "single file: explicit output name"
W="$WORKROOT/case2"; mkdir -p "$W"; make_mod "$W/in.mod"
run_convert "$W/in.mod" "$W/custom.wav"
assert_file "$W/custom.wav" "explicit output path honored"

echo "openmpt routing: .xm extension"
W="$WORKROOT/case3"; mkdir -p "$W"; make_mod "$W/track.xm"
run_convert "$W/track.xm"
assert_file "$W/track.wav" "track.wav produced"
assert_eq openmpt "$(backend_used)" "  .xm routed to openmpt"

echo "batch mode: -o outdir with mixed formats"
W="$WORKROOT/case4"; mkdir -p "$W/out"
make_mod "$W/a.mod"; make_mod "$W/b.xm"; make_mod "$W/tfmx.boss"
run_convert -o "$W/out" "$W/a.mod" "$W/b.xm" "$W/tfmx.boss"
assert_file "$W/out/a.wav"    "batch: a.wav"
assert_file "$W/out/b.wav"    "batch: b.wav"
assert_file "$W/out/tfmx.wav" "batch: tfmx.wav (prefix-named)"

echo "adplay routing: AdLib/OPL extension"
W="$WORKROOT/caseA"; mkdir -p "$W"; make_mod "$W/song.rad"   # content irrelevant for stub
run_convert "$W/song.rad"
assert_file "$W/song.wav" "song.wav produced"
assert_eq adplay "$(backend_used)" "  .rad routed to adplay"

echo "sidplayfp routing: .sid extension"
W="$WORKROOT/caseS"; mkdir -p "$W"; make_mod "$W/chip.sid"
run_convert "$W/chip.sid"
assert_file "$W/chip.wav" "chip.wav produced"
assert_eq sid "$(backend_used)" "  .sid routed to sidplayfp"

echo "schism routing: IT_ENGINE=schism reroutes .it"
W="$WORKROOT/caseSch"; mkdir -p "$W"; make_mod "$W/tune.it"
IT_ENGINE=schism run_convert "$W/tune.it"
assert_file "$W/tune.wav" "tune.wav produced"
assert_eq schism "$(backend_used)" "  IT_ENGINE=schism: .it routed to schism"

echo "default IT routing unchanged (openmpt) when IT_ENGINE unset"
W="$WORKROOT/caseIT"; mkdir -p "$W"; make_mod "$W/d.it"
run_convert "$W/d.it"
assert_eq openmpt "$(backend_used)" "  default: .it still routed to openmpt"

echo "fallback chain: unknown extension, content recognized by openmpt"
W="$WORKROOT/case5"; mkdir -p "$W"; make_mod "$W/mystery.zzz"
run_convert "$W/mystery.zzz"
assert_file "$W/mystery.wav" "fallback produced a wav"
assert_eq openmpt "$(backend_used)" "  unknown ext fell back to openmpt (content probe)"

echo "error handling"
assert_false "missing input fails"        -- run_convert "$WORKROOT/does-not-exist.mod"
assert_false "no args fails (usage)"      -- run_convert
assert_true  "--help exits 0"             -- run_convert --help
assert_false "unknown option fails"       -- run_convert --bogus

echo "env override: SAMPLE_RATE threaded to backend args"
W="$WORKROOT/case6"; mkdir -p "$W"; make_mod "$W/r.mod"
# Capture uade123 args by swapping in a recording stub for this case only.
cat > "$BIN/uade123" <<'EOF'
#!/usr/bin/env bash
echo "$@" > "$STUB_ARGS"
out=""; prev=""; for a in "$@"; do [[ "$prev" == "-f" ]] && out="$a"; prev="$a"; done
[[ -n "$out" ]] && _wavbytes "$out"
EOF
chmod +x "$BIN/uade123"
export STUB_ARGS="$WORKROOT/uade_args"
SAMPLE_RATE=48000 run_convert "$W/r.mod" >/dev/null
TESTS_RUN=$((TESTS_RUN+1))
if grep -q -- "--frequency=48000" "$STUB_ARGS"; then
  _pass "SAMPLE_RATE=48000 passed to uade123 --frequency"
else
  _fail "SAMPLE_RATE not threaded (got: $(cat "$STUB_ARGS"))"
fi

finish
