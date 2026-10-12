#!/bin/sh
# Installs a Linux build of Perch for this user, from a release build (./scripts/linux/build.sh release, run where Swift
# is). Needs no Swift: the binary carries its runtime. Needs GTK 4 and WebKitGTK 6.0 (Ubuntu: libwebkitgtk-6.0-4).
#   ./scripts/linux/install.sh            install or update, and start it
#   ./scripts/linux/install.sh --remove   stop it and remove everything it installed (your settings stay)
set -e
cd "$(dirname "$0")/../.."
share="$HOME/.local/share/perch" bin="$HOME/.local/bin" apps="$HOME/.local/share/applications"
icon="$HOME/.local/share/icons/hicolor/256x256/apps/perch.png" autostart="$HOME/.config/autostart/perch.desktop"

stop() { pkill -x perch 2>/dev/null || true; pkill -x PerchLinux 2>/dev/null || true; }

if [ "$1" = "--remove" ]; then
  stop
  rm -rf "$share" "$bin/perch" "$apps/perch.desktop" "$icon" "$autostart"
  echo "Perch removed. Its hooks stay until you turn Live status off first (or run: perch --uninstall-hooks before removing)."
  exit 0
fi

build=.build/release/PerchLinux
[ -x "$build" ] || build=.build/debug/PerchLinux
[ -x "$build" ] || { echo "No build found. Run ./scripts/linux/build.sh release where Swift is installed."; exit 1; }
if ! ldconfig -p | grep -q libwebkitgtk-6.0.so.4; then
  echo "WebKitGTK 6.0 is missing. On Ubuntu: sudo apt install libwebkitgtk-6.0-4"; exit 1
fi

stop
mkdir -p "$share/ui/dist/fonts" "$bin" "$apps" "$(dirname "$icon")"
cp "$build" "$share/perch.new" && mv "$share/perch.new" "$share/perch"
cp ui/index.html ui/app.js ui/orbs.js "$share/ui/"
cp ui/dist/ui.css "$share/ui/dist/"
cp ui/dist/fonts/* "$share/ui/dist/fonts/"
cp docs/assets/icon.png "$icon"
ln -sf "$share/perch" "$bin/perch"
cat > "$apps/perch.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Perch
Comment=Where you left off with your coding agents
Exec=$share/perch
Icon=perch
Categories=Development;Utility;
StartupNotify=false
EOF
# Launch at login is Perch's own setting (Settings): an earlier install's entry is pointed at this copy.
[ -f "$autostart" ] && sed -i "s|^Exec=.*|Exec=$share/perch|" "$autostart"

(nohup "$share/perch" >/dev/null 2>&1 &)
echo "Perch installed in $share and started. Open it with the shortcut, or from the tray."
