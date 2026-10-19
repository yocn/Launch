#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
cd "${project_dir}"

swift build --product LaunchApp

bundle_dir="${project_dir}/.build/Launch.app"
contents_dir="${bundle_dir}/Contents"
macos_dir="${contents_dir}/MacOS"
mkdir -p "${macos_dir}"
cp "${project_dir}/.build/debug/LaunchApp" "${macos_dir}/LaunchApp"
cp "${project_dir}/Resources/Info.plist" "${contents_dir}/Info.plist"

echo "${bundle_dir}"
