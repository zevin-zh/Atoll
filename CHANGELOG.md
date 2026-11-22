# Changelog

All notable changes to Z-island will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-11-22

Z-island 是从 Atoll 精简出来的个人自用版本：只留刘海上的文件暂存、剪贴板和几组 HUD。

### 刘海面板
- 鼠标悬停展开黑岛，岛内提供文件暂存架与剪贴板两个页面
- 两套布局（默认 / 简约），在菜单栏下拉里切换；简约布局把剪贴板做成岛内独立页

### 文件暂存架
- 把文件拖到刘海上自动展开并接收，也可以点开暂存架手动添加
- 文件以 26pt 卡片网格排列，隔空投送入口为 60pt 窄条
- 每项右键菜单：打开、打开方式（含默认应用）、在访达中显示、快速查看、共享、图像操作（移除背景 / 转换图像 / 存储为 PDF）、压缩、重命名、拷贝、拷贝路径、移除

### 剪贴板历史
- 文本、图片、文件三类条目，卡片可直接拖出到访达或其他 app
- 随 app 启动开始监控，可一键清空历史

### HUD
- 音量、亮度、键盘背光、AirPods 聆听模式、大写锁定，随系统状态在岛内内联显示

### 菜单栏
- 布局切换、开机自启（按系统真实状态显示，待系统允许时给出提示）、一键授权全部权限、显示/隐藏菜单栏图标、检查更新、重启、退出
- 菜单栏图标按 18pt 单独绘制，与 app 图标同一套设计语言

### 自动更新
- Sparkle 自建 appcast（仓库 Updates/appcast.xml，经 raw 地址分发），每日自动检查，也可手动「检查更新…」

### 相对上游 Atoll 移除的功能
- 音乐播放与歌词、锁屏面板、日历、计时器、提醒、专注模式、录屏与隐私指示、电池活动、下载监控、网络 HUD、插件（Extensions）宿主、设置窗口

### 分发
- ad-hoc 签名，不需要 Apple 开发者账号；首次打开需右键 → 打开，或 `xattr -dr com.apple.quarantine /Applications/Z-island.app`
