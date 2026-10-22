#!/bin/bash
# Build TheRock for gfx906 (MI50/MI60) inside an Ubuntu 24.04 container.
# For hosts with Docker but no toolchain (e.g. Unraid). Runs the GFX906.md
# recipe; sources, build tree, venv and ccache all stay in this checkout, so
# re-running resumes/rebuilds incrementally.
#
#   ./build-gfx906-docker.sh            # fetch sources (first run) + build
#   JOBS=8 ./build-gfx906-docker.sh     # more parallelism (needs more RAM)
#   ./build-gfx906-docker.sh shell      # interactive shell in the build env
#
# Needs ~250GB free here and ~4-8GB RAM per job. Output: build/dist/rocm/ and
# build/archives/*.tar.xz.
set -euo pipefail

SRC=$(cd "$(dirname "$0")" && pwd)
JOBS=${JOBS:-4}
IMAGE=${IMAGE:-therock-gfx906-builder}

docker build -t "$IMAGE" -f - "$SRC/dockerfiles" <<'EOF'
FROM ubuntu:24.04
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        gfortran git ninja-build cmake g++ pkg-config xxd automake libtool \
        python3-venv python3-dev libegl1-mesa-dev texinfo bison flex \
        curl make ca-certificates xz-utils jq \
    && rm -rf /var/lib/apt/lists/*
COPY install_pinned_patchelf.sh install_patchelf.sh install_ccache.sh \
     build_manylinux_x86_64.Dockerfile /tmp/inst/
RUN cd /tmp/inst \
    && env INSTALL_PREFIX=/usr/local ./install_pinned_patchelf.sh \
    && ./install_ccache.sh 4.11.2 \
    && rm -rf /tmp/inst
RUN git config --system --add safe.directory '*'
EOF

tty=()
[ -t 0 ] && tty=(-it)

if [ "${1:-}" = shell ]; then
    exec docker run --rm "${tty[@]}" -v "$SRC:/src" -w /src "$IMAGE" bash
fi

exec docker run --rm "${tty[@]}" \
    -v "$SRC:/src" -w /src \
    -e JOBS="$JOBS" -e CMAKE_BUILD_PARALLEL_LEVEL="$JOBS" \
    "$IMAGE" bash -euo pipefail -c '
if [ ! -d .venv ]; then
    python3 -m venv .venv
    .venv/bin/pip install --upgrade pip
    .venv/bin/pip install -r requirements.txt
fi
source .venv/bin/activate

# First run only: submodules + patches. Re-running fetch_sources.py resets
# every submodule, so it is skipped once sources exist.
if [ ! -e .gfx906-sources-fetched ]; then
    python3 ./build_tools/fetch_sources.py
    touch .gfx906-sources-fetched
fi

eval "$(./build_tools/setup_ccache.py)"

if [ ! -f build/build.ninja ]; then
    cmake -B build -GNinja \
        -DTHEROCK_AMDGPU_FAMILIES=gfx906 \
        -DTHEROCK_TEST_AMDGPU_TARGETS=gfx906 \
        -DTHEROCK_ENABLE_ROCWMMA=OFF \
        -DTHEROCK_ENABLE_HIPBLASLTPROVIDER=OFF \
        -DTHEROCK_ENABLE_ROCJITSU=OFF \
        -DTHEROCK_ENABLE_EMULATION=OFF \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
fi

ninja -C build -j"$JOBS"
ninja -C build artifacts
ninja -C build archives
echo "Done: build/dist/rocm/ and build/archives/"
'
