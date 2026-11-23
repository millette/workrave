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

// Recorded at every build by cmake/modules/BuildInfo.cmake and defined in
// ui/app/BuildInfo.cc, so only that file is recompiled at each build.

// Build date and time with time zone, e.g. "2026-11-23 17:05:12 EST (-0500)".
extern const char *const workrave_build_datetime;

// Git branch, e.g. "rym", or "detached HEAD".
extern const char *const workrave_build_branch;

// Abbreviated git commit, followed by " (modified)" when the source tree had
// uncommitted changes to tracked files.
extern const char *const workrave_build_commit;

#endif // WORKRAVE_UI_COMMON_BUILDINFO_H
