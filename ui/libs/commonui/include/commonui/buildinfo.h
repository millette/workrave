/*
 * buildinfo.h --- When and from what source Workrave was built
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef WORKRAVE_UI_COMMON_BUILDINFO_H
#define WORKRAVE_UI_COMMON_BUILDINFO_H

// Recorded by cmake/modules/BuildInfo.cmake and defined in ui/app/BuildInfo.cc.
// They change only when the source state does (commit, branch, uncommitted
// changes), and then only that file is recompiled.

// Date and time, with time zone, of the first build of this source state,
// e.g. "2026-11-23 17:05:12 EST (-0500)". From SOURCE_DATE_EPOCH when set.
extern const char *const workrave_build_datetime;

// Git branch, e.g. "rym", or "detached HEAD". Empty outside a git tree.
extern const char *const workrave_build_branch;

// Abbreviated git commit, followed by " (modified)" when the source tree had
// uncommitted changes to tracked files. Empty outside a git tree.
extern const char *const workrave_build_commit;

#endif // WORKRAVE_UI_COMMON_BUILDINFO_H
