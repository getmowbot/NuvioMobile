#!/usr/bin/env bash
# Checks that an IPA carries the AetherEngine player correctly:
#   * NuvioAetherKit.framework and AetherEngine's FFmpeg frameworks are embedded,
#   * NuvioAetherKit binds avcodec_* to AetherLibavcodec, not to the static FFmpeg MPVKit
#     links into the app executable (AetherEngine docs/api.md, "One FFmpeg, and it has to be
#     the engine's").
# Usage: aether/scripts/verify-ipa.sh path/to/Nuvio.ipa   (macOS)

set -euo pipefail

ipa_path="${1:?Usage: verify-ipa.sh path/to/app.ipa}"
work_directory="$(mktemp -d "${TMPDIR:-/tmp}/nuvio-aether-verify.XXXXXX")"
trap 'rm -rf "${work_directory}"' EXIT

unzip -q "${ipa_path}" -d "${work_directory}"
app_path="$(find "${work_directory}/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
if [[ -z "${app_path}" ]]; then
    echo "No .app in ${ipa_path}." >&2
    exit 1
fi
frameworks="${app_path}/Frameworks"

status=0
for framework in NuvioAetherKit AetherLibavcodec AetherLibavformat AetherLibavutil AetherLibswresample; do
    if [[ -d "${frameworks}/${framework}.framework" ]]; then
        echo "ok: ${framework}.framework embedded"
    else
        echo "error: ${framework}.framework is missing from ${frameworks}" >&2
        status=1
    fi
done

kit_binary="${frameworks}/NuvioAetherKit.framework/NuvioAetherKit"
if [[ -f "${kit_binary}" ]]; then
    binding="$(xcrun nm -m "${kit_binary}" | grep -E ' _avcodec_open2( |$)' || true)"
    if [[ "${binding}" == *"(from AetherLibavcodec)"* ]]; then
        echo "ok: NuvioAetherKit binds avcodec to AetherLibavcodec"
    else
        echo "error: NuvioAetherKit does not bind avcodec_open2 to AetherLibavcodec:" >&2
        echo "  ${binding:-<symbol not found>}" >&2
        status=1
    fi
    xcrun otool -L "${kit_binary}" | grep -E 'Aether|NuvioAetherKit' || true
fi

executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${app_path}/Info.plist")"
if xcrun nm -m "${app_path}/${executable}" | grep -E ' _avcodec_open2 .*\(from AetherLibavcodec\)' >/dev/null; then
    echo "error: the app executable links AetherEngine's FFmpeg directly; AetherEngine must only be linked into NuvioAetherKit." >&2
    status=1
fi

minimum_os="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "${app_path}/Info.plist")"
echo "MinimumOSVersion: ${minimum_os}"

exit "${status}"
