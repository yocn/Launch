#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
cd "${project_dir}"

install=false
configuration=debug
if [[ "${1:-}" == "--install" ]]; then
    install=true
    configuration=release
fi

swift build -c "${configuration}" --product LaunchApp
bin_dir=$(swift build -c "${configuration}" --show-bin-path)

bundle_dir="${project_dir}/.build/Launch.app"
contents_dir="${bundle_dir}/Contents"
rm -rf "${bundle_dir}"
mkdir -p "${contents_dir}/MacOS" "${contents_dir}/Resources"
cp "${bin_dir}/LaunchApp" "${contents_dir}/MacOS/LaunchApp"
cp "${project_dir}/Resources/Info.plist" "${contents_dir}/Info.plist"
# KeyboardShortcuts 的 Bundle.module 从 Contents/Resources 加载，缺失时直接 fatalError
cp -R "${bin_dir}/KeyboardShortcuts_KeyboardShortcuts.bundle" "${contents_dir}/Resources/"
cp -R "${bin_dir}/Launch_LaunchApp.bundle" "${contents_dir}/Resources/"

# 生成标准 macOS 多尺寸图标；透明边缘保留，默认安装图标为浅色九宫格。
iconset_dir="${project_dir}/.build/LaunchAppIcon.iconset"
mkdir -p "${iconset_dir}"
icon_master="${project_dir}/Sources/LaunchApp/AppIcons/grid-light.png"
for side in 16 32 128 256 512; do
    sips -z "${side}" "${side}" "${icon_master}" --out "${iconset_dir}/icon_${side}x${side}.png" >/dev/null
    double_side=$((side * 2))
    sips -z "${double_side}" "${double_side}" "${icon_master}" --out "${iconset_dir}/icon_${side}x${side}@2x.png" >/dev/null
done
iconutil -c icns "${iconset_dir}" -o "${contents_dir}/Resources/AppIcon.icns"

if [[ "${install}" != true ]]; then
    echo "${bundle_dir}"
    exit 0
fi

codesign --force --sign "${LAUNCH_SIGN_IDENTITY:--}" "${bundle_dir}"

if pgrep -x LaunchApp >/dev/null; then
    pkill -x LaunchApp
    for _ in {1..50}; do
        pgrep -x LaunchApp >/dev/null || break
        sleep 0.2
    done
    if pgrep -x LaunchApp >/dev/null; then
        echo "Launch 仍在运行，请手动退出后重试" >&2
        exit 1
    fi
fi

install_dir="${HOME}/Applications"
target_dir="${install_dir}/Launch.app"
staging_dir="${install_dir}/.Launch.app.installing"
mkdir -p "${install_dir}"
rm -rf "${staging_dir}"
ditto "${bundle_dir}" "${staging_dir}"
rm -rf "${target_dir}"
mv "${staging_dir}" "${target_dir}"
open "${target_dir}"
echo "${target_dir}"
