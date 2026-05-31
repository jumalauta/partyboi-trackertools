#!/usr/bin/env bash
#
# convert.sh — convert tracker modules to WAV with the most accurate tool per format.
#
# Routing philosophy (accuracy first):
#   * Amiga formats, including ProTracker .mod, are rendered with UADE (uade123),
#     which runs the original 68k replay routine through Paula emulation — the most
#     authentic reproduction of the original Amiga playback.
#   * PC tracker formats (XM, IT, S3M, ...) are rendered with libopenmpt (openmpt123),
#     the de-facto reference engine for those formats.
#   * xmp (libxmp) is a last-resort fallback for anything the two above decline.
#
# All backends render at the target sample rate natively; the only post-processing is a
# bit-depth / channel-count normalization with sox at the SAME sample rate (no resampling).
#
# Usage:
#   convert.sh <input> [output.wav]        # single file; default output is <input>.wav
#   convert.sh -o <outdir> <input...>      # batch; writes <name>.wav into <outdir>
#   convert.sh --help
#
# Environment overrides:
#   SAMPLE_RATE   output sample rate in Hz            (default 44100)
#   CHANNELS      output channel count                (default 2)
#   BIT_DEPTH     output bit depth                    (default 16)
#   HARD_TIMEOUT  per-file wall-clock safety net (s)  (default 3600)
#   UADE_TIMEOUT  pass-through uade123 -t song timeout (default: unset = until song end)
#   UADE_OPTS     extra raw options appended to uade123 invocation (advanced)

set -euo pipefail

SAMPLE_RATE="${SAMPLE_RATE:-44100}"
CHANNELS="${CHANNELS:-2}"
BIT_DEPTH="${BIT_DEPTH:-16}"
HARD_TIMEOUT="${HARD_TIMEOUT:-3600}"
UADE_TIMEOUT="${UADE_TIMEOUT:-}"
UADE_OPTS="${UADE_OPTS:-}"

prog="$(basename "$0")"

# --- Format → backend tables -------------------------------------------------
# Matched against BOTH the lowercased filename suffix (foo.mod) AND the lowercased
# prefix before the first dot (mod.foo), since Amiga modules are commonly named with
# a player prefix rather than a suffix.

# Amiga / native-replayer formats → uade123 (PRIMARY, incl. .mod per project policy)
UADE_FORMATS="
mod nst wow ust stk st pt m15 mod15 fst
ahx thx
mdat tfx tfmx tfhd smpl
fc fc13 fc14 fc3 fc4 smod
hip hipc hip7 sog mcmd s7g
dw
bp bp3 soundmon
dm dm1 dm2 dl dln delta
mc mcr cook
med mmd mmd0 mmd1 mmd2 mmd3 octamed
digi dgi
sid1 sid2 sidmon smn
ben bd daglish
gray fred jam jcb jpn riff rjp sng sndmon
ml dss puma
"

# PC tracker formats → openmpt123 (libopenmpt reference engine)
OPENMPT_FORMATS="
xm it s3m stm s3z mtm 669 far ult ptm dbm amf psm mt2 umx gdm dmf mdl
j2b ams dsm dtm plm okt imf mptm itp mo3 ptp v2m sfx
"

usage() {
  cat <<EOF
$prog — convert tracker modules to WAV (accuracy-first tool selection)

Usage:
  $prog <input> [output.wav]      Convert one file. Default output: <input>.wav
  $prog -o <outdir> <input...>    Convert many files into <outdir> as <name>.wav
  $prog --help                    Show this help

Backends:
  uade123     Amiga formats incl. .mod (authentic Paula/68k replay)  [PRIMARY]
  openmpt123  PC tracker formats (XM, IT, S3M, ...)  [libopenmpt reference]
  xmp         fallback for anything the above decline

Output is ${SAMPLE_RATE} Hz / ${BIT_DEPTH}-bit / ${CHANNELS} ch WAV.
See the script header for environment overrides.
EOF
}

log()  { printf '%s\n'  "$*" >&2; }
err()  { printf 'error: %s\n' "$*" >&2; }

# membership test: word_in_list <word> <list...>
word_in_list() {
  local w="$1"; shift
  local list=" $* "
  [[ "$list" == *" $w "* ]]
}

lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# detect_backend <filepath> -> echoes: uade | openmpt | "" (unknown)
detect_backend() {
  local f base low suffix prefix
  f="$1"
  base="$(basename "$f")"
  low="$(lc "$base")"
  suffix="${low##*.}"
  prefix="${low%%.*}"
  # Files with no dot: suffix == prefix == whole name; treat as prefix match only.
  [[ "$low" != *.* ]] && suffix=""

  if word_in_list "$prefix" $UADE_FORMATS || word_in_list "$suffix" $UADE_FORMATS; then
    echo uade; return 0
  fi
  if word_in_list "$suffix" $OPENMPT_FORMATS; then
    echo openmpt; return 0
  fi
  echo ""; return 0
}

# openmpt_can_play <file> : true if libopenmpt recognizes the file
openmpt_can_play() {
  openmpt123 --info -- "$1" >/dev/null 2>&1
}

# --- Renderers: each writes a WAV to $2 (raw, pre-normalization) --------------

