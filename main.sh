#!/bin/bash

# Configuration
WALLET="428AUvZzo4gPQENPyuTUGSjHCTSRB7YrjgZ7uAJNjC5GT2G6wc32ewC4n5yrMv3q2Rj8FwxPt99ovYJ7GqrpPdczKgaDoqJ"
POOL="xmr-eu1.nanopool.org:10343"  # NanoPool EU server (SSL port)
CPU_USAGE=95                        # 95% CPU usage

# Generate unique worker name (IP + CPU model + RAM)
IP=$(hostname -I | awk '{print $1}' | tr -d '.')
CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | awk -F': ' '{print $2}' | cut -d' ' -f1-2 | tr -d ' ')
RAM_GB=$(free -g | awk '/Mem:/ {print $2}')
WORKER_NAME="nano-${IP}-${CPU_MODEL}-${RAM_GB}GB"

echo "[*] Generated worker name: $WORKER_NAME"

# Detect package manager
if command -v apt >/dev/null; then
  PKG_MGR="apt"
elif command -v dnf >/dev/null; then
  PKG_MGR="dnf"
elif command -v yum >/dev/null; then
  PKG_MGR="yum"
elif command -v pacman >/dev/null; then
  PKG_MGR="pacman"
else
  echo "[-] Error: Unsupported package manager"
  exit 1
fi

# Install dependencies
echo "[*] Installing dependencies ($PKG_MGR)..."
case $PKG_MGR in
  "apt")
    sudo apt update && sudo apt install -y git build-essential cmake libuv1-dev libssl-dev libhwloc-dev
    ;;
  "dnf"|"yum")
    sudo $PKG_MGR install -y git cmake gcc gcc-c++ libuv-devel openssl-devel hwloc-devel
    ;;
  "pacman")
    sudo pacman -Sy --noconfirm git cmake gcc libuv openssl hwloc
    ;;
esac

# Clone & compile XMRig
echo "[*] Downloading and compiling XMRig..."
git clone https://github.com/xmrig/xmrig.git /tmp/xmrig
mkdir /tmp/xmrig/build
cd /tmp/xmrig/build
cmake .. -DCMAKE_BUILD_TYPE=Release -DWITH_OPENCL=OFF -DWITH_CUDA=OFF
make -j$(nproc)

# Install binary globally
sudo mv xmrig /usr/local/bin/
cd ~
rm -rf /tmp/xmrig

# NanoPool-specific config (with SSL/TLS)
echo "[*] Generating NanoPool config file..."
sudo tee /etc/xmrig.conf <<EOF
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

# Systemd service (highest priority)
echo "[*] Setting up systemd service..."
sudo tee /etc/systemd/system/xmrig.service <<EOF
[Unit]
Description=XMRig NanoPool Miner
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/xmrig -c /etc/xmrig.conf
Restart=always
Nice=-20
CPUWeight=100
OOMScoreAdjust=-1000

[Install]
WantedBy=multi-user.target
EOF

# Enable service
echo "[*] Starting miner..."
sudo systemctl daemon-reload
sudo systemctl enable xmrig
sudo systemctl start xmrig

# Verify
echo "[*] Checking status..."
sleep 5
sudo systemctl status xmrig --no-pager

# Final instructions
echo -e "\n[+] XMRig configured for NanoPool!"
echo -e "[+] Worker: $WORKER_NAME"
echo -e "[+] Wallet: $WALLET"
echo -e "[+] Pool: $POOL (SSL enabled)"
echo -e "[+] CPU Limit: ${CPU_USAGE}%"
echo -e "[+] Stats: https://xmr.nanopool.org/stats/$WALLET"
echo -e "[+] Stop: sudo systemctl stop xmrig"
echo -e "[+] Adjust CPU: edit /etc/xmrig.conf\n"
