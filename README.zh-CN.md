<p align="center">
  <img src="https://clash.md/brand/clash-app-icon.png" width="128" height="128" alt="Clash">
</p>

# Clash

[English](README.md) · 简体中文

[![官方网站](https://img.shields.io/badge/%E5%AE%98%E7%BD%91-%E8%AE%BF%E9%97%AE-2563EB)](https://clash.md/)
[![App Store 下载](https://img.shields.io/badge/App_Store-%E4%B8%8B%E8%BD%BD-black?logo=apple&logoColor=white)](https://apps.apple.com/app/id6794257189)
[![Telegram 频道](https://img.shields.io/badge/Telegram-%E9%A2%91%E9%81%93-26A5E4?logo=telegram&logoColor=white)](https://t.me/clashbyhako)
[![Telegram 交流群](https://img.shields.io/badge/Telegram-%E4%BA%A4%E6%B5%81%E7%BE%A4-26A5E4?logo=telegram&logoColor=white)](https://t.me/+t__WNRvjUbk3M2Nl)

**面向 iPhone、iPad、Mac 和 Apple TV 的原生规则代理客户端，由 [Clash 内核](https://github.com/ProjectClash/Clash)驱动。**

安装官方应用请使用 App Store 链接。以下技术说明面向需要从源码构建的开发者，待源码与依赖同步后适用。

## 仓库迁移状态

本仓库是 **Project Clash** 组织下的客户端新仓库。本次先发布中英文 README，客户端源码、扩展、资源、依赖锁定文件、构建脚本及许可证文件将后续同步。

构建说明统一使用 Clash 工程路径与构建方案名，待源码完成配套改名、验证并同步后适用。

## 关于本仓库

待同步的源码包括 Apple 各平台应用、扩展、共享库及构建所需资源。[Clash 内核](https://github.com/ProjectClash/Clash)位于独立仓库。内核和 Adapter 组件的依赖地址及固定提交，将随源码记录在 `Dependencies.lock.json` 中。

| 目录 | 内容 |
| --- | --- |
| `apple/ClashClient` | 各平台应用、扩展与 XcodeGen 工程配置 |
| `apple/ClashClientKit` | 共享配置与档案模型 |
| `apple/ClashClientUI` | 共享界面组件 |
| `apple/ClashMacClient` | macOS 组件 |

既有源码分发处于预发布阶段。App Store 应用版本与源码检出分别管理；源码同步后，复现构建时请固定具体提交。

iOS 和 macOS 工程通过共享框架封装静态 Core；工程生成时会保留所需的头文件复制步骤。客户端使用的能力以所固定的 Kernel 和 Adapter 提交为准；iOS/tvOS 的 SDK 不包含 EasyTier。

## 从源码构建（源码与依赖同步后）

### 环境要求

- macOS、Xcode 27.0，以及 iOS、macOS、tvOS SDK。
- 可在命令行使用的 XcodeGen 和 Git。
- 启用自动工具链选择的 Go，或安装固定内核绑定模块所选择的 Go 1.26.6 工具链。
- Python 3 和 PyYAML。

### 准备工程

```sh
git clone https://github.com/ProjectClash/Clash-Client.git
cd Clash-Client
python3 -m venv .build/python-env
source .build/python-env/bin/activate
python3 -m pip install PyYAML
python3 scripts/bootstrap.py
python3 scripts/configure.py
```

首次准备依赖时会获取固定提交的公开内核与 Adapter 源码，安装固定版本的 gomobile 工具，并构建五切片 SDK。此过程需要网络，可能耗时数分钟。配置脚本随后生成 Xcode 工程。

打开 `apple/ClashClient/ClashClient.xcodeproj`，选择相应构建方案：

| 平台 | 构建方案 |
| --- | --- |
| iPhone / iPad | `ClashClient` |
| Apple TV | `ClashTV` |
| Mac | `ClashMac` |

不签名编译 iOS 模拟器版本：

```sh
xcodebuild -project apple/ClashClient/ClashClient.xcodeproj \
  -scheme ClashClient -configuration Release \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

### 签名自己的构建

设置自己的 Bundle ID 前缀与 Apple Developer Team ID：

```sh
python3 scripts/configure.py --bundle-base org.yourname.clash --team YOURTEAMID
```

在 Xcode 中为应用和扩展配置签名与所需能力，包括 Network Extensions、App Groups，以及实际使用的 iCloud 能力。仓库不包含证书或描述文件。无签名构建只验证编译；真机安装需要自己的签名配置。

## 问题反馈

应用问题请提交到 [Issues](https://github.com/ProjectClash/Clash-Client/issues)，注明平台与系统版本、应用版本或源码提交、复现步骤，以及预期和实际行为。只分享复现所需的配置与日志，并移除凭据和订阅链接。

内核问题可提交到 [Clash 内核 Issues](https://github.com/ProjectClash/Clash/issues)。数据包桥接与扩展生命周期相关问题，可先在本仓库反馈。

## 许可证

项目源码采用 [GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.html)。许可证文件与第三方资源声明将随源码同步。
