# Cross-build GCC 13.2.0 for powerpc64-ps3-elf (PPU).
# Stay on Debian 12 so the host-linked cross gcc needs only glibc 2.36
# (Bookworm). Building on Trixie produces GLIBC_2.38+ binaries that fail
# on Debian 12 and similar hosts.
# docker build -t gcc-ps3-ppu .
FROM debian:12-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive \
    PS3DEV=/usr/local/ps3dev \
    WORK=/work \
    JOBS=2 \
    PATH="/usr/local/ps3dev/ppu/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
      bison \
      build-essential \
      bzip2 \
      ca-certificates \
      curl \
      file \
      flex \
      gawk \
      libelf-dev \
      libgmp-dev \
      libmpc-dev \
      libmpfr-dev \
      make \
      patch \
      python3 \
      texinfo \
      xz-utils \
      zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . /src
RUN chmod +x /src/ci/build-ppu.sh /src/ci/config.guess /src/ci/config.sub \
    && /src/ci/build-ppu.sh

FROM debian:12-slim AS runtime
ENV PS3DEV=/usr/local/ps3dev \
    PATH="/usr/local/ps3dev/ppu/bin:${PATH}"
COPY --from=builder /usr/local/ps3dev /usr/local/ps3dev
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
CMD ["powerpc64-ps3-elf-gcc", "-v"]
