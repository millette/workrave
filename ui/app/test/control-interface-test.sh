#!/bin/sh
# Regression test: Workrave must export org.workrave.ControlInterface.
#
# 1.11.0 to 1.11.5 connected the interface before its D-Bus binding was
# registered, so it was never exported. This test starts the given workrave
# binary on its own session bus, virtual display and temporary home, so it
# never touches a running Workrave or the user's settings.
#
# Usage: control-interface-test.sh /path/to/workrave
# Exit codes: 0 pass, 1 fail, 77 skipped (missing tool).

set -eu

if [ "${CONTROL_INTERFACE_TEST_INNER:-}" != 1 ]; then
  workrave=${1:?usage: $0 /path/to/workrave}
  for tool in dbus-run-session xvfb-run gdbus; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "SKIP: $tool not found"
      exit 77
    fi
  done
  # A bus with no service directories: a call to org.workrave.Workrave must
  # never activate the installed workrave, which would run with the real HOME
  # and settings of the user.
  config=$(mktemp)
  trap 'rm -f "$config"' EXIT
  cat >"$config" <<'EOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
EOF
  status=0
  CONTROL_INTERFACE_TEST_INNER=1 dbus-run-session --config-file="$config" -- \
    xvfb-run -a "$0" "$workrave" || status=$?
  exit "$status"
fi

workrave=$1
dest=org.workrave.Workrave
ui=/org/workrave/Workrave/UI
core=/org/workrave/Workrave/Core

tmp=$(mktemp -d)
pid=
cleanup() {
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*"
  echo "--- workrave log ---"
  cat "$tmp/workrave.log" 2>/dev/null || true
  exit 1
}

call() {
  object=$1
  method=$2
  shift 2
  gdbus call --session --dest "$dest" --object-path "$object" --method "$method" "$@"
}

HOME=$tmp/home
XDG_CONFIG_HOME=$tmp/home/.config
XDG_DATA_HOME=$tmp/home/.local/share
XDG_CACHE_HOME=$tmp/home/.cache
GSETTINGS_BACKEND=memory
export HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME GSETTINGS_BACKEND
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

# Nothing else may own the name, or the test would talk to the wrong process.
owner=$(gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
  --method org.freedesktop.DBus.NameHasOwner "$dest")
[ "$owner" = "(false,)" ] || fail "$dest is already owned on the test bus"

"$workrave" >"$tmp/workrave.log" 2>&1 &
pid=$!

introspect_ui() {
  gdbus introspect --session --dest "$dest" --object-path "$ui" 2>/dev/null || true
}

# Wait until the UI object carries a Workrave interface.
tries=0
while :; do
  case $(introspect_ui) in
    *"interface org.workrave."*) break ;;
  esac
  kill -0 "$pid" 2>/dev/null || fail "workrave exited during start-up"
  tries=$((tries + 1))
  [ "$tries" -le 60 ] || fail "$ui did not appear on the bus within 30 seconds"
  sleep 0.5
done
# Let start-up finish connecting the remaining interfaces.
sleep 1

case $(introspect_ui) in
  *"interface org.workrave.ControlInterface "*) ;;
  *) fail "org.workrave.ControlInterface is not exported on $ui" ;;
esac
echo "ok: ControlInterface exported"

# Methods compiled out by their condition must not be advertised.
case $(introspect_ui) in
  *" SetOperationMode("*) fail "introspection lists SetOperationMode, which is not compiled in" ;;
esac
echo "ok: SetOperationMode not advertised"

call "$ui" org.workrave.ControlInterface.ReadingMode true >/dev/null ||
  fail "ControlInterface.ReadingMode failed"
mode=$(call "$core" org.workrave.CoreInterface.GetUsageMode)
[ "$mode" = "('reading',)" ] || fail "usage mode is $mode after ReadingMode true, expected ('reading',)"
echo "ok: ReadingMode switches the usage mode"

kill -0 "$pid" 2>/dev/null || fail "workrave died after a ControlInterface call"

call "$ui" org.workrave.ControlInterface.Quit >/dev/null || fail "ControlInterface.Quit failed"
tries=0
while kill -0 "$pid" 2>/dev/null; do
  tries=$((tries + 1))
  [ "$tries" -le 20 ] || fail "workrave did not exit within 10 seconds of Quit"
  sleep 0.5
done
pid=
echo "ok: Quit stops workrave"
echo "PASS"
