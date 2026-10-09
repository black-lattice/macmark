轻截 MacMark 首版，最低支持 macOS 14，同时支持 Apple Silicon（M 系列）和 Intel。

- 区域截图，多显示器分别选择，保留 Retina 分辨率。
- 箭头、直线、自由画笔、方框和中文文字标注。
- Shift 约束横线、竖线、45° 线及正方形。
- 选择、拖动、删除标注，撤销与重做。
- 复制到剪贴板、保存 PNG、打开本地图片、可选登录启动。
- 原生 Swift / AppKit / ScreenCaptureKit，无常驻录屏或后台轮询。

下载 `MacMark-*-universal.dmg`，打开后把 MacMark 拖到 Applications。
同一份安装包可用于两种芯片。

**当前版本采用 ad-hoc 签名，未经 Apple Developer ID 签名和公证。** 首次打开如被系统拦截，
请先尝试打开一次，再进入「系统设置 → 隐私与安全性」点击「仍要打开」。
首次截图还需要允许屏幕录制权限，授权后退出并重新打开应用。
请仅从本仓库 Releases 下载。详细步骤见仓库 `INSTALL.txt` 或 DMG 中的安装说明。

快捷键：⌘⇧2 截图，⌘C 复制，⌘S 保存，⌘Z 撤销，⇧⌘Z 重做。
A 箭头 / L 直线 / P 画笔 / R 方框 / T 文字 / V 选择。

自动测试覆盖两种架构的选区映射、PNG 导出、标注位置和编辑历史。
系统权限、不同显示器组合及实际交互仍需要在真实 Mac 上验证。
`idle-sample.txt` 是 CI 上的短时间空闲样本，不代表长期能耗。
