# Workrave D-Bus interface

Workrave exposes its state and some UI actions on the D-Bus **session bus**.
Other programs can use it to read timers, react to breaks, change the
operation mode, read or write settings, or drive a panel applet.

This page describes Workrave **1.11.5**.

The interfaces are defined in XML files and turned into C++ bindings at build
time by `libs/dbus/bin/dbusgen.py`:

| File | Interfaces |
| --- | --- |
| `libs/core/src/workrave-service.xml` | Core, Config (GTK build) |
| `libs/corenext/src/workrave-service.xml` | Core, Break, Config (Qt build) |
| `ui/app/workrave-gui.xml` | Control, Applet |

## Which core?

Workrave has two core implementations, and their D-Bus interfaces differ:

- **GTK build** (the usual Linux build, `-DWITH_UI=Gtk+3`): uses `libs/core`.
  Break information is on `CoreInterface`, and every break method takes a
  break id. This is described in the main sections below.
- **Qt build** (`-DWITH_UI=Qt`, or `-DWITH_CORE_NEXT=ON`): uses
  `libs/corenext`. Each break has its own object with a `BreakInterface`. See
  [Qt build differences](#qt-build-differences).

`ControlInterface` and `AppletInterface` are the same in both builds.

## Overview (GTK build)

| Bus name | Object path | Interface |
| --- | --- | --- |
| `org.workrave.Workrave` | `/org/workrave/Workrave/Core` | `org.workrave.CoreInterface` |
| `org.workrave.Workrave` | `/org/workrave/Workrave/Core` | `org.workrave.ConfigInterface` |
| `org.workrave.Workrave` | `/org/workrave/Workrave/UI` | `org.workrave.ControlInterface` |
| `org.workrave.Workrave` | `/org/workrave/Workrave/UI` | `org.workrave.AppletInterface` |

The bus name is owned by the running application (in the GTK build, it is the
`GApplication` id). Only one Workrave can run per session: a second instance
exits when it sees the name taken.

The service is D-Bus activatable: `org.workrave.Workrave.service` starts
`workrave` when a client calls the bus name and Workrave is not running.

`AppletInterface` is registered only while the generic D-Bus applet is active,
for example when a panel applet embeds Workrave.

Builds with tests enabled (`HAVE_TESTS`) also export
`org.workrave.DebugInterface` at `/org/workrave/Workrave/Debug`, with a single
`Quit` method. Release builds do not have it.

### String enumerations

Enumerations travel as lower-case strings (D-Bus type `s`):

| Type | Values |
| --- | --- |
| Break id | `microbreak`, `restbreak`, `dailylimit` |
| Operation mode | `normal`, `suspended`, `quiet` |
| Usage mode | `normal`, `reading` |
| Break state | `none`, `prelude`, `break` |

### Break state

`GetBreakState` and the `MicrobreakChanged`, `RestbreakChanged` and
`DailylimitChanged` signals use the same values:

| Value | Meaning |
| --- | --- |
| `none` | No prelude or break window is shown. This includes a break that was ignored and will remind the user again later. |
| `prelude` | The prelude (the "time for a break" reminder) is shown. |
| `break` | The break window is shown. |

Workrave sometimes holds a due break back for a moment before showing it. No
signal is sent for that, and `GetBreakState` returns an empty string while it
lasts.

## `org.workrave.CoreInterface`

Object path: `/org/workrave/Workrave/Core`

All times are in seconds.

### Methods

| Method | In | Out | Description |
| --- | --- | --- | --- |
| `IsActive` | | `b` value | `true` if the user is currently active (typing or using the mouse). |
| `GetOperationMode` | | `s` mode | The regular operation mode. |
| `SetOperationMode` | `s` mode | | Set the operation mode. |
| `GetUsageMode` | | `s` mode | The usage mode. |
| `SetUsageMode` | `s` mode | | Set the usage mode. In `reading` mode, idle time does not count as a break, so timers keep running while you read. |
| `ReportActivity` | `s` who, `b` act | | Report activity from an external source. `act = true` counts the user as active for the next 10 seconds; call it repeatedly while the activity lasts. `act = false` withdraws the report for `who`. |
| `GetTime` | | `i` value | Workrave's current time, in seconds since the Unix epoch. |
| `IsTimerRunning` | `s` timer_id | `b` value | `true` if the timer of that break is counting. |
| `GetTimerElapsed` | `s` timer_id | `i` value | Active time accumulated since the last break. |
| `GetTimerIdle` | `s` timer_id | `i` value | Idle time accumulated since the user stopped being active. |
| `GetTimerRemaining` | `s` timer_id | `i` value | Time until the break is due, `0` when overdue, `-1` when the break has no limit. |
| `GetTimerOverdue` | `s` timer_id | `i` value | Total time the break has been overdue. |
| `GetBreakState` | `s` timer_id | `s` stage | The [break state](#break-state). |
| `PostponeBreak` | `s` timer_id | | Postpone the break. |
| `SkipBreak` | `s` timer_id | | Skip the break. |

`timer_id` is a break id: `microbreak`, `restbreak` or `dailylimit`.

### Signals

| Signal | Arguments | Emitted when |
| --- | --- | --- |
| `MicrobreakChanged` | `s` progress | The micro-break's [break state](#break-state) changes. |
| `RestbreakChanged` | `s` progress | The rest break's break state changes. |
| `DailylimitChanged` | `s` progress | The daily limit's break state changes. |
| `BreakPostponed` | `s` timer_id | A break was postponed. |
| `BreakSkipped` | `s` timer_id | A break was skipped. |
| `OperationModeChanged` | `s` mode | The operation mode changes. |
| `UsageModeChanged` | `s` mode | The usage mode changes. |

## `org.workrave.ConfigInterface`

Object path: `/org/workrave/Workrave/Core`

Reads and writes Workrave settings. Keys are slash-separated paths, for
example `timers/micro_pause/limit` or `timers/rest_break/auto_reset`. The
GSettings schema (`org.workrave.gschema.xml`) lists the available settings.
The break names used in keys are `micro_pause`, `rest_break` and
`daily_limit`.

| Method | In | Out | Description |
| --- | --- | --- | --- |
| `SetString` | `s` key, `s` value | | Write a string. |
| `SetInt` | `s` key, `i` value | | Write a 32-bit integer. |
| `SetBool` | `s` key, `b` value | | Write a boolean. |
| `SetDouble` | `s` key, `d` value | | Write a double. |
| `GetString` | `s` key | `b` found, `s` value | Read a string. |
| `GetInt` | `s` key | `i` value, `b` found | Read a 32-bit integer. |
| `GetBool` | `s` key | `b` value, `b` found | Read a boolean. |
| `GetDouble` | `s` key | `d` value, `b` found | Read a double. |

`found` is `false` when the key does not exist; `value` is then meaningless.

> **Note:** `GetString` returns `found` first, while the other getters return
> it last. Check the order when you unpack the reply.

## `org.workrave.ControlInterface`

Object path: `/org/workrave/Workrave/UI`

Triggers the same actions as the Workrave menu.

| Method | In | Description |
| --- | --- | --- |
| `OpenMain` | | Show the main window. |
| `Preferences` | | Open the preferences dialog. |
| `ReadingMode` | `b` show | Turn reading mode on or off. |
| `Statistics` | | Open the statistics dialog. |
| `Exercises` | | Open the exercises dialog. |
| `RestBreak` | | Start a rest break now. |
| `Quit` | | Quit Workrave. |
| `About` | | Open the about dialog. |

## `org.workrave.AppletInterface`

Object path: `/org/workrave/Workrave/UI`

Used by panel applets (GNOME Shell, Cinnamon, MATE, Xfce, ...) that draw
Workrave's timers and menu inside the desktop panel.

### Methods

| Method | In | Out | Description |
| --- | --- | --- | --- |
| `Embed` | `b` enabled, `s` sender | | Announce that an applet shows Workrave (`enabled = true`) or stopped (`false`). `sender` is the applet's bus name; Workrave watches it and treats the applet as gone when that name leaves the bus. |
| `Command` | `i` command | | Activate the menu item with this command number (from `GetMenu`). |
| `MenuAction` | `s` action | | Activate the menu item with this action id (from `GetMenu`). |
| `ButtonClicked` | `u` button | | The applet was clicked. Cycles the timer shown. `button` is ignored. |
| `GetMenu` | | `a(sssuyy)` menuitems | The full menu as a flat list of menu items. |
| `GetTrayIconEnabled` | | `b` enabled | `true` if the user wants the tray icon shown next to the applet. |

### Signals

| Signal | Arguments | Emitted when |
| --- | --- | --- |
| `TimersUpdated` | `(siuuuuuu)` micro, `(siuuuuuu)` rest, `(siuuuuuu)` daily | Every timer update (about once per second). |
| `MenuUpdated` | `a(sssuyy)` menuitems | The menu structure changes. |
| `MenuItemUpdated` | `(sssuyy)` menuitem | One menu item changes (for example a check box). |
| `TrayIconUpdated` | `b` enabled | The tray icon setting changes. |

### Timer data `(siuuuuuu)`

The three structs are display slots, not breaks: `slot` tells which break
the slot shows.

| # | Type | Field | Meaning |
| --- | --- | --- | --- |
| 1 | `s` | bar_text | Time text to display, for example `"4:32"`. |
| 2 | `i` | slot | Break shown: `0` micro-break, `1` rest break, `2` daily limit, `-1` none. |
| 3 | `u` | bar_secondary_color | Color id of the secondary bar. |
| 4 | `u` | bar_secondary_val | Value of the secondary bar. |
| 5 | `u` | bar_secondary_max | Maximum of the secondary bar. |
| 6 | `u` | bar_primary_color | Color id of the primary bar. |
| 7 | `u` | bar_primary_val | Value of the primary bar. |
| 8 | `u` | bar_primary_max | Maximum of the primary bar. |

Color ids: `0` active, `1` inactive, `2` overdue, `3` inactive over active,
`4` inactive over overdue, `5` background.

### Menu item `(sssuyy)`

| # | Type | Field | Meaning |
| --- | --- | --- | --- |
| 1 | `s` | text | Label. |
| 2 | `s` | dynamic_text | Label with live content, if any. |
| 3 | `s` | action | Action id, for `MenuAction`. |
| 4 | `u` | command | Command number, for `Command`. |
| 5 | `y` | type | Item type, see below. |
| 6 | `y` | flags | Bit set: `1` active (checked), `2` visible. |

Item types: `1` submenu begin, `2` submenu end, `3` radio group begin,
`4` radio group end, `5` action, `6` check, `7` radio, `8` separator.
Begin/end items bracket the items that belong to a submenu or radio group.

## Qt build differences

The Qt build (`libs/corenext`) uses the same bus name, the same
`/org/workrave/Workrave/Core` path, and the same UI interfaces, but splits
break information into one object per break.

### `org.workrave.CoreInterface`

Only these members remain:

| Member | Kind | Signature |
| --- | --- | --- |
| `IsActive` | method | out `b` |
| `GetOperationMode` / `SetOperationMode` | methods | out `s` / in `s` |
| `GetUsageMode` / `SetUsageMode` | methods | out `s` / in `s` |
| `ReportActivity` | method | in `s` who, `b` act |
| `OperationModeChanged` | signal | `s` mode |
| `UsageModeChanged` | signal | `s` mode |

> **Note:** in the Qt build `ReportActivity` is accepted but does nothing;
> external activity reports are not implemented in `libs/corenext` yet.

`GetTime`, the timer and break methods, and the `MicrobreakChanged`,
`RestbreakChanged`, `DailylimitChanged`, `BreakPostponed` and `BreakSkipped`
signals do not exist. Use `BreakInterface` instead.

### `org.workrave.BreakInterface`

Object paths:

| Break | Object path |
| --- | --- |
| Micro-break | `/org/workrave/Workrave/Break/micro_pause` |
| Rest break | `/org/workrave/Workrave/Break/rest_break` |
| Daily limit | `/org/workrave/Workrave/Break/daily_limit` |

| Member | Kind | Signature | Description |
| --- | --- | --- | --- |
| `IsTimerRunning` | method | out `b` | Like the GTK method, for this break. |
| `GetTimerElapsed` | method | out `i` | Like the GTK method, for this break. |
| `GetTimerIdle` | method | out `i` | Like the GTK method, for this break. |
| `GetTimerRemaining` | method | out `i` | Like the GTK method, for this break. |
| `GetTimerOverdue` | method | out `i` | Like the GTK method, for this break. |
| `GetBreakState` | method | out `s` | The [break state](#break-state). |
| `PostponeBreak` | method | | Postpone this break. |
| `SkipBreak` | method | | Skip this break. |
| `BreakStateChanged` | signal | `s` state | The break state changes. Same values as `MicrobreakChanged` and friends. |
| `BreakEvent` | signal | `s` event | Something happens to the break, see below. |

Break events: `show_prelude`, `show_break`, `show_break_forced`,
`break_start`, `break_idle`, `break_stop`, `break_ignored`,
`break_postponed`, `break_skipped`, `break_taken`.

### `org.workrave.ConfigInterface`

Adds `SetInt64` (in `s` key, `x` value). Everything else is the same as in
the GTK build.

## Examples (GTK build)

### `gdbus`

```sh
# Is the user active?
gdbus call --session --dest org.workrave.Workrave \
  --object-path /org/workrave/Workrave/Core \
  --method org.workrave.CoreInterface.IsActive

# Go quiet
gdbus call --session --dest org.workrave.Workrave \
  --object-path /org/workrave/Workrave/Core \
  --method org.workrave.CoreInterface.SetOperationMode quiet

# Seconds until the next micro-break
gdbus call --session --dest org.workrave.Workrave \
  --object-path /org/workrave/Workrave/Core \
  --method org.workrave.CoreInterface.GetTimerRemaining microbreak

# Start a rest break now
gdbus call --session --dest org.workrave.Workrave \
  --object-path /org/workrave/Workrave/UI \
  --method org.workrave.ControlInterface.RestBreak

# Read a setting: prints (value, found)
gdbus call --session --dest org.workrave.Workrave \
  --object-path /org/workrave/Workrave/Core \
  --method org.workrave.ConfigInterface.GetInt timers/micro_pause/limit

# Print the full introspection data
gdbus introspect --session --dest org.workrave.Workrave \
  --object-path /org/workrave/Workrave/Core

# Watch all Workrave signals
gdbus monitor --session --dest org.workrave.Workrave
```

### Python (`dbus-python`)

```python
import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()

core = dbus.Interface(
    bus.get_object("org.workrave.Workrave", "/org/workrave/Workrave/Core"),
    "org.workrave.CoreInterface",
)
print("mode:", core.GetOperationMode())
print("micro-break in", core.GetTimerRemaining("microbreak"), "s")

for signal in ("MicrobreakChanged", "RestbreakChanged", "DailylimitChanged"):
    core.connect_to_signal(signal, lambda state, s=signal: print(s, state))

GLib.MainLoop().run()
```

## Known issues

These inconsistencies were found by comparing the interface definitions, both
core implementations, and the D-Bus clients in this repository. None of them
is fixed in 1.11.5.

### In the interface

- **`GetString` reply order.** `GetString` replies `(found, value)`; `GetInt`,
  `GetBool` and `GetDouble` reply `(value, found)`
  (`libs/core/src/workrave-service.xml`, `libs/corenext/src/workrave-service.xml`).
- **No `GetInt64`.** The Qt build has `SetInt64` but no matching getter, so a
  64-bit value can be written but not read back. The GTK build has neither
  (`libs/corenext/src/workrave-service.xml:123`).
- **Only the regular operation mode is visible.** `GetOperationMode` and
  `OperationModeChanged` report the mode the user chose, not the mode in
  effect. Temporary overrides, such as suspending during power-save, are not
  signalled, and no method returns the active mode
  (`libs/core/src/Core.cc:526`, `libs/corenext/src/CoreModes.cc:148`).
- **`GetTime` is 32-bit.** It returns seconds since the Unix epoch as `i`
  (`int32`), which overflows in January 2038
  (`libs/core/src/workrave-service.xml:73`).
- **`Command` and menu items disagree on type.** `GetMenu` reports each
  item's command number as `u` (`uint32`), but `Command` takes `i`
  (`int32`) (`ui/app/workrave-gui.xml:31`, `ui/app/workrave-gui.xml:65`).
- **`ReportActivity` does nothing in the Qt build.** The method is exported but
  its body is a `TODO` (`libs/corenext/src/Core.cc:329`).
- **Applet name watches can leak.** `Embed` only unwatches bus names that have
  already appeared. A name that was watched but never appeared keeps its watch,
  and embedding again with the same name starts a second one
  (`ui/app/GenericDBusApplet.cc:147`).

### In clients shipped with Workrave

- **Cinnamon applet un-embeds with an invalid bus name.** It embeds as
  `org.workrave.CinnamonApplet` but un-embeds with `'CinnamonApplet'`, which
  is not a valid bus name. Workrave tries to watch it and GLib rejects the
  watch with a critical warning (`ui/applets/cinnamon/src/applet.js:240`).
- **GNOME Shell 45+ ignores the prelude "move out" stage.** Workrave sends
  `SetStage("move_out")`, but the extension checks for `"move-out"`
  (`libs/core/include/core/IApp.hh:79`,
  `ui/applets/gnome-shell-45/src/prelude_window.js:164`).
- **Applets declare GTK-only members.** The Cinnamon and GNOME Shell applets
  declare the GTK build's `CoreInterface`, including 14 members the Qt build
  does not have. They only call members that exist in both builds, so this
  does not break them, but the declarations are misleading.
- **`waybar` script uses hyphenated keys.** `workrave_break_info.py` reads
  `breaks/micro-pause/enabled`. The GSettings backend turns `_` into `-`, so
  this works with it, but the INI and XML backends do not, and the read
  returns "not found"
  (`contrib/waybar-yambar-poss-other-applets/workrave_break_info.py:250`).
- **Test helper uses a missing interface.** `workrave_test_base.py` creates a
  proxy for `org.workrave.NetworkInterface`, which no build exports
  (`libs/core/test/workrave_test_base.py:95`).
- **Example scripts are Python 2 and GTK-only.** `dbus-example.py` uses
  Python 2 `print` statements. The copies in `libs/corenext/src`
  (`dbus-example.py`, `facedetect.py`) listen for `MicrobreakChanged` and
  friends, which the Qt build that uses `libs/corenext` does not send.

## Changing the interface

Edit the XML file for the interface (see the table at the top). The build runs
`dbusgen.py` to regenerate the bindings, so there are no generated files to
check in. Keep names and signatures stable: external applets and scripts
depend on them.
