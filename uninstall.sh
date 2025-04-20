#!/bin/bash

# Detect if we are running as root
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
else
  SUDO=""
fi

# Check if sudo is available
if ! command -v sudo &>/dev/null; then
  SUDO=""
  echo "[*] 'sudo' command not found, running as root."
fi

# Remove the XMRig binary and configuration
echo "[*] Removing XMRig binary..."
$SUDO rm -f /usr/local/bin/xmrig

echo "[*] Removing XMRig configuration..."
$SUDO rm -f /etc/xmrig.conf

# Remove the systemd service if it was created
if [ -f /etc/systemd/system/xmrig.service ]; then
  echo "[*] Removing systemd service..."
  $SUDO systemctl stop xmrig
  $SUDO systemctl disable xmrig
  $SUDO rm -f /etc/systemd/system/xmrig.service
  $SUDO systemctl daemon-reload
fi

# Remove the init.d or rc.local entry if it was used
if [ -f /etc/rc.local ]; then
  echo "[*] Removing rc.local entry..."
  $SUDO sed -i '/xmrig/d' /etc/rc.local
fi

# Remove the downloaded files and extracted directories
echo "[*] Cleaning up..."
rm -rf /tmp/xmrig.tar.gz /tmp/xmrig

# Final message
echo "[+] XMRig has been uninstalled successfully!"
