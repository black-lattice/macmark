# 轻截 MacMark

专用于 Mac 的轻量截图标注工具，使用 Swift、AppKit 和 ScreenCaptureKit。
最低支持 **macOS 14**；同一 Universal 安装包支持 **Apple Silicon 和 Intel**。

## 下载与安装

从 [GitHub Releases](https://github.com/black-lattice/macmark/releases/latest) 下载 `MacMark-版本-universal.dmg`。
打开 DMG，把 MacMark 拖到 Applications（应用程序），然后启动。

首版采用 ad-hoc 签名，尚无 Apple Developer ID 签名与公证。
如果 macOS 拦截，先尝试打开一次，然后进入「系统设置 → 隐私与安全性」点击「仍要打开」。
首次截图需要授权屏幕录制，授权后退出并重新打开。见 [完整安装说明](INSTALL.txt)。

## 日常使用

应用常驻菜单栏。按 **⌘⇧2**，拖动鼠标框选截图；Esc 或右键取消。

| 工具或操作 | 快捷键 |
| --- | --- |
| 箭头 | A |
| 直线、横线、竖线 | L，按住 Shift 约束方向 |
| 自由划线 | P |
| 方框 | R，Shift 画正方形 |
| 文字 | T，点击输入，回车确认 |
| 选择、移动标注 | V，点击后拖动 |
| 删除标注 | Delete |
| 撤销 / 重做 | ⌘Z / ⇧⌘Z |
| 复制截图 / 保存 PNG | ⌘C / ⌘S |

支持红、橙、蓝、黑、白五种颜色，三档粗细，以及画布缩放。
菜单栏可打开本地图片、开关登录启动、打开权限设置或访问发布页。
多显示器可在任意一块显示器选择区域；首版不支持跨屏选区、滚动截图或录屏。
若全局快捷键被其他应用占用，可从菜单栏截图。

## 性能与隐私

- 全原生，不依赖 Electron、WebView 或 Node 运行时。
- 只在主动截图时使用 ScreenCaptureKit 单次抓取屏幕，不维持录屏流。
- 空闲时没有定时器、屏幕轮询、联网更新检查或遥测。
- 标注只在输入事件触发时重绘；导出时才合成完整分辨率图片。
- 关闭编辑窗口后释放截图；截图、标注和导出均在本地进行，不上传图片。
- 保存保留原始像素尺寸；编辑器缩放不会降低导出分辨率。

目前为首版。低耗能来自上述实现策略，尚未进行跨设备长期能耗对比测试。
GitHub Actions 会附带短时间空闲 CPU / RSS 样本，仅用于发现明显异常。

## 开发

需 macOS 14+ 和 Xcode Command Line Tools（Swift 5.9+）。无需 Node 或第三方包。

```sh
# 只做类型检查
xcrun swiftc -typecheck -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macos14.0" Sources/*.swift
# 运行真实几何、渲染和编辑历史测试
scripts/test.sh
# 显式构建 Universal .app
VERSION=0.1.0 scripts/build.sh
# 打包 DMG / ZIP
VERSION=0.1.0 scripts/package.sh
# 本地启动
open dist/MacMark.app
```

也可用 Xcode 打开 `Package.swift` 查看源码；正式分发使用脚本生成带 Info.plist 的 .app。
源文件按菜单栏、快捷键、截图、选区、编辑器、画布、几何和渲染拆分。

## GitHub Actions 发布

推送 main 或 PR：分别在 `macos-15`（arm64）及 `macos-15-intel` 运行测试，随后交叉编译 Universal 安装包。
推送 `vX.Y.Z` 标签：同样测试和构建，再自动发布 GitHub Release，附带 DMG、ZIP、SHA256 和空闲采样。

```sh
git tag v0.1.0
git push origin v0.1.0
```

流水线未导入任何 Apple 私钥。正式无拦截分发需后续配置 Developer ID Application 签名和 Apple 公证。
不要把证书或密码提交到 Git；将相关凭据作为 GitHub Actions Secrets 管理。

## 验证范围

自动化测试覆盖反向拖动、Retina 和越界选区、Shift 约束、标注命中与移动、
导出像素尺寸与方向、PNG 编解码，以及绘制/删除/移动的撤销重做。
CI 启动检查确认菜单栏进程能存活；它不能代替人工检查系统权限、快捷键或选区交互。
发布前后仍需在真实 Mac 上检查屏幕授权、多显示器、不同缩放比例和日常截图流程。
