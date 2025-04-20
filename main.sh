#!/bin/bash

# Configuration
WALLET="428AUvZzo4gPQENPyuTUGSjHCTSRB7YrjgZ7uAJNjC5GT2G6wc32ewC4n5yrMv3q2Rj8FwxPt99ovYJ7GqrpPdczKgaDoqJ"
POOL="xmr-eu1.nanopool.org:10343"
CPU_USAGE=95

# Detect if we are running as root
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
else
  SUDO=""
fi

# Generate unique worker name from hostname and padded IP
HOSTNAME=$(hostname)
IP=$(hostname -I | awk '{print $1}')
PADDED_IP=$(echo "$IP" | awk -F. '{printf "%03d.%03d.%03d.%03d", $1,$2,$3,$4}')
WORKER_NAME="${HOSTNAME}-${PADDED_IP}"

echo "[*] Worker name: $WORKER_NAME"

# Detect package manager
if command -v apt &>/dev/null; then
  PKG_MGR="apt"
elif command -v dnf &>/dev/null; then
  PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
  PKG_MGR="yum"
elif command -v pacman &>/dev/null; then
  PKG_MGR="pacman"
elif command -v zypper &>/dev/null; then
  PKG_MGR="zypper"
else
  PKG_MGR=""
fi

# Install runtime dependencies
echo "[*] Installing dependencies..."
case $PKG_MGR in
  "apt")
    $SUDO apt update && $SUDO apt install -y libhwloc-dev libssl-dev wget tar
    ;;
  "dnf"|"yum")
    $SUDO $PKG_MGR install -y hwloc openssl wget tar
    ;;
  "pacman")
    $SUDO pacman -Sy --noconfirm hwloc openssl wget tar
    ;;
  "zypper")
    $SUDO zypper install -y hwloc openssl wget tar
    ;;
  *)
    echo "[!] Could not detect package manager. Please ensure 'wget', 'tar', 'libssl', and 'libhwloc' are installed."
    ;;
esac

# Check if sudo is available and install if necessary
if ! command -v sudo &>/dev/null && [ "$SUDO" != "" ]; then
  echo "[*] Installing sudo..."
  if [ "$PKG_MGR" == "apt" ]; then
    apt install -y sudo
  elif [ "$PKG_MGR" == "dnf" ] || [ "$PKG_MGR" == "yum" ]; then
    $PKG_MGR install -y sudo
  elif [ "$PKG_MGR" == "pacman" ]; then
    pacman -Sy --noconfirm sudo
  elif [ "$PKG_MGR" == "zypper" ]; then
    zypper install -y sudo
  fi
fi

# Download and install XMRig
echo "[*] Downloading XMRig precompiled binary..."
cd /tmp
wget -q https://github.com/xmrig/xmrig/releases/latest/download/xmrig-*-linux-x64.tar.gz -O xmrig.tar.gz

# Verify if the tarball was downloaded properly (check file size)
if [ ! -s xmrig.tar.gz ]; then
  echo "[!] Error: Failed to download valid tarball. Exiting."
  exit 1
fi

# Extract the tarball
tar -xzf xmrig.tar.gz
XMRIG_DIR=$(tar -tf xmrig.tar.gz | head -1 | cut -f1 -d"/")
$SUDO mv "$XMRIG_DIR/xmrig" /usr/local/bin/
rm -rf xmrig.tar.gz "$XMRIG_DIR"

# Generate config
echo "[*] Creating config..."
$SUDO tee /etc/xmrig.conf >/dev/null <<EOF
{
  "autosave": true,
  "cpu": {
    "enabled": true,
    "huge-pages": true,
    "hw-aes": true,
    "priority": null,
    "max-threads-hint": $CPU_USAGE
  },
  "opencl": false,
  "cuda": false,
  "pools": [
    {
      "coin": "monero",
      "algo": "rx/0",
      "url": "$POOL",
      "user": "$WALLET.$WORKER_NAME",
      "pass": "x",
      "tls": true,
      "keepalive": true,
      "nicehash": false
    }
  ]
}
EOF

# Service Setup
echo "[*] Detecting init system..."
if pidof systemd &>/dev/null; then
  echo "[*] systemd detected - creating systemd service"
  $SUDO tee /etc/systemd/system/xmrig.service >/dev/null <<EOF
[Unit]
Description=XMRig NanoPool Miner
After=network.target

[Service]
ExecStart=/usr/local/bin/xmrig -c /etc/xmrig.conf
Restart=always
Nice=-20
CPUWeight=100
OOMScoreAdjust=-1000

[Install]
WantedBy=multi-user.target
EOF
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable xmrig
  $SUDO systemctl start xmrig

elif [ -f /etc/init.d/cron ] || [ -d /etc/init.d ]; then
  echo "[*] init.d detected - using /etc/rc.local fallback"
  if [ -f /etc/rc.local ]; then
    $SUDO sed -i '/xmrig/d' /etc/rc.local
  else
    echo "#!/bin/bash" | $SUDO tee /etc/rc.local >/dev/null
  fi
  echo "/usr/local/bin/xmrig -c /etc/xmrig.conf &" | $SUDO tee -a /etc/rc.local >/dev/null
  $SUDO chmod +x /etc/rc.local
  $SUDO /etc/rc.local

else
  echo "[!] No service manager detected, running miner in background using nohup..."
  nohup /usr/local/bin/xmrig -c /etc/xmrig.conf >/dev/null 2>&1 &
fi

# Final messages
echo -e "\n[+] XMRig configured successfully!"
echo -e "[+] Worker: $WORKER_NAME"
echo -e "[+] Wallet: $WALLET"
echo -e "[+] Pool: $POOL (SSL enabled)"
echo -e "[+] CPU Limit: ${CPU_USAGE}%"
echo -e "[+] Stats: https://xmr.nanopool.org/stats/$WALLET\n"
