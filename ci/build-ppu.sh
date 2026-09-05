#!/usr/bin/env bash
# Cross-build this GCC as powerpc64-ps3-elf (PPU) with newlib.
# Used by the Dockerfile and GitHub Actions.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CI="${ROOT}/ci"
WORK="${WORK:-${ROOT}/.build}"
PS3DEV="${PS3DEV:-${WORK}/ps3dev}"
PREFIX="${PS3DEV}/ppu"
JOBS="${JOBS:-}"

BINUTILS_VER="2.42"
BINUTILS_TAR="binutils-${BINUTILS_VER}.tar.bz2"
BINUTILS_SHA="aa54850ebda5064c72cd4ec2d9b056c294252991486350d9a97ab2a6dfdfaf12"
BINUTILS_URL="https://sourceware.org/pub/binutils/releases/${BINUTILS_TAR}"

NEWLIB_VER="1.20.0"
NEWLIB_TAR="newlib-${NEWLIB_VER}.tar.gz"
NEWLIB_SHA="c644b2847244278c57bec2ddda69d8fab5a7c767f3b9af69aa7aa3da823ff692"
NEWLIB_URL="https://sourceware.org/pub/newlib/${NEWLIB_TAR}"

ncpu() {
  if [ -n "${JOBS}" ]; then
    echo "${JOBS}"
  elif command -v nproc >/dev/null 2>&1; then
    nproc --all
  elif command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.ncpu
  else
    echo 4
  fi
}

# GCC/binutils Makefiles need GNU make 4+. Apple /usr/bin/make is 3.81
# and rejects --output-sync; recursive recipes call $(MAKE), so we must
# export MAKE and put Homebrew's gnubin first (same idea as ps3toolchain).
if [ "$(uname -s)" = Darwin ] && command -v brew >/dev/null 2>&1; then
  make_pfx="$(brew --prefix make 2>/dev/null || true)"
  if [ -d "${make_pfx}/libexec/gnubin" ]; then
    PATH="${make_pfx}/libexec/gnubin:${PATH}"
  fi
  export PATH
fi
if command -v gmake >/dev/null 2>&1; then
  MAKE=gmake
else
  MAKE=make
fi
export MAKE
make_ver="$("${MAKE}" --version 2>/dev/null | head -1 || echo unknown)"
echo "Using MAKE=${MAKE} (${make_ver})"
case "${make_ver}" in
  'GNU Make 3.'*|unknown)
    if [ "$(uname -s)" = Darwin ]; then
      echo "ERROR: GNU Make 4+ is required (Apple make is 3.81). Run: brew install make" >&2
      exit 1
    fi
    ;;
esac

# Skip Texinfo manuals (makeinfo is often missing; we only need the toolchain).
export MAKEINFO=true

run_make() {
  if "${MAKE}" --help 2>/dev/null | grep -q -- '--output-sync'; then
    "${MAKE}" MAKEINFO=true --output-sync=target "$@"
  else
    "${MAKE}" MAKEINFO=true "$@"
  fi
}

checksum() {
  local file="$1" expect="$2" got
  if command -v sha256sum >/dev/null 2>&1; then
    got="$(sha256sum "$file" | awk '{print $1}')"
  else
    got="$(shasum -a 256 "$file" | awk '{print $1}')"
  fi
  if [ "$got" != "$expect" ]; then
    echo "checksum mismatch for $file" >&2
    echo "  expected $expect" >&2
    echo "  got      $got" >&2
    return 1
  fi
}

fetch() {
  local url="$1" dest="$2" sha="$3"
  if [ -f "$dest" ]; then
    checksum "$dest" "$sha"
    return
  fi
  echo "==> $url"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 -o "${dest}.part" "$url"
  else
    wget -O "${dest}.part" "$url"
  fi
  mv "${dest}.part" "$dest"
  checksum "$dest" "$sha"
}

refresh_config() {
  local dest="$1"
  find "$dest" -name config.guess -exec cp "${CI}/config.guess" {} \;
  find "$dest" -name config.sub -exec cp "${CI}/config.sub" {} \;
}

if [ ! -f "${ROOT}/gcc/BASE-VER" ]; then
  echo "gcc/BASE-VER not found; run from the gcc-PS3 tree" >&2
  exit 1
fi
if [ "$(cat "${ROOT}/gcc/BASE-VER")" != "13.2.0" ]; then
  echo "expected GCC 13.2.0, got $(cat "${ROOT}/gcc/BASE-VER")" >&2
  exit 1
fi

mkdir -p "${WORK}/archives" "${PREFIX}"
export PATH="${PREFIX}/bin:${PATH}"

fetch "${BINUTILS_URL}" "${WORK}/archives/${BINUTILS_TAR}" "${BINUTILS_SHA}"
fetch "${NEWLIB_URL}" "${WORK}/archives/${NEWLIB_TAR}" "${NEWLIB_SHA}"

if [ ! -d "${WORK}/binutils-${BINUTILS_VER}" ]; then
  echo "Unpacking binutils ${BINUTILS_VER}"
  tar -xjf "${WORK}/archives/${BINUTILS_TAR}" -C "${WORK}"
  patch -p1 --batch --forward -d "${WORK}/binutils-${BINUTILS_VER}" \
    < "${CI}/patches/binutils-${BINUTILS_VER}-PS3-PPU.patch"
  refresh_config "${WORK}/binutils-${BINUTILS_VER}"
fi

