#!/bin/bash

set -xe

echo "Building catboost from source..."

# ====================================================================
# Compiler setup (Linux only)
# On Linux, catboost's clang.toolchain expects clang/clang++ on PATH.
# compiler('cxx') provides GCC (sysroot/libstdc++), clangxx provides
# the actual Clang compiler used by catboost's build system.
# On macOS, compiler('cxx') already provides Clang natively.
# ====================================================================
if [[ "$target_platform" == "linux-"* ]]; then
    ln -sf $BUILD_PREFIX/bin/clang $BUILD_PREFIX/bin/${BUILD}-clang++
    ln -sf $BUILD_PREFIX/bin/clang $BUILD_PREFIX/bin/${BUILD}-clang
    ln -sf $BUILD_PREFIX/bin/clang $BUILD_PREFIX/bin/${HOST}-clang++
    ln -sf $BUILD_PREFIX/bin/clang $BUILD_PREFIX/bin/${HOST}-clang
    export CC=${HOST}-clang
    export CXX=${HOST}-clang++
    export CC_FOR_BUILD=${BUILD}-clang
    export CXX_FOR_BUILD=${BUILD}-clang++
fi

# ====================================================================
# CUDA-specific configuration (only for gpu_variant=cuda*)
# ====================================================================
if [[ "${gpu_variant}" == cuda* ]]; then
    echo "Configuring CUDA support..."

    # Clang is the NVCC host compiler (NOT GCC). Without -ccbin, nvcc defaults to
    # `g++` -- which is unprefixed and isn't on PATH in conda's compiler-wrapper
    # layout, so CMake's CUDA compiler-identification step fails before it even
    # gets to our build. --allow-unsupported-compiler suppresses the version check
    # for the newer clang (catboost's clang.toolchain previously set this via
    # set(ENV{NVCC_PREPEND_FLAGS} ...); conda.diff drops that line so it doesn't
    # clobber the -ccbin we set here.
    export NVCC_PREPEND_FLAGS="-ccbin=$BUILD_PREFIX/bin/${HOST}-clang++ --allow-unsupported-compiler -std=c++17"

    # Patch CUDA's host_defines.h to allow catboost's bundled libcxxcuda11.
    # CatBoost builds with -nostdinc++ and its own libc++ fork (libcxxcuda11)
    # designed for CUDA compatibility. CUDA 12.3+ rejects libc++ on x86 with a
    # blanket #error; the wording is the same on aarch64 (SBSA) and on 13.x.
    # Match any "libc++ is not supported" error so future CUDA bumps keep working.
    for arch_dir in x86_64-linux sbsa-linux; do
        host_defines="$BUILD_PREFIX/targets/$arch_dir/include/crt/host_defines.h"
        if [[ -f "$host_defines" ]]; then
            sed -i 's|#error "libc++ is not supported[^"]*"|/* patched: catboost libcxxcuda11 is CUDA-compatible */|' \
                "$host_defines"
            echo "Patched host_defines.h ($arch_dir) to allow libcxxcuda11"
        fi
    done

    # CUDA build flags
    if [[ "$cuda_compiler_version" != "None" ]]; then
        # CMAKE_CUDA_ARCHITECTURES list: drop arches the active nvcc no longer accepts.
        # catboost upstream default is 35;50;60;61;70;75;80;86;89;90.
        #   CUDA 12.x:  nvcc 12.0+ dropped sm_35 (Kepler).
        #   CUDA 13.x:  nvcc 13.0 additionally dropped sm_50/60/61/70 (Maxwell/Pascal/Volta); minimum is sm_75.
        case "$cuda_compiler_version" in
            12.*)
                CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_CUDA_ARCHITECTURES=50-virtual;60-virtual;61-real;70-virtual;75-real;80-real;86-real;89-real;90"
                ;;
            13.*)
                CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_CUDA_ARCHITECTURES=75-real;80-real;86-real;89-real;90"
                ;;
        esac

        # Rewrite static-CUDA-runtime link flags to shared-cudart equivalents.
        # conda's cuda-cudart-dev ships only the dynamic libcudart.so; the
        # static libcudart_static.a / libcudadevrt.a / libculibos.a from the
        # NVIDIA tarball are not packaged. catboost's per-target CMakeLists
        # (including catboost/python-package/catboost/CMakeLists.linux-*-cuda.txt
        # which is what we actually build for _catboost) hardcode the static
        # names, so a global rewrite is necessary -- without this, the final
        # link step fails with `unable to find library -lculibos`.
        find . -name "CMakeLists*.txt" -type f -print0 | xargs -0 sed -i "s/-lcudart_static/-lcudart/g"
        find . -name "CMakeLists*.txt" -type f -print0 | xargs -0 sed -i "s/-lcudadevrt/-lcudart/g"
        find . -name "CMakeLists*.txt" -type f -print0 | xargs -0 sed -i "s/-lculibos/-lcudart/g"

        CMAKE_ARGS="${CMAKE_ARGS} -DHAVE_CUDA=ON"
    fi

    # Restrict CUDA compilation parallelism
    cp ci/cmake/cuda.cmake cmake/cuda.cmake
fi

# ====================================================================
# Python configuration for CMake
# ====================================================================
Python3_INCLUDE_DIR="$(python -c 'import sysconfig; print(sysconfig.get_path("include"))')"
Python3_NumPy_INCLUDE_DIR="$(python -c 'import numpy;print(numpy.get_include())')"
CMAKE_ARGS="${CMAKE_ARGS} -DPython3_EXECUTABLE:PATH=${PYTHON}"
CMAKE_ARGS="${CMAKE_ARGS} -DPython3_INCLUDE_DIR:PATH=${Python3_INCLUDE_DIR}"
CMAKE_ARGS="${CMAKE_ARGS} -DPython3_NumPy_INCLUDE_DIR=${Python3_NumPy_INCLUDE_DIR}"

# ====================================================================
# CMake build
# ====================================================================
(
    mkdir -p cmake_build
    pushd cmake_build

    mkdir -p bin
    ln -sf ${BUILD_PREFIX}/bin/{swig,ragel} bin/
    # yasm only available on x86_64
    if [[ -f "${BUILD_PREFIX}/bin/yasm" ]]; then
        ln -sf ${BUILD_PREFIX}/bin/yasm bin/
    fi

    cmake ${CMAKE_ARGS} \
        -DCMAKE_POSITION_INDEPENDENT_CODE=On \
        -DCMAKE_TOOLCHAIN_FILE=${SRC_DIR}/build/toolchains/clang.toolchain \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_VERBOSE_MAKEFILE=ON \
        -DCATBOOST_COMPONENTS="PYTHON-PACKAGE" \
        ..

    make -j${CPU_COUNT} _catboost _hnsw
    popd
)

# ====================================================================
# Build and install Python wheel
# ====================================================================
cd catboost/python-package/

$PYTHON setup.py bdist_wheel --with-hnsw --no-widget --prebuilt-extensions-build-root-dir=${SRC_DIR}/cmake_build -vv
$PYTHON -m pip install --no-deps --no-build-isolation -vvv dist/catboost*.whl
