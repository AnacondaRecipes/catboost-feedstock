#!/bin/bash

set -xe

# Check if this is a CUDA build or CPU build
if [[ "${gpu_variant}" == cuda* ]]; then
    echo "Building CUDA variant from source with Clang..."

    # Setup Clang compiler (required for catboost CUDA builds)
    if [[ "$target_platform" == "linux-"* ]]; then
        echo "========== DEBUG: Build Environment =========="
        echo "BUILD_PREFIX=$BUILD_PREFIX"
        echo "PREFIX=$PREFIX"
        echo "HOST=$HOST"
        echo "BUILD=$BUILD"
        echo ""

        echo "========== DEBUG: Available compilers =========="
        ls -la $BUILD_PREFIX/bin/clang* || true
        ls -la $BUILD_PREFIX/bin/*g++* || true
        ls -la $BUILD_PREFIX/bin/*gcc* || true
        echo ""

        echo "========== DEBUG: GCC toolchain location =========="
        echo "Checking $BUILD_PREFIX/targets/${HOST}:"
        ls -la $BUILD_PREFIX/targets/${HOST}/ 2>/dev/null || echo "  Directory not found"
        echo "Checking $BUILD_PREFIX/include/c++:"
        ls -la $BUILD_PREFIX/include/c++/ 2>/dev/null || echo "  Directory not found"
        echo ""

        echo "========== DEBUG: GCC search dirs =========="
        $BUILD_PREFIX/bin/${HOST}-g++ -print-search-dirs 2>/dev/null || echo "  g++ not found"
        echo ""

        echo "========== DEBUG: Raw clang include paths (no flags) =========="
        $BUILD_PREFIX/bin/clang++ -v -E -x c++ /dev/null 2>&1 | grep -A 20 "include" || true
        echo ""

        echo "========== DEBUG: Clang with -stdlib=libstdc++ =========="
        $BUILD_PREFIX/bin/clang++ -stdlib=libstdc++ -v -E -x c++ /dev/null 2>&1 | grep -A 20 "include" || true
        echo ""

        echo "========== DEBUG: Clang with --gcc-toolchain =========="
        $BUILD_PREFIX/bin/clang++ --gcc-toolchain=$BUILD_PREFIX -stdlib=libstdc++ -v -E -x c++ /dev/null 2>&1 | grep -A 20 "include" || true
        echo ""

        echo "========== DEBUG: Clang with --gcc-toolchain pointing to targets =========="
        $BUILD_PREFIX/bin/clang++ --gcc-toolchain=$BUILD_PREFIX/targets/${HOST} -stdlib=libstdc++ -v -E -x c++ /dev/null 2>&1 | grep -A 20 "include" || true
        echo ""

        echo "========== DEBUG: Check for libc++ headers (c++/v1) =========="
        find $BUILD_PREFIX -name "v1" -type d 2>/dev/null | head -10 || true
        find $BUILD_PREFIX -name "__config" 2>/dev/null | head -10 || true
        echo ""

        echo "========== DEBUG: Check _LIBCPP_VERSION definition =========="
        echo '#include <cstddef>' | $BUILD_PREFIX/bin/clang++ -stdlib=libstdc++ -dM -E -x c++ - 2>/dev/null | grep LIBCPP || echo "  _LIBCPP_VERSION not defined with -stdlib=libstdc++"
        echo '#include <cstddef>' | $BUILD_PREFIX/bin/clang++ -dM -E -x c++ - 2>/dev/null | grep LIBCPP || echo "  _LIBCPP_VERSION not defined (default)"
        echo ""

        echo "========== DEBUG: Conda clang wrapper vs raw clang =========="
        echo "x86_64-conda-linux-gnu-clang++ location:"
        which ${HOST}-clang++ 2>/dev/null || echo "  Not found in PATH"
        ls -la $BUILD_PREFIX/bin/${HOST}-clang++ 2>/dev/null || echo "  Not in BUILD_PREFIX"
        echo ""

        # For now, keep using the approach but with better toolchain path
        export CC=$BUILD_PREFIX/bin/clang
        export CXX=$BUILD_PREFIX/bin/clang++
        export CC_FOR_BUILD=$BUILD_PREFIX/bin/clang
        export CXX_FOR_BUILD=$BUILD_PREFIX/bin/clang++

        # Try both toolchain paths and see which works
        if [ -d "$BUILD_PREFIX/targets/${HOST}" ]; then
            GCC_TOOLCHAIN="$BUILD_PREFIX/targets/${HOST}"
        else
            GCC_TOOLCHAIN="$BUILD_PREFIX"
        fi
        echo "========== DEBUG: Using GCC_TOOLCHAIN=$GCC_TOOLCHAIN =========="

        # Clang-specific flags - pass via CMAKE_CXX_FLAGS, NOT CXXFLAGS
        # CXXFLAGS gets passed to NVCC which forwards to GCC, causing errors
        CLANG_CXX_FLAGS="--gcc-toolchain=$GCC_TOOLCHAIN -stdlib=libstdc++ -std=c++17 -U_LIBCPP_VERSION"

        # Keep CXXFLAGS clean - don't add Clang-specific flags here
        export CFLAGS="${CFLAGS}"

        # Use GCC as NVCC host compiler to avoid libc++ issues
        # CUDA's bundled libcu++ defines _LIBCPP_VERSION which triggers host_defines.h error
        # Using GCC as NVCC host compiler avoids this in the NVCC host compile path.
        export CUDAHOSTCXX=$BUILD_PREFIX/bin/${HOST}-g++

        # Ensure linkers are available for nvcc's host link step.
        # conda provides ${HOST}-ld, but GCC/collect2 looks for "ld".
        echo "========== DEBUG: Linker availability =========="
        echo "PATH=$PATH"
        echo "which ld: $(command -v ld || echo not found)"
        echo "which ld.lld: $(command -v ld.lld || echo not found)"
        echo "which lld: $(command -v lld || echo not found)"
        ls -la "$BUILD_PREFIX/bin/${HOST}-ld" "$BUILD_PREFIX/bin/ld" 2>/dev/null || true
        ls -la "$BUILD_PREFIX/bin/lld" "$BUILD_PREFIX/bin/ld.lld" 2>/dev/null || true
        echo ""
        if [[ -x "$BUILD_PREFIX/bin/${HOST}-ld" && ! -x "$BUILD_PREFIX/bin/ld" ]]; then
            ln -sf "$BUILD_PREFIX/bin/${HOST}-ld" "$BUILD_PREFIX/bin/ld"
        fi
        # clang.toolchain sets -fuse-ld=lld, so GCC looks for "ld.lld"
        if [[ -x "$BUILD_PREFIX/bin/lld" && ! -x "$BUILD_PREFIX/bin/ld.lld" ]]; then
            ln -sf "$BUILD_PREFIX/bin/lld" "$BUILD_PREFIX/bin/ld.lld"
        fi
        echo "========== DEBUG: Linker symlinks after setup =========="
        ls -la "$BUILD_PREFIX/bin/${HOST}-ld" "$BUILD_PREFIX/bin/ld" 2>/dev/null || true
        ls -la "$BUILD_PREFIX/bin/lld" "$BUILD_PREFIX/bin/ld.lld" 2>/dev/null || true
        echo ""

        # Force NVCC to use GCC as host compiler via -ccbin
        # Also pass -B to ensure binutils (ld) is found under BUILD_PREFIX.
        export NVCC_PREPEND_FLAGS="-ccbin=${CUDAHOSTCXX} --allow-unsupported-compiler -Xcompiler=-B$BUILD_PREFIX/bin"

        echo "========== DEBUG: Final flags =========="
        echo "CC=$CC"
        echo "CXX=$CXX"
        echo "CXXFLAGS=$CXXFLAGS"
        echo "CLANG_CXX_FLAGS=$CLANG_CXX_FLAGS"
        echo "CUDAHOSTCXX=$CUDAHOSTCXX"
        echo "NVCC_PREPEND_FLAGS=$NVCC_PREPEND_FLAGS"
        echo ""

        echo "========== DEBUG: Verify final clang config =========="
        $CXX $CLANG_CXX_FLAGS -v -E -x c++ /dev/null 2>&1 | grep -A 20 "include" || true
        echo '#include <cstddef>' | $CXX $CLANG_CXX_FLAGS -dM -E -x c++ - 2>/dev/null | grep LIBCPP || echo "  _LIBCPP_VERSION not defined with final flags"
        echo "========== END DEBUG =========="
        echo ""
    fi

    # Python configuration for CMake
    Python3_INCLUDE_DIR="$(python -c 'import sysconfig; print(sysconfig.get_path("include"))')"
    Python3_NumPy_INCLUDE_DIR="$(python -c 'import numpy;print(numpy.get_include())')"
    CMAKE_ARGS="${CMAKE_ARGS} -DPython3_EXECUTABLE:PATH=${PYTHON}"
    CMAKE_ARGS="${CMAKE_ARGS} -DPython3_INCLUDE_DIR:PATH=${Python3_INCLUDE_DIR}"
    CMAKE_ARGS="${CMAKE_ARGS} -DPython3_NumPy_INCLUDE_DIR=${Python3_NumPy_INCLUDE_DIR}"

    # Pass Clang-specific flags via CMAKE_CXX_FLAGS (not CXXFLAGS which leaks to NVCC->GCC)
    # Escape spaces to prevent splitting into separate CMake args
    if [[ -n "${CLANG_CXX_FLAGS:-}" ]]; then
        CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_CXX_FLAGS=${CLANG_CXX_FLAGS// /\\ }"
    fi

    # CUDA configuration
    if [[ "$cuda_compiler_version" != "None" ]]; then
        # Set CUDA host compiler explicitly to GCC via CMake
        CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_CUDA_HOST_COMPILER=${CUDAHOSTCXX}"

        echo "========== DEBUG: CUDA host compiler =========="
        echo "CUDAHOSTCXX=$CUDAHOSTCXX"
        ls -la $CUDAHOSTCXX || echo "  Host compiler not found!"
        echo ""

        # Remove older CUDA architectures for CUDA 12+
        if [[ "$cuda_compiler_version" != "11.8" ]]; then
            find . -name "CMakeLists*cuda.txt" -type f -print0 | xargs -0 sed -i -z -r "s/-gencode\s*=?arch=compute_35,code=sm_35//g"
        fi

        # Link with shared version of cudart library instead of static
        find . -name "CMakeLists*.txt" -type f -print0 | xargs -0 sed -i "s/-lcudart_static/-lcudart/g"
        find . -name "CMakeLists*.txt" -type f -print0 | xargs -0 sed -i "s/-lcudadevrt/-lcudart/g"
        find . -name "CMakeLists*.txt" -type f -print0 | xargs -0 sed -i "s/-lculibos/-lcudart/g"

        CMAKE_ARGS="${CMAKE_ARGS} -DHAVE_CUDA=ON"
    fi

    # Restrict CUDA compilation parallelism
    cp ci/cmake/cuda.cmake cmake/cuda.cmake

    # Build catboost
    (
        mkdir -p cmake_build
        pushd cmake_build

        mkdir -p bin
        ln -sf ${BUILD_PREFIX}/bin/{swig,ragel,yasm} bin/

        echo "========== DEBUG: Toolchain file after patching =========="
        cat ${SRC_DIR}/build/toolchains/clang.toolchain
        echo ""
        echo "========== DEBUG: CMAKE_ARGS =========="
        echo "$CMAKE_ARGS"
        echo ""
        echo "========== DEBUG: Environment before cmake =========="
        echo "CC=$CC"
        echo "CXX=$CXX"
        echo "CXXFLAGS=$CXXFLAGS"
        echo "CUDAHOSTCXX=$CUDAHOSTCXX"
        echo "NVCC_PREPEND_FLAGS=$NVCC_PREPEND_FLAGS"
        echo "which ld: $(command -v ld || echo not found)"
        echo "which ld.lld: $(command -v ld.lld || echo not found)"
        echo "which lld: $(command -v lld || echo not found)"
        echo "========================================="
        echo ""

        cmake ${CMAKE_ARGS} \
            -DCMAKE_POSITION_INDEPENDENT_CODE=On \
            -DCMAKE_TOOLCHAIN_FILE=${SRC_DIR}/build/toolchains/clang.toolchain \
            -DCMAKE_BUILD_TYPE=Release \
            -DCATBOOST_COMPONENTS="PYTHON-PACKAGE" \
            ..

        make -j${CPU_COUNT} _catboost _hnsw
        popd
    )

    # Build and install Python wheel
    cd catboost/python-package/

    export YARN_ENABLE_IMMUTABLE_INSTALLS=false
    pushd catboost/widget/js/
        yarn install
    popd

    $PYTHON setup.py bdist_wheel --with-hnsw --prebuilt-extensions-build-root-dir=${SRC_DIR}/cmake_build -vv
    $PYTHON -m pip install dist/catboost*.whl

else
    echo "Building CPU variant from PyPI wheels..."

    # install using pip from the whl files on PyPI
    if [ `uname` == Darwin ]; then
        # A workaround for renaming wheel files for osx-64
        if [ "$target_platform" == "osx-arm64" ]; then
            SDK_VER="11_0"
        elif [ "$target_platform" == "osx-64" ]; then
            SDK_VER="10_9"
        fi

        if [ "$PY_VER" == "3.8" ]; then
            WHL_FILE=catboost-${PKG_VERSION}-cp38-cp38-macosx_${SDK_VER}_universal2.whl
            curl -Lso "$WHL_FILE" https://pypi.org/packages/cp38/c/catboost/catboost-${PKG_VERSION}-cp38-cp38-macosx_11_0_universal2.whl
        elif [ "$PY_VER" == "3.9" ]; then
            WHL_FILE=catboost-${PKG_VERSION}-cp39-cp39-macosx_${SDK_VER}_universal2.whl
            curl -Lso "$WHL_FILE" https://pypi.org/packages/cp39/c/catboost/catboost-${PKG_VERSION}-cp39-cp39-macosx_11_0_universal2.whl
        elif [ "$PY_VER" == "3.10" ]; then
            WHL_FILE=catboost-${PKG_VERSION}-cp310-cp310-macosx_${SDK_VER}_universal2.whl
            curl -Lso "$WHL_FILE" https://pypi.org/packages/cp310/c/catboost/catboost-${PKG_VERSION}-cp310-cp310-macosx_11_0_universal2.whl
        elif [ "$PY_VER" == "3.11" ]; then
            WHL_FILE=catboost-${PKG_VERSION}-cp311-cp311-macosx_${SDK_VER}_universal2.whl
            curl -Lso "$WHL_FILE" https://pypi.org/packages/cp311/c/catboost/catboost-${PKG_VERSION}-cp311-cp311-macosx_11_0_universal2.whl
        elif [ "$PY_VER" == "3.12" ]; then
            WHL_FILE=catboost-${PKG_VERSION}-cp312-cp312-macosx_${SDK_VER}_universal2.whl
            curl -Lso "$WHL_FILE" https://pypi.org/packages/cp312/c/catboost/catboost-${PKG_VERSION}-cp312-cp312-macosx_11_0_universal2.whl
        elif [ "$PY_VER" == "3.13" ]; then
            WHL_FILE=catboost-${PKG_VERSION}-cp313-cp313-macosx_${SDK_VER}_universal2.whl
            curl -Lso "$WHL_FILE" https://pypi.org/packages/cp313/c/catboost/catboost-${PKG_VERSION}-cp313-cp313-macosx_11_0_universal2.whl
        fi
    fi

    echo "ARCH: $ARCH ..."

    if [ `uname` == Linux ]; then
        if [ "$target_platform" == "linux-aarch64" ]; then
            TARGET_ARCH=aarch64
        elif [ "$target_platform" == "linux-64" ]; then
            TARGET_ARCH=x86_64
        fi

        if [ "$PY_VER" == "3.8" ]; then
            WHL_FILE=https://pypi.org/packages/cp38/c/catboost/catboost-${PKG_VERSION}-cp38-cp38-manylinux2014_${TARGET_ARCH}.whl
        elif [ "$PY_VER" == "3.9" ]; then
            WHL_FILE=https://pypi.org/packages/cp39/c/catboost/catboost-${PKG_VERSION}-cp39-cp39-manylinux2014_${TARGET_ARCH}.whl
        elif [ "$PY_VER" == "3.10" ]; then
            WHL_FILE=https://pypi.org/packages/cp310/c/catboost/catboost-${PKG_VERSION}-cp310-cp310-manylinux2014_${TARGET_ARCH}.whl
        elif [ "$PY_VER" == "3.11" ]; then
            WHL_FILE=https://pypi.org/packages/cp311/c/catboost/catboost-${PKG_VERSION}-cp311-cp311-manylinux2014_${TARGET_ARCH}.whl
        elif [ "$PY_VER" == "3.12" ]; then
            WHL_FILE=https://pypi.org/packages/cp312/c/catboost/catboost-${PKG_VERSION}-cp312-cp312-manylinux2014_${TARGET_ARCH}.whl
        elif [ "$PY_VER" == "3.13" ]; then
            WHL_FILE=https://pypi.org/packages/cp313/c/catboost/catboost-${PKG_VERSION}-cp313-cp313-manylinux2014_${TARGET_ARCH}.whl
        fi
    fi

    $PYTHON -m pip install --no-deps --no-build-isolation -vvv $WHL_FILE
fi
