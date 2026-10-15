#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
KDIR=${KDIR:-/lib/modules/$(uname -r)/build}
CROSS_COMPILE=${CROSS_COMPILE:-}
KERNEL_RELEASE=$(make -s -C "$KDIR" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" kernelrelease)
[[ -n $KERNEL_RELEASE ]] || { echo '无法读取内核版本' >&2; exit 1; }

RELEASE_DIR="$SOURCE_DIR/releases/$KERNEL_RELEASE/aarch64"
for firmware in wcnmodem.bin wifi_56630001_3ant.ini; do
  [[ -f "$RELEASE_DIR/$firmware" ]] || {
    echo "缺少固件 $RELEASE_DIR/$firmware；请从已验证的发布版本复制，不能跨版本盲用。" >&2
    exit 1
  }
done
make -C "$SOURCE_DIR" KDIR="$KDIR" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" -j"$(nproc)"

modules=(
  unisocwcn/uwe5621_bsp_sdio.ko
  unisocwifi/sprdwl_ng.ko
  tty-sdio/sprdbt_tty.ko
)
for module in "${modules[@]}"; do
  vermagic=$(modinfo -F vermagic "$SOURCE_DIR/$module")
  [[ ${vermagic%% *} == "$KERNEL_RELEASE" ]] || {
    echo "模块 $module 的 vermagic 不匹配: $vermagic" >&2
    exit 1
  }
done

mkdir -p "$RELEASE_DIR"
for module in "${modules[@]}"; do
  install -m 0644 "$SOURCE_DIR/$module" "$RELEASE_DIR/"
done
install -m 0644 "$SOURCE_DIR/dtb/meson-sm1-a95xf3-air_spdif_uwe5621ds_gbit.dtb" "$RELEASE_DIR/"
install -m 0755 "$SOURCE_DIR/install_uwe5621.sh" "$SOURCE_DIR/install_uwe5621_btattach.sh" "$RELEASE_DIR/"
echo "发布目录: $RELEASE_DIR"
