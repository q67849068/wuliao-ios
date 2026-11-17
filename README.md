# 无聊畅谈 iOS 客户端

## 项目结构

```
ios/
├── project.yml              # XcodeGen 工程定义（不需要手写 .xcodeproj）
├── Sources/
│   ├── AppDelegate.swift    # 入口 + 推送注册
│   └── WebViewController.swift  # WKWebView 外壳 + 原生能力
├── Resources/
│   ├── Info.plist           # 权限声明
│   ├── LaunchScreen.storyboard
│   └── Assets.xcassets      # App 图标
├── .github/workflows/
│   └── build.yml            # 云端编译（GitHub Actions）
└── scripts/
    └── sign-windows.ps1     # Windows 签名脚本
```

## 没有 Mac 的完整流程

### 第一步：上传代码到 GitHub

```bash
git init
git add .
git commit -m "init"
git remote add origin https://github.com/你的用户名/wuliao-ios.git
git push -u origin main
```

### 第二步：配置 GitHub Secrets

仓库 → Settings → Secrets and variables → Actions → New repository secret

| Secret 名称 | 内容 | 怎么生成 |
|---|---|---|
| `P12_BASE64` | p12 文件的 Base64 | `certutil -encode wuliao.p12 p12.txt`（Windows）然后去掉首尾行 |
| `P12_PASSWORD` | p12 密码 | 就是那个随机密码 |
| `PROVISION_BASE64` | 描述文件的 Base64 | 同上方法 |

### 第三步：触发编译

推代码后自动触发，或到 Actions 页面点 **Run workflow**。

编译完成后在 Actions 页面下载 `WuliaoChat-ipa` 压缩包，里面有 `WuliaoChat.ipa`。

### 第四步：装到手机

**方式 A：TestFlight（推荐）**

用 Transporter（微软商店免费下载）上传 IPA 到 App Store Connect，然后在 iPhone 的 TestFlight App 里安装。

**方式 B：直接装**

用 [impactor](https://github.com/claration/impactor) 或 [Sideloader](https://github.com/Dadoum/Sideloader)，USB 连上 iPhone，选择 IPA 安装。

## 网页端配合

App 打开的是 `https://chat.lingguangsh.com/h5/`。

### 推送对接

原生端拿到 APNs token 后会调用：

```js
window.__apnsToken('xxxxx');
```

网页端需要在 `App.vue` 里接：

```js
window.__apnsToken = (token) => {
  // 调后端接口把 token 和 userId 绑定
  uni.request({ url: '/api/push/register', method: 'POST', data: { token } });
};
```

### 调用原生

```js
window.webkit.messageHandlers.wuliaoBridge.postMessage({ action: 'openExternal', url: '...' });
```

## 图标

`Resources/Assets.xcassets/AppIcon.appiconset` 已包含全部尺寸（40/58/60/80/87/120/180/1024）。

## 常见问题

**Q: 编译报 "No signing certificate"**
检查 GitHub Secrets 里的 P12_BASE64 是否完整，以及 P12_PASSWORD 是否正确。

**Q: 报 "Provisioning profile doesn't match"**
描述文件的 Bundle ID 必须是 `com.lingguangsh.wuliao`，且包含的证书要和 p12 一致。

**Q: 装到手机提示"未受信任的企业级开发者"**
去 设置 → 通用 → VPN与设备管理 → 信任你的开发者证书。

**Q: 通话没声音**
检查 Info.plist 里的 NSMicrophoneUsageDescription 是否存在，以及 WebView 的 `mediaTypesRequiringUserActionForPlayback = []` 是否设置。
