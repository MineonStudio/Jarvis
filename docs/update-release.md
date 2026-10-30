# 发布、签名与更新

## 新版标准

所有正式产物（DMG、直接下载 ZIP、应用内更新 ZIP）均在发布电脑使用同一张 `Jarvis Release Signing` 自签名证书签署，Bundle ID 固定为 `com.jarvis.mac`。公证书为 `Resources/JarvisReleaseSigning.pem`。

用户电脑不生成、导入或删除证书，也不重新签署应用。安装来源只用于记录，不影响权限。启动、安装和更新均不自动调用 `tccutil reset`；设置中的手动权限重置仅用于用户主动修复。

不再支持旧版迁移桥接或旧本机签名身份。第一次切换新版标准时手动安装，并按 macOS 提示重新授权。后续更新同时验证：

1. 内置 Ed25519 公钥验证更新清单的原始字节。
2. 下载归档必须匹配清单 SHA-256、应用 ID、版本及构建号。
3. 应用代码签名必须有效，且满足当前安装的 Designated Requirement；ad-hoc、换证书及篡改均拒绝。
4. 替换前再次校验代码身份，保留备份，启动失败回滚。

自签名不提供 Apple 公证。浏览器下载后，首次启动可能需要在系统设置“隐私与安全性”中手动放行。命令行安装器使用仓库固定的发布证书指纹校验下载包，不持有任何私钥。

## 密钥

代码签名私钥在发布电脑登录钥匙串。独立 Ed25519 更新私钥仍使用现有的 `com.jarvis.mac.update-signing.v1` / `release-ed25519` 条目，公钥位于 `Resources/Info.plist`。两个用途不能互相替代；不要因为本次重构重新生成更新密钥。

```bash
# 只输出更新公钥
swift script/JarvisUpdateSigning.swift public-key

# 加密备份两张代码签名证书及其私钥、现有更新密钥
swift script/JarvisSigningBackup.swift export /Volumes/OfflineBackup/Jarvis-signing.enc

# 解密验证身份及公钥匹配，不写钥匙串
swift script/JarvisSigningBackup.swift verify /Volumes/OfflineBackup/Jarvis-signing.enc

# 重装系统后恢复
swift script/JarvisSigningBackup.swift restore /Volumes/OfflineBackup/Jarvis-signing.enc
./script/setup_signing.sh --release
./script/setup_signing.sh --development
```

备份工具只在交互式终端隐藏读取密码；使用 PBKDF2-HMAC-SHA256（600,000 次）和 AES-256-GCM。请把备份存放在加密离线介质上，密码另行保管。工具拒绝覆盖已有备份，导出时检查公证书、更新公钥及密钥是否匹配，恢复前先完成相同验证。恢复后签署两个不同构建并验证代码身份连续性，再发布。

## 构建发布资产

设置递增版本与构建号：

```bash
JARVIS_VERSION=<version> JARVIS_BUILD=<build> ./package_release.sh
```

默认在 `/Users/Shared/Jarvis/Release/Jarvis.app` 构建，避免云盘元数据破坏签名。产物在 `dist/release`：

- `Jarvis-<version>-macos.zip`
- `Jarvis-<version>-macos.dmg`
- `Jarvis-update.zip`
- `Jarvis-update-manifest.json`
- `Jarvis-update-manifest.sig`

上传到对应的非预发布 GitHub Release。不要在签署清单后改动更新 ZIP、清单或签名。私钥不提交、不上传 GitHub Actions。发布前应在真实 macOS 中完成“授权 → 更新 → 检查权限继承”的验收；代码身份测试不能替代 TCC 实测。
