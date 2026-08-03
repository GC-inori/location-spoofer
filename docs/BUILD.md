# Build

## Requirements

- macOS with Xcode and Command Line Tools
- Go 1.23 or newer
- XcodeGen (`brew install xcodegen`)

## One-command build

```bash
./build.sh
```

该脚本会先检查 `xcrun`、`xcodebuild`、`xcodegen` 和 `go`，随后构建 iOS Go 静态库、重新生成 Xcode 工程、构建并输出未签名 IPA。

如需在未签名 IPA 已生成后额外运行 `PaopaoLocationSpoofer` 的 iOS Simulator 单元测试：

```bash
./build.sh --test
```

`--test` 默认使用名为 `iPhone 16` 的 Simulator。若本机没有该设备，请传入已安装设备的 destination：

```bash
SIMULATOR_DESTINATION='platform=iOS Simulator,name=<你的模拟器名称>' ./build.sh --test
```

Output:

```text
dist/PaopaoLocationSpoofer-unsigned.ipa
```

IPA 始终保持未签名。用 [Impact](https://github.com/claration/Impactor) 签名安装即可。

## 发布验收

1. `./build.sh` 通过并输出未签名 IPA
2. 用 Impact 签名后安装到设备
3. 真机安装后，按引导下载 CA → 安装 → 信任，再配置 WiFi HTTP 代理 `127.0.0.1:8888`
4. 环境检测通过后，选点开启虚拟定位
5. 打开 Apple 地图验证定位是否变为虚拟位置
6. 若失败，查看诊断页的日志信息
