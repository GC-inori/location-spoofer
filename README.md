<div align="center">

# 📍 Location Spoofer

### iOS 虚拟定位 · 钉钉定位 · 微信定位 · Apple Watch 国区功能解锁 · Fake GPS

**无需越狱；可使用 APP模式的本机 Wi‑Fi HTTP 代理，或第三方代理模式（支持 Wi‑Fi/4G/5G）改写 Apple 定位响应。**<br>
可修改钉钉、微信及任意依赖系统定位的 App 的位置。地图选点、实时位置、环境检测、证书配置与运行日志集中在一个 App 中。

[![iOS 15+](https://img.shields.io/badge/iOS-15%2B-111111?logo=apple)](project.yml)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](project.yml)
[![Go 1.23+](https://img.shields.io/badge/Go-1.23%2B-00ADD8?logo=go&logoColor=white)](Core/go.mod)
[![Version](https://img.shields.io/badge/version-v1.0.1-2563EB)](docs/CHANGELOG.md)
[![App Mode](https://img.shields.io/badge/APP模式-无需VPN-16A34A)](#为什么不需要-vpn)

[功能介绍](#核心功能) · [安装使用](#快速开始) · [English](README.en.md) · [更新日志](docs/CHANGELOG.md)

<img src="images/主界面.jpg" alt="Location Spoofer iOS 虚拟定位 Fake GPS 主界面" width="380">

</div>

> [!IMPORTANT]
> 本项目用于学习、安全研究与自有设备测试。APP模式需要安装自签 CA，并在当前 Wi‑Fi 上配置本机 HTTP 代理；第三方代理模式的证书、MITM 和代理/VPN 连接由所选客户端处理。请先阅读工作原理和风险说明，并遵守当地法律、网络管理规则及相关服务条款。

## 致谢

核心定位响应改写思路与 Go 实现来源于 [Yu9191/wloc](https://github.com/Yu9191/wloc)。本项目在此基础上增加 SwiftUI 界面、MapKit 选点、证书与代理引导、环境验证、收藏和诊断能力。

## 为什么选择 Location Spoofer？

很多 iOS 虚拟定位工具依赖电脑常驻、开发者调试、VPN 或越狱。本项目采用不同路线：在 iPhone 本机运行 Go 代理，仅对 Apple 定位服务目标请求进行处理。

| 特性 | 说明 |
|---|---|
| 🔀 **双运行模式** | APP模式无需第三方客户端、支持 Wi‑Fi；第三方代理模式可覆盖 Wi‑Fi、4G 和 5G |
| 📱 **无需越狱** | 支持自行签名安装，最低部署目标为 iOS 15 |
| 🗺️ **原生地图体验** | 使用 Apple 地图同款蓝点，搜索、点击、拖动选点体验与 Apple 地图一致 |
| 📍 **系统级虚拟定位** | 支持钉钉、微信、Apple 地图、高德等 App 的虚拟实时定位 |
| 🔍 **可见缩放范围** | 左侧缩放控件显示当前可视范围，地点名称随级别自动适配 |
| 🧪 **环境检测** | 检查本地代理、CA 证书信任与 Wi‑Fi 代理链路 |
| 🧾 **诊断日志** | 每条日志独立可复制，方便整理和反馈问题 |

## 效果预览

<table>
  <tr>
    <th>应用主界面</th>
    <th>钉钉</th>
    <th>微信</th>
  </tr>
  <tr>
    <td><img src="images/主界面.jpg" alt="iOS 虚拟定位应用主界面" width="180"></td>
    <td><img src="images/钉钉.jpg" alt="钉钉虚拟定位打卡" width="180"></td>
    <td><img src="images/微信.jpg" alt="微信虚拟定位" width="180"></td>
  </tr>
  <tr>
    <th>Apple 地图</th>
    <th>高德地图</th>
    <th>Apple Watch</th>
  </tr>
  <tr>
    <td><img src="images/Apple%20Map.jpg" alt="Apple Maps 定位效果" width="180"></td>
    <td><img src="images/高德地图.jpg" alt="高德地图定位效果" width="180"></td>
    <td><img src="images/高血压.jpg" alt="Apple Watch 地区功能验证" width="180"></td>
  </tr>
</table>

## 核心功能

- **iOS 虚拟定位 / Fake GPS**：将当前地图选点应用到本机定位响应改写代理，适配钉钉打卡、微信位置共享等场景。
- **原生实时位置**：地图显示 MapKit 自带蓝点，不再由 App 额外绘制实时位置标记。
- **并发安全选点**：拖动、点击、搜索、收藏和异步定位按用户最新意图处理，旧结果不会覆盖新选点。
- **地点名称分级**：近距离显示 POI、门牌或道路；拉远后显示社区、区县、城市或省份。
- **地图范围显示**：缩放控件中显示 `180 m`、`2.5 km`、`126 km` 等当前可视范围。
- **收藏与快速切换**：保存常用坐标，并明确显示当前准备应用的位置。
- **分流配置引导**：首次启动先选择模式；APP模式引导本机代理和 CA，第三方代理模式引导客户端、配置导入和接口检测。
- **问题诊断**：内置验证流程和结构化运行日志。
- **第三方代理模式（测试）**：内置各客户端模块配置，把收藏或当前选点的 WGS-84 坐标发送到第三方代理模块；代理客户端持久化坐标，关闭本 App 后仍可继续生效。

## 快速开始

### 1. 安装 App

- 从 [Releases](https://github.com/xweiba/location-spoofer/releases) 获取构建产物并自行签名；或
- 在 macOS + Xcode 环境按[构建说明](docs/BUILD.md)编译。

#### 自签安装

免费 Apple ID 即可侧载，无需付费开发者账号。本项目不使用 VPN、Network Extension 或 Packet Tunnel Provider，但签名工具仍需保留 App 的能力与标识。

需要自行构建时执行：

```bash
./build.sh
```

输出文件为 `dist/PaopaoLocationSpoofer-unsigned.ipa`。也可以直接下载 Release 附带的未签名 IPA，然后使用 [Impact](https://github.com/claration/Impactor) 签名并安装到设备。

签名时不要修改以下标识，也不要移除 App Group 和 Wi-Fi 信息能力：

| 组件 | 标识 |
|---|---|
| 主 App Bundle ID | `com.paopaolabs.location-spoofer` |

免费 Apple ID 签名通常只有 7 天有效期，到期后需要重新签名安装；这是 Apple 的侧载限制，不是 App 的证书失效。App 生成的 WLOC CA 私钥保存在 iOS 钥匙串中：使用相同 Bundle ID 和钥匙串访问范围重装时通常可继续复用，但卸载、系统清理或签名能力变化后不保证保留。

### 2. 选择运行模式

#### APP模式

首次打开后选择 APP模式，再按 App 内引导配置代理和 CA。APP模式没有第三方代理客户端依赖，但只支持 Wi‑Fi。免费自签应用无法使用此功能所需的 VPN/Network Extension 能力，因此使用当前 Wi‑Fi 的手动 HTTP 代理实现流量接入。

##### 配置当前 Wi‑Fi 代理

首次打开后，先在当前 Wi‑Fi 的“配置代理”中选择“手动”：

```text
服务器：127.0.0.1
端口：8888
鉴定：关闭
```

返回 App 后运行环境检测；如果设备尚未信任 CA，App 会自动进入证书初始化。

##### 安装并信任 CA

按首次引导下载描述文件，然后完成：

```text
设置 → 通用 → VPN 与设备管理 → 安装 WLOC CA
设置 → 通用 → 关于本机 → 证书信任设置 → 完全信任
```

#### 第三方代理模式

此模式由 App 负责地图选点、收藏和发送 WGS-84 坐标；WLOC 拦截、MITM 与坐标持久化由第三方代理客户端负责。它不会启动本机 Go 代理，不检查或使用 App 的 CA，也不要求配置 `127.0.0.1:8888`，可用于 Wi‑Fi、4G 和 5G。

首次引导或“设置 → 运行模式”切换后，选择客户端。App 提供官方订阅地址复制和客户端跳转按钮；在对应客户端的模块、重写或覆写订阅入口粘贴地址并导入。仓库和 App 包内仍保留以下模块配置快照，用于版本归档和离线核对：

| 客户端 | 状态 | 模块 |
|---|---|---|
| Shadowrocket（小火箭） | **当前可测试** | [wloc.module](https://raw.githubusercontent.com/Yu9191/wloc/refs/heads/main/modules/wloc.module) |
| Surge | 配置已提供，尚未验证 | [wloc.sgmodule](https://raw.githubusercontent.com/Yu9191/wloc/refs/heads/main/modules/wloc.sgmodule) |
| Quantumult X | 配置已提供，尚未验证 | [wloc.conf](https://raw.githubusercontent.com/Yu9191/wloc/refs/heads/main/modules/wloc.conf) |
| Loon | 配置已提供，尚未验证 | [wloc.lpx](https://raw.githubusercontent.com/Yu9191/wloc/refs/heads/main/modules/wloc.lpx) |
| Stash | 配置已提供，尚未验证 | [wloc.stoverride](https://raw.githubusercontent.com/Yu9191/wloc/refs/heads/main/modules/wloc.stoverride) |
| Egern | 配置已提供，尚未验证 | 直接使用 Surge 模块 |

Stash 应直接订阅 `.stoverride`，无需通过 Script Hub 转换。Egern 复用 Surge 配置。导入后还需要按对应客户端自己的流程启用模块、MITM、证书和代理/VPN 连接；这些状态不由本 App 管理。App 只调用 WLOC 配置接口查询和同步坐标，“检测连接”仅在查询返回模块 JSON 时判定成功，不会把普通 HTTP 200 当作成功。

> 第三方代理模式目前是测试模式。内置模块快照来源及版本记录见 [第三方模块说明](docs/THIRD_PARTY_MODULES.md)；模块引用的运行脚本仍由第三方客户端按配置访问。上游更新可能改变行为；当前仅计划使用 Shadowrocket 做真机验证。

### 3. 选点并启用

1. 搜索、点击或拖动地图选择位置；点击实时位置按钮可回到 MapKit 蓝点。
2. APP 模式点击“开始虚拟定位”并等待环境检测；第三方代理模式点击“同步到第三方代理”。
3. 按 App 内"生效说明"刷新飞行模式、Wi‑Fi 和定位服务状态。
4. 打开 Apple 地图或目标 App 验证结果。

### 4. 恢复真实位置

停止虚拟定位，关闭当前 Wi‑Fi 的手动代理，并按 App 内"失效说明"刷新系统定位缓存。若系统仍保留旧缓存，请重启设备后再检查。

## 为什么不需要 VPN？

```text
iPhone 定位请求
      │ 当前 Wi‑Fi HTTP 代理：127.0.0.1:8888
      ▼
本机 wloccore（Go）
      │ 仅处理目标 Apple 定位服务请求
      ├──────────────► Apple 定位服务
      ◄──────────────┘
      │ 改写目标响应中的坐标
      ▼
系统与应用读取定位结果
```

APP 模式不使用 Network Extension 创建 VPN 隧道，因此不会显示 VPN 连接，也不会占用系统 VPN。**APP 模式仍需要为当前 Wi‑Fi 配置 HTTP 代理，并安装、信任本机生成的 CA。** 第三方代理模式则由所选代理客户端管理代理/VPN 和 MITM，可覆盖蜂窝网络；两种模式不得同时拦截 WLOC 请求。

## 兼容性

| 项目 | 要求 |
|---|---|
| iOS | 15.0+ |
| 构建 | macOS、Xcode、XcodeGen |
| Swift | 5.9 |
| Go | 1.23+ |
| 网络 | APP 模式：可手动配置 HTTP 代理的 Wi‑Fi；第三方代理模式（测试）：取决于代理客户端，可覆盖 Wi‑Fi/4G/5G |
| 安装 | 自行签名或使用 Releases 构建产物 |

效果会受到 iOS 版本、网络、系统定位缓存和目标 App 自身策略影响，不承诺兼容所有系统或第三方 App。

## 构建与项目结构

```bash
./build.sh
```

构建产物默认位于：

```text
dist/PaopaoLocationSpoofer-unsigned.ipa
```

```text
App/        SwiftUI、MapKit、定位和配置流程
Core/       Go 本机代理与定位响应改写
Shared/     收藏、设置、日志和共享模型
Resources/  Info.plist、Entitlements 与图标
Scripts/    构建、签名和检查脚本
Tests/      XCTest 与 Bash 契约测试
docs/       构建和版本发布归档
```

## 文档与反馈

- [构建说明](docs/BUILD.md)
- [更新日志](docs/CHANGELOG.md)
- [English README](README.en.md)
- [GitHub Issues](https://github.com/xweiba/location-spoofer/issues)

反馈问题时，请附上复现步骤、iOS 版本、设备型号及已脱敏的运行日志。

## 友链

**LinuxDo** — [https://linux.do](https://linux.do/)
