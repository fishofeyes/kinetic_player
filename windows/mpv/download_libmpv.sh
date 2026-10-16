#!/usr/bin/env bash
# Download prebuilt libmpv-2.dll for Windows (see windows/mpv/manifest.json).
# Usage: bash windows/mpv/download_libmpv.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR="${SCRIPT_DIR}/vendor"
MANIFEST="${SCRIPT_DIR}/manifest.json"
mkdir -p "${VENDOR}"

if [[ -f "${VENDOR}/libmpv-2.dll" ]]; then
  echo "libmpv-2.dll already present."
  exit 0
fi

URL="${KINETIC_PLAYER_LIBMPV_URL:-}"
if [[ -z "${URL}" && -f "${MANIFEST}" ]]; then
  URL="$(python3 -c "import json; print(json.load(open('${MANIFEST}'))['download_url'])" 2>/dev/null || true)"
fi
if [[ -z "${URL}" ]]; then
  URL="https://github.com/zhongfly/mpv-winbuild/releases/download/2026-10-15-a2cd83c56d/mpv-dev-lgpl-x86_64-20261015-git-a2cd83c56d.7z"
fi

TMP="$(mktemp -d)"
ARCHIVE="${TMP}/libmpv.7z"
echo "Downloading ${URL}"
curl -fL --retry 5 -o "${ARCHIVE}" "${URL}"
if command -v 7z >/dev/null; then
  7z x "${ARCHIVE}" -o"${TMP}/out" -y >/dev/null
elif command -v 7za >/dev/null; then
  7za x "${ARCHIVE}" -o"${TMP}/out" -y >/dev/null
else
  echo "Need 7z to extract. Place libmpv-2.dll in ${VENDOR}/ instead."
  exit 1
fi
DLL="$(find "${TMP}/out" -name 'libmpv-2.dll' | head -n 1)"
if [[ -z "${DLL}" ]]; then
  echo "libmpv-2.dll not found in archive."
  exit 1
fi
cp "${DLL}" "${VENDOR}/libmpv-2.dll"
echo "Installed ${VENDOR}/libmpv-2.dll"
rm -rf "${TMP}"
