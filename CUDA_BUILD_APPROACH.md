# CatBoost CUDA Build Approach (PR #11 — `cuda-v2` branch)

## Overview

Add CUDA 12.4 source build for Linux x86_64 to catboost 1.2.8, using conda-forge's
proven Clang-as-NVCC-host-compiler strategy. CPU variants remain unchanged (pre-built
PyPI wheels for Linux, macOS, Windows).

## Previous Attempts

| PR | Approach | Patches | Outcome |
|----|----------|---------|---------|
| #9 | GCC as NVCC host compiler | ~70 | Runtime segfault in `model.fit()` — ABI mismatch |
| #10 | Clang (C++) + GCC (NVCC host) mixed | ~80 | Runtime segfault in `model.fit()` — mixed compiler ABI |
| **#11** | **Clang for everything (conda-forge approach)** | **1** | **Current attempt** |

## Root Cause of Previous Failures

CatBoost vendors its own libc++ and builds most C++ code with Clang. When GCC is used
as the NVCC host compiler (`-ccbin=gcc`), the CUDA-compiled objects use GCC's ABI while
the rest of the codebase uses Clang's ABI. This mismatch causes segfaults at runtime —
even in CPU-only code paths — because the linked objects have incompatible vtables and
type info.

## Current Approach

**Single compiler strategy**: Clang 17 is used as both the C++ compiler and the NVCC
host compiler (`-ccbin=clang++`). This eliminates ABI mismatch entirely.

### Variant Matrix

Follows the pattern established by **llama.cpp-feedstock** and **faiss-split-feedstock**:

```
gpu_variant:           [none,   cuda-12]     # cuda-12 only on linux
cuda_compiler_version: [none,   12.4]        # zipped with gpu_variant
c_compiler_version:    [14.3.0, 11.2.0]      # GCC 11 for CUDA (cuda-nvcc requires gcc<13)
cxx_compiler_version:  [14.3.0, 11.2.0]      # zipped together
```

- **CPU variant** (`gpu_variant=none`): build number 0, GCC 14.3.0, installs PyPI wheel
- **CUDA variant** (`gpu_variant=cuda-12`): build number 100, GCC 11.2.0, builds from source
- Build number +100 ensures conda solver prefers CUDA variant when GPU is available

## CI Build Issues & Solutions

### Issue 1: `gpu_variant` undefined on macOS/Windows

**Error**: `'gpu_variant' is undefined` during CI rendering on non-Linux platforms.

**Root cause**: `gpu_variant` was defined with `# [linux]` selector, making it undefined
on macOS/Windows. Even though meta.yaml uses `(gpu_variant or "")`, the CI renderer
fails before evaluating that fallback.

**Fix**: Define `gpu_variant` for all platforms (no selector on base `none` entry).
Only the `cuda-12` entry has `# [linux]`.

### Issue 2: `gcc_linux-64=14.2.0` does not exist

**Error**: Conda solver can't find `gcc_linux-64=14.2.0`.

**Root cause**: We overrode `c_compiler_version: 14.2.0` for CPU, but this GCC version
doesn't exist in Anaconda channels. Global default is 14.3.0.

**Fix**: Use 14.3.0 (matches global pinning) for CPU variant in zip_keys.

### Issue 3: `cuda-nvcc-impl` requires GCC <13

**Error**: `cuda-nvcc-impl 12.4.131 requires gcc_impl_linux-64 >=6,<13` but CI has
GCC 14.3.0 → solver conflict.

**Root cause**: CUDA 12.4's `cuda-nvcc-impl` package constrains GCC to <13.

**Fix**: Pin `c_compiler_version: 11.2.0` and `cxx_compiler_version: 11.2.0` for the
CUDA variant via zip_keys.

**Why not CUDA 12.8?** llama.cpp and faiss use 12.8 which supports GCC 14, but
CUDA 12.8 introduces the same libc++ rejection as Issue 4 below. CUDA 12.4 avoids it
if we also apply the `-stdlib=libstdc++` workaround (Issue 4).

### Issue 4: `host_defines.h:67: "libc++ is not supported on x86 system"`

**Error**: CUDA's `crt/host_defines.h` detects libc++ and rejects it on Linux x86_64.

