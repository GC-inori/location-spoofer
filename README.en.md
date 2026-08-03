<div align="center">

# 📍 Location Spoofer

### iOS Location Spoofer · DingTalk · WeChat · Apple Watch Region Unlock · Fake GPS

**No VPN, no jailbreak — run a local HTTP proxy on your iPhone to rewrite Apple location responses.**<br>
Works with DingTalk check-in, WeChat location sharing, and any app that uses system location. Map selection, real-time location, environment verification, certificate setup, and runtime logs in a single app.

[![iOS 15+](https://img.shields.io/badge/iOS-15%2B-111111?logo=apple)](project.yml)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](project.yml)
[![Go 1.23+](https://img.shields.io/badge/Go-1.23%2B-00ADD8?logo=go&logoColor=white)](Core/go.mod)
[![Version](https://img.shields.io/badge/version-v1.0.0-2563EB)](docs/CHANGELOG.md)
[![No VPN](https://img.shields.io/badge/VPN-Not%20needed-16A34A)](#why-no-vpn)

[Features](#key-features) · [Quick Start](#quick-start) · [中文](README.md) · [Changelog](docs/CHANGELOG.md)

<img src="images/主界面.jpg" alt="Location Spoofer iOS Fake GPS main interface" width="380">

</div>

> [!IMPORTANT]
> This project is intended for education, security research, and testing on your own devices. It installs a locally generated CA certificate and requires a manual HTTP proxy on the current Wi‑Fi network. Please understand the risks and follow applicable laws and service terms.

## Credits

The core location-response rewriting approach and Go implementation are based on [Yu9191/wloc](https://github.com/Yu9191/wloc). This project adds a SwiftUI interface, MapKit selection, certificate and proxy guidance, environment verification, favorites, and diagnostics.

## Why Location Spoofer?

Unlike tools that require a computer to stay connected, a VPN tunnel, or a jailbroken device, Location Spoofer keeps the control flow on the iPhone itself.

| Feature | Description |
|---|---|
| 🚫 **No VPN** | No VPN tunnel — uses only location permission, no background refresh or notification access required. |
| 📱 **No jailbreak** | Can be installed through self-signing; minimum deployment target is iOS 15. |
| 🗺️ **Native Maps experience** | The same blue dot and selection gestures as Apple Maps — search, tap, and drag. |
| 📍 **System-level location spoofing** | Works with DingTalk, WeChat, Apple Maps, Amap, and other apps for real-time fake GPS. |
| 🔍 **Visible map scale** | Left-side controls show the current visible range; place name adapts to zoom level. |
| 🧪 **Environment verification** | Checks proxy, CA trust, Wi‑Fi interception, coordinate write, and response rewrite. |
| 🧾 **Diagnostics** | Per-entry copy for easy sharing and debugging. |

## Screenshots

| Main Interface | Apple Maps | Amap | Apple Watch |
|---|---|---|---|
| ![Location Spoofer main interface](images/主界面.jpg) | ![Apple Maps result](images/Apple%20Map.jpg) | ![Amap result](images/高德地图.jpg) | ![Apple Watch region feature](images/高血压.jpg) |

## Key Features

- **iOS Location Spoofer / Fake GPS**: Apply the selected coordinate to the local proxy that rewrites location responses, compatible with DingTalk check-in, WeChat location sharing, and more.
- **Native real-time location**: The map displays MapKit's own blue dot — no extra "fake real-time" overlay.
- **Concurrency-safe selection**: Pan, tap, search, favorites, and async location respect the user's latest intent; stale results won't overwrite newer selections.
- **Hierarchical place names**: POI, street, or road at close zoom; neighborhood, district, city, or province at wider zoom.
- **Map scale display**: Zoom controls show the current visible range.
- **Favorites with quick switch**: Save frequent coordinates and see which location is about to be applied.
- **Setup guide**: Certificate download, installation, full trust, Wi‑Fi HTTP proxy, activation, and deactivation instructions.
- **Built-in diagnostics**: Verification flow and structured runtime logs.

## Quick Start

### 1. Install the App

- Download a build from [Releases](https://github.com/xweiba/location-spoofer/releases) and self-sign; or
- Build from source on macOS with Xcode — see the [build guide](docs/BUILD.md).

Detailed steps in the [self-signing guide](docs/SELF-SIGNING.md).

### 2. Install & Trust the CA

Follow the first-setup wizard to download the profile, then:

```text
Settings → General → VPN & Device Management → install WLOC CA
Settings → General → About → Certificate Trust Settings → enable full trust
```

### 3. Configure the Current Wi‑Fi Proxy

On the current Wi‑Fi's proxy settings, choose "Manual":

```text
Server: 127.0.0.1
Port: 8888
Authentication: off
```

### 4. Select a Location & Enable

1. Search, tap, or drag the map to pick a location; tap the real-time location button to jump to the MapKit blue dot.
2. Tap "Start Spoofing" and wait for the environment check to pass.
3. Follow the in‑app activation instructions to refresh airplane mode, Wi‑Fi, and location services.
4. Open Apple Maps or your target app to verify.

### 5. Restore Your Real Location

Stop spoofing, remove the manual proxy from the current Wi‑Fi, and follow the in‑app deactivation instructions to refresh the system location cache. If stale cache persists, restart your device.

## Why No VPN?

```text
iPhone location request
        │ Wi‑Fi HTTP proxy: 127.0.0.1:8888
        ▼
Local wloccore Go proxy
        │ Handles only the targeted Apple location-service traffic
        ▼
Apple location service response
        │ The selected coordinate is written into the response
        ▼
The system and applications receive the modified result
```

The project does not use Network Extension to create a VPN tunnel — there is no VPN icon and no VPN slot occupied. **However, you still need to configure the current Wi‑Fi HTTP proxy and install & trust the locally generated CA.** Re‑check proxy settings after switching Wi‑Fi networks; remove the manual proxy when you stop using the app.

## Compatibility

| Item | Requirement |
|---|---|
| iOS | 15.0+ |
| Build | macOS, Xcode, XcodeGen |
| Swift | 5.9 |
| Go | 1.23+ |
| Network | Wi‑Fi with manual HTTP proxy support |
| Installation | Self-sign or use release builds |

Actual behavior may vary with iOS version, network conditions, system location cache, device model, and the target app's own location strategy. Compatibility with every iOS version or third-party app is not guaranteed.

## Build & Project Structure

```bash
./build.sh
```

The unsigned IPA is at:

```text
dist/PaopaoLocationSpoofer-unsigned.ipa
```

```text
App/        SwiftUI, MapKit, location and setup flow
Core/       Go local proxy and location response rewriting
Shared/     Favorites, settings, logs, and shared models
Resources/  Info.plist, Entitlements, and icons
Scripts/    Build, signing, and verification scripts
Tests/      XCTest and Bash contract tests
docs/       Build, self-signing, and changelog documentation
```

## Documentation & Feedback

- [Build guide](docs/BUILD.md)
- [Self-signing guide](docs/SELF-SIGNING.md)
- [Changelog](docs/CHANGELOG.md)
- [中文文档](README.md)
- [GitHub Issues](https://github.com/xweiba/location-spoofer/issues)

When reporting issues, please include reproduction steps, iOS version, device model, and sanitized runtime logs.

## Links

**LinuxDo** — [https://linux.do](https://linux.do/)
