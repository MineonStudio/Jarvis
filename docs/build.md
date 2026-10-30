# 从源码构建

需要完整 Xcode；构建脚本默认使用 `/Applications/Xcode.app`，也可显式设置 `DEVELOPER_DIR`。

## 固定签名身份

仅在构建电脑初始化一次：

```bash
./script/setup_signing.sh --development
./script/setup_signing.sh --release
```

开发版使用登录钥匙串中的 `Jarvis Dev Signing`。正式版使用 `Jarvis Release Signing`，公证书固定在 `Resources/JarvisReleaseSigning.pem`，可以提交到仓库。私钥不得提交。

构建和打包不会生成证书，也不会退回 ad-hoc。正式证书已固定但私钥丢失时，必须从加密备份恢复，不能重新生成一张同名证书冒充原身份。自签名证书仅用于稳定代码身份，不等同于 Apple Developer ID 或公证。

```bash
# 正式包（不替换 /Applications 中的安装）
./build_app.sh

# 开发包，与正式版的数据及权限隔离
./build_dev_app.sh

# 常用验收入口：构建、打开开发版并检查进程
./script/build_and_run.sh --verify
```

验收脚本使用固定路径 `/Users/Shared/Jarvis/Development/Jarvis-Dev.app`。CI 在一次性独立钥匙串中创建临时开发证书，不持有正式私钥。发版见 [update-release.md](update-release.md)。
