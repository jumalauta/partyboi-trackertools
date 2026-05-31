# partyboi-trackertools

A Docker image that converts tracker module files to WAV, choosing the **most accurate
playback engine for each format**. A single entrypoint script detects the format and
dispatches to the right tool.

## Why these tools

Accuracy is the priority, so each family of formats is rendered by the engine that
reproduces the *original* playback most faithfully:

| Backend | Source | Handles |
|---------|--------|---------|
| **UADE** (`uade123`) | built from source | **Amiga formats, including ProTracker `.mod` (primary).** Runs the original 68k replay routine through Paula hardware emulation — the most authentic Amiga sound. Also TFMX, Future Composer, Jochen Hippel, David Whittaker, SoundMon, Delta Music, Mark Cooksey, AHX/THX, OctaMED, Sidmon, and hundreds more. |
| **libopenmpt** (`openmpt123`) | apt | PC tracker formats: XM, IT, S3M, STM, MTM, 669, FAR, ULT, PTM, DBM, AMF, PSM, MT2, UMX, GDM, DMF, MDL, J2B, OKT, IMF, MPTM, … The reference engine for these formats. |
| **AdPlug** (`adplay`) | apt | AdLib/OPL2 formats: RAD, D00, HSC, A2M, AMD, CMF, DRO, LDS, RIX, and more. |
| **sidplayfp** | apt | C64 SID tunes (`.sid`, `.psid`, `.rsid`) via cycle-accurate reSIDfp emulation. |
| **Schism Tracker** (`schismtracker`) | apt | Opt-in Impulse-Tracker-faithful rendering of IT/S3M/MOD (`IT_ENGINE=schism`). |
| **libxmp** (`xmp`) | apt | Last-resort fallback for anything the engines above decline. |

> **Design choice:** `.mod` and other Amiga formats go to UADE by policy — UADE's real
> replayer + Paula emulation is the most authentic rendering of Amiga music. libopenmpt
> handles the PC tracker formats it is the reference for. AdLib/OPL and C64 SID are
> dispatched by extension to their dedicated emulators. Set `IT_ENGINE=schism` to render
> IT/S3M/MOD with Schism Tracker (which mirrors Impulse Tracker's mixer) instead of
> libopenmpt.

Output is normalized to a uniform WAV spec with `sox` using **bit-depth/channel
conversion only — never sample-rate conversion**, so no resampling artifacts are
introduced beyond what the chosen engine already produces.

## Build

```sh
docker build -t partyboi-trackertools .
```

The build compiles UADE 3.x from source (it is not in the Debian repos), along with its
two from-source dependencies — `libzakalwe` and `bencode-tools` — in a separate builder
stage. `openmpt123`, `adplay`, `sidplayfp`, `schism`, `xmp`, and `sox` are installed from
apt. The final image is ~243 MB and includes UADE's full eagleplayer data set (159 Amiga
replayers).

## Usage

```sh
# Single file -> creates song.wav next to it
docker run --rm -v "$PWD:/work" partyboi-trackertools song.mod

# Single file, explicit output name
docker run --rm -v "$PWD:/work" partyboi-trackertools song.mod out.wav

# Batch many files into an output directory
docker run --rm -v "$PWD:/work" partyboi-trackertools -o out song1.mod song2.xm tfmx.boss
```

### Output format

Default: **44100 Hz, 16-bit, stereo**. Override with environment variables:

```sh
docker run --rm -v "$PWD:/work" \
  -e SAMPLE_RATE=48000 -e BIT_DEPTH=24 -e CHANNELS=2 \
  partyboi-trackertools song.it
```

| Variable | Default | Meaning |
|----------|---------|---------|
| `SAMPLE_RATE` | `44100` | Output sample rate (Hz). Rendered natively by each engine — no resampling. |
| `CHANNELS` | `2` | Output channel count. |
| `BIT_DEPTH` | `16` | Output bit depth. |
| `HARD_TIMEOUT` | `3600` | Per-file wall-clock safety net (seconds) to guard against modules that loop forever. |
| `UADE_TIMEOUT` | _unset_ | Optional `uade123 -t` song timeout; useful for endlessly-looping Amiga tunes. |
| `UADE_OPTS` | _unset_ | Extra raw options passed through to `uade123`. |
| `IT_ENGINE` | `openmpt` | Engine for IT/S3M/MOD: `openmpt` (libopenmpt) or `schism` (Impulse-Tracker-faithful). |
| `SID_TIMEOUT` | `180` | Render length in seconds for SID tunes (they are otherwise endless). |

## Format detection

The script matches **both** the filename suffix (`foo.mod`) and the prefix before the
first dot (`mod.foo`, `tfmx.boss`, `fc.song`) — Amiga modules are frequently named with a
player prefix rather than an extension. AdLib/OPL (`.rad .d00 .hsc …`) and C64 SID
(`.sid .psid …`) are routed by extension to `adplay` and `sidplayfp`. Files whose
extension isn't in any table fall through a probe chain (libopenmpt → UADE → xmp) and use
the first engine that accepts them. Unconvertible files are reported and the run continues.

## Tests

```sh
tests/run.sh            # fast suites: routing + dispatch logic (no Docker needed)
tests/run.sh --docker   # also run the real-image integration test
```

- **`unit_detect.sh`** — unit tests for the pure routing helpers (`detect_backend`,
  `word_in_list`, `lc`), including the AdLib/SID extension tables and the
  `IT_ENGINE=schism` reroute. `convert.sh` is sourced directly; its `main` is guarded so
  it doesn't run on source.
- **`dispatch_stubbed.sh`** — drives `convert.sh` end-to-end with *stubbed* backends on
  `PATH`, covering argument parsing, output naming, single/batch modes, routing to every
  engine (uade/openmpt/adplay/sidplayfp/schism), the unknown-format fallback chain, and
  env-var threading. No real tools or Docker required.
- **`integration_docker.sh`** — runs the actual built image: checks every tool and the
  UADE data are present, converts a generated `.mod` (UADE), a content-`.xm` (libopenmpt),
  an unknown extension (fallback), and an `.it` via `IT_ENGINE=schism`, asserting the WAV
  headers (rate/channels/bits) including a `SAMPLE_RATE=48000` override. Skips cleanly if
  Docker or the image is unavailable.

Fixtures (a minimal valid ProTracker `.mod` and Impulse Tracker `.it`, plus the stub
backends) are generated on the fly by helpers in `tests/lib.sh` — nothing binary is
committed.

## Extending

Adjacent chip-music formats can be added in two places. The one notable format still
*not* bundled is **Atari SNDH** — `sc68` is unmaintained and currently fails to build
under bookworm (its autotools setup is incompatible with modern automake); revisit if an
upstream fix or a maintained fork appears.

1. **Dockerfile** — install or build the tool (e.g. a maintained `sc68`/SNDH player).
2. **`scripts/convert.sh`** — add the extensions to a format table, a matching `render_*`
   function (mirror `render_adplay` / `render_sidplayfp`), and a `case` arm in `attempt`.

The per-engine WAV-output invocations (`uade123 -e wav -f`, `openmpt123 --render`,
`adplay -O disk -d`, `sidplayfp -w`, `schismtracker --diskwrite`, `xmp -o`) are the
load-bearing options; if a future tool version renames one, adjust the matching `render_*`
function in `scripts/convert.sh`.
