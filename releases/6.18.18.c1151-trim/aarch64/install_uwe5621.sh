#!/usr/bin/env bash
set -Eeuo pipefail

PROGRAM_NAME=${0##*/}
KERNEL_RELEASE=$(uname -r)
BASE_URL=${UWE5621_BASE_URL:-https://raw.githubusercontent.com/ktpeng2026/uwe5621ds-aml-6.18/main}
SOURCE_DIR=${UWE5621_SOURCE_DIR:-}
ARCHITECTURE=aarch64
RELEASE_PATH=releases/${KERNEL_RELEASE}/${ARCHITECTURE}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DTB_TARGET=${UWE5621_DTB_TARGET:-}
DTB_NAME=meson-sm1-a95xf3-air_spdif_uwe5621ds_gbit.dtb
ORIGINAL_DTB_NAME=meson-sm1-a95xf3-air-gbit.dtb
MODULE_DIR=/lib/modules/${KERNEL_RELEASE}/extra/uwe5621
FIRMWARE_DIR=/lib/firmware/uwe5621
WIFI_INI_DIR=/lib/firmware
BACKUP_TAG=$(date +%Y%m%d-%H%M%S)
WORK_DIR=
INSTALL_MAC_FILE=0

MODULES=(
  uwe5621_bsp_sdio.ko
  sprdwl_ng.ko
  sprdbt_tty.ko
)

usage() {
  cat <<EOF
Usage:
  sudo ./${PROGRAM_NAME} [--dtb-target PATH]
  sudo ./${PROGRAM_NAME} --url URL [--dtb-target PATH]
  sudo ./${PROGRAM_NAME} --source-dir DIR [--dtb-target PATH] [--install-mac-file]

Options:
  --url URL            Repository raw URL. Defaults to the ktpeng2026 GitHub repo.
  --source-dir DIR     Repository checkout or releases/<kernel>/aarch64 directory.
  --dtb-target PATH    Existing boot DTB path to replace. Auto-detected when omitted.
  --install-mac-file   Install unisoc_wifi_mac.txt if it exists in the source.
  -h, --help           Show this help.

Required source files:
  ${RELEASE_PATH}/{${DTB_NAME},uwe5621_bsp_sdio.ko,sprdwl_ng.ko,sprdbt_tty.ko,wcnmodem.bin,wifi_56630001_3ant.ini}

Optional source file:
  ${RELEASE_PATH}/unisoc_wifi_mac.txt

Default installation:
  sudo ./${PROGRAM_NAME} --dtb-target /boot/dtb/amlogic/${ORIGINAL_DTB_NAME}
EOF
}

log() {
  printf '[uwe5621] %s\n' "$*"
}

die() {
  printf '[uwe5621] ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n ${WORK_DIR} && -d ${WORK_DIR} ]]; then
    rm -rf "${WORK_DIR}"
  fi
}
trap cleanup EXIT

while (($#)); do
  case "$1" in
    --url)
      (($# >= 2)) || die "--url requires a value"
      BASE_URL=${2%/}
      shift 2
      ;;
    --source-dir)
      (($# >= 2)) || die "--source-dir requires a value"
      SOURCE_DIR=$2
      shift 2
      ;;
    --dtb-target)
      (($# >= 2)) || die "--dtb-target requires a value"
      DTB_TARGET=$2
      shift 2
      ;;
    --install-mac-file)
      INSTALL_MAC_FILE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[[ ${EUID} -eq 0 ]] || die "run this script as root"
[[ $(uname -m) == ${ARCHITECTURE} ]] || die "this release requires ${ARCHITECTURE}, got $(uname -m)"

if [[ -z ${SOURCE_DIR} ]]; then
  if [[ -f ${SCRIPT_DIR}/${RELEASE_PATH}/${DTB_NAME} ]]; then
    SOURCE_DIR=${SCRIPT_DIR}/${RELEASE_PATH}
  elif [[ -f ${SCRIPT_DIR}/${DTB_NAME} ]]; then
    SOURCE_DIR=${SCRIPT_DIR}
  fi
elif [[ -d ${SOURCE_DIR}/${RELEASE_PATH} ]]; then
  SOURCE_DIR=${SOURCE_DIR}/${RELEASE_PATH}
fi

WORK_DIR=$(mktemp -d /tmp/uwe5621-install.XXXXXX)

fetch_file() {
  local remote_path=$1
  local output_name=$2
  local required=${3:-1}
  local destination=${WORK_DIR}/${output_name}

  if [[ -n ${SOURCE_DIR} ]]; then
    if [[ ! -f ${SOURCE_DIR}/${remote_path} ]]; then
      [[ ${required} -eq 0 ]] && return 1
      die "missing source file: ${SOURCE_DIR}/${remote_path}"
    fi
    cp -f "${SOURCE_DIR}/${remote_path}" "${destination}"
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    if ! curl --fail --location --silent --show-error \
      "${BASE_URL}/${RELEASE_PATH}/${remote_path}" -o "${destination}"; then
      [[ ${required} -eq 0 ]] && return 1
      die "failed to download ${BASE_URL}/${RELEASE_PATH}/${remote_path}"
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget -q "${BASE_URL}/${RELEASE_PATH}/${remote_path}" -O "${destination}"; then
      [[ ${required} -eq 0 ]] && return 1
      die "failed to download ${BASE_URL}/${RELEASE_PATH}/${remote_path}"
    fi
  else
    die "curl or wget is required"
  fi
}

backup_and_install() {
  local source=$1
  local destination=$2
  local mode=$3

  install -d "$(dirname "${destination}")"
  if [[ -e ${destination} ]]; then
    cp -a "${destination}" "${destination}.bak.${BACKUP_TAG}"
    log "backup: ${destination}.bak.${BACKUP_TAG}"
  fi
  install -m "${mode}" "${source}" "${destination}"
  log "installed: ${destination}"
}

detect_dtb_target() {
  local matches=()

  while IFS= read -r path; do
    matches+=("${path}")
  done < <(find /boot -type f \
    \( -name "${DTB_NAME}" -o -name "${ORIGINAL_DTB_NAME}" \) \
    2>/dev/null | sort)

  if ((${#matches[@]} == 1)); then
    DTB_TARGET=${matches[0]}
    return
  fi
  if ((${#matches[@]} > 1)); then
    printf '[uwe5621] Multiple DTB targets found:\n' >&2
    printf '  %s\n' "${matches[@]}" >&2
    die "rerun with --dtb-target PATH"
  fi
  die "cannot find a supported board DTB under /boot; rerun with --dtb-target PATH"
}

log "kernel: ${KERNEL_RELEASE}"
log "collecting installation files"

fetch_file "${DTB_NAME}" "${DTB_NAME}"
for module in "${MODULES[@]}"; do
  fetch_file "${module}" "${module}"
done
fetch_file wcnmodem.bin wcnmodem.bin
fetch_file wifi_56630001_3ant.ini wifi_56630001_3ant.ini
if [[ ${INSTALL_MAC_FILE} -eq 1 ]]; then
  fetch_file unisoc_wifi_mac.txt unisoc_wifi_mac.txt 0 || \
    die "--install-mac-file requested but unisoc_wifi_mac.txt is unavailable"
fi

for module in "${MODULES[@]}"; do
  vermagic=$(modinfo -F vermagic "${WORK_DIR}/${module}" 2>/dev/null || true)
  [[ -n ${vermagic} ]] || die "cannot read vermagic from ${module}"
  if [[ ${vermagic%% *} != "${KERNEL_RELEASE}" ]]; then
    die "${module} was built for '${vermagic%% *}', target kernel is '${KERNEL_RELEASE}'"
  fi
done

[[ -n ${DTB_TARGET} ]] || detect_dtb_target
[[ -f ${DTB_TARGET} ]] || die "DTB target does not exist: ${DTB_TARGET}"

log "installing DTB to ${DTB_TARGET}"
backup_and_install "${WORK_DIR}/${DTB_NAME}" "${DTB_TARGET}" 0644

log "installing kernel modules"
install -d -m 0755 "${MODULE_DIR}"
for module in "${MODULES[@]}"; do
  backup_and_install "${WORK_DIR}/${module}" "${MODULE_DIR}/${module}" 0644
done

log "installing firmware"
backup_and_install "${WORK_DIR}/wcnmodem.bin" \
  "${FIRMWARE_DIR}/wcnmodem.bin" 0644
backup_and_install "${WORK_DIR}/wifi_56630001_3ant.ini" \
  "${WIFI_INI_DIR}/wifi_56630001_3ant.ini" 0644
if [[ ${INSTALL_MAC_FILE} -eq 1 ]]; then
  backup_and_install "${WORK_DIR}/unisoc_wifi_mac.txt" \
    /lib/firmware/unisoc_wifi_mac.txt 0644
fi

cat >/etc/modules-load.d/uwe5621.conf <<'EOF'
uwe5621_bsp_sdio
sprdwl_ng
sprdbt_tty
EOF

install -d -m 0755 /etc/NetworkManager/conf.d
cat >/etc/NetworkManager/conf.d/uwe5621-powersave.conf <<'EOF'
[connection]
wifi.powersave=2
EOF

depmod -a "${KERNEL_RELEASE}"

if command -v systemctl >/dev/null 2>&1; then
  BTATTACH=$(command -v btattach || true)
  RFKILL=$(command -v rfkill || true)
  [[ -n ${BTATTACH} ]] || die "btattach is required for Bluetooth auto-start (install bluez)"
  [[ -n ${RFKILL} ]] || die "rfkill is required for Bluetooth auto-start"

  cat >/etc/systemd/system/uwe5621-bluetooth.service <<EOF
[Unit]
Description=UWE5621 Bluetooth HCI over SDIO
After=systemd-modules-load.service dev-ttyBT0.device
Requires=dev-ttyBT0.device
Before=bluetooth.service

[Service]
Type=simple
ExecStartPre=${RFKILL} unblock bluetooth
ExecStart=${BTATTACH} -B /dev/ttyBT0 -P h4 -S 115200
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable uwe5621-bluetooth.service
  log "Bluetooth auto-start enabled (uwe5621-bluetooth.service)"
else
  log "systemd not found; start btattach manually after reboot"
fi

log "installation complete"
log "DTB backup suffix: .bak.${BACKUP_TAG}"
log "reboot the machine to activate the new DTB and modules"
