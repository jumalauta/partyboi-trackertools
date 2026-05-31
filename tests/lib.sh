#!/usr/bin/env bash
# Tiny test harness + shared helpers for the partyboi-trackertools test suite.
# No external dependencies — pure bash. Source this from a test file.

# --- assertion counters ------------------------------------------------------
: "${TESTS_RUN:=0}"
: "${TESTS_FAILED:=0}"

_pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
_fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; TESTS_FAILED=$((TESTS_FAILED+1)); }

# assert_eq <expected> <actual> <message>
assert_eq() {
  TESTS_RUN=$((TESTS_RUN+1))
  if [[ "$1" == "$2" ]]; then
    _pass "$3"
  else
    _fail "$3"
    printf '         expected: %q\n         actual:   %q\n' "$1" "$2"
  fi
}

# assert_true <message> -- <command...>  : command must exit 0
assert_true() {
  local msg="$1"; shift; [[ "$1" == "--" ]] && shift
  TESTS_RUN=$((TESTS_RUN+1))
  if "$@" >/dev/null 2>&1; then _pass "$msg"; else _fail "$msg ($* -> $?)"; fi
}

# assert_false <message> -- <command...> : command must exit non-zero
assert_false() {
  local msg="$1"; shift; [[ "$1" == "--" ]] && shift
  TESTS_RUN=$((TESTS_RUN+1))
  if "$@" >/dev/null 2>&1; then _fail "$msg (unexpectedly succeeded)"; else _pass "$msg"; fi
}

# assert_file <path> <message> : file exists and is non-empty
assert_file() {
  TESTS_RUN=$((TESTS_RUN+1))
  if [[ -s "$1" ]]; then _pass "$2"; else _fail "$2 (missing/empty: $1)"; fi
}

# Print a summary and exit with the right status. Call at the end of a test file.
finish() {
  echo
  if [[ "$TESTS_FAILED" -eq 0 ]]; then
    printf '\033[32m%d passed, 0 failed\033[0m\n' "$TESTS_RUN"
    exit 0
  else
    printf '\033[31m%d passed, %d failed (of %d)\033[0m\n' \
      "$((TESTS_RUN-TESTS_FAILED))" "$TESTS_FAILED" "$TESTS_RUN"
    exit 1
  fi
}

# --- fixtures ----------------------------------------------------------------

# make_mod <path> : write a minimal but valid 4-channel ProTracker (M.K.) module:
# 20-byte title, 31 empty sample headers, 1-order song, one empty pattern.
make_mod() {
  local out="$1"
  python3 - "$out" <<'PY'
import struct, sys
d = bytearray()
d += b'partyboi test'.ljust(20, b'\x00')          # song title
for _ in range(31):                                # 31 sample headers (all empty)
    d += b''.ljust(22, b'\x00') + struct.pack('>H', 0) + bytes([0, 64]) \
       + struct.pack('>H', 0) + struct.pack('>H', 1)
d += bytes([1, 127]) + bytes(128)                  # song length, restart, order table
d += b'M.K.' + bytes(1024)                         # magic + one empty 64-row pattern
open(sys.argv[1], 'wb').write(bytes(d))
PY
}

# make_it <path> : write a minimal valid empty Impulse Tracker (.it) module —
# 'IMPM' magic, zero orders/instruments/samples/patterns. Plays as silence; enough
# to exercise the schism/libopenmpt loaders.
make_it() {
  local out="$1"
  python3 - "$out" <<'PY'
import struct, sys
d = bytearray(b'IMPM')
d += b'partyboi it'.ljust(26, b'\x00')             # song name (26)
d += struct.pack('<H', 0)                           # pattern row highlight
d += struct.pack('<HHHH', 0, 0, 0, 0)               # Ord/Ins/Smp/Pat counts
d += struct.pack('<HH', 0x0214, 0x0214)             # created/compat tracker version
d += struct.pack('<HH', 0, 0)                        # flags, special
d += bytes([128, 48, 125, 6, 0, 0])                 # GV, MV, IS, IT, Sep, PWD
d += struct.pack('<H', 0)                            # message length
d += struct.pack('<I', 0)                            # message offset
d += struct.pack('<I', 0)                            # reserved
d += bytes(64) + bytes(64)                           # channel pan + volume tables
open(sys.argv[1], 'wb').write(bytes(d))
PY
}