**Root cause**: NVIDIA dropped libc++ support on Linux starting with CUDA 12.3
([catboost/catboost#2755](https://github.com/catboost/catboost/issues/2755)). The
check in `host_defines.h` uses `__has_include(<__config>)` or similar to detect libc++.
When Clang 17 is the NVCC host compiler, it exposes libc++ in its internal include
search paths. Even though catboost uses `-nostdinc++` and its own vendored
`libcxxcuda11` (which doesn't define `_LIBCPP_VERSION`), the detection happens in
CUDA SDK headers that are force-included by NVCC before any user code.

**Why conda-forge doesn't hit this**: They use `clangxx >=15,<16` for CUDA builds.
Clang 15/16 may have different default stdlib behavior or different libc++ header
layout that doesn't trigger the detection.

**Failed approaches**:
- CUDA 12.8 (also has the check, even stricter)
- CUDA 12.4 without workaround (has the check since CUDA 12.3+)

**Fix**: Add `-Xcompiler=-stdlib=libstdc++` to `NVCC_PREPEND_FLAGS`. This tells Clang
to use libstdc++ as its default C++ standard library during CUDA host compilation.
Combined with `-nostdinc++` (which suppresses all C++ standard headers), this only
affects Clang's internal detection — `__has_include(<__config>)` returns false because
Clang looks in GCC's libstdc++ paths (which don't have `<__config>`). CatBoost's own
`libcxxcuda11` headers are still used via explicit `-I` paths.

```bash
export NVCC_PREPEND_FLAGS="-ccbin=$BUILD_PREFIX/bin/${HOST}-clang++ -Xcompiler=-stdlib=libstdc++"
```

## Key Design Decisions

1. **`gpu_variant` defined for all platforms** — not just `# [linux]`. Otherwise
   `(gpu_variant or "").startswith("cuda")` selectors in meta.yaml cause undefined
   variable errors on macOS/Windows during CI rendering.

2. **No `ANACONDA_ROCKET_ENABLE_CUDA` gate** — CI pipeline supports CUDA natively.
   CUDA variant is always built on Linux (same as llama.cpp-feedstock).

3. **GCC 11.2.0 for CUDA variant** — `cuda-nvcc-impl 12.4` requires `gcc <13`.
   CPU variant uses global default GCC 14.3.0. Both are zip_keys'd together.

4. **CUDA 12.4 + `-stdlib=libstdc++` workaround** — CUDA 12.3+ dropped libc++ on
   Linux. We work around `host_defines.h` detection by telling Clang to present
   itself as using libstdc++ during CUDA compilation. CatBoost's actual C++ code
   uses vendored `libcxxcuda11` via `-nostdinc++` + explicit includes.

5. **Windows CUDA not built from source** — PyPI Windows wheels already include CUDA
   statically linked. No benefit to source-building on Windows.

## Files

| File | Role |
|------|------|
| `recipe/conda_build_config.yaml` | CUDA variant matrix (gpu_variant, cuda_compiler_version, c/cxx_compiler_version, zip_keys) |
| `recipe/meta.yaml` | Variant selectors for deps, build number/string, missing_dso_whitelist |
| `recipe/build.sh` | CPU path: pip install PyPI wheel. CUDA path: Clang symlinks + cmake source build |
| `recipe/patches/conda.diff` | Single patch — OpenSSL from system, toolchain cleanup, libcxxcuda11 for clang <18, remove conan/cmake from setup_requires, remove missing aarch64 builtins |
| `recipe/run_test.py` | Basic smoke test: tokenizer + CatBoostRegressor fit/predict on CPU |

## The Patch (`conda.diff`)

Adapted from conda-forge with one key change: `VERSION_LESS 18` instead of
`VERSION_LESS 16` for the libcxxcuda11 threshold, because we use Clang 17 (conda-forge
uses Clang 15/16).

What it patches:
- **CMakeLists.txt**: Use system OpenSSL instead of conan-provided
- **build/toolchains/clang.toolchain**: Remove hardcoded compiler paths, let conda env handle it
- **catboost/python-package/setup.py + pyproject.toml**: Remove cmake/conan from build requires
- **contrib/libs/cxxsupp/CMakeLists.\*.txt**: Use `libcxxcuda11` (CUDA-compatible libc++) for clang <18
- **contrib/libs/cxxsupp/builtins/CMakeLists.linux-aarch64\*.txt**: Remove bfloat16/SME builtins that don't exist in clang 17

## Build Flow (CUDA variant)

```
build.sh
├── Create Clang symlinks in $BUILD_PREFIX/bin
├── Set CC/CXX to ${HOST}-clang / ${HOST}-clang++
├── Set NVCC_PREPEND_FLAGS="-ccbin=clang++ -Xcompiler=-stdlib=libstdc++"
├── Configure CMake with -DHAVE_CUDA=ON, clang.toolchain
├── Replace -lcudart_static with -lcudart (shared linking)
├── make -j${CPU_COUNT} _catboost _hnsw
└── python setup.py bdist_wheel --prebuilt-extensions-build-root-dir=...
```

## CUDA Version Compatibility Matrix

| CUDA | GCC 14 | libc++ on x86 | Status |
|------|--------|---------------|--------|
| 12.0-12.2 | No (gcc <12) | Supported | conda-forge uses 12.0 |
| 12.3-12.5 | No (gcc <13) | **Rejected** in host_defines.h | Need `-stdlib=libstdc++` workaround |
| 12.6+ | Yes | **Rejected** in host_defines.h | Need `-stdlib=libstdc++` workaround |

We use **CUDA 12.4 + GCC 11.2.0 + `-stdlib=libstdc++`** because:
- 12.4 is the lowest version available on Anaconda CI
- GCC 11.2.0 satisfies `cuda-nvcc-impl`'s `gcc <13` constraint
- `-stdlib=libstdc++` bypasses the libc++ detection in host_defines.h

## Reference Feedstocks

- **llama.cpp-feedstock**: Primary reference for variant config pattern, build number strategy
- **faiss-split-feedstock**: Reference for `cuda_compiler_version != "None"` selector style
- **conda-forge/catboost-feedstock**: Uses Clang 15 + CUDA 12.0 (avoids both GCC and libc++ issues)
