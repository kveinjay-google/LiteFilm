# LiteFilm 通透光带图标 — build 13

用户选定生图方案 A，原图由内置 image_gen 生成，不使用 SVG。保留选定构图，仅用 sips 缩放为资产目录要求的尺寸。

## 替换范围

- AppIcon：13 个不重复 PNG 尺寸，包含 1024×1024 商店图标。
- BrandIcon：96、192、288 像素，共用于系统 LaunchScreen、SwiftUI 启动页、首页空状态、设置与关于入口。
- 版本：0.1.0 (13)。未改变编辑逻辑。

## 验证

- 所有 16 个 PNG 尺寸正确且无 alpha；主图 SHA256：`8bce3ba7455fb898cf627866113348c0ef67635b7616b37c5c08bba0977eb76e`。
- Release 真机构建、Debug 模拟器构建通过；每次 1 job、1800 秒进程组超时，构建串行。
- Release 包 codesign --verify --deep --strict 通过，CFBundleVersion 为 13。
- 已通过 devicectl 安装到 Kevin 的 iPhone 17 Pro Max，并成功启动。
- 专用模拟器启动成功；CUA 实际检查设置页面，新光带图标与版本 0.1.0 · 13 正确显示。
- 真机屏幕自动化 runner 离线，因此不声称已获取真机截图。simctl 截图保存被系统拒绝，改用 CUA 检查实际显示。
- 既有构建警告：脚本无输出依赖、EngineClient 冗余 try、Core Image 旧接口弃用；没有构建错误。
- 本次未提交 App Store 或 TestFlight。

## 素材与日志

外置归档：`/Volumes/LEXA 4TB DISK/媒体资源库/发布/LiteFilm/2026-11-12-icon-redesign/`，含选定原图、资产校验 manifest、构建与安装启动日志。

## 原始生图提示词

Create one exquisite, finished iOS app icon for LiteFilm, a premium photographic film editing app. Concept A: CHROMATIC LIGHT. A single bold sculptural ribbon of photographic light folds into an abstract lowercase l / open photographic frame, simple instantly recognizable silhouette, luminous apricot transitioning through vermilion to subtle rose, with a restrained translucent cyan glint at one overlapping edge. Deep ink teal full-bleed square background. Beautiful optical glass material, soft directional studio light, restrained depth, extremely refined contemporary commercial app identity. The symbol occupies 68 percent of the square, optically centered, balanced spacious composition, legible at 40px. No text, no lettering, no camera illustration, no sprocket holes, no metallic gold, no chunky bevel, no elaborate details, no multiple icons or mockup. Deliver only the actual square icon artwork, edge to edge opaque background, no rounded outer corners and no surrounding margin.
