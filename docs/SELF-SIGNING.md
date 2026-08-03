# 自签安装指南

**免费 Apple ID 即可自签安装**，无需付费开发者账号。

## 原理

本项目只是一个本地 HTTP 代理配合 WiFi 手动代理，不涉及 VPN / Network Extension / Packet Tunnel Provider。无需特殊权限，个人免费 Apple ID 侧载完全可用。

## 构建未签名 IPA

```bash
./build.sh
```

输出：`dist/PaopaoLocationSpoofer-unsigned.ipa`

## 使用 Impact 签名安装

用 [Impact](https://github.com/claration/Impactor) 打开 IPA 签名并安装到设备。

关键标识符不可更改：

| 组件 | Bundle ID |
|------|-----------|
| 主 App | `com.paopaolabs.location-spoofer` |
| App Group | `group.com.paopaolabs.location-spoofer` |

## 安装后步骤

1. 首次打开，按引导下载 CA 证书 → 安装描述文件 → 开启完全信任
2. 在 WiFi 设置中配置 HTTP 代理为 `127.0.0.1:8888`
3. 环境检测通过后即可使用

## iOS 26+ 注意事项

开启虚拟定位后需重启设备清除定位缓存，详见 README 中的使用说明。
