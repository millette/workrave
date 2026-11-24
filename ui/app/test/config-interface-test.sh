#!/bin/sh
# Regression test: org.workrave.ConfigInterface must survive a key it does
# not know.
#
# With the GSettings backend, asking for or setting a key that is not in the
# schema reached GLib, which treats that as a programming error and aborts
# the process: one D-Bus call with a mistyped key ended Workrave. An unknown
# key must be answered as "not found" instead.
#
# This test starts the given workrave binary on its own session bus, virtual
# display and temporary home, so it never touches a running Workrave or the
# user's settings.
#
# Usage: config-interface-test.sh /path/to/workrave
# Exit codes: 0 pass, 1 fail, 77 skipped (missing tool).

set -eu

if [ "${CONFIG_INTERFACE_TEST_INNER:-}" != 1 ]; then
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
  CONFIG_INTERFACE_TEST_INNER=1 dbus-run-session --config-file="$config" -- \
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

config=org.workrave.ConfigInterface

alive() {
  kill -0 "$pid" 2>/dev/null || fail "workrave died after $1"
}

# expect <what> <expected reply> <method> <args...>
expect() {
  what=$1
  want=$2
  shift 2
  got=$(call "$core" "$@" 2>&1) || true
  alive "$what"
  [ "$got" = "$want" ] || fail "$what: got $got, expected $want"
  echo "ok: $what"
}

# A key that exists is found, with its value.
expect "a known key is found" "(180, true)" "$config.GetInt" timers/micro_pause/limit

# A key the schema does not have: not found, and Workrave is still there.
expect "GetInt on an unknown key" "(0, false)" "$config.GetInt" timers/micro_pause/no_such_key
expect "GetBool on an unknown key" "(false, false)" "$config.GetBool" timers/micro_pause/no_such_key
expect "GetDouble on an unknown key" "(0.0, false)" "$config.GetDouble" timers/micro_pause/no_such_key
expect "GetString on an unknown key" "(false, '')" "$config.GetString" timers/micro_pause/no_such_key

# A path the schema does not have.
expect "GetInt on an unknown path" "(0, false)" "$config.GetInt" no_such_path/limit

# A key of another type: not found as an integer.
expect "GetInt on a boolean key" "(0, false)" "$config.GetInt" breaks/micro_pause/enabled

# Setting what does not exist, or with the wrong type, changes nothing and
# must not end Workrave either. Whether the call itself reports an error is
# not checked here.
call "$core" "$config.SetInt" timers/micro_pause/no_such_key 5 >/dev/null 2>&1 || true
alive "SetInt on an unknown key"
echo "ok: SetInt on an unknown key"
call "$core" "$config.SetInt" no_such_path/limit 5 >/dev/null 2>&1 || true
alive "SetInt on an unknown path"
echo "ok: SetInt on an unknown path"
call "$core" "$config.SetInt" breaks/micro_pause/enabled 5 >/dev/null 2>&1 || true
alive "SetInt on a boolean key"
expect "a boolean key keeps its value" "(true, true)" "$config.GetBool" breaks/micro_pause/enabled

# Setting a key that exists still works.
call "$core" "$config.SetInt" timers/micro_pause/limit 240 >/dev/null || fail "SetInt on a known key failed"
expect "a known key can be set" "(240, true)" "$config.GetInt" timers/micro_pause/limit

call "$ui" org.workrave.ControlInterface.Quit >/dev/null || fail "ControlInterface.Quit failed"
tries=0
while kill -0 "$pid" 2>/dev/null; do
  tries=$((tries + 1))
  [ "$tries" -le 20 ] || fail "workrave did not exit within 10 seconds of Quit"
  sleep 0.5
done
pid=
echo "PASS"
