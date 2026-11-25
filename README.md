# CarPlayCast

一个最小的 CarPlay 音频 App，外加一个「补偿版导出」工具（给 CarMovie 这类车机视频播放器用）。

仓库里只有 7 个文件，全部是文本，手机浏览器就能建完。

```
App.swift                       全部代码（约 700 行，单文件）
Info.plist                      含 CarPlay scene 声明
CarPlayCast.entitlements        com.apple.developer.carplay-audio
project.yml                     XcodeGen 工程配置
build.sh                        macOS 上一键出包
README.md                       本文件
.github/workflows/build-ipa.yml 云端出包流水线
```

## 只有手机，怎么变成安装包

前提：一个 GitHub 账号。整个过程不需要 Mac。

### 1. 建仓库

github.com → New repository → 名字随意（比如 `carplaycast`）→ 选 **Public** → 不要勾任何初始化文件 → Create。

### 2. 上传 6 个文件

仓库页 → `Add file` → `Upload files` → 从「文件」App 里多选这 6 个（都在本压缩包根目录）：

- `App.swift`
- `Info.plist`
- `CarPlayCast.entitlements`
- `project.yml`
- `build.sh`
- `README.md`

上传完点 `Commit changes`。注意别把 `.github` 文件夹拖进去（手机上传不保留目录结构）。

### 3. 单独建流水线文件

仓库页 → `Add file` → `Create new file` → 文件名输入：

```
.github/workflows/build-ipa.yml
```

（输完整路径，GitHub 会自动建目录）→ 把压缩包里同名文件的内容整段粘进去 → Commit。

### 4. 跑一次

仓库页 → `Actions` → 左侧 `build-ipa` → 右侧 `Run workflow` → 绿色按钮。

第一次会问你是否信任这个 workflow，点确认。等 3–5 分钟。

### 5. 取包

跑完点进那次运行 → 页面底部 `Artifacts` → 下载 `CarPlayCast-ipa.zip`。

用「文件」App 点一下解压，得到 `CarPlayCast.ipa`。

### 6. 装

用 TrollStore 打开这个 ipa → Install。

## 第一次大概率会遇到的三个错

| 报错 | 原因 | 处理 |
|---|---|---|
| `xcodebuild: error: The directory does not contain a project` | `project.yml` 没上传成功 | 回仓库确认文件在根目录 |
| `ldid: command not found` | brew 装 ldid 失败 | 把日志贴给我，我改成下载二进制 |
| `error: Multiple commands produce Info.plist` | Info.plist 被当成了资源 | 确认 `project.yml` 里 `sources` 只有 `App.swift` |

## 有 Mac 的话

```bash
chmod +x build.sh && ./build.sh
# 产物 build/CarPlayCast.ipa
```

## 验证装没装上

```bash
ldid -e Payload/CarPlayCast.app/CarPlayCast
```

要能看到 `com.apple.developer.carplay-audio`。看不到就是签名那步没生效，手机主屏能开、车机不显示。

## 功能

**车载播放**：车机主屏出现「车载播放」列表，播放/停止 440Hz 测试音（运行时合成，没有二进制资源）。

**视频同步**：画面在手机、声音走车机时，拖滑杆把画面延后 0–600ms，补偿 CarPlay 音频链路延迟。每秒自动纠偏一次，长视频不会越看越偏。

**补偿版导出**：给 CarMovie 这类闭源播放器用。它内部时序改不了，那就把音画补偿做进文件——导出 `synced_XXXms.mp4`，存到「文件」App → CarPlayCast，用 CarMovie 打开。

方向判断：先听到声音、后看到动作 = 声音偏早，用正值；反过来用负值。

## 边界

- CarPlay 没有视频通道，第三方 App 在车机上放视频只能靠私有 API 或镜像，本工程不做。
- entitlement 靠 TrollStore 的 ldid 写进签名，系统认不认要实机试。
- 补偿值是每台车一个常数，换车、换有线/无线都要重调。
- 流媒体（m3u8 链接）没法预先补偿，只能处理本地文件。
