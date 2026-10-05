#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
build_dir="$project_dir/build"
mkdir -p "$build_dir/tmp" "$build_dir/modules" "$build_dir/cache" "$build_dir/config" "$build_dir/security"
export TMPDIR="$build_dir/tmp/"
export CLANG_MODULE_CACHE_PATH="$build_dir/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_dir/modules"
export COPYFILE_DISABLE=1
swift build --package-path "$project_dir" --disable-sandbox \
  --cache-path "$build_dir/cache" --config-path "$build_dir/config" \
  --security-path "$build_dir/security" --scratch-path "$build_dir/swift" -c release
app_dir="$build_dir/BioRA.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp -X "$build_dir/swift/release/BioRA" "$app_dir/Contents/MacOS/BioRA"
cp -X "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp -X "$project_dir/Resources/BioRAIcon.png" "$app_dir/Contents/Resources/BioRAIcon.png"
mkdir -p "$app_dir/Contents/Resources/en.lproj"
cp -X "$project_dir/Resources/en.lproj/Localizable.strings" "$app_dir/Contents/Resources/en.lproj/Localizable.strings"
icon_dir="$build_dir/LabMonitor.iconset"
mkdir -p "$icon_dir"
for icon_size in 16 32 128 256 512; do
  sips -z "$icon_size" "$icon_size" "$project_dir/Resources/BioRAIcon.png" --out "$icon_dir/icon_${icon_size}x${icon_size}.png" >/dev/null
  retina_size=$((icon_size * 2))
  sips -z "$retina_size" "$retina_size" "$project_dir/Resources/BioRAIcon.png" --out "$icon_dir/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil -c icns "$icon_dir" -o "$app_dir/Contents/Resources/BioRA.icns"
cp -X "$project_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE.txt"
# Only generated bundle metadata is disposable; source/data directories are
# never cleaned. External FAT volumes otherwise confuse code signing.
dot_clean -m "$app_dir"
codesign --force --sign - "$app_dir"
print "Built: $app_dir"