# make_stub_backends <bindir> : create fake uade123/openmpt123/xmp/sox/timeout that
# emit a tiny valid-enough WAV to their output path, so convert.sh logic can be tested
# end-to-end without the real tools or Docker. Each records its name into $STUB_LOG.
make_stub_backends() {
  local bin="$1"
  mkdir -p "$bin"

  # A 44-byte WAV header + a few sample frames, enough for `[[ -s ]]` and `soxi`-free tests.
  cat > "$bin/_wavbytes" <<'EOF'
#!/usr/bin/env bash
# _wavbytes <outfile> : write a minimal valid 44-byte PCM WAV (silence).
out="$1"
python3 - "$out" <<'PY'
import struct, sys
data = b'\x00\x00' * 8                      # 8 frames of silence, mono 16-bit
hdr = b'RIFF' + struct.pack('<I', 36+len(data)) + b'WAVE'
hdr += b'fmt ' + struct.pack('<IHHIIHH', 16, 1, 1, 44100, 88200, 2, 16)
hdr += b'data' + struct.pack('<I', len(data))
open(sys.argv[1], 'wb').write(hdr + data)
PY
EOF

  cat > "$bin/uade123" <<'EOF'
#!/usr/bin/env bash
echo uade >> "${STUB_LOG:-/dev/null}"
out=""; prev=""
for a in "$@"; do [[ "$prev" == "-f" ]] && out="$a"; prev="$a"; done
[[ -n "$out" ]] && _wavbytes "$out"
EOF

  cat > "$bin/openmpt123" <<'EOF'
#!/usr/bin/env bash
# Modes used by convert.sh: `--info -- <file>` (probe) and `--render ... <tmp/module>`.
if [[ "$1" == "--info" ]]; then
  # Recognize anything whose CONTENT starts with our MOD-ish marker, else fail.
  f="${!#}"
  head -c 20 "$f" 2>/dev/null | grep -q "partyboi" && exit 0 || exit 1
fi
echo openmpt >> "${STUB_LOG:-/dev/null}"
mod="${!#}"; _wavbytes "$mod.wav"
EOF

  cat > "$bin/xmp" <<'EOF'
#!/usr/bin/env bash
echo xmp >> "${STUB_LOG:-/dev/null}"
out=""; prev=""
for a in "$@"; do [[ "$prev" == "-o" ]] && out="$a"; prev="$a"; done
[[ -n "$out" ]] && _wavbytes "$out"
EOF

  cat > "$bin/adplay" <<'EOF'
#!/usr/bin/env bash
echo adplay >> "${STUB_LOG:-/dev/null}"
out=""; prev=""
for a in "$@"; do [[ "$prev" == "-d" ]] && out="$a"; prev="$a"; done
[[ -n "$out" ]] && _wavbytes "$out"
EOF

  cat > "$bin/sidplayfp" <<'EOF'
#!/usr/bin/env bash
echo sid >> "${STUB_LOG:-/dev/null}"
out=""
for a in "$@"; do [[ "$a" == -w* ]] && out="${a#-w}"; done
[[ -n "$out" ]] && _wavbytes "$out"
EOF

  cat > "$bin/schismtracker" <<'EOF'
#!/usr/bin/env bash
echo schism >> "${STUB_LOG:-/dev/null}"
out=""
for a in "$@"; do [[ "$a" == --diskwrite=* ]] && out="${a#--diskwrite=}"; done
[[ -n "$out" ]] && _wavbytes "$out"
EOF

  # sox stub: copy source -> dest (last arg). Good enough for normalize().
  cat > "$bin/sox" <<'EOF'
#!/usr/bin/env bash
src="$1"; eval "out=\${$#}"; cp "$src" "$out"
EOF

  # timeout stub (macOS has no coreutils timeout): drop the duration, exec the rest.
  cat > "$bin/timeout" <<'EOF'
#!/usr/bin/env bash
shift; exec "$@"
EOF

  chmod +x "$bin"/*
}
