#!/bin/bash
# Xcode phase AFTER resource copy, BEFORE framework signing. SDK digest checked by prepare step.
set -euo pipefail
: "${PROJECT_DIR:?}" "${CODESIGNING_FOLDER_PATH:?}" "${ARCHS:?}" "${EFFECTIVE_PLATFORM_NAME:?}"
case "$ARCHS" in arm64|x86_64) ;; *) echo 'Python SDK installation requires one selected architecture per build' >&2; exit 1;; esac
SDK=Vendors/Python/Python.xcframework
# SideStore build is unsigned at archive stage. Extension frameworks receive ad-hoc
# signatures here and must ALL be re-signed by the distribution/install process.
export EXPANDED_CODE_SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
export EXPANDED_CODE_SIGN_IDENTITY_NAME="${EXPANDED_CODE_SIGN_IDENTITY_NAME:-Ad Hoc}"
export PLATFORM_FAMILY_NAME=iOS
source "$PROJECT_DIR/$SDK/build/utils.sh"
# Pin the directory instead of upstream's grep-based version autodetection.
install_stdlib "$SDK"
[[ -d "$CODESIGNING_FOLDER_PATH/python/lib/python3.13/lib-dynload" ]] || { echo 'Pinned stdlib missing' >&2; exit 1; }
process_dylibs "$SDK" python/lib/python3.13/lib-dynload
process_dylibs "$SDK" app_packages
# Runtime resources never retain bytecode caches or stdlib test fixtures.
# CPython test-only WAV/AIFF fixtures are not production dependencies.
rm -rf "$CODESIGNING_FOLDER_PATH/python/lib/python3.13/test"
find "$CODESIGNING_FOLDER_PATH/python" "$CODESIGNING_FOLDER_PATH/app_packages" -type d -name __pycache__ -prune -exec rm -rf {} +
find "$CODESIGNING_FOLDER_PATH/python" "$CODESIGNING_FOLDER_PATH/app_packages" -name '*.pyc' -delete
# Fail closed if packaging failed to relocate a Python extension binary.
if find "$CODESIGNING_FOLDER_PATH/python" "$CODESIGNING_FOLDER_PATH/app_packages" -name '*.so' -print -quit | grep -q .; then
  echo 'Unrelocated Python extension library in app resources' >&2; exit 1
fi
