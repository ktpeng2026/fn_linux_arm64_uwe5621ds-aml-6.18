#!/usr/bin/env bash
set -euo pipefail

SERVICE=uwe5621-bluetooth.service

if (( EUID != 0 )); then
  echo "请用 sudo bash $0 执行" >&2
  exit 1
fi

for command in systemctl modprobe; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "缺少命令: $command" >&2
    exit 1
  }
done

packages=()
command -v btattach >/dev/null 2>&1 || packages+=(bluez)
command -v rfkill >/dev/null 2>&1 || packages+=(rfkill)
if (( ${#packages[@]} )); then
  command -v apt-get >/dev/null 2>&1 || {
    echo "请先安装缺失的软件包: ${packages[*]}（系统没有 apt-get）" >&2
    exit 1
  }
  echo "安装缺失的软件包: ${packages[*]}"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
fi

BTATTACH=$(command -v btattach)
RFKILL=$(command -v rfkill)
MODPROBE=$(command -v modprobe)

cat >"/etc/systemd/system/$SERVICE" <<EOF
[Unit]
Description=UWE5621 Bluetooth HCI over SDIO
After=systemd-modules-load.service
Before=bluetooth.service

[Service]
Type=simple
ExecStartPre=$MODPROBE sprdbt_tty
ExecStartPre=/bin/sh -c 'for attempt in \$(seq 1 30); do test -e /dev/ttyBT0 && exit 0; sleep 1; done; exit 1'
ExecStartPre=$RFKILL unblock bluetooth
ExecStart=$BTATTACH -B /dev/ttyBT0 -P h4 -S 115200
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "$SERVICE"
echo "已安装并启动 $SERVICE；重启后也会自动启动。"
echo "查看状态: systemctl status $SERVICE"
echo "查看日志: journalctl -u $SERVICE -b --no-pager"
