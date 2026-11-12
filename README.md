# LiteFilm for iOS

LiteFilm 是基于 SpektraFilm / SpektraLab 的 iPhone 与 iPad 胶片照片编辑应用。工程和 scheme 保留 SpektraFilm 名称。

[官网与帮助](https://www.superaitest.com/litefilm/) · [隐私政策](https://www.superaitest.com/litefilm/privacy.html)

当前版本 0.1.0（build 10）：36 款相框、本地画廊、裁剪、精细调色、局部修饰、文字、水印、配方与批量导出。RAW/DNG 仅支持系统可解码格式，并非完整 RAW 显影流程。

把 [spektrafilm](https://github.com/andreavolpato/spektrafilm) 的光谱胶片模拟做到 iPhone / iPad 上。渲染走 [SpektraLab](https://github.com/JamesQiu2005/SpektraLab) 的 C++ / Metal 引擎（`spk_engine.h` + `spektrafilm.metallib`），不是 LUT 套色，也不是把 Python 参考实现重写一遍。

film modeling powered by spektrafilm。引擎来自 SpektraLab（Hanze Qiu）。

## 用 Xcode 打开

需要 Xcode 26（本机验证过 26.6）和 iOS 17 以上的模拟器或真机。Apple 芯片。

1. 打开 `SpektraFilm.xcodeproj`。
2. 方案选 **SpektraFilm**。
3. 目标选任意 iPhone 或 iPad 模拟器，运行。

真机运行前请在 Xcode 的 Signing & Capabilities 中选择自己的开发团队，并将 Bundle Identifier 改成自己的唯一标识。仓库不包含签名证书、描述文件或账户凭据。

命令行编模拟器（把模拟器名字换成 `xcrun simctl list devices available` 里有的那一台）：

```bash
xcodebuild -project SpektraFilm.xcodeproj -scheme SpektraFilm \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -configuration Debug -derivedDataPath build/DerivedData -jobs 4 build
```

第一次会把 `vendor/SpektraLab/engine` 编成静态库，并用 iOS Metal 编译器打出 `spektrafilm.metallib`（`-fmetal-math-mode=safe`，和上游 macOS 脚本一样）。之后只改 Swift 时，引擎有戳记，不会整份重编。

装上模拟器后可以跑一次无界面自检。它用内置色卡走 Kodak Portra 400 / Portra Endura，并写出 JPEG、PNG、HEIC：

```bash
xcrun simctl boot "iPhone 17"
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/LiteFilm.app
xcrun simctl launch --console booted com.spektrafilm.ios --self-test
```

成功时日志里有一行 `SPEKTRAFILM_SELFTEST_OK`。

编译通用真机包（使用自己的开发团队）：

```bash
xcodebuild -project SpektraFilm.xcodeproj -scheme SpektraFilm \
  -destination 'generic/platform=iOS' -jobs 4 \
  -configuration Debug -derivedDataPath build/DerivedData \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID -allowProvisioningUpdates build
```

## 精细编辑与批量处理（build 10）

- **调整**：色温、色调、黑场、白场，与原有曝光、高光、阴影、对比度和饱和度共用预览与导出流程。「曲线与 HSL」提供五点主曲线和六个颜色通道，编辑时实时预览，取消不会写入。
- **局部与修复**：渐变、径向、画笔可局部调整曝光与饱和度；取样修复先指定来源，再涂抹目标。修复是带羽化的取样覆盖，不是 AI 内容识别。最多 24 个局部图层；改变裁剪或几何校正会清空位置相关的修饰，并可撤销恢复。
- **放大与分析**：预览下方放大镜进入 1–8 倍缩放、平移、原图对比、亮度直方图和高光提示。分析使用不含相框、文字、水印的照片预览；红色提示不会写入导出。1× 表示适合屏幕，并非原片像素级显示。
- **我的配方**：编辑器「更多」里命名保存、复制或应用调整。最多 50 个本地配方；套用时保留目标照片的裁剪与局部修饰。
- **编辑历史**：支持撤销、重做和跳回指定步骤，包括系统撤销手势。保留当前照片本次会话的最近 60 步；切换照片或重启后历史清空，已保存的配方和效果保持独立。
- **批量处理**：「全部作品 → 选择 → 批量」，每批最多 50 张。可按各作品保存方案导出，或统一使用当前效果、命名配方、已复制调整。没有保存方案的原始导入照片使用打开批量页面时的当前效果，界面会明确提示。逐张串行处理，支持取消、逐张错误反馈和分享已完成文件。
- **导出设置**：JPEG / PNG / HEIC、原尺寸（受设备内存上限约束）或长边 1280 / 2048 / 4096、每张体积上限、相框、水印；批量可单独关闭文字。体积上限可能降低质量与分辨率，无法满足时明确报错。

所有处理在本机完成，无需账号或外部 AI 服务。原始照片不会被覆盖。已有相册/画廊切换、原生翻页、文字与免费商用字体保持可用。

安装 Debug 包到专用模拟器后，可运行隔离的编辑测试（240 秒超时、96 线程上限）：

```bash
python3 Scripts/test_editing_suite.py --device SIMULATOR_UDID --output /path/to/editing-suite-test.log
```

测试覆盖颜色与局部处理的实际像素、旧配方解码、直方图方向、配方持久化、原生/自定义撤销、历史分支、照片切换，以及实际批量 JPEG / PNG 输出和体积限制。

## 相册与画廊（build 9）

「全部作品」顶部可切换相册与画廊，默认保留相册，并记住上次选择。
画廊以暖灰展墙、细边装裱与作品铭牌展示完整照片；竖屏向下浏览，宽屏支持双列，
手机横屏切换为横向看展。点按继续编辑、长按菜单、最近筛选和多选删除均可使用。
这只是浏览样式，不改变原照片或导出效果。文字工具改为独立的加号文字图标。

## 图片文字（build 8）

底部「文字」可添加最多 8 段文字，每段最多 200 字，支持换行、拖动位置、
字号、六种颜色、对齐和阴影。编辑页「完成」保存为一个可撤销步骤；「取消」
保留原状。文字随作品存档、恢复及导出，导出不带相框时仍保留文字。

内置 Noto Sans CJK SC Regular、Noto Serif CJK SC Regular 和霞鹜文楷 Regular，
均为未修改的 SIL OFL 1.1 字体，可免费商用；完整许可与版权保存在 `Licenses/`
并显示于应用「关于」。固定来源和 SHA-256 在
`SpektraFilm/Resources/Fonts/SOURCES.json`。照片和文字均在本机处理。

专用模拟器安装 Debug 后运行文字回归（90 秒超时、96 线程上限）：

```bash
python3 Scripts/test_photo_text.py --device SIMULATOR_UDID --output /path/to/text-test.log
```

## 应用里有什么

- 从照片里选一张图，或先看内置色卡。
- 选胶片和相纸。底部并排两列密实滚轮，上下拨动；分组仍是彩色负片、反转片、黑白，以及彩色/黑白相纸，组与组之间有一条细线。快速拨动会等停稳约 0.15 秒再渲染。换胶片时会带上该片建议的相纸。点预览或右上角进入全屏，全屏里同样可以拨滚轮，下滑或点向下箭头退出。目录来自真正的 spektrafilm 剖面，外加 SpektraLab 自己的黑白片和 CineStill 800T 别名。
- 曝光补偿大约 ±2 EV。自动曝光仍开着（中心加权）。
- 预览长边 2048。引擎的 `live` 档用同一长边，避免再留一份更大的工作集。
- 导出 JPEG、PNG 或 HEIC，支持单张与批量。导出前会丢掉预览用的 GPU 会话。导出长边按物理内存封顶：约 4 GB 以下 2048，约 6 GB 以下 3072，再大 4096，并且不会超过原图。这是为了躲开 jetsam，不是引擎的像素上限。
- 照片按 Display P3、带传输曲线送进引擎（`input_cctf_decoding`），结果也直接要 Display P3 编码，方便预览和导出。macOS 版默认停在 ProPhoto 工作空间里再做一次输出变换；这里没有那一层调色，所以没有照搬。

## 许可证

| 内容 | 许可证 | 文件 |
| --- | --- | --- |
| 本应用，以及它链接的 SpektraLab 引擎 | GPL-3.0 或更高版本 | `LICENSE`、`Licenses/GPL-3.0.txt` |
| spektrafilm 剖面、烘焙常数、打印 LUT | CC BY-SA 4.0，Andrea Volpato | `Licenses/SPEKTRAFILM_LICENSE.txt` |
| SpektraLab 黑白剖面 | SpektraLab 自己的数据，见说明 | `Licenses/PRODUCT_PROFILES_NOTICE.md` |
| metal-cpp | Apache-2.0 | `Licenses/metal-cpp-Apache-2.0.txt` |

署名写在 `Licenses/CREDITS.txt`，应用包里也会带上 `Licenses/`。剖面的再分发要保留 CC BY-SA 4.0、作者和项目链接。本应用是 SpektraLab 引擎的衍生作品，整体按 GPL-3.0 发布。SpektraLab 与 spektrafilm 项目没有从属或背书关系。

胶片和相纸名字是各自权利人的商标，只用来标明剖面依据的公开资料。

`vendor/SpektraLab` 随仓库包含构建所需源码，基于上游提交 `267ee24380091e5bee87658d00f6c33d77321194`，并包含下文所述 iOS 模拟器适配。以下为上游参考获取命令；不要在现有工作目录中覆盖适配源码：

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/JamesQiu2005/SpektraLab.git /tmp/SpektraLab-upstream
git -C /tmp/SpektraLab-upstream sparse-checkout set --skip-checks engine license LICENSE.txt README.md README.zh-CN.md CITATION.cff
```

改完剖面清单后重新生成应用里的目录：

```bash
python3 Scripts/gen_catalog.py
```

`SpektraFilm/Resources/FilmCatalog.json` 已经按这次检出的剖面生成好了。增删 Swift 文件之后，用 `python3 Scripts/generate_xcodeproj.py` 重写工程文件。

## 已经接上的

- iOS 17+ SwiftUI 应用，iPhone 和 iPad。
- SpektraLab `engine/src` 的 Metal 后端：核心、流水线、`metal_gpu.cpp`，以及全部 `src/shaders/*.metal`。模拟器目标 `air64-apple-ios17.0-simulator`，真机 `air64-apple-ios17.0`。
- 资源：`spektrafilm_constants.bin`、spektrafilm 的 28 个剖面、打印 LUT 索引，以及 SpektraLab 的黑白剖面。打包时把黑白中性滤色片并进 `neutral_print_filters.json`，否则黑白组合在引擎的滤色数据库里是空的。
- 至少一条真实胶片链路：Kodak Portra 400 负片 + Kodak Portra Endura 相纸。自检走的就是这一对。
- 模拟器上 `spk_result.texture` 不是 `MTLTexture`。模拟器会在共享缓冲上创建线性纹理时直接断言，而 `rgba16` 必须留在 `MTLStorageModeShared` 里才能给 CPU 读。`vendor/SpektraLab/engine/src/gpu/metal_gpu.cpp` 在 `TARGET_OS_SIMULATOR` 下改成持有这块缓冲的替身，`spk_result_free` 时释放。真机仍是原来的 buffer-backed texture。这个应用只读 `rgba16`。

## 还没有移植的

- 完整 RAW 显影。这里使用系统图像解码，只支持系统能够解码的 RAW/DNG。
- macOS 应用里的调色面板：曲线、蒙版、裁剪、白平衡吸管、对比度蒙版、场景宽容度、数字中间片、胶片齿孔和日期背印的界面。这些内核大多已经编进静态库（过扫和日期背印走 Core Text，iOS 上能编过），默认关着，界面没有开关。
- 逐帧 Metal 画布、直方图、多张胶片条、半格双幅、边车文件、代理 MCP。
- 预览是渲染完的 `CGImage`，不是把引擎纹理直接画进 `CAMetalLayer`。换胶片或曝光会重新跑引擎。
- 导出不是相机原尺寸。长边按上面的内存档封顶。
- 仓库不包含开发者的签名材料。
- 没有在真机上跑过渲染自检。模拟器 Metal 和设备 Metal 的数值、耗时、内存都会有差别。模拟器上的结果纹理替身不会编进真机包。

## 目录

```
SpektraFilm.xcodeproj    应用工程
SpektraFilm/             SwiftUI、桥接头、剖面目录、色卡
Scripts/build_engine_ios.py
Scripts/generate_xcodeproj.py
Licenses/                GPL、CC BY-SA、metal-cpp、黑白剖面说明
vendor/SpektraLab/       上游引擎源码（只读参考，构建会编译它）
```
