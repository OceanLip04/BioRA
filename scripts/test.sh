#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
build_dir="$project_dir/build"
mkdir -p "$build_dir/tmp" "$build_dir/modules" "$build_dir/cache" "$build_dir/config" "$build_dir/security"
export TMPDIR="$build_dir/tmp/"
export CLANG_MODULE_CACHE_PATH="$build_dir/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_dir/modules"
swift test --package-path "$project_dir" --disable-sandbox --cache-path "$build_dir/cache" --config-path "$build_dir/config" --security-path "$build_dir/security" --scratch-path "$build_dir/swift"
