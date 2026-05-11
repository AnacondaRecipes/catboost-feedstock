REM Repack the upstream PyPI catboost wheel.
REM Compute the wheel filename from PY_VER (e.g. 3.14 -> cp314) so we
REM automatically pick up any new Python that catboost upstream ships a wheel
REM for, instead of maintaining a brittle IF chain that fails silently when a
REM new Python version drops through.
set "PY_TAG=cp%PY_VER:.=%"

%PYTHON% -m pip install --no-deps --no-build-isolation https://pypi.org/packages/%PY_TAG%/c/catboost/catboost-%PKG_VERSION%-%PY_TAG%-%PY_TAG%-win_amd64.whl
if errorlevel 1 exit 1
