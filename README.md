# CalorieFit 卡路里管家

基于 ArkTS / ArkUI 的 HarmonyOS 原生饮食与活动记录应用。当前应用包名为 `com.rinne.caloriefit`，目标 SDK 为 HarmonyOS API 26。

## 功能概览

- 首次启动引导：目标、活动量、通知、补剂和生活方式；目标与活动量写入体征档案，并用于 BMR/TDEE 推导。
- 三个主 Tab：今日、进度、我的，**底栏只保留图标按钮**（不显示文字标签）。今日含热量主卡与今日黑板。产品面向单用户，不包含社群、好友动态或公开资料功能。
- **应用完全免费**：无应用内购买、无订阅、无付费墙，所有已实现功能默认全部开放。NutriScan 原版的「免费试用 1 周」与渐变「升级」入口已按产品决策整体删除。
- 食物与运动记录、餐食详情、宏量营养素目标、体征档案、主题偏好。
- “我的”页可清除本地健康档案、目标、记录和 AI 凭证；删除后不再用虚构体征值填充档案，饮水目标显示为未设置。
- 饮水和断食记录保存在本地 RDB；示例和推断内容有来源标识，尚未实现的入口进入说明页。
- **步数自动采集**：运动页可开启计步传感器自动统计当日步数（`SensorId.PEDOMETER`）。传感器给的是开机以来的累计值，本地做基线差值换算成当日步数，跨零点按时间比例重新拆分基线。手动填写的值优先于传感器，点「恢复自动采集」后交回传感器。
- AI 食物识别支持内置演示数据和用户配置的兼容服务。演示模式不发送网络请求；真实识别会将选中的照片发送到配置的 AI 服务进行分析。照片分析结果仅供参考。**默认服务方是 OpenCSG 模型网关（`https://opencsg.com/aigateway/v1`），默认模型 `deepseek-v4.1-flash-1017`**——该模型支持图片输入，识别实测 5~7 秒返回，并同时给出食物轮廓坐标供抠图使用。阿里云百炼（DashScope）仍可在 AI 设置里切换。
- **食物轮廓贴纸按 nosh 的模切贴纸做**：AI 给出的粗略轮廓只当先验，抠图会在边界带内用颜色模型把边界吸附到真实图像边缘上，边缘做抗锯齿，再沿轮廓烘一圈白色纸边（die-cut edge）——出来的是「浮在便签上的剪贴贴纸」，不是「方框里裁了一块照片」。纯本地计算，不新增网络请求。
- **今日黑板是可以自由摆放的手帐画布**（2026-10-21 改造）：贴纸与便签能拖拽、双指缩放、双指旋转、单击打开编辑抽屉、双击翻到背面看碎碎念，位置/缩放/角度/层级都落在本地库里，第二天打开还是自己摆的样子。板面可切黑板/软木/点阵三种底纹，可在「自由画布」与「按餐次分组的网格视图」之间切换，一键规整按早餐/午餐/晚餐/加餐排成两列，粉笔分栏线打开后把贴纸拖进哪一栏就归到哪一餐。**没有照片时黑板会自动铺 3 张内置矢量美食贴纸和 1 张心情便签**（示例不写入饮食记录，因此不会污染「今日摄入」；这一天有了真实记录后示例自动让位）。
- **端侧主体分割优先，抠图多一道保险**：支持 `CoreVisionKit` 的设备会用端侧主体掩膜给 AI 给的粗轮廓纠偏（取交集，重叠太少就退回原轮廓，绝不把食物抠空）；模拟器与不支持的机型自动降级回原来的颜色模型抠图，功能不受影响。

## 定价与收费

**本应用完全免费。** 没有应用内购买、没有订阅套餐、没有试用倒计时、没有权益墙，也没有服务端订阅校验。

唯一的外部成本来自 AI 食物识别：真实识别使用**用户自己配置的 API Key**，调用额度与费用由用户的模型服务商承担，与本应用无关。演示模式不发送网络请求。

界面上的体现：今日页页头显示不可点的「全部功能免费」标识；「我的 → 版本与授权」写明上述边界。

## 发布上架

**不需要自建服务器，不需要应用内账号体系**——核心功能（记录/统计/步数/目标）全部本地，断网可用。

上架前发布者需要准备的是：华为开发者账号（**实名认证是前提**）、release certificate 与 Profile、一个**公开可访问的隐私政策页面**、以及商店物料（图标/截图/描述/年龄分级）。

两个要拍板的点：

