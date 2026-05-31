# partyboi-trackertools

A Docker image that converts tracker module files to WAV, choosing the **most accurate
playback engine for each format**. A single entrypoint script detects the format and
dispatches to the right tool.

## Backends

| Backend | Handles |
|---------|---------|
| **UADE** (`uade123`) | Amiga formats, incl. ProTracker `.mod` (primary). Runs the original 68k replayers through Paula emulation. Also TFMX, Future Composer, Hippel, AHX/THX, OctaMED, and hundreds more. |
| **libopenmpt** (`openmpt123`) | PC tracker formats: XM, IT, S3M, STM, MTM, 669, FAR, ULT, PTM, DBM, AMF, PSM, MT2, GDM, DMF, MDL, J2B, OKT, … |
| **AdPlug** (`adplay`) | AdLib/OPL2 formats: RAD, D00, HSC, A2M, CMF, DRO, LDS, RIX, … |
| **sidplayfp** | C64 SID tunes (`.sid`, `.psid`, `.rsid`) via reSIDfp emulation. |
| **Schism Tracker** | Opt-in Impulse-Tracker-faithful IT/S3M/MOD (`IT_ENGINE=schism`). |
| **libxmp** (`xmp`) | Fallback for anything the engines above decline. |

`.mod` and other Amiga formats go to UADE by policy — its real replayer + Paula emulation
is the most authentic rendering. Output is normalized with `sox` using bit-depth/channel
conversion only — **never sample-rate conversion**, so no resampling artifacts are added
beyond what the chosen engine produces.

## Build

```sh
docker build -t partyboi-trackertools .
```

## Usage

```sh
# Single file -> creates song.wav next to it
docker run --rm -v "$PWD:/work" partyboi-trackertools song.mod

# Explicit output name
docker run --rm -v "$PWD:/work" partyboi-trackertools song.mod out.wav

# Batch into an output directory
docker run --rm -v "$PWD:/work" partyboi-trackertools -o out song1.mod song2.xm tfmx.boss
```

Output defaults to **44100 Hz, 16-bit, stereo**, overridable via environment variables:

| Variable | Default | Meaning |
|----------|---------|---------|
| `SAMPLE_RATE` | `44100` | Output sample rate (Hz), rendered natively — no resampling. |
| `CHANNELS` | `2` | Output channel count. |
| `BIT_DEPTH` | `16` | Output bit depth. |
| `HARD_TIMEOUT` | `3600` | Per-file wall-clock safety net (seconds). |
| `UADE_TIMEOUT` | _unset_ | `uade123 -t` song timeout for endlessly-looping Amiga tunes. |
| `IT_ENGINE` | `openmpt` | Engine for IT/S3M/MOD: `openmpt` or `schism`. |
| `SID_TIMEOUT` | `180` | Render length (seconds) for SID tunes (otherwise endless). |

## Format detection

The script matches both the filename suffix (`foo.mod`) and the prefix before the first
dot (`mod.foo`, `tfmx.boss`) — Amiga modules are often named with a player prefix. Unknown
extensions fall through a probe chain (libopenmpt → UADE → xmp) and use the first engine
that accepts them.

## Tests

```sh
tests/run.sh            # fast routing + dispatch tests (no Docker)
tests/run.sh --docker   # also run the real-image integration test
```

## Extending

To add a format, install/build its tool in the `Dockerfile`, then add the extensions to a
format table and a matching `render_*` function in `scripts/convert.sh`.

> **Atari SNDH** is not bundled — `sc68` is unmaintained and fails to build under bookworm.
