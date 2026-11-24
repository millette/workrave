# Workrave: `ControlInterface` is not exported

A defect in Workrave 1.11.5 (branch `rym` of `~/git/workrave`), found while
analysing its D-Bus interface, and the fix proposed for it.

Status on 2026-11-23: **fixed on branch `rym` (commit `efb99a2ff`), with a
regression test and documentation, built and verified in isolation.** Not
pushed, not packaged, not installed: the Workrave running on this machine is
still the unpatched 1.11.5. See [Result](#result) and
[Follow-up](#follow-up-2026-11-23-afternoon) for what was tested and what
remains.

## Summary

`org.workrave.ControlInterface` is defined in `ui/app/workrave-gui.xml`,
described in `docs/dbus.md`, and used by clients shipped with Workrave, but
the running application never exports it. Every call to it fails.

The cause is an ordering mistake at start-up, in two parts. It has been
there since the 1.11 line began; 1.10 does not have it.

## Symptom

On the running 1.11.5 (GTK build, package `1.11.5-0local1`):

```bash
gdbus introspect --session --dest org.workrave.Workrave --object-path /org/workrave/Workrave/UI
```

lists `org.workrave.AppletInterface` and no `org.workrave.ControlInterface`.
A call to any of its methods is refused:

```text
GDBus.Error:org.freedesktop.DBus.Error.UnknownMethod: L’interface
« org.workrave.ControlInterface » n’existe pas pour l’objet à l’emplacement
/org/workrave/Workrave/UI
```

The same check on Workrave 1.10.53, made earlier the same day on this
machine before the 1.11.5 build was installed, listed `ControlInterface`
with all its methods.

Nothing is logged: the failure is swallowed (see below).

## Cause

All references are to `ui/app/Application.cc` on branch `rym`.

### 1. The interface is connected before its binding exists

`Application::init_dbus()` does two things, in this order:

```cpp
      try
        {
          dbus->register_object_path("/org/workrave/Workrave/UI");
          dbus->connect("/org/workrave/Workrave/UI", "org.workrave.ControlInterface", menus.get());   // line 296
        }
      catch (workrave::dbus::DBusException &)
        {
        }
    }

#if defined(HAVE_DBUS)
  try
    {
      extern void init_DBusGUI(workrave::dbus::IDBus::Ptr dbus);
      init_DBusGUI(dbus);                                                                             // line 307
    }
```

`init_DBusGUI` is the generated function that registers the bindings for the
interfaces in `workrave-gui.xml` (`dbus->register_binding(...)`, from
`libs/dbus/data/gio-cc.jinja`). `DBusGio::connect` looks the binding up
first and throws when it is missing (`libs/dbus/src/DBusGio.cc`):

```cpp
  auto *binding = dynamic_cast<DBusBindingGio *>(find_binding(interface_name));
  if (binding == nullptr)
    {
      TRACE_MSG("No such interface");
      throw DBusException("No such interface");
    }
```

At line 296 the binding is not registered yet, so `connect` throws
"No such interface". The empty `catch` drops the exception.

### 2. The object passed does not exist yet

`init_dbus()` is called at line 107. `menus` is created at line 113:

```cpp
  init_dbus();                                    // line 107

  preferences_registry = std::make_shared<PreferencesRegistry>();
  context->set_preferences_registry(preferences_registry);
  menu_model = std::make_shared<MenuModel>();
  context->set_menu_model(menu_model);
  menus = std::make_shared<Menus>(context);       // line 113
```

So `menus.get()` at line 296 is a null pointer. Today this is hidden by the
first defect: `connect` throws before it stores the pointer.

**This matters for the fix.** Swapping the two blocks inside `init_dbus()`
would make `connect` succeed with a null object, and the first call to
`RestBreak` or any other method would then dereference it. Reordering inside
`init_dbus()` alone turns a missing feature into a crash.

### Why `AppletInterface` works

`GenericDBusApplet` connects its interface later
(`ui/app/GenericDBusApplet.cc:124`), when the applet is initialised: after
`init_DBusGUI` has run, and with `this` as the object. It has neither problem.

## History

In 1.10 the two steps were in separate functions, called in the right order
(`frontend/gtkmm/src/GUI.cc` on `origin/branch_v1_10`):

- `GUI::init_dbus()` registered the object path and called `init_DBusGUI`
- `GUI::init_gui()`, called later, created the menus and then connected
  `ControlInterface`

Commit `14a11bb7a` ("Toolkit refactoring", 2021-09-01) merged both into
`Application::init_dbus()` with the `connect` first. The earliest tag that
contains it is `v1_11_0_alpha1`, so every 1.11 release has the defect.

Branch `main` no longer has this code: `ui/app/Application.cc` there contains
neither `ControlInterface` nor `init_DBusGUI`. Whether `main` exports the
interface has not been checked.

## Who is affected

| Client | Effect |
| --- | --- |
| `ui/applets/common/src/control.c` | Creates a proxy for `ControlInterface` and hands it to the panel applets; calls through it fail |
| `contrib/send_dbus_command/kde/workrave-kde.sh` | Its `ControlInterface` commands fail |
| `docs/dbus.md` | Lists the interface in the overview, has a section for it, and uses `ControlInterface.RestBreak` in its examples; none of this works on 1.11.5 |
| Any external script | No D-Bus method starts a rest break, opens the statistics, or toggles reading mode by name |

The one working route to those actions is
`org.workrave.AppletInterface.MenuAction` with an action id from `GetMenu`
(`workrave.restbreak`, `workrave.mode_reading`, ...). It exists only while
the generic D-Bus applet is active.

## Proposed fix

Restore the 1.10 order: register the bindings early, connect the interface
once `menus` exists.

```diff
@@ Application::main (around line 107)
   init_dbus();
 
   preferences_registry = std::make_shared<PreferencesRegistry>();
   context->set_preferences_registry(preferences_registry);
   menu_model = std::make_shared<MenuModel>();
   context->set_menu_model(menu_model);
   menus = std::make_shared<Menus>(context);
+  init_dbus_control();
 
@@ Application::init_dbus
       try
         {
           dbus->register_object_path("/org/workrave/Workrave/UI");
-          dbus->connect("/org/workrave/Workrave/UI", "org.workrave.ControlInterface", menus.get());
         }
       catch (workrave::dbus::DBusException &)
         {
         }
     }
 
+// (init_DBusGUI block unchanged)
+}
+
+void
+Application::init_dbus_control()
+{
+#if defined(HAVE_DBUS)
+  auto dbus = get_core()->get_dbus();
+
+  if (dbus->is_available())
+    {
+      try
+        {
+          dbus->connect("/org/workrave/Workrave/UI", "org.workrave.ControlInterface", menus.get());
+        }
+      catch (workrave::dbus::DBusException &e)
+        {
+          spdlog::warn("Cannot export org.workrave.ControlInterface: {}", e.details());
+        }
+    }
+#endif
+}
```

Plus the declaration of `init_dbus_control()` in `ui/app/Application.hh`.

This is the patch as applied (`git diff -- ui` in `~/git/workrave`: two
files, 24 lines added, 1 removed).

Points considered when writing it:

- **Log instead of swallowing.** The empty `catch` is why this went unnoticed
  for five years. The sketch logs a warning with `spdlog`, which the file
  already includes, and `details()`, the accessor of Workrave's exception
  class
- **`HAVE_DBUS` guard.** Today the `connect` is outside the guard and
  `init_DBusGUI` inside it. The new function keeps both consistent
- **Object registration.** `register_object_path` marks the path as
  registered, so a later `connect` takes the "update registration" branch of
  `DBusGio::connect`. That is the same path `GenericDBusApplet` uses, and it
  works there
- **Shutdown.** Neither 1.10 nor 1.11 disconnects the interface before
  `menus` is destroyed. Not made worse by this change; worth a look
- **Qt build.** `Application.cc` is shared by both toolkits, so the fix
  covers both, but only the GTK build can be checked here

## Result

Applied and tested on 2026-11-23.

**Build.** Out of tree, in `~/git/workrave-build-rym` (GTK+3,
`RelWithDebInfo`, install prefix inside the build directory). 252 targets,
no error.

**Test method.** The patched binary was run away from the real session, so
the running Workrave and its data were never touched:

- its own D-Bus session bus (`dbus-run-session`)
- its own display (`xvfb-run`)
- a temporary `HOME`, and `GSETTINGS_BACKEND=memory` so no setting is read
  from or written to the real configuration

The unpatched `/usr/bin/workrave` was run in the same harness as a baseline.

| Check | Unpatched 1.11.5 | Patched |
| --- | --- | --- |
| `ControlInterface` in the introspection of `/org/workrave/Workrave/UI` | absent | present, with all its methods |
| `ControlInterface.Statistics` | `UnknownMethod` | succeeds |
| `ControlInterface.ReadingMode true`, then `GetUsageMode` | `UnknownMethod`, `normal` | succeeds, `reading` |
| `ControlInterface.RestBreak`, then `GetBreakState restbreak` | `UnknownMethod`, `none` | succeeds, `break` |
| Process alive after the calls | yes | yes (no null dereference) |
| `ControlInterface.Quit` | `UnknownMethod` | succeeds, process exits |
| `AppletInterface` still exported | yes | yes |
| "Cannot export" warning in the log | not applicable | none |

After the tests the real instance was still running under the same process
id, in `normal` usage mode.

**Not done:**

- Committed locally as `efb99a2ff` on `rym`, not pushed. The earlier
  uncommitted change to `docs/dbus.md` is left as it was. `clang-format` is
  not installed here, so the formatting was matched by hand, not checked
- Not packaged or installed. `ControlInterface` stays unavailable on this
  machine until a patched build replaces `1.11.5-0local1`
- No regression test added to the Workrave tree
- `docs/dbus.md` not updated
- Qt build not built or tested
- Not tested with a real panel applet, nor on a real desktop session; the
  windows were opened on a virtual display and not looked at
- `SetOperationMode` shows in the introspection of `ControlInterface`
  although `workrave-gui.xml` marks it `condition="defined(NOT_YET)"`. It was
  not called. Worth checking separately

## Follow-up (2026-11-23, afternoon)

**Rebuilt.** `~/git/workrave-build-rym` was deleted and rebuilt from scratch
with the same options plus `WITH_TESTS=ON`, then installed into its
`prefix/`. No errors or warnings.

**Regression test added.** `ui/app/test/control-interface-test.sh`, registered
with CTest as `workrave-control-interface-test` (Linux, D-Bus and
`WITH_TESTS` only; exits 77, counted as skipped, when `dbus-run-session`,
`xvfb-run` or `gdbus` is missing). It starts the given binary on a private
bus, a virtual display and a temporary `HOME` with
`GSETTINGS_BACKEND=memory`, then checks that:

- `ControlInterface` is in the introspection of `/org/workrave/Workrave/UI`
- `ReadingMode true` switches `GetUsageMode` to `reading`
- the process survives the call
- `Quit` makes it exit

It passes on the patched build and fails on the unpatched `/usr/bin/workrave`.
All 7 CTest tests pass.

**Lesson learned writing it.** A plain `dbus-run-session` bus still reads
`/usr/share/dbus-1/services`. The first draft polled `org.workrave.Workrave`
before the binary under test had claimed it, so the bus *activated* the
installed `/usr/bin/workrave` with the real `HOME` and dconf. That stray
instance rotated `~/.cache/workrave/workrave.log` twice, so the oldest rotated
log from an earlier session was lost. Settings, stats and the running instance
were not touched. The test now uses a bus configuration with no service
directories and refuses to run if the name is already owned. Later runs were
checked against checksums of the real log and dconf database.

**`SetOperationMode` explained.** It is expected behaviour of the code
generator, not caused by the fix. `gio-cc.jinja` lists every method in the
introspection data whatever its `condition`, and compiles a conditional-out
method as a stub replying `org.workrave.NotImplemented`. Called on the
patched build: that error, operation mode unchanged, process alive.

**`docs/dbus.md` updated.** Note in the `ControlInterface` section with the
`MenuAction` workaround, a caveat on the `RestBreak` example, and two
"Known issues" entries (this defect, and `SetOperationMode`).

**Qt build: blocked by an unrelated defect.** Configured in
`~/git/workrave-build-rym-qt` (Qt 6.8.2, the only version CMake accepts). The
build fails in `libs/utils/src/Platform-unix.cc`, which still uses Qt 5-only
API (`QApplication::desktop()`, `QDesktopWidget`, `QPlatformNativeInterface`).
`main` has reworked that file. The fix itself could not be checked on Qt.

### Later the same afternoon

**`SetOperationMode` hidden (commit `cea56df29`).** `gio-cc.jinja` and
`qt-cc.jinja` now wrap a conditional method in the same `#if` in the
introspection string as in its stub. `SetOperationMode` is no longer
advertised, and GDBus itself now rejects a call with `UnknownMethod`. The
regression test asserts it is absent (it failed before the change, passes
after).

**Qt build: stopped after three attempts.** Branch `rym-qt-build`
(`f87dff068`, not merged) ports `main`'s Qt 6 changes to `Platform-unix.cc`,
with `Qt::GuiPrivate` (a separate CMake component only from Qt 6.9). The
build then fails on two more defects that predate the fix: `WaylandInputMonitor`
includes GDK headers (`main` adds a separate `QtWaylandInputMonitor`; worked
around with `-DWITH_WAYLAND=OFF`), and `ui/app/toolkits/qt/ToolkitUnix.hh`
includes `UnixLocker.hh`, which on `rym` exists only for gtkmm. The Linux Qt
build on `rym` needs a larger port of `main`'s Qt work; the fix is unchecked
on Qt.

**Real session (i3, X11), 13:13–13:17.** The packaged Workrave was quit with
`AppletInterface.MenuAction workrave.quit`, the patched build started from
`prefix/` with the real settings, then quit with `ControlInterface.Quit`, and
the packaged one restarted. Operation and usage modes were `normal` before
and after.

| Check | Result |
| --- | --- |
| `ControlInterface` in introspection, no `SetOperationMode` | yes |
| `Statistics` | window opened with the real history |
| `ReadingMode true` / `false` | usage mode `reading`, then `normal` |
| `SetOperationMode` | `UnknownMethod` |
| `AppletInterface.GetMenu` | 33 actions |
| `Quit` | process exits |
| Warnings in the log | none |
| Tray icon in `i3bar` | missing at first, see below; present after the build fix |

`RestBreak` was not called on the real desktop, because it would take over
the screen; it was checked in the isolated harness.

**Tray icon: separate build bug (commit `d831feded`).** The first patched run
had no tray icon. The binary contained no `StatusIcon` code: CMake only set
`HAVE_STATUSICON` when dbusmenu was found and AppIndicator was not, and
`libdbusmenu-gtk3-dev` is not installed here. The fix falls back to the
status icon whenever AppIndicator is not used. A second run then showed the
icon in `i3bar`.

**Still not done:**

- ~~Not packaged or installed~~ Done at 13:25: `~/git/workrave_1.11.5-0local2_amd64.deb`
  (built from `8fbf2944a`, same layout and dependencies as `0local1`) is
  installed, and the running Workrave was restarted on it. `ControlInterface`
  is exported and the tray icon shows in `i3bar`
- Qt build not tested (see above)
- No GNOME/Cinnamon/MATE panel applet test: this machine runs i3
- Release notes not written
- `clang-format` still not installed, so formatting still unchecked

## How to verify on the real session

After installing a patched build and restarting Workrave:

1. Introspection lists the interface:

   ```bash
   gdbus introspect --session --dest org.workrave.Workrave --object-path /org/workrave/Workrave/UI
   ```

2. A harmless call succeeds and opens the statistics window:

   ```bash
   gdbus call --session --dest org.workrave.Workrave --object-path /org/workrave/Workrave/UI --method org.workrave.ControlInterface.Statistics
   ```

3. `ControlInterface.RestBreak` starts a rest break.
4. `AppletInterface` still works: `GetMenu` returns the menu, and a panel
   applet still shows the timers.
5. Workrave starts and stops cleanly with no new warning in its log.

A regression test belongs with the existing D-Bus tests in
`libs/core/test/` (`workrave_test_base.py` already opens proxies on the
session bus): assert that `/org/workrave/Workrave/UI` exposes
`org.workrave.ControlInterface`.

## Documentation to update with the fix

- `docs/dbus.md`, "Known issues": add an entry stating that
  `ControlInterface` is not exported in 1.11.0 to 1.11.5, with the
  `MenuAction` workaround. This is true today and can be added before the fix
- `docs/dbus.md`, examples: the `ControlInterface.RestBreak` example needs
  the same note until the fix ships
- Release notes: `ControlInterface` available again

## Effect on this project

None of the stages the productivity-integration project was built in
depends on the fix: they use `AppletInterface.MenuAction`. Once the fix is
installed and running, `ControlInterface.RestBreak` becomes a second route
that does not depend on the D-Bus applet being active, and `src/workrave.ts`
can prefer it when present.
