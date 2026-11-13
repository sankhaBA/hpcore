#!/bin/bash
# Compiles hpcore, hpfs and hpws inside the offline builder container.
# Read-only inputs: /src/{hpcore,hpfs,hpws} and /deps/<name>.tar.gz. Writable output: /out.

set -euo pipefail

readonly SRC_DIR=/src
readonly DEPS_DIR=/deps
readonly OUT_DIR=/out
readonly WORK_DIR=/work
# Same place dev-setup.sh uses. Headers there are system headers, so hpcore's -Wall -Werror
# never fails on warnings inside third-party code. The container is thrown away after the build.
readonly PREFIX=/usr/local
readonly JOBS=${BUILD_JOBS:-1}

function log() {
    echo "[build-engine] $*" >&2
}

# Unpacks /deps/<name>.tar.gz into WORK_DIR/deps/<name> and prints that folder.
function unpack() {
    local name=$1
    local dir=$WORK_DIR/deps/$name
    mkdir -p "$dir"
    tar -xzf "$DEPS_DIR/$name.tar.gz" -C "$dir" --strip-components=1
    echo "$dir"
}

function install_header_deps() {
    local dir
    mkdir -p "$PREFIX/include/jsoncons_ext" "$PREFIX/include/readerwriterqueue" "$PREFIX/lib"

    dir=$(unpack jsoncons)
    cp -r "$dir/include/jsoncons" "$PREFIX/include/"
    cp -r "$dir/include/jsoncons_ext/bson" "$PREFIX/include/jsoncons_ext/"

    dir=$(unpack flatbuffers)
    cp -r "$dir/include/flatbuffers" "$PREFIX/include/"

    dir=$(unpack readerwriterqueue)
    cp "$dir"/*.h "$PREFIX/include/readerwriterqueue/"

    dir=$(unpack concurrentqueue)
    cp "$dir/concurrentqueue.h" "$PREFIX/include/"

    dir=$(unpack plog)
    cp -r "$dir/include/plog" "$PREFIX/include/"

    dir=$(unpack cli11)
    cp -r "$dir/include/CLI" "$PREFIX/include/"
}

# Same flags as dev-setup.sh, so developer builds and host builds link the same BLAKE3.
function build_blake3() {
    local dir
    dir=$(unpack blake3)/c
    (
        cd "$dir"
        gcc -c -fPIC -O3 blake3.c blake3_dispatch.c blake3_portable.c \
            blake3_sse2_x86-64_unix.S blake3_sse41_x86-64_unix.S \
            blake3_avx2_x86-64_unix.S blake3_avx512_x86-64_unix.S
        ar rcs "$PREFIX/lib/libblake3.a" ./*.o
        cp blake3.h "$PREFIX/include/"
    )
}

function build_hpcore() {
    cmake -S "$SRC_DIR/hpcore" -B "$WORK_DIR/hpcore" -DHP_BUNDLE_DEV_BINARIES=OFF
    make -C "$WORK_DIR/hpcore" -j "$JOBS" hpcore
    install -m 0755 "$WORK_DIR/hpcore/build/hpcore" "$OUT_DIR/hpcore"
}

function build_hpfs() {
    cmake -S "$SRC_DIR/hpfs" -B "$WORK_DIR/hpfs"
    make -C "$WORK_DIR/hpfs" -j "$JOBS" hpfs
    install -m 0755 "$WORK_DIR/hpfs/build/hpfs" "$OUT_DIR/hpfs"
}

function build_hpws() {
    cp -a "$SRC_DIR/hpws" "$WORK_DIR/hpws"
    make -C "$WORK_DIR/hpws" hpws
    install -m 0755 "$WORK_DIR/hpws/hpws" "$OUT_DIR/hpws"
}

# Records the toolchain and package versions next to the binaries, for the build manifest.
function write_build_info() {
    {
        echo "compiler=$(gcc --version | head -n 1)"
        echo "cmake=$(cmake --version | head -n 1)"
        dpkg-query -W -f="package=\${Package} \${Version}\n"
    } >"$OUT_DIR/build-info.txt"
}

log "Installing pinned dependencies"
install_header_deps
build_blake3
log "Compiling hpcore"
build_hpcore
log "Compiling hpfs"
build_hpfs
log "Compiling hpws"
build_hpws
strip --strip-unneeded "$OUT_DIR/hpcore" "$OUT_DIR/hpfs" "$OUT_DIR/hpws"
write_build_info
log "Done"
