#!/bin/zsh
set -euo pipefail

# 仅在用户明确同意后运行；拒绝覆盖任何已有目标。
project_dir=${0:A:h:h}
fixture_app="${HOME}/Applications/LaunchCleanupFixture.app"
fixture_cache="${HOME}/Library/Caches/dev.yocn.launch.cleanupfixture"
fixture_logs="${HOME}/Library/Logs/dev.yocn.launch.cleanupfixture"
fixture_support="${HOME}/Library/Application Support/LaunchCleanupFixture"
for destination in "${fixture_app}" "${fixture_cache}" "${fixture_logs}" "${fixture_support}"; do
    if [[ -e "${destination}" || -L "${destination}" ]]; then
        echo "拒绝覆盖已有目标：${destination}" >&2
        exit 1
    fi
done
if [[ -z "${LAUNCH_FIXTURE_SIGN_IDENTITY:-}" ]]; then
    echo "请指定 LAUNCH_FIXTURE_SIGN_IDENTITY（Apple Development 证书）" >&2
    exit 1
fi
fixture_staging=$(mktemp -d /tmp/launch-cleanup-fixture.XXXXXX)
mkdir -p "${fixture_staging}/LaunchCleanupFixture.app/Contents/MacOS"
swiftc -parse-as-library "${project_dir}/scripts/fixtures/CleanupFixture.swift" -o "${fixture_staging}/LaunchCleanupFixture.app/Contents/MacOS/CleanupFixture"
cp "${project_dir}/scripts/fixtures/CleanupFixture-Info.plist" "${fixture_staging}/LaunchCleanupFixture.app/Contents/Info.plist"
codesign --sign "${LAUNCH_FIXTURE_SIGN_IDENTITY}" "${fixture_staging}/LaunchCleanupFixture.app"
mkdir -p "${HOME}/Applications"
ditto "${fixture_staging}/LaunchCleanupFixture.app" "${fixture_app}"
for destination in "${fixture_cache}" "${fixture_logs}" "${fixture_support}"; do
    mkdir "${destination}"
    cp "${project_dir}/scripts/fixtures/cleanup-fixture.txt" "${destination}/fixture.txt"
done
echo "已创建：${fixture_app}"
echo "测试残留：${fixture_cache}、${fixture_logs}、${fixture_support}"
echo "构建中间件保留于：${fixture_staging}"
