#!/bin/bash

# Configuration
WALLET="428AUvZzo4gPQENPyuTUGSjHCTSRB7YrjgZ7uAJNjC5GT2G6wc32ewC4n5yrMv3q2Rj8FwxPt99ovYJ7GqrpPdczKgaDoqJ"
POOL="xmr.2miners.com:2222"  # 2Miners XMR pool
CPU_USAGE=95                 # 95% CPU usage (adjust if needed)

# Generate unique worker name (IP + CPU model + RAM)
IP=$(hostname -I | awk '{print $1}' | tr -d '.')
CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | awk -F': ' '{print $2}' | cut -d' ' -f1-2 | tr -d ' ')
RAM_GB=$(free -g | awk '/Mem:/ {print $2}')
WORKER_NAME="worker-${IP}-${CPU_MODEL}-${RAM_GB}GB"

echo "[*] Generated worker name: $WORKER_NAME"

# Detect package manager (cross-distro support)
if command -v apt >/dev/null; then
  PKG_MGR="apt"
elif command -v dnf >/dev/null; then
  PKG_MGR="dnf"
elif command -v yum >/dev/null; then
  PKG_MGR="yum"
elif command -v pacman >/dev/null; then
  PKG_MGR="pacman"
else
  echo "[-] Error: Unsupported package manager. Exiting."
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

# Create config file (95% CPU usage)
echo "[*] Generating config file..."
sudo tee /etc/xmrig.conf <<EOF
{
  "autosave": true,
  "cpu": {
    "enabled": true,
    "huge-pages": true,
    "hw-aes": true,
    "priority": null,
    "max-threads-hint": $CPU_USAGE  # 95% CPU usage
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
      "tls": false,
      "keepalive": true,
      "nicehash": false
    }
  ]
}
EOF

# Create systemd service (highest priority)
echo "[*] Setting up systemd service (highest priority)..."
sudo tee /etc/systemd/system/xmrig.service <<EOF
[Unit]
Description=XMRig Monero Miner (High Power)
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/xmrig -c /etc/xmrig.conf
Restart=always
Nice=-20           # Highest priority (range: -20 to 19)
CPUWeight=100      # Max CPU allocation
OOMScoreAdjust=-1000  # Prevent OOM killer

[Install]
WantedBy=multi-user.target
EOF

# Enable & start service
echo "[*] Starting XMRig miner..."
sudo systemctl daemon-reload
sudo systemctl enable xmrig
sudo systemctl start xmrig

# Check status
echo "[*] Checking miner status..."
sleep 5
sudo systemctl status xmrig --no-pager

# Final instructions
echo -e "\n[+] XMRig installed and running at MAX PRIORITY!"
echo -e "[+] Worker Name: $WORKER_NAME"
echo -e "[+] CPU Usage: $CPU_USAGE% (adjust in /etc/xmrig.conf)"
echo -e "[+] Pool: $POOL"
echo -e "[+] Check stats: https://2miners.com/xmr-miners"
echo -e "[+] To stop: sudo systemctl stop xmrig"
echo -e "[+] To adjust CPU: edit 'max-threads-hint' in /etc/xmrig.conf\n"