render_uade() {
  local in="$1" out="$2"
  # uade123 needs "-e wav" to choose the WAV writer for the "-f" output file.
  # "--one" plays a single subsong; the built-in 512 s subsong-timeout (plus
  # HARD_TIMEOUT) bounds endlessly-looping tunes. Channel count is fixed up later.
  local args=(-e wav -f "$out" --frequency="$SAMPLE_RATE" --one)
  [[ -n "$UADE_TIMEOUT" ]] && args+=(-t "$UADE_TIMEOUT")
  # shellcheck disable=SC2206
  [[ -n "$UADE_OPTS" ]] && args+=($UADE_OPTS)
  # NOTE: uade123 uses custom arg parsing and does not accept the "--" marker, so the
  # input path is passed last without it.
  timeout "$HARD_TIMEOUT" uade123 "${args[@]}" "$in"
}

render_openmpt() {
  local in="$1" out="$2" tmp wav
  tmp="$(mktemp -d)"
  # In --render mode, openmpt123 ignores -o and writes "<input>.wav" beside the input,
  # so render inside a temp dir and pick up the produced .wav by glob (robust to the
  # exact name). Format detection is content-based, so the temp name is irrelevant.
  cp -- "$in" "$tmp/module"
  timeout "$HARD_TIMEOUT" openmpt123 --render --output-type wav \
    --samplerate "$SAMPLE_RATE" --force "$tmp/module"
  wav="$(find "$tmp" -maxdepth 1 -name '*.wav' -print -quit)"
  [[ -n "$wav" ]] && mv -- "$wav" "$out"
  rm -rf "$tmp"
  [[ -s "$out" ]]
}

render_xmp() {
  local in="$1" out="$2"
  # xmp: -o writes a WAV file, -f sets the mixing frequency.
  timeout "$HARD_TIMEOUT" xmp -o "$out" -f "$SAMPLE_RATE" -- "$in"
}

# normalize <src.wav> <dst.wav> : enforce bit depth + channels, NO sample-rate change.
normalize() {
  local src="$1" dst="$2"
  sox "$src" -b "$BIT_DEPTH" -c "$CHANNELS" "$dst"
}

# convert_one <input> <output.wav>
convert_one() {
  local in="$1" out="$2"
  if [[ ! -f "$in" ]]; then err "no such file: $in"; return 1; fi

  local backend raw tmp
  backend="$(detect_backend "$in")"

  tmp="$(mktemp -d)"; raw="$tmp/raw.wav"
  local used=""

  attempt() {
    local b="$1"
    case "$b" in
      uade)    render_uade    "$in" "$raw" ;;
      openmpt) render_openmpt "$in" "$raw" ;;
      xmp)     render_xmp     "$in" "$raw" ;;
    esac
  }

  if [[ -n "$backend" ]]; then
    if attempt "$backend" 2>"$tmp/err" && [[ -s "$raw" ]]; then used="$backend"; fi
  fi

  # Fallback / unknown-format probe chain.
  if [[ -z "$used" ]]; then
    rm -f "$raw"
    # Prefer the engine that actually recognizes the file; keep UADE high for Amiga.
    if openmpt_can_play "$in" && attempt openmpt 2>>"$tmp/err" && [[ -s "$raw" ]]; then
      used="openmpt"
    elif rm -f "$raw"; attempt uade 2>>"$tmp/err" && [[ -s "$raw" ]]; then
      used="uade"
    elif rm -f "$raw"; attempt xmp 2>>"$tmp/err" && [[ -s "$raw" ]]; then
      used="xmp"
    fi
  fi

  if [[ -z "$used" || ! -s "$raw" ]]; then
    err "could not convert '$in' — no backend accepted it"
    [[ -s "$tmp/err" ]] && sed 's/^/  /' "$tmp/err" >&2 || true
    rm -rf "$tmp"
    return 1
  fi

  mkdir -p "$(dirname "$out")"
  normalize "$raw" "$out"
  rm -rf "$tmp"
  log "ok: $in -> $out  [$used]"
}

# --- Argument parsing --------------------------------------------------------

main() {
  local outdir=""
  local -a inputs=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -o|--outdir) outdir="${2:-}"; shift 2 ;;
      --) shift; while [[ $# -gt 0 ]]; do inputs+=("$1"); shift; done ;;
      -*) err "unknown option: $1"; usage; exit 2 ;;
      *) inputs+=("$1"); shift ;;
    esac
  done

  if [[ ${#inputs[@]} -eq 0 ]]; then usage; exit 2; fi

  local rc=0

  # Single-file form with explicit output name: convert.sh in.mod out.wav
  if [[ -z "$outdir" && ${#inputs[@]} -eq 2 && "${inputs[1]}" == *.wav ]]; then
    convert_one "${inputs[0]}" "${inputs[1]}" || rc=1
    return $rc
  fi

  local in out name
  for in in "${inputs[@]}"; do
    name="$(basename "$in")"
    name="${name%.*}.wav"
    if [[ -n "$outdir" ]]; then
      out="$outdir/$name"
    else
      out="$(dirname "$in")/$name"
    fi
    convert_one "$in" "$out" || rc=1
  done
  return $rc
}

main "$@"
