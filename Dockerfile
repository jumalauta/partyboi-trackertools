# partyboi-trackertools — accurate tracker module → WAV conversion
#
# Multi-stage build:
#   1. builder  — compile bencode-tools + UADE from source (UADE is not packaged for
#                 Debian). UADE provides authentic Amiga playback (incl. ProTracker
#                 .mod) by running the original 68k replay routines through Paula
#                 emulation.
#   2. runtime  — slim image with openmpt123 (libopenmpt), xmp (libxmp) and sox from
#                 apt, plus the UADE binary + its eagleplayer data copied in.

# ----------------------------------------------------------------------------
# Stage 1: build UADE (and its bencode-tools dependency)
# ----------------------------------------------------------------------------
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        git \
        ca-certificates \
        pkg-config \
        libao-dev \
        python3 \
        python3-distutils \
        python3-setuptools \
    && rm -rf /var/lib/apt/lists/*

# Make the freshly-installed /usr/local libs and pkg-config files visible while
# building each successive dependency.
ENV LD_LIBRARY_PATH=/usr/local/lib \
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig

WORKDIR /src

# UADE 3.x build chain (all from source; none are packaged for Debian):
#   libzakalwe  -> bencode-tools -> uade
# bencode-tools' install runs a Python step, hence python3-distutils/-setuptools.
# libao-dev is needed for the uade123 audio backend.
RUN git clone --depth 1 https://gitlab.com/hors/libzakalwe.git \
    && cd libzakalwe \
    && ./configure --prefix=/usr/local \
    && make -j"$(nproc)" \
    && make install \
    && ldconfig

RUN git clone --depth 1 https://gitlab.com/heikkiorsila/bencodetools.git \
    && cd bencodetools \
    && ./configure --prefix=/usr/local \
    && make -j"$(nproc)" \
    && make install \
    && ldconfig

# Canonical UADE source. (Mirror: https://gitlab.com/uade-music-player/uade)
RUN git clone --depth 1 https://github.com/dv1/uade.git \
    && cd uade \
    && ./configure --prefix=/usr/local \
    && make -j"$(nproc)" \
    && make install \
    && ldconfig

# ----------------------------------------------------------------------------
# Stage 2: runtime
# ----------------------------------------------------------------------------
FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="partyboi-trackertools" \
      org.opencontainers.image.description="Accurate tracker module to WAV conversion (UADE + libopenmpt + libxmp)" \
      org.opencontainers.image.source="partyboi-trackertools"

RUN apt-get update && apt-get install -y --no-install-recommends \
        openmpt123 \
        xmp \
        sox \
        libao4 \
    && rm -rf /var/lib/apt/lists/*

# Bring in UADE + its from-source deps: binaries, libs, and — crucially — UADE's
# runtime data (eagleplayers / score / uade.conf) under /usr/local/share/uade.
COPY --from=builder /usr/local/ /usr/local/
RUN ldconfig

COPY scripts/convert.sh /usr/local/bin/convert.sh
RUN chmod +x /usr/local/bin/convert.sh

WORKDIR /work
ENTRYPOINT ["convert.sh"]
CMD ["--help"]
