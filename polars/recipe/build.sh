# This recipe has been adopted from https://github.com/conda-forge/polars-feedstock

#!/usr/bin/env bash

set -ex

case "${target_platform}" in
  linux-aarch64|osx-arm64|linux-ppc64le)
    arch="aarch64"
    ;;
  *)
    arch="x86_64"
    ;;
esac

if [[ "$target_platform" == "linux-ppc64le" ]]; then
  CFLAGS="$(echo $CFLAGS | sed 's/-fno-plt //g')"
  CXXFLAGS="$(echo $CXXFLAGS | sed 's/-fno-plt //g')"
  LDFLAGS="$(echo $LDFLAGS | sed 's/-fno-plt //g')"
fi

cpu_check_module="py-polars/polars/_cpu_check.py"
features=""

if [[ ${arch} == "x86_64" ]]; then
  features=+sse3,+ssse3,+sse4.1,+sse4.2,+popcnt,+avx,+avx2,+fma,+bmi1,+bmi2,+lzcnt,+pclmulqdq
  export RUSTFLAGS="-C target-feature=$features"
fi

sed -i.bak "s/^_POLARS_ARCH = \"unknown\"$/_POLARS_ARCH = \"$arch\"/g" $cpu_check_module
sed -i.bak "s/^_POLARS_FEATURE_FLAGS = \"\"$/_POLARS_FEATURE_FLAGS = \"$features\"/g" $cpu_check_module

# Use jemalloc on linux-aarch64
if [[ "${target_platform}" == "linux-aarch64" ]]; then
  export JEMALLOC_SYS_WITH_LG_PAGE=16
fi

rustc --version

if [[ ("${target_platform}" == "win-64" && "${build_platform}" == "linux-64") ]]; then
  # we need to add the generate-import-lib feature since otherwise
  # maturin will expect libpython DSOs at PYO3_CROSS_LIB_DIR
  # which we don't have since we are not able to add python as a host dependency
  cargo feature pyo3 +generate-import-lib --manifest-path py-polars/Cargo.toml

  # cc-rs hardcodes ml64.exe as the MASM assembler for x86_64-pc-windows-msvc
  # We want to use LLVM's MASM assembler instead
  # https://github.com/rust-lang/cc-rs/issues/1022
  cat > $BUILD_PREFIX/bin/ml64.exe <<"EOF"
#!/usr/bin/env bash
llvm-ml -m64 $@
EOF

  chmod +x $BUILD_PREFIX/bin/ml64.exe

  maturin build --release --strip
  pip install target/wheels/polars*.whl --target $PREFIX/lib/site-packages --platform win_amd64
else
  # Run the maturin build via pip which works for direct and
  # cross-compiled builds.
  $PYTHON -m pip install . -vv
fi

# The root level Cargo.toml is part of an incomplete workspace
# we need to use the manifest inside the py-polars
cd py-polars
cargo-bundle-licenses --format yaml --output ../THIRDPARTY.yml
