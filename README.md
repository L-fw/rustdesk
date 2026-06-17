<p align="center">
  <img src="res/logo-header.svg" alt="LinkEase - 你的远程桌面"><br>
  <a href="#项目简介">简介</a> •
  <a href="#windows-端构建">Windows 构建</a> •
  <a href="#android-端构建">Android 构建</a> •
  <a href="#android-权限说明">权限</a> •
  <a href="#项目结构">结构</a>
</p>

> [!Caution]
> **免责声明：** <br>
> 本应用仅供合法、正当的远程协助用途（如个人设备管理、IT 技术支持等）。您只能在获得设备所有者**明确同意**的前提下发起远程连接或操控。严禁用于未经授权的访问、监控、控制，或任何违反法律法规的行为，由此产生的一切后果由使用者自行承担。

## 项目简介

**LinkEase** 是佳影寰球科技有限公司基于开源项目 [RustDesk](https://github.com/rustdesk/rustdesk) 二次开发的远程桌面解决方案，使用 Rust 编写，开箱即用，无需复杂配置。数据完全由你掌控，可使用自建的 rendezvous/relay 服务器，安全可靠。

核心功能：

- **远程屏幕查看**：实时查看被控设备的屏幕画面
- **远程操控**：在获得对方授权后，对被控设备进行触控/键鼠模拟操作
- **点对点 / 中继连接**：通过网络在两台设备间建立加密通信通道

本仓库仅维护 **Windows 桌面端** 与 **Android 移动端** 两个平台，UI 全部基于 Flutter 实现（已弃用旧版 Sciter UI）。

> 账号服务由独立的后端服务提供，详见 `D:\git_rustdesk\server`（Node + SQLite）。

## 环境依赖

通用依赖：

- [Rust](https://www.rust-lang.org/tools/install) 开发环境
- [Python 3](https://www.python.org/)（用于运行 `build.py` 构建脚本）
- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- [vcpkg](https://github.com/microsoft/vcpkg)，并正确设置 `VCPKG_ROOT` 环境变量
- C++ 构建工具链

通过 vcpkg 安装 C++ 依赖（`libvpx`、`libyuv`、`opus`、`aom`）：

```sh
vcpkg install libvpx:x64-windows-static libyuv:x64-windows-static opus:x64-windows-static aom:x64-windows-static
```

## Windows 端构建

1. 安装上述环境依赖，确认 `VCPKG_ROOT` 已正确配置。

2. 构建并运行 Flutter 桌面版：

   ```sh
   python build.py --flutter
   ```

3. 发布版（release）构建：

   ```sh
   python build.py --flutter --release
   ```

常用可选参数：

- `--hwcodec`  启用硬件编解码（推荐，可显著降低 CPU 占用）
- `--vram`     启用 VRAM 优化（仅 Windows 可用）
- `--portable` 生成 Windows 便携版
- `--skip-portable-pack` 跳过打包，仅生成 Flutter + Windows 程序

示例（带硬件编解码的发布版）：

```sh
python build.py --flutter --release --hwcodec
```

> 仅需快速调试 Rust 核心、使用旧版 Sciter UI 时，可执行 `cargo run`，但需自行下载 [sciter.dll](https://raw.githubusercontent.com/c-smile/sciter-sdk/master/bin.win/x64/sciter.dll) 并放入可执行文件目录。日常开发请优先使用 Flutter 版。

## Android 端构建

Android 端复用 Rust 核心 + Flutter UI。构建分为两步：先编译 Rust 原生依赖，再打包 APK。

1. 准备 Android SDK / NDK，并安装好 Flutter SDK。

2. 编译 Android 端 Rust 原生库依赖：

   ```sh
   cd flutter
   ./build_android_deps.sh
   ```

3. 构建 APK：

   ```sh
   ./build_android.sh
   ```

   或直接使用 Flutter 命令：

   ```sh
   cd flutter
   flutter build apk        # 构建发布 APK
   flutter run              # 连接设备进行调试运行
   ```

> F-Droid 版本可使用 `flutter/build_fdroid.sh` 进行构建。

## Android 权限说明

本应用在 Android 设备上可能申请以下权限，以实现相应功能；仅在使用相关功能时请求，且可随时在设备设置中撤销：

| 权限 | 用途 |
| --- | --- |
| 🌐 网络访问 | 建立远程连接 |
| ♿ 无障碍服务 | 在被控制端模拟触控与键盘操作 |
| 🪟 悬浮窗 | 显示远程控制操作工具栏 |
| 📹 屏幕录制 | 在被控制端采集屏幕画面 |

> 应用不收集姓名、手机号等个人身份信息，也不收集位置信息或设备中的私人文件（除非您主动在会话中共享）。详见应用内《隐私政策》（`privacy_policy.html`）与《用户协议》（`terms_of_service.html`）。

## 测试

- Rust 测试：

  ```sh
  cargo test
  ```

- Flutter 测试：

  ```sh
  cd flutter
  flutter test
  ```

## 项目结构

- **[libs/hbb_common](libs/hbb_common)**：视频编解码、配置、TCP/UDP 封装、protobuf、文件传输等通用工具函数
- **[libs/scrap](libs/scrap)**：屏幕采集
- **[libs/enigo](libs/enigo)**：平台相关的键鼠控制
- **[libs/clipboard](libs/clipboard)**：跨平台剪贴板与文件复制粘贴实现
- **[src/server](src/server)**：音频/剪贴板/输入/视频服务及网络连接
- **[src/client.rs](src/client.rs)**：发起对端连接
- **[src/rendezvous_mediator.rs](src/rendezvous_mediator.rs)**：与 [rustdesk-server](https://github.com/rustdesk/rustdesk-server) 通信，等待直连（TCP 打洞）或中继连接
- **[src/platform](src/platform)**：平台相关代码
- **[src/ui](src/ui)**：旧版 Sciter UI（已弃用）
- **[flutter](flutter)**：桌面端与移动端的 Flutter 代码
  - **[flutter/lib/desktop](flutter/lib/desktop)**：Windows 桌面端 UI
  - **[flutter/lib/mobile](flutter/lib/mobile)**：Android 移动端 UI
  - **[flutter/lib/common](flutter/lib/common)**、**[flutter/lib/models](flutter/lib/models)**：共享代码

## 配置说明

所有配置项位于 [libs/hbb_common/src/config.rs](libs/hbb_common/src/config.rs)，分为 4 类：

- Settings（设置）
- Local（本地）
- Display（显示）
- Built-in（内置）

## 开源许可

本应用基于 [RustDesk](https://github.com/rustdesk/rustdesk)（版权归属 RustDesk, Inc.）二次开发，遵循 **GNU AGPL-3.0** 许可证发布。

- 原始项目：https://github.com/rustdesk/rustdesk
- 修改版源码：https://github.com/L-fw/rustdesk

依据 AGPL-3.0 协议，您有权获取、使用及修改上述源代码。

## 联系我们

- 公司：佳影寰球科技有限公司
- 应用：LinkEase
- 官网：[jygamwing.com](https://jygamwing.com/)

---

© 2026 佳影寰球科技有限公司 版权所有
