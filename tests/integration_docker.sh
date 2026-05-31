#!/usr/bin/env bash
# Integration test: runs the REAL Docker image end-to-end.
# Opt-in (slow, needs Docker + a built image). Skips cleanly if Docker is absent.
#
#   IMAGE=partyboi-trackertools tests/integration_docker.sh
#
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"

IMAGE="${IMAGE:-partyboi-trackertools}"

if ! command -v docker >/dev/null 2>&1; then
  echo "SKIP: docker not installed"; exit 0
fi
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "SKIP: image '$IMAGE' not found — build it first: docker build -t $IMAGE ."
  exit 0
fi

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
make_mod "$WORK/test.mod"
make_it  "$WORK/song.it"                  # for the schism (IT-faithful) path
cp "$WORK/test.mod" "$WORK/probe.xm"      # MOD content; content-detected by openmpt
cp "$WORK/test.mod" "$WORK/weird.zzz"     # unknown ext -> fallback chain

dr() { docker run --rm -v "$WORK:/work" "$IMAGE" "$@"; }

# wav_ok <file> <rate> <channels> <bits> : verify header via the image's own soxi.
wav_ok() {
  local f="$1" rate="$2" ch="$3" bits="$4" info
  info="$(docker run --rm -v "$WORK:/work" --entrypoint soxi "$IMAGE" "/work/$f" 2>/dev/null)"
  grep -q "Sample Rate    : $rate" <<<"$info" \
    && grep -q "Channels       : $ch" <<<"$info" \
    && grep -q "Precision      : ${bits}-bit" <<<"$info"
}

echo "tools present in image"
assert_true "uade123 runs"      -- docker run --rm --entrypoint uade123      "$IMAGE" --version
assert_true "openmpt123 runs"   -- docker run --rm --entrypoint openmpt123   "$IMAGE" --version
assert_true "xmp runs"          -- docker run --rm --entrypoint xmp          "$IMAGE" --version
assert_true "adplay present"    -- docker run --rm --entrypoint adplay       "$IMAGE" --version
assert_true "sidplayfp present" -- docker run --rm --entrypoint sidplayfp    "$IMAGE" --help
assert_true "schism present"    -- docker run --rm --entrypoint schismtracker "$IMAGE" --version

echo "UADE eagleplayer data shipped"
assert_true "uade.conf present" -- \
  docker run --rm --entrypoint test "$IMAGE" -f /usr/local/share/uade/uade.conf

echo "real conversions (default 44100/2ch/16-bit)"
assert_true "convert test.mod"  -- dr test.mod
assert_file "$WORK/test.wav"    "test.wav exists on host"
assert_true "test.wav header"   -- wav_ok test.wav 44100 2 16

assert_true "convert probe.xm"  -- dr probe.xm
assert_true "probe.wav header"  -- wav_ok probe.wav 44100 2 16

assert_true "convert weird.zzz (fallback)" -- dr weird.zzz
assert_true "weird.wav header"  -- wav_ok weird.wav 44100 2 16

echo "schism path (IT_ENGINE=schism) renders .it"
docker run --rm -e IT_ENGINE=schism -v "$WORK:/work" "$IMAGE" song.it >/dev/null 2>&1
assert_file "$WORK/song.wav"    "song.wav produced by schism"
assert_true "song.wav header (schism, 44100)" -- wav_ok song.wav 44100 2 16

echo "env override honored (SAMPLE_RATE=48000)"
rm -f "$WORK/test.wav"
docker run --rm -e SAMPLE_RATE=48000 -v "$WORK:/work" "$IMAGE" test.mod >/dev/null 2>&1
assert_true "48000 Hz output" -- wav_ok test.wav 48000 2 16

finish
