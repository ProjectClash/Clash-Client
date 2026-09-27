<p align="center">
  <img src="https://clash.md/brand/clash-app-icon.png" width="128" height="128" alt="Clash">
</p>

# Clash

English · [简体中文](README.zh-CN.md)

[![Website](https://img.shields.io/badge/Website-Official-2563EB)](https://clash.md/)
[![App Store Download](https://img.shields.io/badge/App_Store-Download-black?logo=apple&logoColor=white)](https://apps.apple.com/app/id6794257189)
[![Telegram Channel](https://img.shields.io/badge/Telegram-Channel-26A5E4?logo=telegram&logoColor=white)](https://t.me/clashbyhako)
[![Telegram Group](https://img.shields.io/badge/Telegram-Group-26A5E4?logo=telegram&logoColor=white)](https://t.me/+t__WNRvjUbk3M2Nl)

**A native, rule-based proxy client for iPhone, iPad, Mac and Apple TV, powered by the [Clash core](https://github.com/ProjectClash/Clash).**

Use the App Store link to install the official app. The build notes below apply after the source and dependencies have been migrated.

## Repository migration status

This is the new client repository under **Project Clash**. This first publication contains the English and Chinese READMEs. Client source, extensions, resources, dependency locks, build scripts and license files will follow.

The build notes use the Clash project paths and scheme names planned for the source migration. They apply after that rename is complete and the source and dependencies are available here.

## About this repository

The source to be migrated includes the Apple applications, their extensions, shared libraries and resources needed to build them. The [Clash core](https://github.com/ProjectClash/Clash) has its own repository. Kernel and Adapter source locations and pinned revisions will be recorded in `Dependencies.lock.json` with the source publication.

| Directory | Contents |
| --- | --- |
| `apple/ClashClient` | Platform applications, extensions and XcodeGen project specification |
| `apple/ClashClientKit` | Shared configuration and profile models |
| `apple/ClashClientUI` | Shared interface components |
| `apple/ClashMacClient` | macOS components |

The existing source distribution is pre-release. The App Store app version and a source checkout are separate artifacts; once the source is available here, pin a revision when reproducing a build.

The iOS and macOS projects wrap the static Core in a shared framework, with the required header-copy build step included in project generation. Available features depend on the pinned Kernel and Adapter revisions; the iOS/tvOS SDK does not include EasyTier.

## Build from source (after source and dependency migration)

### Requirements

- macOS with Xcode 27.0 and the iOS, macOS and tvOS SDKs.
- XcodeGen and Git available on your command path.
- Go with automatic toolchain selection enabled, or the Go 1.26.6 toolchain selected by the pinned kernel's binding module.
- Python 3 with PyYAML.

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

The first bootstrap fetches the pinned public Kernel and Adapter sources, installs the pinned gomobile tools and builds the five-slice SDK. It requires network access and can take several minutes. The configure step generates the Xcode project.

Open `apple/ClashClient/ClashClient.xcodeproj` and choose a scheme:

| Platform | Scheme |
| --- | --- |
| iPhone / iPad | `ClashClient` |
| Apple TV | `ClashTV` |
| Mac | `ClashMac` |

For an unsigned iOS Simulator build:

```sh
xcodebuild -project apple/ClashClient/ClashClient.xcodeproj \
  -scheme ClashClient -configuration Release \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

### Sign your own build

Set your own bundle identifier family and Apple Developer Team ID:

```sh
python3 scripts/configure.py --bundle-base org.yourname.clash --team YOURTEAMID
```

Configure signing and capabilities for the app and its extensions in Xcode, including Network Extensions, App Groups and any iCloud capabilities you use. Certificates and provisioning profiles are not included. An unsigned build checks compilation; installing on a device requires your own signing setup.

## Feedback

Report app problems in [Issues](https://github.com/ProjectClash/Clash-Client/issues). Include the platform and OS version, app version or source revision, reproduction steps, and expected versus actual behavior. Share only the configuration and logs needed to reproduce the problem, with credentials and subscription links removed.

Kernel issues can be reported in [Clash core Issues](https://github.com/ProjectClash/Clash/issues). Packet bridge and provider lifecycle issues can be reported in this client repository during the migration.

## License

The project source uses [GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.html). License files and third-party resource notices will accompany the source migration.
