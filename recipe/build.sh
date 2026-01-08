#!/bin/bash

set -xe

# Check if this is a CUDA build or CPU build
if [[ "${gpu_variant}" == cuda* ]]; then
    echo "Building CUDA variant from source..."

    # Debug: Show patched CMakeLists files to verify patches applied correctly
    echo "=== DEBUG: Verifying patches applied correctly ==="
    echo "--- contrib/libs/cxxsupp/CMakeLists.linux-x86_64-cuda.txt ---"
    if [[ -f "contrib/libs/cxxsupp/CMakeLists.linux-x86_64-cuda.txt" ]]; then
        cat contrib/libs/cxxsupp/CMakeLists.linux-x86_64-cuda.txt
    else
        echo "WARNING: File not found!"
    fi
    echo "--- End of CMakeLists.linux-x86_64-cuda.txt ---"
    echo ""

    if [[ "$target_platform" == "linux-"* ]]; then
        # Use GCC for CUDA host compilation
        export NVCC_PREPEND_FLAGS="-ccbin=${GCC}"
    fi

    # Python configuration for CMake
    Python3_INCLUDE_DIR="$(python -c 'import sysconfig; print(sysconfig.get_path("include"))')"
    Python3_NumPy_INCLUDE_DIR="$(python -c 'import numpy;print(numpy.get_include())')"
    CMAKE_ARGS="${CMAKE_ARGS} -DPython3_EXECUTABLE:PATH=${PYTHON}"
    CMAKE_ARGS="${CMAKE_ARGS} -DPython3_INCLUDE_DIR:PATH=${Python3_INCLUDE_DIR}"
    CMAKE_ARGS="${CMAKE_ARGS} -DPython3_NumPy_INCLUDE_DIR=${Python3_NumPy_INCLUDE_DIR}"

    echo "=== Initial Environment Flags ==="
    echo "CFLAGS=$CFLAGS"
    echo "CXXFLAGS=$CXXFLAGS"
    echo "CPPFLAGS=$CPPFLAGS"
    echo "LDFLAGS=$LDFLAGS"
    echo "================================="

    # CUDA configuration
    if [[ "$cuda_compiler_version" != "None" ]]; then
        # Remove older CUDA architectures if not using CUDA 11.8
        if [[ "$cuda_compiler_version" != "11.8" ]]; then
            find . -name "CMakeLists*cuda.txt" -type f -print0 | xargs -0 sed -i -z -r "s/-gencode\s*=?arch=compute_35,code=sm_35//g"
        fi

        # Link with shared version of cudart library instead of static
        # cudadevrt and culibos are dependencies of libcudart_static.a
        # When using libcudart.so, it has all the symbols, so replace all three
        find . -name "CMakeLists*.txt" -type f -print0 | xargs -0 sed -i "s/-lcudart_static/-lcudart/g"
        find . -name "CMakeLists*.txt" -type f -print0 | xargs -0 sed -i "s/-lcudadevrt/-lcudart/g"
        find . -name "CMakeLists*.txt" -type f -print0 | xargs -0 sed -i "s/-lculibos/-lcudart/g"

        CMAKE_ARGS="${CMAKE_ARGS} -DHAVE_CUDA=ON"
    fi

    # Restrict CUDA compilation parallelism
    cp ci/cmake/cuda.cmake cmake/cuda.cmake

    # Filter out flags that might be present in conda's activation scripts but are harmful to GCC/NVCC
    # -fuse-init-array: Clang specific (mostly)
    # -fdebug-default-version: Clang specific
    # -fcolor-diagnostics: Clang specific
    # -Wimport-preprocessor-directive-pedantic: Clang specific
    # -faligned-allocation: C++17 feature that might conflict or be implicit
    for flag in "-fuse-init-array" "-fdebug-default-version=[0-9]*" "-fcolor-diagnostics" "-Wimport-preprocessor-directive-pedantic" "-faligned-allocation"; do
        export CFLAGS=$(echo "$CFLAGS" | sed "s/$flag//g")
        export CXXFLAGS=$(echo "$CXXFLAGS" | sed "s/$flag//g")
        export CPPFLAGS=$(echo "$CPPFLAGS" | sed "s/$flag//g")
        export DEBUG_CFLAGS=$(echo "$DEBUG_CFLAGS" | sed "s/$flag//g")
        export DEBUG_CXXFLAGS=$(echo "$DEBUG_CXXFLAGS" | sed "s/$flag//g")
    done
    
    # Disable linker garbage collection to preserve LAPACK symbols like ilaslc_
    # These symbols are called indirectly by other LAPACK functions but not directly by catboost
    # Remove --gc-sections from LDFLAGS as it strips needed LAPACK symbols
    # Also remove --as-needed which can prevent transitive LAPACK dependencies from being linked
    export LDFLAGS=$(echo "$LDFLAGS" | sed 's/-Wl,--gc-sections//g' | sed 's/-Wl,--as-needed//g')

    echo "=== Processed Environment Flags ==="
    echo "CFLAGS=$CFLAGS"
    echo "CXXFLAGS=$CXXFLAGS"
    echo "CPPFLAGS=$CPPFLAGS"
    echo "LDFLAGS=$LDFLAGS"
    echo "==================================="

    # recursively remove clang-specific flags from all CMakeLists.txt and .cmake files
    # This is necessary because CatBoost's internal build system (ya make -> cmake)
    # seems to hardcode these flags for Linux x86_64, assuming Clang.
    echo "Removing Clang-specific flags from CMake files..."
    find . -type f \( -name "CMakeLists.txt" -o -name "*.cmake" -o -name "*.toolchain" \) -print0 | xargs -0 sed -i \
        -e 's/-fcolor-diagnostics//g' \
        -e 's/-faligned-allocation//g' \
        -e 's/-fdebug-default-version=4//g' \
        -e 's/-fuse-init-array//g' \
        -e 's/-Wimport-preprocessor-directive-pedantic//g' \
        -e 's/-Wl,--gc-sections//g' \
        -e 's/-Wl,--as-needed//g'

    # Disable vendored libc++ for CUDA builds on Linux (since we removed the patch)
    if [[ "$target_platform" == "linux-"* ]]; then
        echo "Disabling vendored libc++ in CMakeLists.linux-x86_64-cuda.txt..."
        sed -i 's/add_subdirectory(libcxxcuda11)/# add_subdirectory(libcxxcuda11)/g' contrib/libs/cxxsupp/CMakeLists.linux-x86_64-cuda.txt
        sed -i 's/add_subdirectory(libcxxabi-parts)/# add_subdirectory(libcxxabi-parts)/g' contrib/libs/cxxsupp/CMakeLists.linux-x86_64-cuda.txt
        sed -i 's/add_subdirectory(libcxxrt)/# add_subdirectory(libcxxrt)/g' contrib/libs/cxxsupp/CMakeLists.linux-x86_64-cuda.txt
        sed -i 's/add_subdirectory(builtins)/# add_subdirectory(builtins)/g' contrib/libs/cxxsupp/CMakeLists.linux-x86_64-cuda.txt
        sed -i 's/libs-cxxsupp-libcxxcuda11//g' contrib/libs/cxxsupp/CMakeLists.linux-x86_64-cuda.txt
    fi

    # Build catboost
    (
        mkdir -p cmake_build
        pushd cmake_build

        mkdir -p bin
        ln -sf ${BUILD_PREFIX}/bin/{swig,ragel,yasm} bin/

        cmake ${CMAKE_ARGS} \
            -DCMAKE_POSITION_INDEPENDENT_CODE=On \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_CUDA_HOST_COMPILER=${GCC} \
            -DCMAKE_CUDA_FLAGS="-O2 -fPIC" \
            -DCMAKE_C_FLAGS="${CFLAGS}" \
            -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
            -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS} -llapack -lblas" \
            -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS} -llapack -lblas" \
            -DTHREADS_PREFER_PTHREAD_FLAG=ON \
            -DCMAKE_THREAD_LIBS_INIT="-lpthread" \
            -DCMAKE_USE_PTHREADS_INIT=ON \
            -DCMAKE_VERBOSE_MAKEFILE=ON \
            -DCATBOOST_COMPONENTS="PYTHON-PACKAGE" \
            ..

        echo "=== CMake Cache Flags ==="
        grep "_FLAGS" CMakeCache.txt || true
        echo "========================="

        make -j${CPU_COUNT} VERBOSE=1 _catboost _hnsw
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
        # A workaround for renaming wheel files for osx-64 because the maintainers provides wheels only for MacOS SDK 11.0
        # but if we replace it with 10.9, it will work on older versions of MacOS without issues.
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
