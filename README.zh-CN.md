<p align="center">
  <img src="https://clash.md/brand/clash-app-icon.png" width="128" height="128" alt="Clash">
</p>

# Clash Apple 客户端

[English](README.md) · 简体中文

[![官方网站](https://img.shields.io/badge/%E5%AE%98%E7%BD%91-%E8%AE%BF%E9%97%AE-2563EB)](https://clash.md/)
[![App Store 下载](https://img.shields.io/badge/App_Store-%E4%B8%8B%E8%BD%BD-black?logo=apple&logoColor=white)](https://apps.apple.com/app/id6794257189)
[![Telegram 频道](https://img.shields.io/badge/Telegram-%E9%A2%91%E9%81%93-26A5E4?logo=telegram&logoColor=white)](https://t.me/clashbyclash)
[![Telegram 交流群](https://img.shields.io/badge/Telegram-%E4%BA%A4%E6%B5%81%E7%BE%A4-26A5E4?logo=telegram&logoColor=white)](https://t.me/+t__WNRvjUbk3M2Nl)

基于 Clash 内核的原生规则代理客户端，适用于 iPhone、iPad、Mac 和 Apple TV。

安装官方应用请使用 App Store 链接。以下说明面向需要从源码构建的开发者。

## 关于本仓库

本仓库包含 Apple 各平台应用、扩展、共享库及构建所需资源。[Clash 内核](https://github.com/ProjectClash/Clash)和 [Adapter 组件](https://github.com/ProjectClash/Clash-Adapter)位于独立仓库，依赖源码提交固定在 [`Dependencies.lock.json`](Dependencies.lock.json) 中。

| 目录 | 内容 |
| --- | --- |
| `apple/ClashClient` | 各平台应用、扩展与 XcodeGen 工程配置 |
| `apple/ClashClientKit` | 共享配置与档案模型 |
| `apple/ClashClientUI` | 共享界面组件 |
| `apple/ClashMacClient` | macOS 组件 |
| `cli` | Mac 应用内置终端工具及编译所需的使用说明 |

## 版本与依赖

客户端源码目前按提交发布，尚无独立发行标签。各平台的 App Store 版本分别管理，内核的 `1.19.34` 不是客户端应用版本。复现构建时请固定 Client 提交，并保持该提交的依赖锁不变。

本次源码对应的最近验收产品构建：

| 平台 | 版本 | 构建号 |
| --- | --- | --- |
| iOS / iPadOS | 1.0.13 | 133 |
| macOS | 1.0.15 | 100 |
| tvOS | 1.0.16 | 49 |

这些是产品构建版本，App Store 与 TestFlight 的可用版本可能不同。自行构建时，请在 Xcode 中为目标平台设置应用版本和构建号。

| 依赖 | 固定源码或工具版本 |
| --- | --- |
| [Clash 内核](https://github.com/ProjectClash/Clash) | [`c8f2fc1d5`](https://github.com/ProjectClash/Clash/commit/c8f2fc1d58bf9ac856a0bf161bc9489591821f45)，从源码构建 |
| [Clash Adapter](https://github.com/ProjectClash/Clash-Adapter) | [`9ba5c2724`](https://github.com/ProjectClash/Clash-Adapter/commit/9ba5c2724b68c753d57496c1036f4dfb1587e482) |
| Swift Certificates / Crypto / ASN.1 | **1.9.0 / 3.15.1 / 1.7.3**，固定在 XcodeGen 工程中 |
| gomobile / gobind | `github.com/sagernet/gomobile` **v0.1.13** |

上述固定值以 [`Dependencies.lock.json`](Dependencies.lock.json) 为准。依赖准备脚本使用锁定的公开源码，不会自动选择最新发行版。

iOS 和 macOS 工程通过共享框架封装静态 Core；工程生成时会保留所需的头文件复制步骤。客户端使用的能力以所固定的 Kernel 和 Adapter 提交为准；iOS/tvOS 的 SDK 不包含 EasyTier。

## 从源码构建

### 环境要求

- macOS、Xcode 27.0 或更新版本，以及 iOS、macOS、tvOS SDK。
- 可在命令行使用的 XcodeGen 和 Git。
- 启用自动工具链选择的 Go，或安装固定内核绑定模块所选择的 Go 1.26.11 工具链。
- Python 3 和 PyYAML。
- 部署目标为 iOS/iPadOS 15+、macOS 13+ 和 tvOS 17+，以 [`project.yml`](apple/ClashClient/project.yml) 为准。

请将完整 Xcode 设为当前开发工具目录。安装在标准路径时，可按需设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

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

首次准备依赖时会获取固定提交的公开内核与 Adapter 源码，安装固定版本的 gomobile 工具，并从源码构建五切片 SDK；不会下载发行版中的预编译压缩包。此过程需要网络，可能耗时数分钟。后续只有在保存的文件清单和源码来源校验通过时才复用 SDK。配置脚本随后生成 Xcode 工程，并构建 macOS 通用终端工具，即使你接下来只打算编译 iOS 或 tvOS。修改应用标识后需重新运行配置脚本。

打开 `apple/ClashClient/ClashClient.xcodeproj`，选择相应构建方案：

| 平台 | 构建方案 |
| --- | --- |
| iPhone / iPad | `ClashiOS` |
| Apple TV | `ClashtvOS` |
| Mac | `ClashmacOS` |

各平台无签名 Release 编译命令：

```sh
xcodebuild -project apple/ClashClient/ClashClient.xcodeproj \
  -scheme ClashiOS -configuration Release \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

xcodebuild -project apple/ClashClient/ClashClient.xcodeproj \
  -scheme ClashtvOS -configuration Release \
  -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO build

xcodebuild -project apple/ClashClient/ClashClient.xcodeproj \
  -scheme ClashmacOS -configuration Release \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

### 签名自己的构建

设置自己的 Bundle ID 前缀与 Apple Developer Team ID：

```sh
python3 scripts/configure.py --bundle-base org.yourname.clash --team YOURTEAMID
```

在 Xcode 中为应用和扩展配置签名与所需能力，包括 Network Extensions、App Groups，以及实际使用的 iCloud 能力。仓库不包含证书或描述文件。无签名构建只验证编译；真机安装需要自己的签名配置。

## 问题反馈

应用问题请提交到 [Issues](https://github.com/ProjectClash/Clash-Client/issues)，注明平台与系统版本、应用版本或源码提交、复现步骤，以及预期和实际行为。只分享复现所需的配置与日志，并移除凭据和订阅链接。

内核问题可提交到 [Clash](https://github.com/ProjectClash/Clash/issues)，数据包桥接与扩展生命周期问题请提交到 [Clash-Adapter](https://github.com/ProjectClash/Clash-Adapter/issues)。

## 许可证

[GPL-3.0](LICENSE)。第三方资源的许可证随资源保留。
