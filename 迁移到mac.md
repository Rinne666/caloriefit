# 迁移到 macOS 继续开发

本项目在 Windows 上开发，迁移到 Mac 时**代码基本零改动**，需要处理的是环境、SDK 路径、
模拟器镜像和签名材料。下面按实际执行顺序写。

---

## 0. 先确认一个决定性的事实：你的 Mac 是什么芯片

这一步决定了你**能不能用本地模拟器**，先查再动手。

```bash
uname -m        # arm64 = Apple Silicon；x86_64 = Intel
```

| 芯片 | DevEco Studio | 本地模拟器 | 结论 |
|---|---|---|---|
| **Apple Silicon (arm64)** | 有 ARM 版 | ✅ 支持（直板手机机型） | 可以完整复刻现在的开发+回归流程 |
| **Intel (x86_64)** | 有 x86 版 | ❌ **官方已不再支持 macOS x86 本地模拟器** | 只能装到**真机**上调试 |

华为官方 FAQ 原文：*"DevEco Studio 当前只支持 Mac ARM 版本的本地模拟器，x86 本地模拟器计划什么时间支持? 当前优先提供直板手机的模拟器，支持 Mac ARM 和 Windows X86，不再支持 macOS x86 本地模拟器。"*

**如果是 Intel Mac**：编译、调试、单测都正常，只是 `tools/verify_all.py` 这种依赖
模拟器 UI 树的自动化回归跑不了，得改成真机手工验证，或把项目放到另一台机器上跑回归。

---

## 1. 把代码带走

### 1.1 当前仓库状态

**本项目没有配置 git remote**（`git remote -v` 为空），所以现在推不了。先建一个远端：

```bash
cd <项目目录>
git remote add origin <你的 GitHub / Gitee 仓库地址>
git push -u origin feature/glass-poster-ui
git push origin main
```

分支情况：

| 分支 | 说明 |
|---|---|
| `main` | 停在 `20f9f01`，是干净基线，**不要动** |
| `feature/glass-poster-ui` | 当前所有工作都在这里，**21 个提交** |
| `feature/nutriscan-parity` | 早期分支，可不管 |

> 没有远端的话，退而求其次：直接拷贝整个项目目录（见 1.3 的注意事项）。

### 1.2 跟着 git 走的（会完整迁移）

`entry/`、`AppScope/`、`tools/`、`.gitignore`、`.gitattributes`、
`README.md`、`交付说明_NutriScan复现.md`、`build-profile.json5`、
`oh-package.json5` / `oh-package-lock.json5`。

**构建配置里没有任何绝对路径**（已核查 `build-profile.json5`、`oh-package*.json5`），
换平台不会因为路径写死而失败。

### 1.3 不跟着 git 走的（要单独处理）

| 目录/文件 | 内容 | 迁移办法 |
|---|---|---|
| `entry/oh_modules/` | 依赖（含 `@ohos/hypium`） | **不用拷**，在 Mac 上 `ohpm install` 重装 |
| `work/` | 证据归档、release 产物、**Windows 版 platform-tools（adb.exe 等）** | 需要的话单独拷；其中的 `.exe`/`.zip` 在 Mac 上用不了 |
| `store-assets/` | AppGallery 图标素材 | 在版本控制内，会自动跟着走 |
| `_tools/` | 一次性改造脚本 | 可选；可复用的脚本已迁到 `tools/` |
| 签名材料 `.p12` / `.cer` / `.p7b` | **不在仓库里** | 必须单独拷贝，Mac 上重新配置到 `build-profile.json5` |

`work/` 体积约 45 MB（大部分是第三方二进制），用 git 传不划算，也不该进仓库。

---

## 2. Mac 上装环境

### 2.1 DevEco Studio

