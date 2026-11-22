#!/bin/bash
# After merging an upstream release: build this checkout in a fresh Manjaro
# stable container with the Manjaro settings and with upstream's, run the
# tests, install it, check the installed files and the app list, and start it
# under Xvfb (it must still be running after 15 s; screenshots in OUTDIR).
# Needs docker. Usage: tools/test-manjaro.sh [OUTDIR]
# Behind a TLS-inspecting proxy: TEST_CA=/path/to/ca.pem (added to the
# container's trust store); TEST_MIRROR=URL overrides Manjaro's mirrorlist.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-$(mktemp -d)}
mkdir -p "$out" && chmod 777 "$out"
ca=()
[ -n "${TEST_CA:-}" ] && ca=(-v "$TEST_CA:/run/test-ca.pem:ro")
docker run --rm --network host -e HTTPS_PROXY -e HTTP_PROXY -e https_proxy -e http_proxy -e TEST_MIRROR \
    "${ca[@]}" -v "$root:/src:ro" -v "$out:/out" manjarolinux/base:latest bash -c '
set -e
trap "echo failed at line \$LINENO, logs in the output directory" ERR
[ -e /run/test-ca.pem ] && { cp /run/test-ca.pem /etc/ca-certificates/trust-source/anchors/test-ca.crt; update-ca-trust; }
[ -n "$TEST_MIRROR" ] && printf "Server = %s\n" "$TEST_MIRROR" >/etc/pacman.d/mirrorlist
# an older image lacks keys the packages are now signed with
pacman -Sy --noconfirm --needed archlinux-keyring manjaro-keyring >/out/keyring.log 2>&1
pacman -Su --noconfirm --needed base-devel cmake ninja git qt6-tools vulkan-headers \
    appstream-qt archlinux-appstream-data elfutils hicolor-icon-theme kimageformats libjxl manjaro-icons \
    pacman-mirrors polkit qt6-base qt6-declarative qt6-svg \
    xorg-server-xvfb xdotool imagemagick ttf-dejavu >/out/deps.log 2>&1
useradd -m tester
# a copy: the build must not depend on anything left in the checkout
mkdir /tmp/src && tar -C /src --exclude=./build --exclude=./.git -cf - . | tar -C /tmp/src -xf -
cmake -C /tmp/src/cmake/Manjaro.cmake -S /tmp/src -B /tmp/pi-build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=ON >/out/cmake.log 2>&1
ninja -C /tmp/pi-build >/out/build.log 2>&1
ctest --test-dir /tmp/pi-build --output-on-failure --no-tests=error >/out/ctest.log 2>&1
ninja -C /tmp/pi-build install >/out/install.log 2>&1
# The upstream configuration still builds and passes its tests.
cmake -S /tmp/src -B /tmp/pi-default -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON >/out/cmake-default.log 2>&1
ninja -C /tmp/pi-default >/out/build-default.log 2>&1
ctest --test-dir /tmp/pi-default --output-on-failure --no-tests=error >/out/ctest-default.log 2>&1
for f in /usr/bin/packageinstaller-manjaro /usr/bin/packageinstaller-manjaro-scan \
         /usr/lib/packageinstaller-manjaro/packageinstaller-manjaro-helper \
         /usr/share/applications/packageinstaller-manjaro.desktop \
         /usr/share/polkit-1/actions/org.packageinstaller-manjaro.policy \
         /usr/share/polkit-1/rules.d/49-packageinstaller-manjaro.rules; do
    [ -e "$f" ] || { echo "missing: $f"; exit 1; }
done
for f in /usr/bin/cachyos-pi /usr/share/applications/cachyos-pi.desktop /usr/share/icons/hicolor/256x256/apps/cachyos-pi.png \
         /usr/share/polkit-1/actions/org.cachyos.cachyos-pi.policy /usr/share/metainfo/org.cachyos.cachyos-pi.metainfo.xml; do
    [ ! -e "$f" ] || { echo "installed by mistake: $f"; exit 1; }
done
! grep -qi cachyos /usr/share/applications/packageinstaller-manjaro.desktop || { echo "CachyOS in the desktop file"; exit 1; }
grep -i cachyos /usr/share/polkit-1/actions/org.packageinstaller-manjaro.policy | grep -v vendor_url && { echo "CachyOS in the policy"; exit 1; }
grep -q "/usr/lib/packageinstaller-manjaro/packageinstaller-manjaro-helper" /usr/share/polkit-1/actions/org.packageinstaller-manjaro.policy
strings /usr/lib/packageinstaller-manjaro/packageinstaller-manjaro-helper | grep -qx /usr/bin/pacman-mirrors
strings /usr/lib/packageinstaller-manjaro/packageinstaller-manjaro-helper | grep -qx -- --no-color
/tmp/src/manjaro/check-pkglist.sh
su tester -c "cd; Xvfb :99 -screen 0 1280x860x24 >/dev/null 2>&1 & sleep 2
  DISPLAY=:99 packageinstaller-manjaro >/out/run.log 2>&1 & pid=\$!; sleep 15
  DISPLAY=:99 import -window root /out/start.png
  # the sidebar: the window opens at the top left, at its default size, without a window manager
  DISPLAY=:99 xdotool mousemove 70 284 click 1; sleep 3
  DISPLAY=:99 import -window root /out/aur.png
  DISPLAY=:99 xdotool mousemove 70 738 click 1; sleep 3
  DISPLAY=:99 xdotool mousemove 700 500 click 4 click 4 click 5 click 5 click 5 click 5 click 5 click 5 click 5 click 5 click 5 click 5; sleep 1
  DISPLAY=:99 import -window root /out/settings.png
  kill -0 \$pid"
echo "all checks passed"
'
echo "screenshots: $out/start.png $out/aur.png $out/settings.png"
