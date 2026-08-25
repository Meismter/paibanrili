# ShiftScheduler · iOS 排班应用

按月计划排班的本地 iOS 应用：支持导入 Word/Excel/TXT/微信文本智能识别排班、手动点击排班、快速轮转排班、自定义班次（名称/时间段/颜色）、系统日历双向同步、桌面小组件（大/中/小三种尺寸：Small=当前/下一班次、Medium=未来7天、Large=未来30天）。

## 技术栈

- iOS 17+ · Swift 5.9 · SwiftUI
- SwiftData（本地持久化，App Group 共享）
- WidgetKit（小组件扩展）
- EventKit（日历双向同步）
- ZIPFoundation（解析 .docx / .xlsx，唯一第三方依赖）
- XcodeGen（工程描述）

## 工程结构

```
shift_scheduler_ios/
├── project.yml            # XcodeGen 配置：App / Widget / Tests 三 target
├── ShiftScheduler/        # 主 App（模型、服务、解析引擎、界面）
├── SharedKit/             # 双 target 共享层（常量、快照加载、颜色、格式化）
├── ShiftWidget/           # 小组件扩展（Small/Medium/Large 三尺寸）
└── Tests/ParsingTests/    # 单元测试（日期识别、docx/xlsx 解析、跨午夜逻辑）
```

## 编译运行（需 macOS + Xcode 15+）

1. 安装 XcodeGen：`brew install xcodegen`
2. 在本目录执行 `xcodegen generate`，生成 `ShiftScheduler.xcodeproj`
3. 打开工程，在 Signing & Capabilities 为 App 和 Widget 两个 target 选择同一开发者团队
   - App Group 首次使用可能需要在开发者后台注册 `group.shiftscheduler.shared`
4. 选 iPhone 模拟器（iOS 17+），`Cmd+R` 运行；`Cmd+U` 运行单元测试
5. 小组件验证：模拟器桌面长按 → 添加「排班」小组件，可切换大/中/小三种尺寸

> 备选方案：不用 XcodeGen 可手动新建 iOS App 工程，对照 project.yml 建 Widget Extension target、勾选 SharedKit 目录双 target membership、添加 App Group capability，并通过 File → Add Package Dependencies 添加 ZIPFoundation（https://github.com/weichsel/ZIPFoundation.git）。

## 功能入口

| 功能 | 入口 |
|------|------|
| 月历排班 / 手动点击排班 | 排班 Tab，点击日期格子 |
| 快速排班 | 排班 Tab 底部「⚡快速排班」 |
| 导入 Word/Excel/TXT/微信文本 | 排班 Tab 底部「⬆️导入」，解析后预览确认再写入 |
| 班次自定义（名称/时间/颜色） | 班次 Tab |
| 同步到日历 / 从日历导入 | 设置 Tab → 日历同步 |

## 关键设计约定

- 颜色统一存 `#RRGGBB`（12 色预设色板）；时间用距午夜的分钟数（0...1439）存储
- 跨午夜班次（如 22:00–06:00）归属开始日，结束时间自动 +1 天（`DateUtils.crossesMidnight` 单点判定）
- 日历事件去重标识：notes 首行 `[SS:<entryUUID>]`，同步冲突以 App 数据为准删旧建新
- 智能识别为规则引擎（正则 + 关键词词典 + 启发式打分），置信度 <0.6 的结果黄色高亮强制人工确认

## 无 Mac / 无开发者证书：GitHub Actions 云端打包 IPA

本仓库内置 `.github/workflows/build-ipa.yml`，可在 GitHub 免费 macOS 虚拟机上编译出未签名 IPA，无需本机 Mac、无需证书：

1. 把本项目推送到 GitHub 仓库（私有仓库即可，免费版每月 2000 分钟 macOS 构建额度）
2. 仓库 **Actions** 页面 → 左侧选中 **Build IPA** → 点 **Run workflow** 手动触发
3. 构建完成后（约 5 分钟）在本次运行页面底部 **Artifacts** 下载 `ShiftScheduler-unsigned-ipa.zip`，解压得到 `ShiftScheduler-unsigned.ipa`
4. Windows 电脑安装 **Sideloadly**（https://sideloadly.io），用您的**免费 Apple ID** 将 IPA 签名安装到 iPhone（需 USB 连接 + 安装 iTunes）

⚠️ 免费签名限制：① 不支持 App Group → **小组件无法读取排班数据（显示空白）**，主 App 功能不受影响；② 签名有效期 7 天，到期需重新签名安装；③ 同时最多 3 个免费签名应用。
