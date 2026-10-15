# UWE5621 / fnOS ARM64 / Linux 6.18.18

本目录包含 Amlogic SM1 板卡使用的 UWE5621 SDIO Wi-Fi、蓝牙驱动及部署文件。可重复安装的发布包归档于 `releases/<uname -r>/aarch64/`；当前已归档 `releases/6.18.18.c1151-trim/aarch64/`。预编译的 DTB 和 KO **仅适用于相应的板卡和内核构建**；不要仅凭内核主版本相同就安装到其他机器。

## 文件说明

| 路径 | 用途 |
| --- | --- |
| `releases/<uname -r>/aarch64/` | 对应内核的 DTB、三个 KO、两个固件文件及两个安装脚本，文件直接放在此目录 |
| `dtb/meson-sm1-a95xf3-air_spdif_uwe5621ds_gbit.dts` | 板卡设备树源文件；已编译 DTB 也保存在 `dtb/` |
| `build.sh` | 编译 KO 并整理到对应发布目录，**不会在构建主机安装模块** |
| `install_uwe5621.sh` | 一次安装 DTB、KO、固件并配置开机加载；发布目录内也有副本 |
| `install_uwe5621_btattach.sh` | **仅**安装并启动蓝牙 `btattach` 服务；发布目录内也有副本 |

## 完整安装（目标 fnOS 机器）

先确认机器的板卡型号、当前内核和实际启动的 DTB。安装脚本会检查 KO 的 `vermagic` 是否与 `uname -r` 一致，但**不能**验证板卡硬件或内核 ABI 完全兼容。建议保留可用的旧 DTB 和其他恢复启动的途径。

```sh
uname -r
find /boot -type f -name '*a95xf3*dtb'
modinfo -F vermagic "releases/$(uname -r)/aarch64/uwe5621_bsp_sdio.ko"
```

将对应 `releases/<uname -r>/aarch64/` 目录复制到目标机，在该发布目录运行（把 DTB 路径改成该机器**实际启动使用**的文件）：

```sh
sudo apt-get update
sudo apt-get install -y bluez rfkill
sudo bash ./install_uwe5621.sh \
  --source-dir "$PWD" \
  --dtb-target /boot/dtb/amlogic/meson-sm1-a95xf3-air-gbit.dtb
sudo reboot
```

脚本在发布目录内运行时可省略 `--source-dir`；在仓库根目录运行时也会优先使用本地匹配版本的发布目录。若没有本地文件，则从仓库 `main` 分支的 GitHub raw 地址下载 `releases/$(uname -r)/aarch64/` 的文件，需要 `curl` 或 `wget` 及网络连接。若 `/boot` 下有多个候选 DTB，必须明确指定 `--dtb-target`。**不要在没有确认启动路径的情况下猜测 DTB 目标。**

脚本会安装模块到 `/lib/modules/$(uname -r)/extra/uwe5621/`，固件到 `/lib/firmware/uwe5621/wcnmodem.bin`，配置到 `/lib/firmware/wifi_56630001_3ant.ini`，并设置模块开机加载、禁用 NetworkManager 的 Wi-Fi 省电及启用蓝牙 `uwe5621-bluetooth.service`。已有的 DTB、KO 和固件会生成带时间戳的 `.bak.*` 备份。完整安装脚本**不会自动安装** `bluez`/`rfkill`，请先执行上面的 apt 命令。

## 只安装蓝牙服务

如果 DTB、KO、固件和 Wi-Fi 已经正常，只缺开机自动注册 `hci0`，在目标机上仅运行：

```sh
sudo bash ./install_uwe5621_btattach.sh
systemctl status uwe5621-bluetooth.service
bluetoothctl list
```

该脚本在缺少 `btattach` 或 `rfkill` 时，通过 `apt-get` 安装对应的 `bluez`、`rfkill` 包，需要可用的软件源；随后加载 `sprdbt_tty`、等待 `/dev/ttyBT0`、解除 rfkill，并启动和启用服务。它**不安装** DTB、KO 或固件，前提是 `sprdbt_tty` 模块已安装且设备节点可以生成。运行前先退出手动启动的 `btattach`，避免重复占用设备。

蓝牙数据路径是 SDIO → `sprdbt_tty` → `/dev/ttyBT0` → `btattach` → `hci0`。DTS 中的 `sprd,mtty` 节点只负责 TTY 设备，不会单独注册 `hci0`。

## `uwe5621-bluetooth.service` 服务

服务文件位于 `/etc/systemd/system/uwe5621-bluetooth.service`。它负责持续运行 `btattach -B /dev/ttyBT0 -P h4 -S 115200`，让内核注册蓝牙控制器 `hci0`；`bluetooth.service` 则是 BlueZ 的蓝牙管理服务，两者不是同一个服务。**只启动 `bluetooth.service`，不会替代 `btattach`。**

- 完整安装脚本在依赖已安装时创建并**启用开机自启**，但不会立即启动 `uwe5621-bluetooth.service`；按前述步骤重启后生效。
- 独立脚本创建服务并执行 `systemctl enable --now`，会**立即启动且开机自启**。
- 服务启动前需要已安装的 `sprdbt_tty.ko`、能出现的 `/dev/ttyBT0`、`btattach` 和 `rfkill`。独立脚本会加载模块并等待节点最多约 30 秒；完整安装依靠模块开机加载及设备节点依赖。
- `btattach` 进程需要保持运行；手动测试时不要同时让服务和另一个 `btattach` 占用 `/dev/ttyBT0`。