if [ ! -d "${WORK}/binutils-${BINUTILS_VER}/build-ppu" ]; then
  mkdir "${WORK}/binutils-${BINUTILS_VER}/build-ppu"
fi
if [ ! -x "${PREFIX}/bin/powerpc64-ps3-elf-as" ]; then
  echo "Building binutils PPU"
  (
    cd "${WORK}/binutils-${BINUTILS_VER}/build-ppu"
    unset LDFLAGS || true
    MAKEINFO=true \
    ../configure --prefix="${PREFIX}" --target="powerpc64-ps3-elf" \
      --with-gcc --with-gnu-as --with-gnu-ld \
      --enable-64-bit-bfd --enable-lto \
      --disable-nls --disable-shared --disable-debug \
      --disable-dependency-tracking --disable-werror \
      --disable-gprofng --disable-install-libiberty \
      --with-system-zlib
    run_make -j"$(ncpu)"
    "${MAKE}" MAKEINFO=true install
  )
  rm -f "${PREFIX}/lib/libiberty.a" "${PREFIX}/lib64/libiberty.a"
fi

if [ ! -d "${WORK}/newlib-${NEWLIB_VER}" ]; then
  echo "Unpacking newlib ${NEWLIB_VER}"
  tar -xzf "${WORK}/archives/${NEWLIB_TAR}" -C "${WORK}"
  patch -p1 --batch --forward -d "${WORK}/newlib-${NEWLIB_VER}" \
    < "${CI}/patches/newlib-${NEWLIB_VER}-PS3.patch"
fi
refresh_config "${WORK}/newlib-${NEWLIB_VER}"
refresh_config "${ROOT}"

ln -sfn "${WORK}/newlib-${NEWLIB_VER}/newlib" "${ROOT}/newlib"
ln -sfn "${WORK}/newlib-${NEWLIB_VER}/libgloss" "${ROOT}/libgloss"

# Same as ps3toolchain 002-gcc-newlib-PPU.sh: GCC needs GMP/MPFR/MPC.
# Homebrew puts headers in $(brew --prefix)/include, which configure does
# not search unless --with-gmp is set. Fall back to in-tree tarballs.
with_gmp=()
if [ "$(uname -s)" = Darwin ] && command -v brew >/dev/null 2>&1; then
  gmp_pfx="$(brew --prefix gmp 2>/dev/null || true)"
  mpfr_pfx="$(brew --prefix mpfr 2>/dev/null || true)"
  mpc_pfx="$(brew --prefix libmpc 2>/dev/null || true)"
  if [ -f "${gmp_pfx}/include/gmp.h" ] \
     && [ -f "${mpfr_pfx}/include/mpfr.h" ] \
     && [ -f "${mpc_pfx}/include/mpc.h" ]; then
    with_gmp=(
      --with-gmp="${gmp_pfx}"
      --with-mpfr="${mpfr_pfx}"
      --with-mpc="${mpc_pfx}"
    )
  fi
fi
if [ ${#with_gmp[@]} -eq 0 ] && [ ! -e "${ROOT}/gmp" ]; then
  echo "Downloading GCC prerequisites (GMP/MPFR/MPC)"
  (cd "${ROOT}" && ./contrib/download_prerequisites --no-isl)
fi

mkdir -p "${WORK}/build-gcc"
echo "Configuring GCC $(cat "${ROOT}/gcc/BASE-VER") for powerpc64-ps3-elf"
(
  cd "${WORK}/build-gcc"
  # -Wno-int-conversion is C-only; g++ then warns on every file and the
  # real make error is easy to miss in Docker's truncated log.
  unset CXXFLAGS || true
  CFLAGS="${CFLAGS:--Wno-int-conversion}" \
  "${ROOT}/configure" --prefix="${PREFIX}" --target="powerpc64-ps3-elf" \
    --disable-dependency-tracking \
    --disable-libcc1 \
    --disable-libstdcxx-pch \
    --disable-multilib \
    --disable-nls \
    --disable-shared \
    --disable-win32-registry \
    --enable-languages="c,c++" \
    --enable-long-double-128 \
    --enable-lto \
    --enable-threads \
    --with-cpu="cell" \
    --with-newlib \
    --enable-newlib-multithread \
    --enable-newlib-hw-fp \
    --with-system-zlib \
    "${with_gmp[@]}"
  echo "Building GCC"
  jobs="$(ncpu)"
  echo "${MAKE} -j${jobs}"
  if ! run_make -j"${jobs}" all; then
    echo "Parallel build failed; rerunning -j1 so the failing recipe is last." >&2
    "${MAKE}" MAKEINFO=true -j1 all
  fi
  "${MAKE}" MAKEINFO=true MULTIOSDIR=. install
)

echo "Smoke test"
cat > "${WORK}/hello.c" <<'EOF'
int main(void) { return 0; }
EOF
cat > "${WORK}/hello.cc" <<'EOF'
int main() { return 0; }
EOF

"${PREFIX}/bin/powerpc64-ps3-elf-gcc" -dumpmachine | grep -x powerpc64-ps3-elf
"${PREFIX}/bin/powerpc64-ps3-elf-gcc" -c "${WORK}/hello.c" -o "${WORK}/hello.o"
"${PREFIX}/bin/powerpc64-ps3-elf-g++" -c "${WORK}/hello.cc" -o "${WORK}/hello.o++"

echo "PPU GCC 13.2.0 build OK -> ${PREFIX}"
