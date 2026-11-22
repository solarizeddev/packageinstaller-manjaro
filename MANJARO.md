# Package Installer for Manjaro

CachyOS's package installer ([CachyOS/packageinstaller](https://github.com/CachyOS/packageinstaller),
GPL-3.0), version 2.0 (the QML app store: Discover, Browse, Installed,
Updates, AUR with PKGBUILD review, Flatpak, AppImage, colour themes), built
for Manjaro: Manjaro's name and logo, Manjaro's app list and mirror ranking.
Everything else is upstream's, and each upstream release is merged here.

This tracks upstream's `fresh` branch until 2.0.0 is tagged, then its
releases.

![The Discover page on Manjaro KDE](manjaro/screenshots/discover.png)

The four pictures in README.md's table (`screenshots/`) are ours, of the
Manjaro build, under upstream's file names, so README.md itself stays
upstream's. `tools/screenshots.sh` takes them again (Manjaro container, Xvfb,
needs docker); `tools/update-upstream.sh` keeps ours on a merge and says when
upstream changed its pictures. Screenshots from a real desktop go in
`manjaro/screenshots/`.

## What differs from upstream

| Where | What |
|---|---|
| `src/brand.{hpp,cpp}` (new), two lines in `src/main.cpp` | With a distribution's name set: a translator that puts "Manjaro" in place of "CachyOS" (and rewrites the few texts that say more than the name); the app's pictures of the CachyOS logo replaced by the logo from the icon theme (`manjarolinux`, from `manjaro-icons`); window icon, desktop file name and settings name |
| `src/alpmdb.cpp` | Which repositories are shown as the distribution's own: all of them on Manjaro (upstream: those starting with `cachyos`, the rest show as "Arch") |
| `src/helper/shared.hpp`, `src/helper/main.cpp` | The mirror ranking program: `pacman-mirrors --no-color --fasttrack 10` |
| `src/transaction.cpp` | An uninstalled build finds its helper by the installed name (one line); without paru, paru itself is built with makepkg (its build dependencies through the helper) and installed through the helper |
| `src/backend.{hpp,cpp}`, `qml/AurDetailsPage.qml`, `qml/Main.qml` | "Install paru" where the repositories have no paru: paru's AUR page, buildable without paru |
| `CMakeLists.txt` | The `PI_*` options; the program, scanner and helper names; the polkit file with its own ids and the admin password asked for outside the login session too (as pamac), since Plasma 6 runs apps outside it; the desktop file; no CachyOS icon or AppStream entry |
| `src/instance.{hpp,cpp}` (new), two hooks in `src/main.cpp` | One window per user; `--updates` opens it (or brings it forward) on the Updates page, for the notifier |
| `screenshots/` | The README's pictures, of the Manjaro build (`tools/screenshots.sh`) |
| `cmake/Manjaro.cmake`, `manjaro/` | The Manjaro settings, the app list (only packages in Manjaro's repositories), its check, the desktop file |
| `MANJARO.md`, `packaging/PKGBUILD`, `tools/test-manjaro.sh` | This file, the package, the container test |

Two QML files get a few lines (the paru case) and no upstream text is edited, so a merge only conflicts where
upstream changes the few lines above. Without `cmake/Manjaro.cmake` the
build is upstream's; the container test builds and tests both.

Known: every sync repository is badged "Manjaro", third-party ones (such
as chaotic-aur) too; the helper's own error messages still start with
`cachyos-pi-helper:`; upstream's helper test checks upstream's mirror
command, the container test checks ours.

Not yet done for Manjaro (next step):
- Upstream's update notice is CachyOS's and stays off here; Manjaro's
  stable-update announcement should be shown before Update all.
- Installing a package does not check that the system is up to date, and
  pacman's lock is not waited for.

## Update notifier

The tray icon and notifications at login are a separate package, built from
CachyOS's update notifier (cachy-update) in its own repository:
[update-notifier-manjaro](https://github.com/solarizeddev/update-notifier-manjaro).
Its click runs `packageinstaller-manjaro --updates`: the app opens on its
Updates page, or its window comes forward if it is open (one window per
user, `src/instance.cpp`). That repository's `tools/test-manjaro.sh` builds
both packages and checks the two together.

## Build

```bash
sudo pacman -S --needed base-devel cmake ninja git qt6-tools vulkan-headers appstream-qt archlinux-appstream-data \
    elfutils kimageformats libjxl manjaro-icons pacman-mirrors qt6-declarative qt6-svg
cmake --fresh -C cmake/Manjaro.cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=ON
cmake --build build && ctest --test-dir build
./build/packageinstaller-manjaro
```

Run from the build directory, package operations use the helper next to
it behind polkit's generic prompt, and the taskbar shows a generic icon
(Wayland takes it from the installed desktop file). `--fresh` matters when
`build/` holds an older configuration: `-C` does not override a cache. Or as a package: `cd packaging && makepkg -sif`
(`-f` builds again after your edits). The first build downloads rapidyaml
and backward-cpp (CPM).

AUR builds need `paru`, which Manjaro does not package. "Install paru" (on
any AUR package's page) opens paru's own AUR page instead: it is reviewed
like any AUR package, its build dependencies (Rust) are installed from the
repositories, it is built from source with makepkg (paru-bin is linked
against Arch's newer libraries) and installed through the helper. From then
on paru builds AUR packages. AUR packages are written for Arch, which is
often ahead of Manjaro stable; the settings page says so.

## Merging an upstream release

```bash
tools/update-upstream.sh
```

It fetches upstream (and adds the `upstream` remote the first time), merges
the newest v2 release tag (`upstream/fresh` until 2.0 is tagged; another ref
can be given), lists new texts that name CachyOS and apps upstream added to
its list (marking those Manjaro's repositories have), checks our app list,
then builds, tests and installs the package with `makepkg -sif`. It does not
push: try the app (install and remove a package, Update all, an AUR page),
then `git push`. `--no-install` stops after the checks.

On conflicts it stops and lists the files; they can only be where our
changes are (the table above, each marked `Manjaro fork` in the code). Keep
upstream's new code, put our lines back, commit, and run it again: it goes on
from that merge. A conflict in README.md is resolved by itself: it is upstream's README under our header (`manjaro/README-header.md`).

A new text that says more than the name (CachyOS's repositories, mirrors or
tools) gets a whole-text entry in `src/brand.cpp`; the name alone is replaced
by itself. `tools/test-manjaro.sh` also builds and tests both configurations
in a clean Manjaro container (needs docker).


## Without the Manjaro logo

```bash
NO_MANJARO_LOGO=1 makepkg -sif        # or: tools/update-upstream.sh --no-logo
```

builds it with a generic icon (`system-software-install` from the icon theme)
in place of the Manjaro logo: window, menu entry, sidebar, banner and password
prompt. The texts keep the Manjaro name. For when Manjaro asks us not to use
the logo; the notifier has the same switch.

## Name and logo

Shown as "Manjaro / Package Installer", window title "Package Installer for
Manjaro", packaged as `packageinstaller-manjaro`. The Manjaro name and logo
are trademarks of Manjaro GmbH & Co. KG. The logo is not copied into this
repository: it is read from the icon theme (`manjaro-icons`), and
`manjaro-…` is how Manjaro names its own packages, so this one does not
start with it.
