<p align="center">
  <img src="DynamicIsland/Assets.xcassets/AppIcon.appiconset/icon1024.png" width="110" alt="Z-island icon">
</p>

<h1 align="center">Z-island</h1>

<p align="center">把 MacBook 的刘海，变成一个随手就能塞东西的暂存格。</p>

<p align="center">
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-0a84ff?logo=apple&logoColor=white">
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-native-f05138?logo=swift&logoColor=white">
  <img alt="License" src="https://img.shields.io/badge/license-GPL--3.0-3da639">
  <img alt="Code size" src="https://img.shields.io/badge/Swift-~31k%20lines-lightgrey">
</p>

Z-island 是我从 [Atoll](https://github.com/Ebullioscopic/Atoll) fork 出来、按自己的使用习惯重写的版本。Atoll 功能很全，但我日常真正用到的只有三样：把文件临时丢在刘海上、翻剪贴板历史、用刘海看音量和亮度。于是把其余的全删了——Swift 代码从约 7.5 万行砍到 3.1 万行，启动更快，交互路径更短。

> 个人向 fork，不是 Atoll 的替代品。需要音乐控制、锁屏小组件、日历、计时器那一整套，请直接装原版 [Atoll](https://github.com/Ebullioscopic/Atoll)。

## 它只做三件事

### 1. 暂存架：拖进来，随时拿走
- 悬停刘海展开；直接把文件拖到刘海上也会自动弹开接住
- 26pt 卡片网格，拖到任意 App 或 Finder 即可拿走
- 顶部一条 60pt 的隔空投送窄条，选中即可投
- 暂存内容落盘保存，重启不丢

### 2. 剪贴板历史
- 文本、图片、文件都能收，点一下写回剪贴板，也可以直接拖出去
- 独立面板，可一键清空历史
- 内容只留在本机，不上传

### 3. 系统 HUD
- 音量、亮度、键盘背光、大写锁定
- AirPods 聆听模式：降噪 / 通透模式 / 自适应音频 / 对话感知 / 关闭
- 用刘海区域做 inline 提示，比系统原生那块方块更贴边

## 菜单栏
- 开机自启（走 `SMAppService`，与系统「登录项」双向同步）
- 一键授权全部权限（辅助功能 / 屏幕录制 / 通知，缺哪个补哪个）
- 显示 / 隐藏菜单栏图标
- 重启 Z-island、退出

## 和 Atoll 比，删掉了什么
音乐播放与歌词、锁屏小组件与全屏封面、日历、计时器、提醒、专注模式、录屏、摄像头 / 麦克风隐私指示、电池与充电、下载与网络监控、终端、CPU / GPU / 内存指标、LLM 用量、取色器、便签、完整设置窗口、XPC 插件宿主。

换来的：少掉约六成代码、更少的后台轮询，以及不再需要 Automation 权限——它以前每次启动都会问你能不能控制音乐 App。

## 系统要求
- macOS 15 或更高
- 带刘海的 MacBook（14 / 16 英寸 MBP）
- 从源码构建需要 Xcode 16+

## 构建
```bash
git clone git@github.com:zevin-zh/Z-island.git
cd Z-island
open Z-island.xcodeproj   # 选 Z-island scheme，Release 构建
```

命令行构建：
```bash
xcodebuild -project Z-island.xcodeproj -scheme Z-island -configuration Release build
```

图标是代码画出来的（没有位图源文件），改了设计就重新生成：
```bash
swift scripts/generate_app_icon.swift --install
```

把构建出的 `Z-island.app` 拷进 `/Applications` 再启动即可。

## 权限
首次启动会请求三项，菜单栏里的「一键授权全部权限」可以一次补齐：

| 权限 | 用途 |
| --- | --- |
| 辅助功能 | 接收拖放、读取菜单栏布局 |
| 屏幕录制 | 刘海覆盖层渲染 |
| 通知 | HUD 与提示 |

授权后建议重启一次 App——macOS 不会给已在运行的进程刷新权限。

## 说明与限制
- 暂存架、菜单栏、对话框的主流程已全部中文化，历史遗留的英文文案还有零星几十处
- `DynamicIslandTests` 里保留着一些已删功能的旧用例，只影响测试 target，不影响 app 构建
- 只有单窗口（刘海覆盖层），App 是 `LSUIElement`，不出现在 Dock 和 Cmd-Tab

## 开源协议
本项目以 **GPL-3.0** 发布，是 [Atoll](https://github.com/Ebullioscopic/Atoll) 的衍生作品。原始版权声明与许可证全文完整保留在仓库中（[LICENSE](LICENSE)、[NOTICE](NOTICE)）。按 GPL-3.0 的要求，修改版同样以 GPL-3.0 分发、源码公开于此；二次分发请一并保留许可证文本与下面的致谢。

## 致谢

这个项目里几乎没有什么是完全原创的，交互范式都来自上游：

- [**Atoll**](https://github.com/Ebullioscopic/Atoll) — 本项目的直接上游。刘海交互模型、暂存架、HUD、动画骨架都源自这里。感谢 Ebullioscopic 以及所有 Atoll 贡献者，没有这个项目就没有 Z-island。
- [**Boring.Notch**](https://github.com/TheBoredTeam/boring.notch) — Atoll 的底座，文件坞 / 暂存架的最初形态出自这里，GPL-3.0。感谢 TheBoredTeam。
- [**DynamicNotch**](https://github.com/jackson-storm/DynamicNotch) — 系统 HUD 部分的参考实现。
- [**Sparkle**](https://sparkle-project.org)、[**Lottie**](https://github.com/airbnb/lottie-ios) — 更新框架与动画运行时。

原项目作者与团队并未为本 fork 背书。遇到问题请提到[本仓库](https://github.com/zevin-zh/Z-island/issues)，不要去打扰上游。