```sh
sudo systemctl start uwe5621-bluetooth.service    # 完整安装后不重启，手动启动
systemctl is-enabled uwe5621-bluetooth.service    # 查看是否开机自启
systemctl status uwe5621-bluetooth.service        # 查看运行状态
journalctl -u uwe5621-bluetooth.service -b --no-pager
sudo systemctl restart uwe5621-bluetooth.service  # 重新连接 TTY
sudo systemctl stop uwe5621-bluetooth.service     # 停止 btattach
```

若服务不断重启，先检查 `/dev/ttyBT0` 是否存在、`modprobe sprdbt_tty` 是否成功、是否有手动运行的 `btattach`，再查看上述日志；服务运行成功后用 `bluetoothctl list` 确认控制器已注册。

## 验证及排查

```sh
lsmod | grep -E 'uwe5621_bsp_sdio|sprdwl_ng|sprdbt_tty'
ip link show wlan0
ls -l /dev/ttyBT0
systemctl status uwe5621-bluetooth.service
journalctl -u uwe5621-bluetooth.service -b --no-pager
rfkill list bluetooth
bluetoothctl list
dmesg | grep -E 'sdiohal|WCN|sprdwl|mtty|Bluetooth'
```

如果 `bluetoothctl list` 为空，优先检查 `sprdbt_tty` 是否加载、`/dev/ttyBT0` 是否出现、`btattach` 服务日志及 rfkill 状态。单纯有 `/dev/ttyBT0` 不等于已经注册 `hci0`。

## 从源码编译：通用前提

以下命令针对使用 apt 的 Debian/Ubuntu 类环境；fnOS 软件源中的包名或可用性以实际系统为准。**最重要的依赖不是 apt 包，而是目标机器实际运行内核的匹配构建目录**：内核配置、源码/补丁、生成文件和 `Module.symvers` 应来自同一次内核构建，且必须启用模块支持。对于定制内核 `6.18.18.c1151-trim`，发行版的通用 `linux-headers-*` 不一定匹配。仅执行 `modules_prepare` 不会生成 `Module.symvers`；启用符号版本校验的内核尤其需要匹配的符号表。

### 目标 ARM64 本机编译

在目标机安装基础构建工具（编译本驱动通常不需要交叉编译器；后面的 `bc`、`bison` 等主要供准备/构建内核树使用）：

```sh
sudo apt-get update
sudo apt-get install -y build-essential make gcc binutils kmod \
  bc bison flex libssl-dev libelf-dev dwarves rsync
```

若系统仓库提供与 **`uname -r` 完全一致**的头文件，可安装：

```sh
sudo apt-get install "linux-headers-$(uname -r)"
```

若找不到该包，应从目标内核的实际源码/构建产物取得匹配的 `KDIR`，不要安装其他版本的头文件硬凑。编译前确认：

```sh
KDIR=/lib/modules/"$(uname -r)"/build
test -f "$KDIR/Makefile" && test -f "$KDIR/.config" && test -f "$KDIR/Module.symvers"
KDIR="$KDIR" bash ./build.sh
modinfo -F vermagic unisocwcn/uwe5621_bsp_sdio.ko
```

如果构建目录不是 `/lib/modules/$(uname -r)/build`，将 `KDIR` 改为对应的内核构建目录。`build.sh` 仅编译并归档，不安装/加载模块；运行前需在对应发布目录中准备 `wcnmodem.bin` 和 `wifi_56630001_3ant.ini`。

### x86_64 主机交叉编译 ARM64

在 x86_64 Debian/Ubuntu 主机上安装基础工具和 GNU ARM64 交叉工具链：

```sh
sudo apt-get update
sudo apt-get install -y build-essential make gcc binutils kmod \
  bc bison flex libssl-dev libelf-dev dwarves rsync \
  gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
```

另从**目标 fnOS 内核同一构建**取得 ARM64 内核树/构建输出（包括 `.config`、生成头文件和 `Module.symvers`），而不是使用 x86_64 主机的 `/lib/modules/$(uname -r)/build`。如果内核是用 `O=` 分离输出构建的，`KDIR` 应指向对应的已准备构建输出目录：

```sh
KDIR=/path/to/target-arm64-kernel-build
test -f "$KDIR/Makefile" && test -f "$KDIR/.config" && test -f "$KDIR/Module.symvers"
command -v aarch64-linux-gnu-gcc
KDIR="$KDIR" CROSS_COMPILE=aarch64-linux-gnu- bash ./build.sh
modinfo -F vermagic unisocwcn/uwe5621_bsp_sdio.ko
```

`build.sh` 根据目标内核构建目录的 `kernelrelease` 生成 `releases/<kernelrelease>/aarch64/`，拷贝编译好的三个 KO、板卡 DTB 及两个安装脚本；固件需预先放入同一发布目录，脚本不会凭空生成或跨版本复制固件。构建后可把整个目录存档或复制到目标机，直接运行其中的 `install_uwe5621.sh`，无需再次编译。核对每个 KO 的 `vermagic`、目标架构和目标内核后再加载。
