#!/bin/bash
# Takes the README's screenshots of the Manjaro build, in place of upstream's
# CachyOS ones (same file names in screenshots/, so README.md stays upstream's):
#   discover.png     the start page
#   details.png      a package with its AppStream screenshots (MuseScore)
#   aur-review.png   an AUR package's review page with the PKGBUILD check (1password)
#   aur-updates.png  the AUR page with two updates (two old stand-in packages)
# Builds this checkout in a Manjaro stable container and drives the app under
# Xvfb (dark theme, 1220x800, no window frame). Needs docker and the network
# (AUR, AppStream screenshot hosts).
# Usage: tools/screenshots.sh [OUTDIR]   (default: screenshots/)
# Behind a TLS-inspecting proxy: TEST_CA=/path/to/ca.pem; TEST_MIRROR=URL.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(mkdir -p "${1:-$root/screenshots}" && cd "${1:-$root/screenshots}" && pwd)
work=$(mktemp -d)
chmod 777 "$work"
trap 'rm -rf "$work"' EXIT
ca=()
[ -n "${TEST_CA:-}" ] && ca=(-v "$TEST_CA:/run/test-ca.pem:ro")

docker run --rm --network host -e HTTPS_PROXY -e HTTP_PROXY -e https_proxy -e http_proxy -e TEST_MIRROR \
    "${ca[@]}" -v "$root:/src:ro" -v "$work:/out" manjarolinux/base:latest bash -c '
set -e
[ -e /run/test-ca.pem ] && { cp /run/test-ca.pem /etc/ca-certificates/trust-source/anchors/test-ca.crt; update-ca-trust; }
[ -n "$TEST_MIRROR" ] && printf "Server = %s\n" "$TEST_MIRROR" >/etc/pacman.d/mirrorlist
pacman -Sy --noconfirm --needed archlinux-keyring manjaro-keyring >/dev/null 2>&1
pacman -Su --noconfirm --needed base-devel cmake ninja git qt6-tools vulkan-headers appstream-qt archlinux-appstream-data \
    elfutils hicolor-icon-theme kimageformats libjxl manjaro-icons pacman-mirrors polkit qt6-base \
    qt6-declarative qt6-svg xorg-server-xvfb xdotool imagemagick noto-fonts ttf-dejavu breeze-icons >/out/deps.log 2>&1
mkdir /tmp/src && tar -C /src --exclude=./build --exclude=./.git -cf - . | tar -C /tmp/src -xf -
cmake -C /tmp/src/cmake/Manjaro.cmake -S /tmp/src -B /tmp/b -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=OFF >/out/cmake.log 2>&1
ninja -C /tmp/b install >/out/build.log 2>&1
useradd -m tester
# two packages "from the AUR" at an old version, for the AUR updates page
for p in yay-bin pacman-cleanup-hook; do
    mkdir -p /tmp/fake/$p
    printf "pkgname=%s\npkgver=0.0.1\npkgrel=1\npkgdesc=x\narch=(any)\npackage() { :; }\n" $p >/tmp/fake/$p/PKGBUILD
done
chown -R tester /tmp/fake
for p in yay-bin pacman-cleanup-hook; do
    su tester -c "cd /tmp/fake/$p && makepkg -f >/dev/null 2>&1"
    pacman -U --noconfirm /tmp/fake/$p/*.pkg.tar.* >/dev/null
done
# AUR on, and paru present as on a system that has it (no install banner)
mkdir -p /home/tester/.config/packageinstaller-manjaro
printf "[aur]\nenabled=true\n" >/home/tester/.config/packageinstaller-manjaro/packageinstaller-manjaro.conf
chown -R tester /home/tester/.config
printf "#!/bin/sh\nexit 0\n" >/usr/local/bin/paru && chmod +x /usr/local/bin/paru

su tester -c "
export DISPLAY=:99 XDG_RUNTIME_DIR=/tmp/xdg; mkdir -p -m 700 \$XDG_RUNTIME_DIR
Xvfb :99 -screen 0 1220x800x24 >/dev/null 2>&1 & sleep 2
packageinstaller-manjaro >/out/run.log 2>&1 & sleep 14
shot() { import -window root /out/\$1.png; }
k() { xdotool \"\$@\"; sleep 1; }
shot discover
# the window opens at its default size at the top left: search field, first result, sidebar
k mousemove 500 33 click 1; k type musescore; sleep 5
k mousemove 480 275 click 1; sleep 40; shot details
k mousemove 500 33 click 1; k key ctrl+a BackSpace; sleep 1
k mousemove 70 290 click 1; sleep 15; shot aur-updates
k mousemove 500 33 click 1; k type 1password; sleep 8
k mousemove 700 192 click 1; sleep 30; shot aur-review
"
'
for f in discover details aur-review aur-updates; do
    cp "$work/$f.png" "$out/$f.png"
done
echo "screenshots in $out: look at each before committing"