- **AI 识别功能怎么申报**。本项目是 **BYOK（自带 Key）模式**：API Key 由用户自己填、掏钱签约的是用户，**开发者与服务方没有合作关系**（拿不出「双方合作协议」）。但 Base URL 被 `validateBaseUrl()` 锁在**隐私政策已声明的服务方域名**内：默认 **OpenCSG（opencsg.com）**，同时保留 **阿里云百炼（DashScope）** 供用户切换——**真实识别只可能发给这两家**，所以审核要的「第三方大模型」备案截图对象也是这两家（均公开可查）。三个选项：①按「工具/客户端」申报，交备案截图、主张无合作协议（**审核方是否接受由其判定**）；②与其中一家签一份服务采购/授权文件；③发布版不含 AI（代码已留口子：AI 可选，演示模式零网络请求）。另外**放开域名白名单**（允许任意 OpenAI 兼容地址）能让 App 变成真正的通用客户端，按 ① 申报更站得住——这是个产品决策。
- **"单机 APP"判定**。官方标准是"断网后所有核心功能仍能正常使用"；AI 联网不在官方列出的豁免场景里，勾选前需谨慎。

完整流程、官方条款原文与给发布者的决策清单见[《NutriScan 复现交付说明》](交付说明_NutriScan复现.md) §11.2 与 §11.3。

## 跨平台

本项目在 Windows 上开发，**迁移到 macOS 继续开发不需要改代码**：构建配置里没有绝对路径，
验证脚本（`tools/`）已改为按仓库位置反推路径 + 按平台探测 DevEco SDK。

**但要先确认你的 Mac 芯片**：Apple Silicon 有本地模拟器；**Intel (x86_64) 官方已不支持
macOS 本地模拟器**，只能装真机调试。完整步骤（环境、镜像、签名、验证清单、已知坑）见
[《迁移到 macOS 继续开发》](迁移到mac.md)。

## 技术栈与数据

- **UI / 语言**：ArkUI 声明式 UI、ArkTS、Stage 模型。
- **SDK**：HarmonyOS 26.0.0，`compatibleSdkVersion` / `targetSdkVersion` 为 `26.0.0`。
- **持久化**：ArkData RDB（`caloriefit.db`），当前 7 张业务表：`app_settings`、`food_log`、`exercise_log`、`daily_activity`、`body_profile`、`water_log`、`fasting_log`。`food_log_v2` 是迁移过程使用的临时表。
- **依赖**：`@pura/harmony-dialog`（`^1.1.8`）。
- **运动数据**：运动记录（类型/时长/热量）由用户手动填写；**步数可由计步传感器自动采集**，需在运动页主动开启并授予 `ohos.permission.ACTIVITY_MOTION`。设备没有计步传感器时自动采集不可用，手动填写仍然可用。
- **主题**：新安装默认深色以还原 NutriScan 实测视觉；用户可改为跟随系统或浅色。

## 单元测试（ohosTest）

步数基线算法和步数写入优先级这类**边界逻辑**跑在设备上的真实代码里，不是等价实现复写：

```powershell
$env:DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk"
& "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" `
  --mode module -p product=default -p module=entry@ohosTest -p buildMode=debug assembleHap --no-daemon

$hdc="C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
& $hdc install -r entry\build\default\outputs\ohosTest\entry-ohosTest-unsigned.hap
& $hdc shell aa test -b com.rinne.caloriefit -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000
```

当前 **22 项全通过**：18 项覆盖基线算法（首日/跨天拆分/重启复位/负值钳制/时间戳单位自标定），4 项覆盖步数写入优先级（手动值不被传感器覆盖、恢复自动采集后重新接管、来源角标文案）。

测试包与主包同样是未签名包，只能装在模拟器/调试设备上。

## 构建与安装（调试版）

使用本机 DevEco Studio 自带的 Hvigor 与 HDC：

```powershell
$env:DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk"
& "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" `
  --mode module -p product=default -p buildMode=debug assembleHap --no-daemon

$hdc="C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
& $hdc tconn 127.0.0.1:5555
& $hdc install -r entry\build\default\outputs\default\entry-default-unsigned.hap
& $hdc shell aa start -b com.rinne.caloriefit -a EntryAbility
```

上面的 HAP 是未签名调试包，可用于本机模拟器调试。目前 `build-profile.json5` 没有配置签名档，尚未产出可分发的正式签名包；发布前需要配置开发者证书、Profile 和正式签名设置。

## 当前验证状态（2026-10-21）

