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

    # Clang is the NVCC host compiler (NOT GCC)
    export NVCC_PREPEND_FLAGS="-ccbin=$BUILD_PREFIX/bin/${HOST}-clang++"

    # Patch CUDA 12.4's host_defines.h to allow catboost's bundled libcxxcuda11.
    # CatBoost builds with -nostdinc++ and its own libc++ fork (libcxxcuda11)
    # designed for CUDA compatibility. CUDA 12.3+ added a blanket #error rejecting
    # libc++ on x86, which is a false positive for this use case.
    if [[ -f "$BUILD_PREFIX/targets/x86_64-linux/include/crt/host_defines.h" ]]; then
        sed -i 's/#error "libc++ is not supported on x86 system"/\/\* patched: catboost libcxxcuda11 is CUDA-compatible *\//' \
            "$BUILD_PREFIX/targets/x86_64-linux/include/crt/host_defines.h"
        echo "Patched host_defines.h to allow libcxxcuda11 on x86"
    fi

    # CUDA build flags
    if [[ "$cuda_compiler_version" != "None" ]]; then
        # Remove older CUDA architectures for CUDA 12+
        if [[ "$cuda_compiler_version" != "11.8" ]]; then
            find . -name "CMakeLists*cuda.txt" -type f -print0 | xargs -0 sed -i -z -r \
                "s/-gencode\s*=?arch=compute_35,code=sm_35//g"
        fi

        # Link with shared cudart instead of static
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
