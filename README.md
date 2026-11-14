<p align="center">
  <img src="https://clash.md/brand/clash-app-icon.png" width="128" height="128" alt="Clash">
</p>

# Clash Client for Apple Platforms

English · [简体中文](README.zh-CN.md)

[![Website](https://img.shields.io/badge/Website-Official-2563EB)](https://clash.md/)
[![App Store Download](https://img.shields.io/badge/App_Store-Download-black?logo=apple&logoColor=white)](https://apps.apple.com/app/id6794257189)
[![Telegram Channel](https://img.shields.io/badge/Telegram-Channel-26A5E4?logo=telegram&logoColor=white)](https://t.me/clashbyclash)
[![Telegram Group](https://img.shields.io/badge/Telegram-Group-26A5E4?logo=telegram&logoColor=white)](https://t.me/+t__WNRvjUbk3M2Nl)

A native, rule-based proxy client for iPhone, iPad, Mac and Apple TV, powered by the Clash kernel.

Use the App Store link to install the official app. The instructions below are for building from source.

## About this repository

This repository contains the Apple applications, their extensions, shared libraries and resources needed to build them. The [Clash kernel](https://github.com/ProjectClash/Clash) and [Adapter components](https://github.com/ProjectClash/Clash-Adapter) are maintained in separate repositories; their source revisions are pinned in [`Dependencies.lock.json`](Dependencies.lock.json).

| Directory | Contents |
| --- | --- |
| `apple/ClashClient` | Platform applications, extensions and XcodeGen project specification |
| `apple/ClashClientKit` | Shared configuration and profile models |
| `apple/ClashClientUI` | Shared interface components |
| `apple/ClashMacClient` | macOS components |
| `cli` | Terminal helper bundled with the Mac app, including its embedded usage guide |

## Versions and dependencies

Client source is currently published by commit, without a separate release tag. App Store versions are managed separately for each platform; the kernel's `1.19.34` is not the Client app version. Pin a Client revision to reproduce a build, and keep its dependency lock unchanged.

The latest accepted product builds corresponding to this source are:

| Platform | Version | Build |
| --- | --- | --- |
| iOS / iPadOS | 1.0.13 | 133 |
| macOS | 1.0.15 | 100 |
| tvOS | 1.0.16 | 49 |

These identify the product builds; availability on the App Store and TestFlight may differ. For a source build, set the app version and build number in Xcode for the platform you are building.

| Dependency | Pinned source or tool version |
| --- | --- |
| [Clash Kernel](https://github.com/ProjectClash/Clash) | [`c8f2fc1d5`](https://github.com/ProjectClash/Clash/commit/c8f2fc1d58bf9ac856a0bf161bc9489591821f45), built from source |
| [Clash Adapter](https://github.com/ProjectClash/Clash-Adapter) | [`9ba5c2724`](https://github.com/ProjectClash/Clash-Adapter/commit/9ba5c2724b68c753d57496c1036f4dfb1587e482) |
| Swift Certificates / Crypto / ASN.1 | **1.9.0 / 3.15.1 / 1.7.3**, pinned in the XcodeGen project |
| gomobile / gobind | `github.com/sagernet/gomobile` **v0.1.13** |

[`Dependencies.lock.json`](Dependencies.lock.json) is the source of truth for these pins. The bootstrap uses the pinned public source; it does not select the latest release automatically.

The iOS and macOS projects wrap the static Core in a shared framework, with the required header-copy build step included in project generation. Available features depend on the pinned Kernel and Adapter revisions; the iOS/tvOS SDK does not include EasyTier.

## Build from source

### Requirements

- macOS with Xcode 27.0 or later and the iOS, macOS and tvOS SDKs.
- XcodeGen and Git available on your command path.
- Go with automatic toolchain selection enabled, or the Go 1.26.11 toolchain selected by the pinned kernel's binding module.
- Python 3 with PyYAML.
- Deployment targets: iOS/iPadOS 15+, macOS 13+ and tvOS 17+, as declared in [`project.yml`](apple/ClashClient/project.yml).

Use the full Xcode installation as your active developer directory. If needed, set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for a standard installation.

### Prepare the project

```sh
git clone https://github.com/ProjectClash/Clash-Client.git
cd Clash-Client
python3 -m venv .build/python-env
source .build/python-env/bin/activate
python3 -m pip install PyYAML
python3 scripts/bootstrap.py
python3 scripts/configure.py
```

The first bootstrap fetches the pinned public Kernel and Adapter sources, installs the pinned gomobile tools and builds the five-slice SDK from source. It requires network access and can take several minutes; it does not download a prebuilt Release archive. Subsequent runs reuse the SDK only after its saved file inventory and source provenance pass verification. The configure step generates the Xcode project and builds the universal macOS terminal helper, including when you intend to build an iOS or tvOS scheme. Run it again after changing your bundle identifiers.

Open `apple/ClashClient/ClashClient.xcodeproj` and choose a scheme:

| Platform | Scheme |
| --- | --- |
| iPhone / iPad | `ClashiOS` |
| Apple TV | `ClashtvOS` |
| Mac | `ClashmacOS` |

Unsigned Release compilation commands:

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

### Sign your own build

Set your own bundle identifier family and Apple Developer Team ID:

```sh
python3 scripts/configure.py --bundle-base org.yourname.clash --team YOURTEAMID
```

Configure signing and capabilities for the app and its extensions in Xcode, including Network Extensions, App Groups and any iCloud capabilities you use. Certificates and provisioning profiles are not included. An unsigned build checks compilation; installing on a device requires your own signing setup.

## Feedback

Report app problems in [Issues](https://github.com/ProjectClash/Clash-Client/issues). Include the platform and OS version, app version or source revision, reproduction steps, and expected versus actual behavior. Share only the configuration and logs needed to reproduce the problem, with credentials and subscription links removed.

Kernel issues can be reported in [Clash](https://github.com/ProjectClash/Clash/issues); packet bridge and provider lifecycle issues belong in [Clash-Adapter](https://github.com/ProjectClash/Clash-Adapter/issues).

## License

[GPL-3.0](LICENSE). Third-party resource licenses remain with their resources.