从[下载中心](https://developer.huawei.com/consumer/cn/download)按芯片选 ARM 或 x86 版，
拖进 `/Applications`。HarmonyOS SDK、Node.js、Hvigor、OHPM、模拟器平台都**已内嵌**，
不用单独装。

系统要求：macOS 11+ (Intel) / 12+ (ARM)，内存 8 GB 以上（建议 16 GB），磁盘留 100 GB。

装完在 DevEco 里跑一次 `Help → Diagnostic Tools → Diagnose Development Environment` 确认环境。

### 2.2 路径对照

| | Windows | macOS |
|---|---|---|
| SDK 根目录 | `C:\Program Files\Huawei\DevEco Studio\sdk` | `/Applications/DevEco-Studio.app/Contents/sdk` |
| hdc | `...\sdk\default\openharmony\toolchains\hdc.exe` | `.../sdk/default/openharmony/toolchains/hdc` |
| hvigor | `...\tools\hvigor\bin\hvigorw.bat` | `.../tools/hvigor/bin/hvigorw` |
| ohpm | `...\tools\ohpm\bin\ohpm.bat` | `.../tools/ohpm/bin/ohpm` |

**编译**（Mac 版）：

```bash
export DEVECO_SDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk"
export PATH="$PATH:/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin"
export PATH="$PATH:/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin"
export PATH="$PATH:/Applications/DevEco-Studio.app/Contents/tools/node/bin"
export PATH="$PATH:$DEVECO_SDK_HOME/default/openharmony/toolchains"

# 确认环境就绪：三个都能出版本号即可
hvigorw --version
ohpm --version
node --version
hdc list targets
java -version     # hvigor 需要 JDK

"/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw" \
  --mode module -p product=default -p buildMode=debug assembleHap --no-daemon
```

> 如果 DevEco 不在 `/Applications`，把 `DEVECO_SDK_HOME` 改成实际安装路径即可；
> 仓库里没有写死任何路径。`tools/harmony_paths.py` 也会自动探测这两个位置。

### 2.3 依赖

```bash
cd <项目目录>
"/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm" install
```

`oh-package-lock.json5` 在版本控制内，锁的是 `@ohos/hypium@1.0.29` 和
`@pura/harmony-dialog`。若 ohpm 拉取慢，先确认 registry：

```bash
ohpm config set registry https://repo.harmonyos.com/ohpm/
```

### 2.4 模拟器镜像（**要重新下载，3–8 GB**）

Windows 上那份镜像在 `AppData\Local\Huawei\...` 下，**不能直接搬**。Mac 上要重新下：

- 图形界面：`Tools → Device Manager → Local Emulator → New Emulator`，选 Phone → 选型号 → Download 镜像
- 命令行（可选，需先 `npm install -g @deveco/deveco-cli@latest`）：
  ```bash
  devecocli emulator image list --device-type phone --all
  devecocli emulator image download --device-type phone --os-version 6.0.0.112
  devecocli emulator create myPhone --device-type phone --os-version 6.0.0.112
  devecocli emulator start myPhone
  devecocli device list        # 成功后能看到 127.0.0.1:5555
  ```

模拟器 serial 与 Windows 一样是 `127.0.0.1:5555`，所以 `tools/` 里的脚本不用改。

### 2.5 签名

- 调试签名：DevEco 里 `File → Project Structure → Signing Configs` 勾选自动生成，登录华为账号即可
  （命令行：`devecocli auth login` + `devecocli signature generate --product default`，材料落在 `~/.ohos/config/`）
- 发布签名：**必须在 AGC 申请 release certificate + Profile**，把 `.p12` / `.cer` / `.p7b`
  三个文件从 Windows 拷过去，填进 `build-profile.json5` 的 `signingConfigs`

---

## 3. 跨平台路径已经处理好了

原先所有脚本都把 `C:\Program Files\...` 和 `C:\Users\18165\Desktop\calories\...` 写死，
迁到 Mac 全部会失效。**本轮已改造**：

- 新增 `tools/harmony_paths.py` —— 统一解析 hdc 路径、仓库根目录、截图目录
  - SDK 位置按平台自动探测（Windows 走 `C:\Program Files\...`，macOS 走 `/Applications/...`）
  - 仓库内路径一律从 `__file__` 反推，跟着仓库走
  - 可用环境变量覆盖：`DEVECO_SDK_HOME`、`HARMONY_HDC`
- 可复用脚本已从 `_tools/`（不入库）**迁到 `tools/`（已纳入版本控制）**：
  `verify_all.py`、`ui_drive.py`、`verify_privacy_runtime.py`、`verify_sweep.py`、`dump_texts.py`
- 截图输出改到 `tools/shots/`（不入库）
- 新增 `.gitattributes` 统一行尾为 LF，避免跨平台假 diff

**Mac 上跑验证脚本不需要改任何路径**：

```bash
cd <项目目录>
python3 -u tools/verify_all.py
```

> `verify_sweep.py` 需要 Pillow（`pip3 install pillow`），其余脚本只用标准库。

---

## 4. 迁移后的验证清单

按顺序做，每步都要看到明确的成功输出，别凭"应该没问题"：

| # | 动作 | 期望 |
|---|---|---|
| 1 | `ohpm install` | 装出 `entry/oh_modules/`，无报错 |
| 2 | `assembleHap` | `BUILD SUCCESSFUL`，产出 `entry/build/default/outputs/default/entry-default-unsigned.hap` |
| 3 | 装到模拟器并启动 | `install bundle successfully.` + `start ability successfully.` |
| 4 | 跑单元测试 | `Tests run: 22, Failure: 0, Error: 0, Pass: 22` |
| 5 | 跑 UI 回归 | `10 passed, 1 skipped, 0 failed (11 checks)` |
| 6 | 手动看一遍 | 今日页页头「全部功能免费」、运动页「自动采集/已开启」、我的页「版本与授权」 |

第 4 步的完整命令：

```bash
export DEVECO_SDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk"
"/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw" \
  --mode module -p product=default -p module=entry@ohosTest -p buildMode=debug assembleHap --no-daemon
HDC="$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc"
$HDC install -r entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap
$HDC shell aa test -b com.rinne.caloriefit -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000
```

---

## 5. 已知会踩的坑

1. **模拟器息屏会让自动化脚本在第一步就失败。**
   报 `dumpLayout failed: Get window nodes failed`，看起来像代码坏了，其实是屏幕黑了。
   `tools/verify_all.py` 现在每次取 UI 树前会先 `power-shell wakeup`；手工操作时
   若又遇到，先唤醒屏幕再跑。

2. **模拟器会自己掉线。** 本轮 Windows 上反复出现 `hdc list targets` 变 `[Empty]`、
   `Emulator.exe` 进程还在但 5555 端口不监听。Mac 上如果同样，重新启动模拟器实例即可；
   `tools/verify_all.py` 会在桥接不通时直接退出，不会假装跑过。

3. **测试状态会被上一次跑残留污染。** 脚本要求"隐私同意 + 五步引导"作为硬前置，
   中途失败会留下半截状态。重新开始前先清干净：
   ```bash
   $HDC shell bm clean -n com.rinne.caloriefit -d
   $HDC shell aa start -b com.rinne.caloriefit -a EntryAbility
   ```

4. **传感器在模拟器上不产生真实步数。** 计步传感器存在（`sensorId 266`）但读数恒为 0，
   所以"真实走路→步数累加"没有端到端证据，只有单测覆盖。真实步数必须在真机上验。

5. **macOS x86 机器没有本地模拟器**（见第 0 节），UI 回归自动化在 Intel Mac 上跑不了。

---

## 6. 一句话总结

代码不用改，**改的是三样东西**：DevEco Studio + SDK、模拟器镜像、签名材料。
`tools/` 里的脚本已经做成跨平台的，克隆下来就能跑。
