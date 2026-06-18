# ClipPixTran

[English](README_EN.md)

[![CI](https://github.com/krissss/clip-pix-tran/actions/workflows/ci.yml/badge.svg)](https://github.com/krissss/clip-pix-tran/actions/workflows/ci.yml)
[![Release](https://github.com/krissss/clip-pix-tran/actions/workflows/release.yml/badge.svg)](https://github.com/krissss/clip-pix-tran/actions/workflows/release.yml)

ClipPixTran 是一个 macOS 桌面效率工具，围绕 Clip、Pix、Tran 三个常用工作流，把剪贴板、截图和翻译放进同一个轻量控制面板。

## 功能

- Clip: 管理剪贴板历史，让常用文本可以快速找回和复用。
- Pix: 处理截图、标注、贴图和录屏，让屏幕内容捕获更顺手。
- Tran: 翻译选中文本或手动输入的内容，适合阅读和写作时快速切换语言。

## 安装

推荐通过 Homebrew 安装：

```bash
brew install --cask krissss/tap/clip-pix-tran
```

也可以从 [Releases](https://github.com/krissss/clip-pix-tran/releases) 下载最新的 ZIP 或 DMG，解压后把 `ClipPixTran.app` 放到 `/Applications`。

如果 macOS 提示应用来自未验证开发者、已损坏或阻止启动，请确认安装包来源可信后清理扩展属性：

```bash
xattr -cr /Applications/ClipPixTran.app
```

## 权限

ClipPixTran 的核心操作在本机完成。根据启用的功能，macOS 可能会请求以下权限：

- 辅助功能: 用于读取选中文本和辅助截图定位。
- 屏幕录制: 用于截图、录屏和区域捕获。
- 输入监控: 用于部分全局快捷键。

启用网络翻译服务时，翻译请求可能访问网络。

## 开发环境

- macOS 26.0 或更新版本。
- 支持 macOS 26 SDK 的 Xcode。
- Swift 5。
- Swift Package Manager 依赖由 Xcode 自动解析，包括 `KeyboardShortcuts` 和 `Sparkle`。

也可以直接打开 `ClipPixTran.xcodeproj`，选择 `ClipPixTran` scheme 后运行。

## 常用命令

```bash
make resolve-packages
make run-dev
make test
make package
```

常用目标：

- `make run-dev`: 构建 Debug 版并运行。
- `make test`: 运行测试。
- `make package`: 生成 Release ZIP 和 DMG。
- `make clean`: 清理构建产物。

## 项目结构

```text
App/
  Shell/       macOS 应用入口、菜单栏、设置、快捷键、更新和引导
  Features/
    Clip/      剪贴板历史和快速面板
    Pix/       截图、录屏、标注、贴图和历史
    Tran/      翻译、provider、发音、快速面板和历史
  Shared/      公共 UI、服务、持久化和工具
Tests/         Swift Testing 测试
Config/        Info.plist 和签名配置示例
docs/          更新日志和发布说明
```

## 贡献

欢迎通过 issue 或 pull request 反馈问题和改进建议。提交改动前请尽量运行：

```bash
make test
```

## 许可证

本项目使用 MIT License，详见 [LICENSE](LICENSE)。