- **今日黑板自由画布改造（本轮最新）**：调试 HAP `entry/build/default/outputs/default/entry-default-unsigned.hap`，
  3,331,019 字节，SHA-256 `cdbb4bf6c054112ed8e0c2d4bcf1542c7364806dfa85a7858dc2031438356d27`，18:41 构建。
  今日黑板从「只能看的横向便签卡流」重做成**可自由摆放的手帐画布**：拖拽/双指缩放/双指旋转、
  点击置顶、单击开编辑抽屉、双击翻面、一键按餐次规整、自由画布↔结构化网格切换、
  粉笔分栏（拖进哪一栏就归哪一餐）、三套底纹、componentSnapshot 生成手帐分享卡。
  另有端侧主体分割（`CoreVisionKit`）给抠图先验纠偏，以及三张内置矢量美食贴纸当空板示例。
  验证：设备端单测 **65/65 PASS**（新增 `BoardCanvas.test.ets` 11 条）；
  `tools/verify_all.py` **14/14 PASS**；黑板画布专项 `tools/verify_board_canvas.py`（新增）**11/11 PASS**；
  `tools/verify_blackboard.py` **15/15 PASS**；`tools/verify_free_markers.py` 全部通过；
  `tools/verify_privacy_runtime.py` 全部通过。
  截图：`tools/shots/bc_*.jpeg`、`tools/shots/bb_*.jpeg`，证据在 `work/board-canvas-20261021/evidence/`。
  详见 `交付说明_NutriScan复现.md` §17。
