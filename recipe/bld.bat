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

if errorlevel 1 exit 1
