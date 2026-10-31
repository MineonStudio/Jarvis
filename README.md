# 工作搭子 Jarvis

<img src="docs/icon.png" width="96" alt="工作搭子 Jarvis">

协助办公，也陪你摸鱼放松的 macOS 工作搭子。工作时处理截图、屏幕录制、剪贴板、会议记录、窗口布局和简历；休息时换壁纸、逛娱乐广场，或打一局欢乐麻将。

macOS 26 及以上。

## 安装

[下载最新版](https://github.com/MineonStudio/Jarvis/releases/latest)，打开 DMG，把 Jarvis.app 拖进「应用程序」。

或者：

```bash
curl -fsSL https://raw.githubusercontent.com/MineonStudio/Jarvis/dev/install.sh | zsh
```

安装包已使用固定发布证书签名。安装和更新无需在你的电脑生成证书或重新签名，正常更新不会主动清除权限。首次安装可能需要在系统设置“隐私与安全性”中允许打开。

卸载：

```bash
curl -fsSL https://raw.githubusercontent.com/MineonStudio/Jarvis/dev/install.sh | zsh -s -- --uninstall
```

卸载脚本只移除应用，保留数据和钥匙串。新版不再兼容旧版本的本机改签流程；首次切换需要手动安装并重新授权。

## 快捷键

| 按键 | 作用 |
| --- | --- |
| F1 | 截图 |
| F2 | 屏幕录制（打开准备面板 / 开始 / 停止） |
| F3 | 剪贴板 |
| F4 | 开始或停止会议录音 |

都可以在设置里改。剪贴板面板里，⌘1–9 或回车会粘贴。

## 里面有什么

- 截图。框选，或点一个窗口。图留在原地，可以画箭头、打马赛克、写字，然后复制或另存。
- 屏幕录制。支持全屏、窗口和自定义区域，系统声音和麦克风可独立开关，窗口隐藏时自动暂停并在恢复后继续，支持历史回看和未完成片段恢复。使用说明见 [docs/screen-recording.md](docs/screen-recording.md)。
- 剪贴板。文本、图片、文件、视频。可以筛选、搜索、收藏。超过 1GB 的文件只记住原路径。
- 会议记录。麦克风和系统声音留在本机，转写也在本机。总结用设置里填的模型。第一次用要先下载本地识别模型。
- 局域网传输。在同一 Wi-Fi 或手机热点下启动共享，手机扫描二维码即可通过浏览器上传或下载文件。Mac 端可选择文件或拖拽到共享区。共享目录是 `~/Library/Application Support/Jarvis/局域网传输/共享`，接收目录是同级的 `接收`，单文件上限固定为 2 GB。传输使用局域网 HTTP，请在可信网络中使用。
- 桌面壁纸、窗口布局、简历制作。
- AI 聚合、娱乐广场。在应用里打开的网页。
- 欢乐麻将。支持单人对战和局域网对战；局域网内由一位玩家开房，好友可搜索并加入。

截图、屏幕录制、剪贴板、录音和逐字稿都在本机。会议总结和截图翻译会把内容发给设置里的服务。

截图需要允许「屏幕与系统音频录制」。会议需要麦克风。

## 从源码构建

```bash
./build_app.sh
open dist/Jarvis.app
```

开发版是 `./build_dev_app.sh`，产物是 `dist/Jarvis-Dev.app`。证书写在 [docs/build.md](docs/build.md)。发版见 [docs/update-release.md](docs/update-release.md)。