- 回归脚本要用**系统 Python**跑：`/usr/bin/python3`（只有它装了 Pillow，PATH 上的 homebrew python 没有）。
- 上一版（2026-10-20「完全免费」版本，本轮最新）**：调试 HAP `entry/build/default/outputs/default/entry-default-unsigned.hap`，2,824,437 字节，SHA-256 `eb04da31e0a5ba40b98807398c328fe6c95cd786bf1109932ec6b25a0f89d56c`，09:29 构建。`assembleHap` BUILD SUCCESSFUL，已安装到 Mate 90 Pro 模拟器。`tools/verify_all.py` 结果 **10 PASS、1 SKIP、0 FAIL（11 项）**；唯一 SKIP 是饮水 V4 持久化 —— 模拟器已有饮水记录，脚本为避免覆盖现有记录主动跳过，与本次改动无关。专项实机确认：今日页页头渲染「全部功能免费」且 UI 树中已无「免费试用 1 周」/「升级」；「我的 → 版本与授权」卡正常渲染；饮水页火焰图标仍为橙色（`streak_orange` 生效）。日志：`work/nutriscan-ui-fidelity-20261019/evidence/verification-20261020-free-version.txt`；截图：`tools/shots/free_header.jpeg`、`free_profile.jpeg`、`free_license.jpeg`、`free_water.jpeg`。
- 上一版调试 HAP（SHA-256 `70636AD95DFDF149DB5C7C1B615E735931B5A9A4C5EB9B1C20520CF8030933DD`）的回归为 11 PASS、0 SKIP、0 FAIL，已被上述版本取代。
- 最新调试 HAP 由当前源码构建，已安装到 Mate 90 Pro 模拟器并用于本轮回归：`entry/build/default/outputs/default/entry-default-unsigned.hap`，2,812,758 字节，SHA-256 `70636AD95DFDF149DB5C7C1B615E735931B5A9A4C5EB9B1C20520CF8030933DD`。本轮 `tools/verify_all.py` 结果为 **11 PASS、0 SKIP、0 FAIL**，覆盖综合页、AI 入口和本地演示识别、轮播像素差分、餐食列表与详情、饮水/断食 V4 重启持久化。饮水测试读取 250 ml 后通过页面“撤销”清理了测试记录；断食测试结束了本次测试方案。日志：`work/nutriscan-ui-fidelity-20261019/evidence/verification-20261020-single-user-final.txt`；截图位于 `tools/shots/`。此 HAP 未签名，项目没有配置发布签名；ArkTS 编译警告仍需发布前处理或逐条确认。
- 本轮将“综合”子页图标换为本地食物碗 SVG，并将饮水“撤销”入口移入快捷记录区；轮播像素变化 **16.6%**，主卡锚点变化 **0.00%**。最新综合页与轮播截图分别为 `tools/shots/v_01_home.jpeg`、`tools/shots/v_03_carousel.jpeg`。回归结束后模拟器已返回“今日热量”首页。
- release `assembleHap` 也成功编译；未签名包已在 Mate 90 Pro 模拟器安装并启动到首页，完成一次冒烟确认。Hvigor明确跳过签名：工程没有 release certificate/Profile。release HAP 单独留档于 `work/nutriscan-ui-fidelity-20261019/artifacts/entry-default-release-unsigned.hap`（1,273,773 字节，SHA-256 `B9D686CE9672923B90D70EA9BC8FF87B006E613DEB47ECF37C42A0A20C4E72AB`），不能上传 AppGallery。当前 release 混淆仍关闭，需在完成规则配置和运行回归后再决定启用。
- Hvigor `assembleApp` 也成功生成 release App Pack；Hvigor 对 `.app` 同样跳过签名。产物留档于 `work/nutriscan-ui-fidelity-20261019/artifacts/calories-default-release-unsigned.app`（618,088 字节，SHA-256 `B39FA1511D66395334D690279CFD9A8EB2830129DB6D96441EFBA94A5D782BA4`）。这不是可上传的签名包。
- 首页半环、单卡提示轮播与方形空餐食卡已按参考图修正；较早单用户校准截图为 `work/nutriscan-ui-fidelity-20261019/evidence/single-user-scope/home-layout-final.jpeg`。模拟器截图只验证模拟器画面；当前 ADB 未列出真机，因此真机逐页安全区域和视觉对照仍待设备桥接恢复。
- 此前 **8/8** 的完整回归属于旧 HAP（SHA-256 `90137BE19295323D973AE2DE56004DCFF9FFDB55261C706B9230B30F3BE6963F`，15:09 构建），不是本轮结果。该次确认新安装默认深色，隐私页与首页背景/卡片/描边为 `#0C0C0C / #1C1C1E / #2F2F33`；轮播横带像素变化 **36.6%**、首页主卡锚点变化 **0.00%**。截图见 `work/nutriscan-ui-fidelity-20261019/evidence/regression-20261019-1509-dark-default/`。
- 饮水 V4 的重启持久化曾因模拟器已有记录而跳过；此限制已由 2026-10-20 当前 HAP 的回归覆盖并通过。更早水与断食都通过强停重启的记录属于前一 HAP（SHA-256 `9DD96224E0F8FA9990D94C3BC9B0034FB62681827218F6AF3C4B70FE6EF30055`）。
- AppGallery 图标已从项目矢量图标生成 `store-assets/appgallery/icon-1024.png`，尺寸与 PNG 格式已检查；商店截图尚未生成，须从已验证的最新构建采集。HarmonyOS 手机/平板要求 3–5 张 1080×1920 竖屏截图，详见[华为 AppGallery 素材规格](https://developer.huawei.com/consumer/en/doc/agc-help-app-visual-asset-spec-0000002277607976)。
- 本次设备复查中 HDC 只发现 `127.0.0.1:5555` Mate 90 Pro 模拟器；ADB 设备列表与 mDNS 服务列表为空，Windows PnP 中也没有 Xiaomi/Android 设备。因此本轮不能声称已完成真机逐屏验收。
- 隐私专项运行通过：临时假 API Key 开启“安全记住”后，强制停止并重启应用仍可读回；真实识别展示 HTTPS 接收地址、照片与 API Key 说明，点取消后没有识别结果，也未发送网络请求；删除/撤回操作将应用送回首启同意页。HDC 不允许直接列出应用沙箱，因此未独立读取数据库/Asset 内容确认删除后的底层值。记录见 `work/nutriscan-ui-fidelity-20261019/evidence/verification-20261019-privacy-runtime.txt`。
- 深色主题已恢复为平面样式：页面底 `#0C0C0C`、卡面 `#1C1C1E`、描边 `#2F2F33`；新安装默认深色，饮水页统计行的加号避让也有模拟器截图验证。真机目前仅采到底栏参考，其他页面的安全区域和视觉对照仍待补齐。
- 删除操作已通过应用界面运行验证；API Key 跨重启读取已验证。关闭“安全记住”后的清除边界仍需单独验收。
- HarmonyOS 模块/Ability 的英文模板描述已替换为 CalorieFit 中文文案；开发者身份、正式隐私政策和商店发布物料仍待确认。
- 上架仍受未签名、隐私政策草案中的发布者/AI 接收方/未成年人信息待补、发布者资料待确认，以及 Mock/ComingSoon 功能范围未定等事项阻塞。首启同意和 AI 上传前告知已实现并通过模拟器验证。具体清单见[《NutriScan 复现交付说明》](交付说明_NutriScan复现.md) §11。

复现范围、实测依据和已知限制见[《NutriScan 复现交付说明》](交付说明_NutriScan复现.md)。本轮模拟器截图保存在 `work/nutriscan-ui-fidelity-20261019/evidence/`（本地工作证据）。
