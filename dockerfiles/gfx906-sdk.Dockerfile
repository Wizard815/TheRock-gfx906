# Full gfx906 ROCm SDK image (headers, LLVM toolchain, libraries) from the
# tarball build-gfx906-docker.sh produces. Used as the base for building and
# running mx-llama.cpp / whisper.cpp against this ROCm build.
#
#   docker build -f dockerfiles/gfx906-sdk.Dockerfile \
#     -t rocm10-gfx906:10.2-sdk build/archives
#
# The build context is build/archives, so only the tarball is sent to Docker.
FROM ubuntu:24.04

ARG ROCM_TARBALL=rocm-gfx906-10.2.0.tar.xz

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates python3 libgfortran5 \
    && rm -rf /var/lib/apt/lists/*

# ADD unpacks local tar archives; the tarball's top-level directory is rocm/.
ADD ${ROCM_TARBALL} /opt/

ENV ROCM_PATH=/opt/rocm \
    HIP_PATH=/opt/rocm \
    PATH=/opt/rocm/bin:/opt/rocm/lib/llvm/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/rocm/lib:/opt/rocm/lib/llvm/lib

RUN test -x /opt/rocm/bin/hipcc && test -d /opt/rocm/lib/rocblas/library/gfx906 \
    && echo "/opt/rocm/lib" > /etc/ld.so.conf.d/rocm.conf && ldconfig

LABEL org.opencontainers.image.description="gfx906 ROCm SDK built from Wizard815/TheRock-gfx906" \
      org.opencontainers.image.source="https://github.com/Wizard815/TheRock-gfx906"
