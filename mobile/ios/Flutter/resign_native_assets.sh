#!/bin/sh

set -e

APP_FRAMEWORKS_DIR="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Frameworks"
OBJECTIVE_C_FRAMEWORK="${APP_FRAMEWORKS_DIR}/objective_c.framework"

if [ ! -d "${OBJECTIVE_C_FRAMEWORK}" ]; then
  exit 0
fi

if [ -z "${EXPANDED_CODE_SIGN_IDENTITY}" ] || [ "${CODE_SIGNING_ALLOWED}" = "NO" ]; then
  exit 0
fi

echo "Re-signing native asset: ${OBJECTIVE_C_FRAMEWORK}"
/usr/bin/codesign \
  --force \
  --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
  ${OTHER_CODE_SIGN_FLAGS:-} \
  --preserve-metadata=identifier,entitlements \
  "${OBJECTIVE_C_FRAMEWORK}"