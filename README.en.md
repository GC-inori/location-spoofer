<div align="center">

# 📍 Location Spoofer

### iOS Location Spoofer · DingTalk · WeChat · Apple Watch Region Unlock · Fake GPS

**No jailbreak — use App Mode's on-device Wi-Fi HTTP proxy or Third-party Proxy Mode (Wi-Fi/4G/5G) to rewrite Apple location responses.**<br>
Works with DingTalk check-in, WeChat location sharing, and any app that uses system location. Map selection, real-time location, environment verification, certificate setup, and runtime logs in a single app.

[![iOS 15+](https://img.shields.io/badge/iOS-15%2B-111111?logo=apple)](project.yml)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](project.yml)
[![Go 1.23+](https://img.shields.io/badge/Go-1.23%2B-00ADD8?logo=go&logoColor=white)](Core/go.mod)
[![Version](https://img.shields.io/badge/version-v1.0.1-2563EB)](docs/CHANGELOG.md)
[![App Mode](https://img.shields.io/badge/App%20Mode-No%20VPN-16A34A)](#why-no-vpn)

[Features](#key-features) · [Quick Start](#quick-start) · [中文](README.md) · [Changelog](docs/CHANGELOG.md)

<img src="images/主界面.jpg" alt="Location Spoofer iOS Fake GPS main interface" width="380">

</div>

> [!IMPORTANT]
> This project is intended for education, security research, and testing on your own devices. App Mode installs a locally generated CA and requires a manual HTTP proxy on the current Wi-Fi network. In Third-party Proxy Mode, the selected client owns certificate, MITM, and proxy/VPN setup. Please understand the risks and follow applicable laws and service terms.

## Credits

The core location-response rewriting approach and Go implementation are based on [Yu9191/wloc](https://github.com/Yu9191/wloc). This project adds a SwiftUI interface, MapKit selection, certificate and proxy guidance, environment verification, favorites, and diagnostics.

## Why Location Spoofer?

Unlike tools that require a computer to stay connected, a VPN tunnel, or a jailbroken device, Location Spoofer keeps the control flow on the iPhone itself.

| Feature | Description |
|---|---|
| 🔀 **Two runtime modes** | Stable App Mode, plus a Third-party Proxy Mode under testing for Wi-Fi, 4G, and 5G. |
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
- **Mode-specific setup**: Choose a mode first; App Mode guides local proxy and CA setup, while Third-party Proxy Mode guides client selection, configuration import, and API verification.
- **Built-in diagnostics**: Verification flow and structured runtime logs.
- **Third-party Proxy Mode (testing)**: Send a favorite or current pin as WGS-84 to a supported proxy module; the proxy client persists it after this App exits.

## Quick Start

### 1. Install the App

- Download a build from [Releases](https://github.com/xweiba/location-spoofer/releases) and self-sign; or
- Build from source on macOS with Xcode — see the [build guide](docs/BUILD.md).

The release asset is an unsigned IPA. Sign it with [Impact](https://github.com/claration/Impactor) before installation. Keep the app Bundle ID `com.paopaolabs.location-spoofer`, the App Group `group.com.paopaolabs.location-spoofer`, and the declared entitlements unchanged. A free Apple ID signature normally expires after seven days and must then be renewed.

### 2. Choose a Runtime Mode

#### App Mode

Choose App Mode during first launch, then configure `127.0.0.1:8888` and fully trust the locally generated CA. It has no third-party client dependency but supports Wi-Fi only. Free self-signed apps cannot use the VPN/Network Extension capability required for cellular interception, so this mode uses the current Wi-Fi's manual HTTP proxy.

#### Third-party Proxy Mode

The App handles map selection, favorites, and WGS-84 coordinate delivery. A third-party proxy client handles WLOC interception, MITM, and persistence over Wi-Fi, 4G, or 5G. This mode skips the App's local proxy and CA checks.

Shadowrocket is the only client currently available for device testing. Surge, Quantumult X, Loon, Stash, and Egern configurations are provided but unverified. The App lets the user copy the official subscription URL and open the selected client; the URL is then pasted into that client's module, rewrite, or override subscription UI. Configuration snapshots remain bundled for release provenance and offline inspection, but the setup UI does not export files. Egern uses the Surge module, and Stash imports `.stoverride` directly without Script Hub conversion. The third-party client—not this App—owns MITM, certificate, and proxy/VPN setup. Snapshot provenance is recorded in [the module snapshot document](docs/THIRD_PARTY_MODULES.md).

### 3. Local-mode CA Setup

Follow the first-setup wizard to download the profile, then:

```text
Settings → General → VPN & Device Management → install WLOC CA
Settings → General → About → Certificate Trust Settings → enable full trust
```

Configure the current Wi-Fi proxy before installing the CA:

On the current Wi‑Fi's proxy settings, choose "Manual":

```text
Server: 127.0.0.1
Port: 8888
Authentication: off
```

### 4. Select a Location & Enable

1. Search, tap, or drag the map to pick a location; tap the real-time location button to jump to the MapKit blue dot.
2. In App Mode, tap “Start Spoofing” and wait for verification. In Third-party Proxy Mode, tap “Sync to Third-party Proxy.”
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

App Mode does not use Network Extension, so it does not occupy the VPN slot. **App Mode still requires the current Wi-Fi HTTP proxy and the locally generated CA.** Third-party Proxy Mode delegates proxy/VPN and MITM handling to the selected proxy client and may cover cellular networks. Do not enable both interception paths at once.

## Compatibility

| Item | Requirement |
|---|---|
| iOS | 15.0+ |
| Build | macOS, Xcode, XcodeGen |
| Swift | 5.9 |
| Go | 1.23+ |
| Network | Local mode: Wi-Fi with manual HTTP proxy support; third-party test mode: client-dependent Wi-Fi/4G/5G |
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
- [Changelog](docs/CHANGELOG.md)
- [中文文档](README.md)
- [GitHub Issues](https://github.com/xweiba/location-spoofer/issues)

When reporting issues, please include reproduction steps, iOS version, device model, and sanitized runtime logs.

## Links

**LinuxDo** — [https://linux.do](https://linux.do/)
