#!/bin/bash

set -xe

# install using pip from the whl files on PyPI

if [ `uname` == Darwin ]; then  
    # A workaround for renaming wheel files for osx-64 because the maintainers provides wheels only for MacOS SDK 11.0
    # but if we replace it with 10.9, it will work on older versions of MacOS without issues.
    # In our case, it looks like catboost 1.2 only links against libSystem.B using LC_LOAD_DYLIB, which is standard. 
    # A list of imported symbols tells us that it's not importing anything that wouldn't be found on a standard system 
    # that's older than OS 11.0. So it certainly looks like this'd work on our systems too.
    # If you look at the commit history of the file https://github.com/catboost/catboost/blob/master/catboost/app/CMakeLists.darwin-x86_64.txt#LL48C32-L48C35, 
    # it looks like they were originally targeting 10.15 SDK and OS versions. At some point they chose to target a different SDK (11), 
    # but they also chose a newer deployment_target (OS version 11).
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
    fi
fi

$PYTHON -m pip install --no-deps --no-build-isolation -vvv $WHL_FILE
