@echo off
setlocal EnableDelayedExpansion

REM Check if this is a CUDA build or CPU build
if "%gpu_variant:~0,5%"=="cuda-" (
    echo Building CUDA variant from source...
    goto :cuda_build
) else (
    echo Building CPU variant from PyPI wheels...
    goto :cpu_build
)

:cuda_build
REM CUDA source build for Windows
REM CatBoost CUDA build requires: cmake, ninja, CUDA toolkit

REM Python configuration for CMake
for /f "delims=" %%i in ('%PYTHON% -c "import sysconfig; print(sysconfig.get_path('include'))"') do set Python3_INCLUDE_DIR=%%i
for /f "delims=" %%i in ('%PYTHON% -c "import numpy;print(numpy.get_include())"') do set Python3_NumPy_INCLUDE_DIR=%%i

set CMAKE_ARGS=%CMAKE_ARGS% -DPython3_EXECUTABLE:PATH=%PYTHON%
set CMAKE_ARGS=%CMAKE_ARGS% -DPython3_INCLUDE_DIR:PATH=%Python3_INCLUDE_DIR%
set CMAKE_ARGS=%CMAKE_ARGS% -DPython3_NumPy_INCLUDE_DIR=%Python3_NumPy_INCLUDE_DIR%

REM CUDA configuration
set CMAKE_ARGS=%CMAKE_ARGS% -DHAVE_CUDA=ON
set CMAKE_ARGS=%CMAKE_ARGS% -DCMAKE_CUDA_ARCHITECTURES=all-major

REM Link with shared version of cudart library instead of static
REM This is done automatically by CMake on Windows

REM Copy CUDA cmake file
copy ci\cmake\cuda.cmake cmake\cuda.cmake
if errorlevel 1 exit 1

REM Create build directory
mkdir cmake_build
if errorlevel 1 exit 1
cd cmake_build

REM Create bin directory and copy tools
mkdir bin
if errorlevel 1 exit 1
copy %BUILD_PREFIX%\Library\bin\swig.exe bin\ 2>nul
copy %BUILD_PREFIX%\Library\bin\ragel.exe bin\ 2>nul
copy %BUILD_PREFIX%\Library\bin\yasm.exe bin\ 2>nul

REM Run CMake
cmake -G Ninja ^
    %CMAKE_ARGS% ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ^
    -DCATBOOST_COMPONENTS="PYTHON-PACKAGE" ^
    ..
if errorlevel 1 exit 1

REM Build
cmake --build . --config Release --parallel %CPU_COUNT% --target _catboost _hnsw
if errorlevel 1 exit 1

cd ..

REM Build and install Python wheel
cd catboost\python-package

REM Build widget JS
set YARN_ENABLE_IMMUTABLE_INSTALLS=false
cd catboost\widget\js
call yarn install
if errorlevel 1 exit 1
cd ..\..\..

REM Build wheel
%PYTHON% setup.py bdist_wheel --with-hnsw --prebuilt-extensions-build-root-dir=%SRC_DIR%\cmake_build
if errorlevel 1 exit 1

REM Install wheel
for %%f in (dist\catboost*.whl) do (
    %PYTHON% -m pip install --no-deps --no-build-isolation %%f
    if errorlevel 1 exit 1
)

goto :end

:cpu_build
REM CPU builds use PyPI wheels

IF "%PY_VER%"=="3.8" (
	%PYTHON% -m pip install --no-deps --no-build-isolation https://pypi.org/packages/cp38/c/catboost/catboost-%PKG_VERSION%-cp38-cp38-win_amd64.whl
)

IF "%PY_VER%"=="3.9" (
	%PYTHON% -m pip install --no-deps --no-build-isolation https://pypi.org/packages/cp39/c/catboost/catboost-%PKG_VERSION%-cp39-cp39-win_amd64.whl
)

IF "%PY_VER%"=="3.10" (
	%PYTHON% -m pip install --no-deps --no-build-isolation https://pypi.org/packages/cp310/c/catboost/catboost-%PKG_VERSION%-cp310-cp310-win_amd64.whl
)

IF "%PY_VER%"=="3.11" (
	%PYTHON% -m pip install --no-deps --no-build-isolation https://pypi.org/packages/cp311/c/catboost/catboost-%PKG_VERSION%-cp311-cp311-win_amd64.whl
)

IF "%PY_VER%"=="3.12" (
	%PYTHON% -m pip install --no-deps --no-build-isolation https://pypi.org/packages/cp312/c/catboost/catboost-%PKG_VERSION%-cp312-cp312-win_amd64.whl
)

IF "%PY_VER%"=="3.13" (
	%PYTHON% -m pip install --no-deps --no-build-isolation https://pypi.org/packages/cp313/c/catboost/catboost-%PKG_VERSION%-cp313-cp313-win_amd64.whl
)

if errorlevel 1 exit 1

:end
echo Build completed successfully
