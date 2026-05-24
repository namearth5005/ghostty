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
readonly WINDOW_TITLE="ForemanManagedLaunchManual"
readonly VERIFY_LAUNCHES="${1:-}"

find_visible_window_id() {
  local pid="$1"
  local window_title="$2"
  cua-driver call list_windows "{\"pid\":${pid}}" | ruby -rjson -e '
    data = JSON.parse(STDIN.read)
    window = data.fetch("windows").find do |entry|
      entry["on_current_space"] && entry["is_on_screen"] && entry["title"] == ARGV.fetch(0)
    end
    abort("Failed to find visible Foreman window titled #{ARGV.fetch(0)}.") unless window
    puts window.fetch("window_id")
  ' "${window_title}"
}

clear_capture_suite() {
  defaults delete "${DEFAULTS_SUITE}" >/dev/null 2>&1 || true
}

read_capture_value() {
  local key="$1"
  defaults read "${DEFAULTS_SUITE}" "${key}" 2>/dev/null || true
}

prime_window_state() {
  local pid="$1"
  local window_id="$2"
  cua-driver call get_window_state "{\"pid\":${pid},\"window_id\":${window_id}}" >/dev/null
}

wait_for_capture() {
  local expected_identity="$1"
  local expected_window_id="$2"
  local attempts=20

  while (( attempts > 0 )); do
    local identity
    local location
    local working_directory
    local source_window_number

    identity="$(read_capture_value ForemanManagedLaunch.identity)"
    location="$(read_capture_value ForemanManagedLaunch.location)"
    working_directory="$(read_capture_value ForemanManagedLaunch.workingDirectory)"
    source_window_number="$(read_capture_value ForemanManagedLaunch.sourceWindowNumber)"

    if [[ "${identity}" == "${expected_identity}" ]] &&
      [[ "${location}" == "tab" ]] &&
      [[ -n "${working_directory}" ]] &&
      [[ "${source_window_number}" == "${expected_window_id}" ]]; then
      return 0
    fi

    sleep 0.1
    (( attempts -= 1 ))
  done

  return 1
}

verify_launch_capture() {
  local label="$1"
  local expected_identity="$2"
  local x="$3"
  local y="$4"
  local window_id="$5"
  local attempt

  for attempt in 1 2 3; do
    clear_capture_suite
    cua-driver call click "{\"pid\":${APP_PID},\"window_id\":${window_id},\"x\":${x},\"y\":${y}}" >/dev/null

    if wait_for_capture "${expected_identity}" "${window_id}"; then
      echo "verified ${label}: ${expected_identity}"
      return 0
    fi

    sleep 0.5
  done

  echo "Managed-launch verification failed for ${label} (${expected_identity})." >&2
  plutil -p "${HOME}/Library/Preferences/${DEFAULTS_SUITE}.plist" 2>/dev/null || true
  exit 1
}

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

clear_capture_suite

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

if [[ "${VERIFY_LAUNCHES}" == "--verify-launches" ]]; then
  readonly WINDOW_ID="$(find_visible_window_id "${APP_PID}" "${WINDOW_TITLE}")"
  sleep 1
  prime_window_state "${APP_PID}" "${WINDOW_ID}"

  verify_launch_capture "Claude Code" "claude_code" 1506 219 "${WINDOW_ID}"
  verify_launch_capture "Codex" "codex" 1506 244 "${WINDOW_ID}"
  verify_launch_capture "Kimi" "kimi" 1506 271 "${WINDOW_ID}"

  cat <<EOF
Managed-launch verification succeeded.

app_bundle: ${APP_BUNDLE}
pid: ${APP_PID}
window_id: ${WINDOW_ID}
defaults_suite: ${DEFAULTS_SUITE}
config_path: ${CONFIG_PATH}
EOF
  exit 0
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
