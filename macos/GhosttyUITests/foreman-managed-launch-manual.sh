#!/usr/bin/env bash

set -euo pipefail

readonly MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly APP_BUNDLE="${MACOS_DIR}/build/Debug/Foreman.app"
readonly APP_EXEC="${APP_BUNDLE}/Contents/MacOS/ghostty"
readonly DEFAULTS_SUITE="${GHOSTTY_USER_DEFAULTS_SUITE:-GHOSTTY_UI_TESTS_FOREMAN_MANAGED_LAUNCH}"
readonly CONFIG_PATH="${TMPDIR:-/tmp}/foreman-managed-launch-manual.ghostty"
readonly FORCE_AGENT_READINESS="${GHOSTTY_FOREMAN_TEST_FORCE_AGENT_READINESS:-installed}"
readonly CAPTURE_MANAGED_LAUNCH="${GHOSTTY_FOREMAN_TEST_CAPTURE_MANAGED_LAUNCH:-1}"
readonly START_VISIBLE="${GHOSTTY_FOREMAN_TEST_START_VISIBLE:-1}"

if [[ ! -x "${APP_EXEC}" ]]; then
  echo "Missing built app executable: ${APP_EXEC}" >&2
  echo "Build it first with: ${MACOS_DIR}/build.nu --scheme Ghostty --configuration Debug --action build" >&2
  exit 1
fi

cat >"${CONFIG_PATH}" <<'EOF'
window-position-x = 50
window-position-y = 50
window-width = 70
window-height = 24
title = "ForemanManagedLaunchManual"
EOF

defaults delete "${DEFAULTS_SUITE}" >/dev/null 2>&1 || true

while IFS= read -r pid; do
  kill "${pid}" >/dev/null 2>&1 || true
done < <(pgrep -f "${APP_EXEC}" || true)

launchctl setenv GHOSTTY_CONFIG_PATH "${CONFIG_PATH}"
launchctl setenv GHOSTTY_USER_DEFAULTS_SUITE "${DEFAULTS_SUITE}"
launchctl setenv GHOSTTY_CLEAR_USER_DEFAULTS YES
launchctl setenv GHOSTTY_FOREMAN_TEST_FORCE_AGENT_READINESS "${FORCE_AGENT_READINESS}"
launchctl setenv GHOSTTY_FOREMAN_TEST_CAPTURE_MANAGED_LAUNCH "${CAPTURE_MANAGED_LAUNCH}"
launchctl setenv GHOSTTY_FOREMAN_TEST_START_VISIBLE "${START_VISIBLE}"

open -na "${APP_BUNDLE}"
sleep 2

launchctl unsetenv GHOSTTY_CONFIG_PATH
launchctl unsetenv GHOSTTY_USER_DEFAULTS_SUITE
launchctl unsetenv GHOSTTY_CLEAR_USER_DEFAULTS
launchctl unsetenv GHOSTTY_FOREMAN_TEST_FORCE_AGENT_READINESS
launchctl unsetenv GHOSTTY_FOREMAN_TEST_CAPTURE_MANAGED_LAUNCH
launchctl unsetenv GHOSTTY_FOREMAN_TEST_START_VISIBLE

readonly APP_PID="$(pgrep -f "${APP_EXEC}" | tail -n 1)"

if [[ -z "${APP_PID}" ]]; then
  echo "Failed to find a running Foreman debug process for ${APP_BUNDLE}" >&2
  exit 1
fi

cat <<EOF
Launched Foreman managed-launch manual harness.

app_bundle: ${APP_BUNDLE}
pid: ${APP_PID}
defaults_suite: ${DEFAULTS_SUITE}
config_path: ${CONFIG_PATH}

Useful follow-ups:
  cua-driver call list_windows '{"pid":${APP_PID}}'
  plutil -p "${HOME}/Library/Preferences/${DEFAULTS_SUITE}.plist"
  kill ${APP_PID}
EOF
