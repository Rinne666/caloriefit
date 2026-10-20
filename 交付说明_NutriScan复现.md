# NutriScan → CalorieFit 复现交付说明

> 分支 `feature/glass-poster-ui` · 目标平台 HarmonyOS NEXT (API 26) · 单用户导航已检查；当前 HAP 模拟器回归 10 PASS / 1 SKIP

---

## 0. 一句话说明

按 NutriScan 实测路由树重建了信息架构与视觉语言。
**每一个入口都可达**：做了的进真实页面，没做的进占位页并写清「本应功能 / 未实现原因 / 补上需要」。
所有 mock 与推断内容在界面上都带来源角标，不伪装成实测数据。

**产品范围已调整为单用户个人记录**：不提供社群动态、好友关系、点赞评论或公开个人资料。NutriScan 原版的 Club 页面仅保留为逆向研究记录，不进入应用导航与当前交付范围。

**产品定价已定为完全免费**：不设试用、不设升级入口、无应用内购买、无订阅校验、无权益墙。所有已实现功能默认全部开放。详见 §0.6。

---

## 0.5 ✅ 曾存在的最大偏差：视觉语言已恢复

**这处偏差已在当前实现中修复，保留记录说明原因与校准依据。新安装默认启用深色实测色板；用户仍可在「我的 → 外观」切换跟随系统或浅色。**

| | NutriScan 实测 | 本项目实现 |
|---|---|---|
| 页面底 | 平面 `#0C0C0C` | 平面 `#0C0C0C` |
| 卡片 | 平面 `#1C1C1E` | 不透明平面 `#1C1C1E` |
| 描边 | `#2F2F33` 细描边 | 细描边 `#2F2F33` |
| 主色点缀 | 荧光绿 `#D5EE6E` | 同（这项对齐了） |

上面那组「平面 `#0C0C0C` / `#1C1C1E` / `#2F2F33`」是**本项目自己的逆向结论**，
出自 `NutriScan_设计系统与鸿蒙复现.md`。当前深色主题按这组实测值呈现平面暗色。

**问题来由**：在「一比一还原」这个要求之前，项目先落地了另一段电商产品卡的
视觉规范，因此曾短暂采用渐变背景与玻璃拟态卡片，偏离了 NutriScan 原版。

**修复方式**：深色资源已恢复实测底色、卡面与描边色；卡片模糊、投影、色调 veil
已去除，页面和主视觉渐变也改为平面色标。现有卡片 token API 保留，避免逐页重写组件。
浅色主题沿用自己的中性色板，页面与卡面同样使用平面材质。

已对齐的部分（实测精确命中）：深色 `#D5EE6E` / `#0A84FF` / `#FF2E63` / `#4CC94E`；
底 Tab 已补为「图标 + 文字」；进度页已补 `🔥 Streak` 与 `Report`；
饮水页与原版逐元素对齐（选中态药丸、水瓶、`% completed` 青色、带铅笔的 goal、
`ml consumed`、M–S 圆环今天描边、250/500 + 自定义、This Week 卡七柱）。

导航结构也已按参考截图校正：底栏是五个等宽入口，首页内容区的蓝色「+」为独立悬浮操作，不是中间相机 Tab；对应说明已修正在设计系统文档中。

---

## 0.6 产品定位调整：完全免费（订阅 / 试用 / 升级已整体移除）

本项目按产品决策定为**完全免费**。NutriScan 原版的付费相关界面已整体删除，不做"先给试用再谈钱"的引导。

### 已删除的东西

| 原版位置 | 原版内容 | 本项目 |
|---|---|---|
| 今日页页头 | 「免费试用 1 周」可点按钮 | **删除** |
| 今日页页头 | 粉橙渐变「升级」胶囊 | **删除** |
| 点击后 | 会员权益 / 试用开通占位页 | **随入口一并删除** |
| 引导流程 | 订阅墙（5 步之后的第 6 屏） | **本就没有**，引导以「生活方式」收尾 |
| 设计系统 | `premium_pink` / `premium_orange` 两枚色标 | **删除**，火焰强调色改为独立的 `streak_orange` |
| 「我的」 | 订阅 / 权益类二级入口 | **本就没有** |

### 改成了什么

- **今日页页头**：`[‹ 今天] ············· [全部功能免费]`
  后者是不可点的静态标识 —— 让"免费"在界面上是明示的，而不是让人以为少了点什么。
- **「我的 → 版本与授权」**：新增一张卡片，写明无应用内购买、无订阅、无付费墙。

### 边界（写清楚，避免误导）

AI 食物识别使用**用户自己的 API Key**，调用额度与费用由用户的模型服务商承担，与本应用无关。
除此之外，本应用不设任何收费点。

### 「免费」在哪一层生效（重要，别改错字段）

| 层 | 状态 |
|---|---|
| 应用代码 | ✅ 已生效 —— 没有付费墙、没有试用态、没有权益判断分支，任何功能都不检查订阅状态 |
| 商店上架价 | ⬜ **需在上架时人工设置为免费**（AppGallery 控制台），代码里没有对应开关 |
| `module.json5` 的 `installationFree` | **保持 `false`，不要动** |

最后一条容易踩坑：该字段的含义是「当前 Module 是否支持**免安装特性**（元服务 / 原子化服务）」，
**不是**「应用是否免费安装」。HarmonyOS 官方文档明确写了
「当 bundleType 为元服务时该标签自动配置为 true，反之自动配置为 false」，
且「该标签在编译构建时自动生成，手动配置不生效」；
若强行设成 `true`，模块会被视为元服务，需要走元服务独立的签名与审核流程。
SDK schema（`hms/toolchains/configcheck/configSchema_rich.json`）对它的描述是
"Indicates whether free installation of the current hap is supported"，同样指免安装特性。
本项目是普通手机应用（非元服务），因此维持 `false` 是正确值 —— **"免费"这件事不靠这个字段表达**。

### 代价：一处与原版的视觉偏差

原版页头的「免费试用 1 周」+ 渐变「升级」两个按钮在本项目**不复现**。
这是产品决策导致的**主动偏差**，不是遗漏：原版那一屏还是「划线价与实付价相同却宣称 70% off」的虚假折扣。
其余页头元素（日期胶囊、返回箭头、位置、尺寸层级）与原版保持一致。

---

## 1. 证据分级（贯穿全项目）

| 等级 | 含义 | 界面表现 |
|---|---|---|
| **实测** | 真机截图 / `strings_all.txt` 直接命中 | 角标「实测」 |
| **推断** | 有实测证据支撑，但算法或数值是我推的 | 角标「推断」 |
| **示例** | 原样编的假数据，只为让界面与跳转走通 | 角标「示例」 |

来源集中定义在 `entry/src/main/ets/services/MockContent.ets`，页面只从这里取数。

---

## 2. 信息架构对齐情况

### 2.1 底 Tab（5 个，对齐实测路由图）

| Tab | NutriScan 对应 | CalorieFit 实现 | 状态 |
|---|---|---|---|
| 启动/引导 | splash_screen + setup_screen | `OnboardingPage.ets` 5 步 | ✅ 结果真实落库 |
| 今日 | 个人记录（综合/饮水/断食） | `HomeTabs.ets` 手写分段控件 | ✅ 3 个子页 |
| 膳食 | Diet Plan（4 个子页） | `DietPlanPage.ets` | ✅ 界面 + 示例数据 |
| 进度 | Progress（Today/Week/30 Days + Readiness） | `ProgressPage.ets` | ✅ 图表真实数据 / Readiness 占位 |
| 营养师 | NutriBites（AI 对话） | `NutriBitesPage.ets` | ⚠ 未实现跳转 |
| 我的 | You（8 个二级入口） | `ProfilePage.ets` | ✅ 入口全立，2 个实页 + 6 个占位 |

### 2.1.1 引导流程

| 步骤 | 原版对应 | CalorieFit | 结果写到 |
|---|---|---|---|
| 启动页 | splash_screen | 品牌 + 副标题，1.4s 自动进 | — |
| 1 目标 | 目标选择 | 减脂/维持/增重/重组 药丸单选 | `body_profile.mode` |
| 2 活动量 | Activity Level | 久坐/轻度/中度/高强度 | `body_profile.activity` |
| 3 通知 | 通知诱导 | 预览通知卡 + 三条说明（照 flow_02 布局） | — |
| 4 补剂 | Can you take Nutritional Supplements? | 愿意/不吃 | 引导草稿 |
| 5 生活方式 | Lifestyle & Feelings | 作息规律 + 外食频率 | 引导草稿 |

引导结束时 `OnboardingService.applyToProfile()` 把目标模式与活动量**真的写进体征档案**，
直接参与 BMR/TDEE 推导 —— 不是走形式的装饰步骤。模拟器已验证：引导选「增重 / 高强度」后，
「我的 → 体征档案」里两项同步变化。

**两处有意不复制**：
- 语言选择屏 —— 本 App 只发中文，做一屏只能选自己
- 订阅墙 —— 本项目定价为**完全免费**，不设试用与订阅墙；引导以生活方式收尾（详见 §0.6）

### 2.2 今日页三个个人记录子页

| 子页 | 数据来源 | 状态 |
|---|---|---|
| 综合 | 真实（已有 `CalorieEngine` / `MacroRepository`） | ✅ |
| 饮水 | **真实落库**（V4 `water_log`，逐笔可撤销） | ✅ |
| 断食 | **真实落库**（V4 `fasting_log`，计时与完成标记） | ✅ |

### 2.3 「我的」二级入口

| 入口 | 状态 | 证据 |
|---|---|---|
| 全部餐食 | ✅ 实页 | — |
| 运动记录 | ✅ 实页 | — |
| 修改宏量 | ✅ 实页（本页内） | — |
| 收藏餐食 | ⚠ 占位 | `/api/v1/favourite_food_items` |
| 问你自己 | ⚠ 占位 | 路由图有，无协议 |
| 重复餐食 | ⚠ 占位 | `Edit repeat meal schedule` |
| 提醒 | ⚠ 占位 | `Choose Reminder Type` |
| 假期模式 | ⚠ 占位 | `You can only start vacation mode up to 30 days in the past.` |

---

## 3. 本轮新增的实测依据

从 `strings_all.txt` 直接命中的字段/文案，不是猜的：

```
断食方案   16:8 / 18:6 / 20:4 / 14:10 / 12:12 + 「你自己的窗口」
饮水       total_ml · goal 可手改（铅笔图标）· 快加 250/500ml
进度       readiness_score / readiness_breakdown
           /api/v1/progress/readiness
           "Average NutriScore Last 30 Days"
膳食       /api/v2/generate_grocery_list · groceryList
补剂       supplement / supplement_needed / supplement_note
生活方式   lifestyle_view_shown / "Lifestyle & Feelings"
自定义首页 CustomizeHomeViewModel
全植物基   "Every scan, meal idea, recipe and grocery list goes
            100% plant-based."
```

---

## 4. 明确未复现的部分及原因

| 功能 | 原因 |
|---|---|
| Readiness Score 算法 | 接口存在，但算法在服务端；`libapp.so` 的 Dart AOT 无法反汇编出函数体 |
| NutriScore 评分 | 界面文案实测存在，打分公式与权重完全未知 |
| 断食热量分配 / 到点提醒 | 原版逻辑无证据，只做了计时与完成标记 |
| 每日膳食计划生成 | `/api/v2/generate_grocery_list` 是服务端行为 |
| AI 对话（NutriBites） | 后端自述 `"agent":"gemini"`，请求体未抓到；不拿本地 MaaS 端点硬凑一个假对话 |
| 订阅墙 + 二次挽留 | 本项目定价为**完全免费**，升级/试用入口整体删除（§0.6）。原版那一屏是「划线价与实付价相同却宣称 70% off」的虚假折扣，本就没有克隆价值 |

以上都在界面上以占位页呈现，写明缺什么、怎么补。

---

## 5. 踩坑记录（供后续维护）

### 5.1 `Navigation` 里嵌 `Tabs` 会静默废掉所有 `NavDestination`
`Tabs → TabContent → Tabs → TabContent` 这种嵌套下，`pushPathByName` 照常成功、
返回键照常出现，但**目标页内容节点挂不上树**，画面全白且日志无任何异常。
`FoodEdit` / `ComingSoon` 同时中招，去掉内层 `Tabs` 立刻恢复。
`HomeTabs` 因此改成手写分段控件 + 条件渲染。

### 5.2 带初始化对象的 `@Component` 作为目标页根节点同样挂不上
`ComingSoonPage({...})` 渲染不出，改成无参调用 + `AppStorage` 读内容，
再改成页内自持 `@State` 的**本地覆盖层**才彻底稳定。
`@Builder` 里也不能写 `const` 声明，只能就地转型。

### 5.3 点击坐标必须从 UI 树取
`uitest dumpLayout` 给的 bounds 才是准的。手算坐标在滚动后会落空，
本轮排查一度被"点空了"带偏。工具见 `_tools/ui_drive.py`（按文本定位并点击）。

### 5.4 ArkTS 装饰器/成员名与内置组件冲突
`onAppear`、`size` 是 `CustomComponent` 上已有的属性，自定义同名方法直接编译失败；
`Row` 是内置组件，`@Builder` 方法不能同名。均已改名。

### 5.5 `@Prop` 不能用于函数类型
API 23 起报 `The V1 decorator '@Prop' cannot be applied to a Function-type variable`。
回调成员用普通成员（参考 `EmptyState.onAction`）。

### 5.6 `private get` 在 `@Component` 中求值不可靠
返回 NaN 会让 `.width("NaN%")` 静默失效。已全项目清零，改用普通方法。

---

## 6. 验证方式

- **编译**：`BUILD SUCCESSFUL`
- **迁移**：hilog 确认 V4 三步在已有 V3 库上全部通过
  （`V4: water_log ready` / `V4: fasting_log ready` / `V4: app_settings water target ready`）
- **逐屏**：模拟器遍历 5 个底 Tab + 4 个子页 + 占位层，截图核对
- **数据**：饮水目标由体重推导（65kg × 35 = 2275 → 取整到 2300），断食方案名逐条对应 strings
- **无 JSError**：hilog 无 jscrash / FATAL / TypeError

---

## 7. 未做的事（如实列出）

1. **综合页的轮播条与餐食卡细节**已补：横向提示轮播 + 早/午/晚/加餐四张餐食卡，
   点击进入餐食详情页（本餐热量、占全天预算比例、宏量三片、逐项明细）。
2. **记录餐食入口**已改为悬浮「+」，四个今日子页均可直接触发。
3. **引导流程**已做（启动页 + 5 步），但**没有语言选择屏**（本 App 只发中文）
   与**没有订阅墙**（本项目定价为完全免费，升级/试用入口已整体删除，见 §0.6）。
4. **AI 拍照识别的 UI 全链路**已补「内置示例图」入口：
   模拟器只有 `/data/local/tmp` 可写、图库塞不进照片，
   `从相册选择` 在模拟器上永远返回空；新增的示例图入口让这条链路
   在任何设备上都能走通（配了 Key 走真实识别，演示模式返回本地模拟数据）。

## 8. ✅ 验证记录（模拟器恢复后已全部补验）

`_tools/verify_all.py` 一键跑完，**8/8 PASS**：

| 检查项 | 结果 |
|---|---|
| 综合页主视觉卡 | PASS |
| AI 拍照识别入口（综合页顶部） | PASS |
| 轮播条横向滚动 | PASS |
| 餐食卡片流点击 | PASS |
| 餐食详情页渲染 | PASS |
| AI 示例图入口 | PASS |
| AI 示例图完整识别链路 | PASS |
| 全部餐食（NavDestination 包裹） | PASS |

另补验深色主题：今日 / 饮水 / 膳食 / 进度 / 我的 五屏截图确认
深底 + 青色饮水强调 + 荧光绿 FAB + 平面细描边均正常，
示例角标在深色下清晰可读。

补验中修掉的问题分两类：
- **应用问题 1 个**：AI 页图片预览空白。`Image()` 解不出沙箱真实路径，
  改成显示走 `$rawfile` 资源、读取仍走 cacheDir 真实路径，两条通道分开。
- **脚本自身 3 个**（与应用无关）：`connected()` 把 `CompletedProcess`
  当字符串判断导致正常设备被误判离线；按钮文案写成「开始识别」
  而实际是「开始 AI 识别」导致点空；找长页面入口用固定滑动次数
  滚少了够不着滚多了滑过头，改为边滑边找。

此前发现一处视觉瑕疵：悬浮「+」盖住「本周」卡的「日均 ml」标签。2026-10-19 已修复，见 §8.2。

### 8.1 2026-10-19 模拟器复测补充

本轮在当前构建上重新运行完整流程，**8/8 PASS**。轮播项不再以“滚动容器中找不到首条文案”判定，而是比较提示条区域与首页独立锚点：提示条区域变化 **32.2%**，纵向锚点变化 **0.00%**，确认是横向移动而非页面纵向滚动。页面检查会先回到首页顶部；AI 与餐食路由还会断言目标页内容，不以点击成功代替页面验证。

AI 示例图流程在会话级演示模式下完成，结果明确显示「演示食物（模拟识别）」；该流程没有发起网络请求。8 项截图位于本地 `work/nutriscan-ui-fidelity-20261019/evidence/` 和 `_tools/shots/`。

本轮也修复了一个主题冷启动问题：此前已保存深色偏好时，模拟器冷启动仍会先显示浅色资源；现在 `EntryAbility` 页面加载完成后通过 `UIAbilityContext` 恢复 ColorMode，冷启动深色界面已确认生效。相关 API 约束见[华为 UIAbilityContext API 文档](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/js-apis-inner-application-uiabilitycontext)。

此前这轮只完成了模拟器验证，真机界面通道当时未接入；后续真机连接记录见 §12。

### 8.3 2026-10-19 模拟器回归（本次凭证修复前）

当前调试 HAP 重装并启动后，完整 UI 流程 **8/8 PASS**。覆盖综合页、AI 入口、轮播横滑、餐食卡片与详情、示例图载入与本地模拟识别、全部餐食二级路由。轮播横带像素变化 **36.6%**，首页主卡锚点变化 **0.00%**。

本轮也复核了已恢复的平面暗色材质：模拟器截图大面积像素命中页面底 `#0C0C0C` 与卡面 `#1C1C1E`，描边为 `#2F2F33`；当前 `glassGradient` 使用同色标、`glassShadow` 资源透明，源码没有 `backdropBlur` 调用。8 张回归截图保存在 `work/nutriscan-ui-fidelity-20261019/evidence/regression-20261019-v_*.jpeg`。

此处 8/8 结果早于 §12.2 所述 API Key 安全存取改动；新改动目前仅完成调试构建，未在模拟器重跑完整 UI 回归。

真机画面本轮仍未取得：Android ADB 已识别到 Xiaomi 13，但只读状态显示设备 Dozing、前台焦点为 `NotificationShade`，NutriScan 在锁屏后方。未尝试绕过锁屏，未截取应用内容；当时状态记录见 §12.1，后续状态见 §12.2。

8/8 回归后的额外启动检查发生在模拟器自动锁屏之后：HDC 日志报告 `isScreenLocked=true`，黑屏快照时窗口未附着，随后任务记录恢复。日志中的 `HandleAppDied` 与主动执行的 `aa force-stop` 同时出现；未发现该次启动的应用级 ArkUI 崩溃记录。因此这次黑屏不能作为应用崩溃证据；已有 8/8 测试是在可交互会话完成的。记录见 `work/nutriscan-ui-fidelity-20261019/evidence/emulator-state-20261019-1104.txt`。

### 8.2 饮水周统计与浮动按钮避让

此前「本周」统计行占满整卡，悬浮加号遮住「日均 ml」。现将统计行限制为卡片内容宽度的 80%，右侧留出加号操作区；下方七日柱图仍保持整卡宽度。调试 HAP 构建成功，模拟器前后截图确认标签不再被遮挡，柱图和底部说明行完整显示。

- 修改：`entry/src/main/ets/pages/WaterPage.ets`
- 修改后回归：现有 UI 流程 **8/8 PASS**；轮播横带变化 **36.5%**，首页主卡锚点变化 **0.00%**。
- 修复前：[emulator-water-layout.jpeg](work/nutriscan-ui-fidelity-20261019/evidence/emulator-water-layout.jpeg)
- 修复后：[emulator-water-layout-fixed.jpeg](work/nutriscan-ui-fidelity-20261019/evidence/emulator-water-layout-fixed.jpeg)
- 构建仍有既有 ArkTS/API 兼容性提示；本项只完成模拟器验证，真机画面当前无法从工具通道读取，最新状态见 §12.1。

---

## 9. 快速开始

```powershell
# 构建
$env:DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk"
& "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" `
  --mode module -p product=default -p buildMode=debug assembleHap --no-daemon

# 装到模拟器（需先在 DevEco 里启动模拟器）
$hdc="C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
& $hdc tconn 127.0.0.1:5555
& $hdc install -r entry\build\default\outputs\default\entry-default-unsigned.hap
& $hdc shell aa start -b com.rinne.caloriefit -a EntryAbility
```

首次启动会走引导流程（5 步），选择会写进体征档案并直接影响 BMR/TDEE 推导。
想重看：`我的 → 记录与偏好 → 重看引导流程`。

调试辅助脚本在 `_tools/`（不入库）：
- `ui_drive.py` —— 按文本在 UI 树里定位并点击，避免手算坐标点空
- `verify_sweep.py` —— 仪器化验证环形扫描动画确实在扫而非跳终值
- `shrink_sample.py` —— 压缩内置示例图

---

## 10. 完整路由表

| 路由 | 落地页 | 状态 |
|---|---|---|
| — | 启动页（品牌 + 1.4s） | ✅ |
| — | 引导 ×5（目标/活动量/通知/补剂/生活方式） | ✅ 真实落库 |
| — | 今日（综合/饮水/断食 子页，单用户个人记录） | ✅ |
| — | 膳食（膳食计划/购物清单/补剂/生活方式 子页） | ✅ 界面 + 示例数据 |
| — | 进度（今天/本周/近30天 + Readiness/NutriScore 入口） | ✅ 图表真实，评分占位 |
| — | 营养师 | ⚠ 未实现跳转 |
| — | 我的（含 9 个二级入口 + 重看引导） | ✅ |
| `MealDetail` | 餐食详情 | ✅ |
| `FoodEdit` | 新增 / 编辑食物 | ✅ |
| `ActivityEdit` | 新增 / 编辑运动 | ✅ |
| `AiRecognition` | AI 拍照识别（含内置示例图） | ✅ |
| `AiSettings` | AI 接口设置 | ✅ |
| `FoodLog` | 全部餐食 | ✅ |
| `ActivityLog` | 运动记录 | ✅ |
| `ComingSoon` | 未实现占位 | 页内覆盖层实现 |

> 目标页必须以 `NavDestination` 为根节点，否则 Navigation 没有可挂载对象，
> 表现为「路由推得进去、返回键也出现、内容全白且日志无异常」。
> 本项目已踩坑两次，FoodPage/ActivityPage 也因此补了 `NavDestination` 包裹。

## 11. 发布状态

- 13:00:14 的调试构建通过，生成 2,758,790 字节未签名 HAP，SHA-256 为 `5B5E41D1B31F3C1372EB0F224920D5DC914B3C6DB28E27FE0CC928B1CE3B5AAB`。该 HAP 已安装到 Mate 90 Pro 模拟器，13:13 完整 UI 回归 **8/8 PASS**；首次隐私政策、分项同意及后续隐私运行验证见 §12.7。
- `build-profile.json5` 的 `signingConfigs` 为空，正式产品仍引用 `default` 签名配置；当前 release 产物是 unsigned HAP，不能分发或上架。华为要求 AppGallery 发布包使用 release certificate；还需配置正式 Profile 和签名设置。
- `entry/build-profile.json5` 的 release 混淆目前关闭。本次调试构建报告 274 条 ArkTS 警告及第三方资源重复提示；发布前需按实际支持设备处理并完成设备验收。

### 11.1 上架前待完成清单

以下事项需要逐项关闭，当前版本还不能标记为可上架：

- [ ] **签名与发布身份**：由发布者提供华为开发者账号、release certificate、Profile 与签名配置；确认最终 bundle、应用名、开发者/厂商身份和联系信息。官方发布证书说明见[华为开发者文档](https://developer.huawei.com/consumer/en/doc/app/agc-help-add-debugcert-0000001914263178)。
- [ ] **隐私告知与同意**：已实现版本化首启告知、通用规则与健康信息分项同意、应用内政策页，以及真实 AI 识别逐次上传确认；首启政策、同意、上传说明和取消流程已在 Mate 90 Pro 模拟器通过。“删除数据并撤回同意”运行后返回未同意的首启页。HDC 禁止直接列出应用沙箱，未做删除后数据库/Asset 的独立低层读取。当前政策明确标为开发预览草案，发布者法定主体/联系渠道、AI 接收方具体主体/留存规则、未成年人适用范围仍是占位信息，补齐并经运营主体审核后方能上架。PIPL 将医疗健康列为敏感个人信息并要求单独同意；应用程序不得强制同意非必要信息或因此拒绝基本功能，正式产品须确认健康数据处理确为核心功能必要。参考[《个人信息保护法》第28–30条](https://www.miit.gov.cn/jgsj/zfs/fl/art/2022/art_515a4b20c12f430eab54bb4f56d89f56.html)、[《移动互联网应用程序信息服务管理规定》第12条](https://www.cac.gov.cn/2022-06/14/c_1656821626455324.htm)和[华为 HarmonyOS 合规指南](https://developer.huawei.com/consumer/cn/doc/appgallery-connect-Guides/agc-auth-harmonyos-arkts-personal-data-0000001631566342)。
- [ ] **产品完成度**：`MockActivityDataSource` 仍提供模拟步数；若目标是正式健康记录产品，需接入真实来源或在发布版本移除/清楚禁用该功能。`ComingSoon` 占位入口仍存在；逐项决定补齐、移除或延后发布。
- [ ] **发布构建与设备验收**：确认 release 混淆策略、修复/接受构建警告，使用正式签名重新构建；在实际支持的 HarmonyOS 设备上跑完整路由、数据持久化、权限/相机、网络错误与升级迁移回归。
- [ ] **商店物料**：补齐最终应用描述、图标/截图、分类、年龄分级和发布者支持联系方式。
- [x] **系统元数据清理**：已将模块/Ability 的默认英文模板描述替换为 CalorieFit 中文说明；最终发布者身份与商店文案仍待确认。

## 12. 真机连接状态（2026-10-19 后续检查）

- Android Debug Bridge 已识别并授权 Xiaomi 13；设备型号为 `2211133C`，型号代号 `fuxi`。官方 Platform Tools 37.0.1 用于设备连接与截图。
- 仅筛选出 NutriScan 包 `app.nutriscan` 并启动主 Activity `app.nutriscan/.MainActivity`，没有读取包内容、个人记录或网络流量。
- 09:42 检查时设备处于 MIUI 锁屏/Dozing，主 Activity 在锁屏后方；普通唤醒与上滑未进入应用。截屏只得到锁屏黑画面，不能作为 NutriScan 视觉参考。该状态是历史记录；当前状态见 §12.2。
- 真机视觉对照仍以可见应用画面采集为准。

### 12.1 本轮复查（2026-10-19 11:03）

- ADB 识别到已授权设备 Xiaomi 13（`2211133C`）；用户已回复设备就绪，但本次只读检查仍见 `mWakefulness=Dozing`、`mCurrentFocus=NotificationShade`，NutriScan 的 `MainActivity` 在锁屏后方。
- 未唤醒或绕过锁屏，也未截取应用画面；所以本轮没有新的真机 UI 证据，不能据此确认用户解锁后的状态。
- 真机视觉验收待设备所有者解锁并保持 NutriScan 首页可见后继续。模拟器 8/8 回归已经完成，见 §8.3。

### 12.2 最新复查（2026-10-19）

- 用户回复设备已就绪后，ADB 初次仍读取到 Xiaomi 13 `mWakefulness=Dozing`、焦点 `NotificationShade`；唤醒一次没有将 NutriScan 带到前台。11:26 的后续状态为 Awake，但焦点仍不在 NutriScan；我停止了设备查看，没有读取或截取其他应用界面。黑屏截图不是 NutriScan 页面证据。
- HarmonyOS 模拟器 `Emulator.exe` 仍运行，但 `hdc list targets -v` 将 `127.0.0.1:5555` 标为 `TCP Offline`；客户端日志为 TCP connection refused（`-4078`），模拟器 `config.ini` 的 `hw.hdc.port=notset`。本轮无法向模拟器安装新包或重跑 8/8；需要从 DevEco 正常重启模拟器以重新初始化 guest HDC，再确认目标 Online。
- 本轮凭证修复后的调试构建成功并生成未签名 HAP；8/8 PASS 是修复之前的结果，修复后的完整回归尚未执行。
- 继续真机 UI 对照需要设备所有者手动解锁并将 NutriScan 首页保持在前台；继续模拟器回归需要先由 DevEco 恢复模拟器 HDC 连接。

### 12.3 用户回复就绪后的复查与本地数据删除（2026-10-19 11:40）

- 用户回复“已就绪”后再次读取 ADB 状态：设备 `190ab5db`（Xiaomi 13 / `2211133C`）仍为 `mWakefulness=Dozing`，窗口焦点 `NotificationShade`，`mFocusedApp=null`。没有截屏或读取其他应用内容，因此真机页面仍未验证。
- HDC `list targets -v` 仍报告 `127.0.0.1:5555 TCP Offline`，本轮无法安装 HAP，也未重跑 8/8。上一轮 8/8 仍只代表 11:00 当时的代码状态。
- “删除健康数据和 AI 配置”入口现清除健康记录、身体档案、目标行、AI 配置/API Key 和未完成引导草稿；外观偏好保留。空档案不再回退显示 65kg/170cm/30 岁、默认性别或目标，饮水在没有档案/手动目标时显示未设置。
- Hvigor debug `assembleHap` 成功，33 个任务；ArkTS 输出 274 条警告。产物为 2,691,598 字节未签名 HAP（`entry/build/default/outputs/default/entry-default-unsigned.hap`，11:40:09 +08）。未安装到设备，删除流程尚无运行时验证。
- 详细构建与设备状态见 `work/nutriscan-ui-fidelity-20261019/evidence/verification-20261019-personal-data-delete.txt`。

### 12.4 真机底栏标签采集与最终调试构建（2026-10-19 11:50）

- 用户解锁真机后，ADB 确认 Xiaomi 13 为 Awake，前台窗口为 `app.nutriscan/.MainActivity`。NutriScan 底栏顺序为 Home、Diet Plan、Progress、NutriBites、You；本项目保留中文本地化标签。只留存底部标签条，不含健康数据的截图：`work/nutriscan-ui-fidelity-20261019/evidence/reference-nutriscan-bottom-nav-labels-20261019.png`。
- 实测截图中“我的”人物图标没有状态点，因此移除 CalorieFit 对应图标上的绿点。项目没有复制可能随用户变化的进度数值。
- 最终源码在该调整后再次通过 debug `assembleHap`：33 个任务，生成 2,690,437 字节未签名 HAP（11:50:09 +08）。`git diff --check` 通过，只有 LF/CRLF 提示。
- HarmonyOS 模拟器 HDC 仍为 `127.0.0.1:5555 TCP Offline`；当前 HAP 未安装，完整 8/8 UI 回归及删除流程运行验证仍待恢复模拟器连接。
- 本轮状态与构建记录：`work/nutriscan-ui-fidelity-20261019/evidence/verification-20261019-live-reference-final-build.txt`。

### 12.5 真机底栏图标参考与回归脚本防误报（2026-10-19 12:03）

- 唤醒真机后再次确认 Xiaomi 13 上 NutriScan `MainActivity` 为前台。只把屏幕底部导航区域裁成 `1080×135`；Progress 上方会随账户变化的百分比已遮蔽。保留图 `work/nutriscan-ui-fidelity-20261019/evidence/reference-nutriscan-bottom-nav-20261019-icons-labels-redacted.png`，未落盘全屏帧或其他页面数据。
- `_tools/verify_all.py` 现在读取 `hdc list targets -v` 并排除 `TCP Offline` / `Disconnected`；运行前输出 HAP 大小、修改时间和 SHA-256，安装或启动未成功时中止，避免对旧安装版本报出通过。
- 当前 HDC 输出为 `127.0.0.1:5555 TCP Offline`；脚本拒绝开始回归并在安装阶段前退出。Python/Pillow 依赖可用，离线保护检查返回 `connected: False`。本次没有安装 HAP、没有执行 8 项 UI 回归，也没有验证数据删除流程。
- 待测构建仍是 11:50:09 生成的 `entry-default-unsigned.hap`，2,690,437 字节，SHA-256：`8881B19A9E87152B1679BDB222F2552B71EB1B85D37E7E3A709DDC008EB2669C`。脚本保护与设备状态记录见 `work/nutriscan-ui-fidelity-20261019/evidence/verification-20261019-regression-guard.txt`。

### 12.6 当前 HAP 安装与模拟器回归（2026-10-19 12:53）

- Mate 90 Pro 模拟器 HDC 恢复为 `127.0.0.1:5555 TCP Connected localhost hdc`。已安装并启动 11:50:09 构建的 HAP，安装输出为 `install bundle successfully.`；HAP 大小 2,690,437 字节，SHA-256：`8881B19A9E87152B1679BDB222F2552B71EB1B85D37E7E3A709DDC008EB2669C`。
- 当前版本完整 UI 回归 **8/8 PASS**：综合页、AI 拍照入口、轮播横滑、餐食卡片流、餐食详情、示例图入口、本地演示识别结果、全部餐食页。轮播横带像素变化 **36.6%**，主卡锚点变化 **0.00%**。
- 八张截图为 `work/nutriscan-ui-fidelity-20261019/evidence/regression-20261019-1253-v_01_home.jpeg` 至 `regression-20261019-1253-v_08_foodlog.jpeg`；设备、HAP 与逐项结果记录见 `work/nutriscan-ui-fidelity-20261019/evidence/verification-20261019-current-hap-regression.txt`。
- 在 12:53 这次回归中尚未触发 API Key 记忆/安全存取，也未执行“删除健康数据和 AI 配置”；后续专项结果见 §12.7。此前 §12.5 记录的 HDC Offline 状态是当时的历史快照，不代表本次运行状态。

### 12.7 隐私流程与最新 HAP 回归（2026-10-19 13:24）

- Mate 90 Pro 模拟器安装并运行 13:00:14 构建的 HAP；13:13 端到端 UI 回归 **8/8 PASS**。覆盖综合页、AI 拍照入口、轮播、餐食卡片与详情、本地示例识别及全部餐食页。轮播横带像素变化 **36.4%**，首页主卡锚点变化 **0.00%**。首次隐私政策打开/返回以及通用规则与健康信息分项同意流程也通过。
- 隐私运行脚本使用临时假 API Key，验证启用“安全记住”后强制停止并重启仍能读回；选择本地示例照片后，真实识别流程展示 HTTPS 接收地址、照片与 API Key 说明，点击取消后无识别结果且未提交网络请求；“删除数据并撤回同意”后返回首启同意页。没有发起真实 AI 请求。
- 删除后的底层 RDB/系统 Asset 值未能独立读取：模拟器 HDC 对应用沙箱返回 `Permission denied`。该限制不影响界面流程观察，但不应表述为已完成底层内容取证。
- 自动化流程结束时模拟器停留在未同意的首启页。截图与日志：`work/nutriscan-ui-fidelity-20261019/evidence/regression-20261019-1313-*`、`verification-20261019-current-hap-privacy-regression.txt`、`verification-20261019-privacy-runtime.txt`；8 项和隐私流程的具体状态以这些本地证据为准。

### 12.8 深色默认与最新调试 HAP（2026-10-19 15:09）

- 视觉复核发现：深色 token 已与 NutriScan 实测值对齐，但无主题偏好时此前默认跟随系统；模拟器处于浅色模式时，新装主界面因此显示浅色。`ThemeService` 的缺省与异常回退现改为深色；用户仍可显式选择跟随系统或浅色。
- Hvigor debug `assembleHap` 成功，33 个任务（17 个执行、16 个复用），产物为未签名 HAP，2,765,775 字节，SHA-256：`90137BE19295323D973AE2DE56004DCFF9FFDB55261C706B9230B30F3BE6963F`。构建保留 ArkTS 警告；项目尚未配置发布签名。
- Mate 90 Pro 全新安装后，首次隐私页及首页截图均验证深色：底 `#0C0C0C`、卡面 `#1C1C1E`、描边 `#2F2F33`。分项隐私同意、五步引导、新用户体征未预填及前 8 项 UI 回归通过；轮播横带像素变化 `36.6%`，首页主卡锚点变化 `0.00%`。截图及逐项记录见 `work/nutriscan-ui-fidelity-20261019/evidence/regression-20261019-1509-dark-default/`。
- 水与断食 V4 持久化在紧邻前一 HAP（SHA-256 `9DD96224E0F8FA9990D94C3BC9B0034FB62681827218F6AF3C4B70FE6EF30055`）的全新安装数据上单独通过：250 ml 饮水和进行中的 16:8 断食在强制停止、重启后均能读回；断食记录也成功结束。此前第一轮 V4 脚本因停留在「全部餐食」路由报过不可达，已修正导航后完成这两项。
- 最新 HAP 的 V4 补验未完成：前 8 项运行后模拟器截图变为全黑，`dumpLayout` 报 `Get window nodes failed`，`127.0.0.1:5555` 随后拒绝连接。模拟器 crash server 日志在 15:08–15:11 多次记录宿主机可用内存接近 `0 MB`，并在 15:11 生成崩溃报告；现有证据指向模拟器/宿主内存状态，不是 CalorieFit 页面崩溃。DevEco 重启后 HDC 仍离线，因此不能把前一 HAP 的 V4 结果表述为最新 HAP 的验证。
- 本次记录不改变真机限制：当前 Android ADB 列表没有 Xiaomi 13 设备；除已保存的底栏参考外，真机逐页视觉验收仍未完成。

### 12.9 首页参考图结构修订与当前源码构建（2026-10-19）

- 按真机参考图 `main_nav_01_Open_water_tracker.png` 调整首页首屏：日期压成单行；热量主卡改为半环、剩余/已摄入/目标三项数据和同卡宏量条；餐食卡改为横向浏览，并把拍照识别入口收至餐食标题行。没有生成或填入虚构的餐食照片及身体数据。
- 首页及运动页的步数卡现在明确标注“手动模拟”；对应数据源为 `MANUAL_SIMULATED`，不应误认为来自设备传感器。
- 热量环新增 NutriScan 实测薄荷色 `#41D9B3`；脂肪条改为参考截图中的蓝色。提示文案删去未经证实的营养/补水效果承诺，改为描述当前已实现功能。
- 按参考图的环宽与卡片高度修正综合页半环：直径由 208vp 降为 128vp，描边由 12vp 调为 8vp，容器高度同步设为 128vp；三项热量数字位于同一底部遮罩层内，避免环与数值错位或裁切。
- `_tools/verify_all.py` 的主卡判据同步为三项热量与三项宏量标签，轮播像素差分仍定位首条提示并检查主卡锚点。
- 静态检查通过：回归脚本 Python 语法、base/dark 色值 JSON、36 个 DesignTokens 颜色资源的双主题键匹配、`git diff --check`（仅 LF/CRLF 提示），AppGallery 图标为 1024×1024 PNG。22:38 Hvigor debug `assembleHap` 成功，33 个任务完成（17 执行、16 up-to-date），`CompileResource`、`CompileArkTS` 与 `PackageHap` 均成功。最新未签名 HAP 为 2,830,962 字节，SHA-256 `3F5C4A461FB7BF474F890F0CED65B04C641D3231A2F38EA62B4F375D076336FA`；构建仍有 ArkTS 警告，项目未配置发布签名。
- 后续重试观察到 DevEco 创建的模拟器 PID `584020` 仅运行数秒便退出；退出前 HDC 仍为 `127.0.0.1:5555 TCP Offline`。随后复查可用内存约 149 MB，HDC 仍 Offline，工作区 Android Platform Tools 的 `adb devices -l` 也未列出真机。该状态不足以判断 App 是否崩溃；设备连接恢复后仍需构建安装并重跑完整 UI 与持久化验证。
- 本次继续重试时新 PID `608416` 也在轮询前退出；启动时可用内存约 70 MB、HDC Offline，退出后约 103 MB。当前仍未观察到模拟器 HDC Online 或 ADB 真机设备。
- 22:32 用户告知真机与模拟器已接入后，本机重启 HDC、ADB 服务重新枚举：HDC 为 `[Empty]`，`adb devices -l` 无设备，`adb mdns services` 无无线调试目标；Windows 当前 PnP 设备列表没有 Huawei、Xiaomi 或 Android 手机标识。模拟器 `-list -details` 显示 Mate 90 Pro `isRunning=false`，CLI 冷启动返回 `Unable to start the emulator`。这些是当前 Codex 工作站工具可见状态，与用户所见状态不一致，尚不能据此判断设备本身是否已连接到其他会话/网络。
- 当前运行 `_tools/verify_all.py` 在 `connected()` 预检处退出，退出码 2、结果 0/8；它在预检失败后没有安装 HAP、启动 App 或改动设备。最新 HAP 的 UI、视觉与 V4 持久化均仍待本机设备桥接恢复后验证。
- 22:38 构建后再次针对当前 HAP 运行 `_tools/verify_all.py`，同样在设备预检退出，结果 0/8、未安装或启动应用；HDC 仍 `[Empty]`，ADB 仍无目标。
- 为降低前次启动时记录到的宿主内存压力，Mate 90 Pro 实例 `hw.ramSize` 暂设为 2048 MiB；修改前配置备份在 `work/nutriscan-ui-fidelity-20261019/evidence/Mate-90-Pro-config-before-ram-adjustment.ini`。此次启动仍未成功，因此该内存调整尚未证明有效。

### 12.10 单用户范围调整与模拟器确认（2026-10-19）

- 按产品范围调整移除今日页社群子页、个人公开开关和示例帖子数据；今日子导航现在为「综合 / 饮水 / 断食」。进度页报告占位改为个人报告本地导出方向，不再描述系统分享。
- Hvigor debug `assembleHap` 成功，33 个任务（22 个执行、11 个复用）。HAP 为 2,802,974 字节，SHA-256 `d9c35aea019570059666be2e112f50280509503e9b2a335464de7965d1a22e99`；无签名配置，仍为未签名调试包。
- HAP 已安装并启动在 Mate 90 Pro 模拟器。首页截图确认只显示三个子页且不含社群入口；逐一点击「饮水」「断食」均打开对应页面。截图：`work/nutriscan-ui-fidelity-20261019/evidence/single-user-scope/home.jpeg`。
- `_tools/verify_all.py` 在五步引导阶段停止：当前模拟器已有本版本隐私同意和引导完成状态，脚本将首步引导作为硬性前置，因此尚未进入后续 8 项回归。没有清除模拟器应用数据。模拟器当前存在饮水记录，空数据持久化脚本不适合直接执行；本轮仅做无数据变更的导航检查。
- 本轮未取得真机页面截图；完整 UI 回归、真机逐屏对照与后续数据持久化验证仍未完成。

### 12.11 单用户范围下的首页校准与当前 HAP 回归（2026-10-19）

- 修正首页热量半环的遮罩与内容定位，使弧线位于三项热量数据上方；提示区改为单卡横向 `Swiper` 并显示页点；空餐食卡调整为方形横向卡片。当前首页截图：`work/nutriscan-ui-fidelity-20261019/evidence/single-user-scope/home-layout-final.jpeg`。此前短暂用于检查遮罩位置的红色诊断背景已移除，最终构建与截图均使用正常深色 token。
- 最新 Hvigor debug `assembleHap` 构建成功，33 个任务（17 执行、16 up-to-date）。HAP 为 2,813,209 字节，SHA-256：`A129357CA4356D748E2D3FF1194B3219580B6990217108602C8A7026A83511F9`；项目未配置发布签名，仍为未签名调试包。
- 最新 HAP 的 `_tools/verify_all.py` 回归结果：**10 passed、1 skipped、0 failed（11 项）**。通过项包括首页主视觉、AI 识别入口、轮播横滑、餐食卡片与详情、示例图入口、本地 AI 演示识别链路、全部餐食页、断食首屏和断食 V4 强停重启持久化。饮水 V4 持久化因模拟器已有饮水记录而跳过；测试没有清除或修改已有记录。截图保存在 `_tools/shots/`。
- 轮播像素差分检查观察到提示横带变化 **16.6%**，首页主卡锚点变化 **0.00%**。像素变化用于确认内容已横向移动；旧版空断言和“UI 树节点消失”均不再作为轮播通过依据。
- Impeccable layout detector 对 `HomePage.ets` 与 `HomeTabs.ets` 返回空问题列表；`git diff --check` 通过，输出只有 Windows 工作区 LF/CRLF 提示。
- 最新工具复查时 `adb devices -l` 未列出真机设备；本节的视觉和回归结果仅代表 Mate 90 Pro 模拟器。Xiaomi 13 真机逐页对照仍需在 ADB 重新识别并且 NutriScan 页面可见后完成。发布签名、政策草案中的主体与接收方信息、商店截图和最终设备验收仍待关闭，见 §11。

### 12.12 当前 debug 精确产物复测与 release 构建检查（2026-10-19）

- 当前源码重新构建 debug `assembleHap` 成功，33 项任务（22 执行、11 up-to-date），HAP 2,813,209 字节，SHA-256 `7D3CFC2BF9D7661DC60988142E735659A4B915276E4D81D9C788308F78BEA429`。该精确产物已安装到 Mate 90 Pro 模拟器并完成 `_tools/verify_all.py`：**10 passed、1 skipped、0 failed**。饮水 V4 因现有记录跳过；断食测试写入自己的计划、强停重启读回并结束了测试计划，没有清空已有数据。完整逐项日志见 `work/nutriscan-ui-fidelity-20261019/evidence/verification-20261019-current-debug-hap-final.txt`；截图已更新到 `_tools/shots/`；脚本结束后已将模拟器恢复到“今日热量”首页。
- Hvigor release `assembleHap` 编译成功；未签名 release HAP 已安装到模拟器并启动到首页（单页冒烟），但输出明确为 `Will skip sign 'hos_hap'. No signingConfigs profile is configured`。产物单独保存为 `work/nutriscan-ui-fidelity-20261019/artifacts/entry-default-release-unsigned.hap`，1,273,773 字节，SHA-256 `B9D686CE9672923B90D70EA9BC8FF87B006E613DEB47ECF37C42A0A20C4E72AB`。这证明 release 编译和本地模拟器启动可运行，不证明可分发；发布签名、Profile 和当前关闭的混淆策略仍需处理。
- 官方 Hvigor 命令 `assembleApp` 亦成功产出 release App Pack：`work/nutriscan-ui-fidelity-20261019/artifacts/calories-default-release-unsigned.app`，618,088 字节，SHA-256 `B39FA1511D66395334D690279CFD9A8EB2830129DB6D96441EFBA94A5D782BA4`。App Pack 签名也被跳过，因此仍不可上传。Hvigor 官方命令说明见[Using hvigorw](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/ide-hvigor-commandline)；华为说明上架需 release certificate/profile，见[证书说明](https://developer.huawei.com/consumer/en/doc/app/agc-help-add-debugcert-0000001914263178)。
- AppGallery Connect 官方规格已复核（2026-01-20 更新）：HarmonyOS 手机/平板支持 3–5 张竖屏截图，9:16、1080×1920，PNG/JPG/JPEG 单张不超过 5 MB。当前还没有从最终真机验收版本制作商店截图；规格见[华为 AppGallery 素材要求](https://developer.huawei.com/consumer/en/doc/agc-help-app-visual-asset-spec-0000002277607976)。
- 本机最新设备枚举只发现 Mate 90 Pro 的 HDC `127.0.0.1:5555 Connected`；`adb devices -l`、ADB mDNS 与 Windows PnP 均未发现 Xiaomi/Android 真机。当前仍缺真机页面安全区、相机/相册交互和最终视觉核对证据。

### 12.13 单用户范围与当前 HAP 全量回归（2026-10-20）

- 产品按单用户个人记录交付：删除社群页面和导航入口，不提供好友关系、动态、点赞评论或公开个人资料。五个底部主 Tab 保留今日、膳食、进度、营养师和我的；今日只含综合、饮水、断食三个个人记录子页。源码扫描没有发现社群入口或页面路由。
- 当前调试 HAP 已安装并运行于 Mate 90 Pro 模拟器：`entry/build/default/outputs/default/entry-default-unsigned.hap`，2,812,758 字节，SHA-256 `70636AD95DFDF149DB5C7C1B615E735931B5A9A4C5EB9B1C20520CF8030933DD`。HAP 未签名，不能作为商店分发包。
- 当前 HAP 的 `_tools/verify_all.py` 回归为 **11 passed、0 skipped、0 failed**。通过项覆盖综合页、AI 入口、本地演示识别、轮播像素差分、餐食卡片和详情、全部餐食列表、饮水 V4 持久化与断食 V4 持久化。水记录重启读回 250 ml 后通过应用内“撤销”清理本次测试记录；断食测试恢复进行中的测试方案后结束该方案。
- 本轮把今日“综合”图标换为本地单色食物碗 SVG，并把饮水“撤销”入口移到快捷记录区。轮播横带像素变化为 **16.6%**，主卡锚点变化为 **0.00%**。当前截图与日志：`_tools/shots/v_01_home.jpeg`、`_tools/shots/v_03_carousel.jpeg`、`work/nutriscan-ui-fidelity-20261019/evidence/verification-20261020-single-user-final.txt`。回归后模拟器恢复到今日首页。
- 本机仍只枚举到 Mate 90 Pro 模拟器；ADB 和 Windows PnP 未发现 Xiaomi 13 真机，因此尚未完成真机逐页视觉对照。10 月 19 日留档的 release HAP/App Pack 未签名，且早于本轮 UI 修改；当前源码尚未重新生成正式 release 包。证书、Profile 和 AppGallery 上架资料仍需完成。

### 12.14 定位「完全免费」后的构建与全量回归（2026-10-20 09:29–09:50）

- 本轮按产品决策把项目定为**完全免费**：删除今日页页头的「免费试用 1 周」与粉橙渐变「升级」两个按钮及其占位入口；删除 `premium_pink` / `premium_orange` 两枚色标（base 与 dark 双份），饮水页火焰图标改用独立的 `streak_orange`；「我的」新增「版本与授权」卡。详见 §0.6。
- 当前调试 HAP：`entry/build/default/outputs/default/entry-default-unsigned.hap`，2,824,437 字节，SHA-256 `eb04da31e0a5ba40b98807398c328fe6c95cd786bf1109932ec6b25a0f89d56c`。`assembleHap` BUILD SUCCESSFUL。
- `_tools/verify_all.py` 全量回归：**10 passed、1 skipped、0 failed（11 项）**。唯一 SKIP 是饮水 V4 持久化 —— 模拟器已有饮水记录，脚本为避免覆盖或撤销现有记录主动跳过，与本次改动无关。轮播横带像素变化 16.6%，主卡锚点变化 0.00%。
- 「完全免费」专项实机确认（同一 HAP）：
  1. 今日页页头 UI 树含「全部功能免费」（bounds `[881,171][1224,283]`），整棵树**已无**「免费试用 1 周」「升级」文本；
  2. 「我的 → 版本与授权」卡实机渲染，两行文案均出现；
  3. 饮水页「连续达标」火焰图标仍为橙色 —— `streak_orange` 替换 `premium_orange` 后未变灰。
- 截图：`_tools/shots/free_header.jpeg`、`free_profile.jpeg`、`free_license.jpeg`、`free_water.jpeg`；日志：`work/nutriscan-ui-fidelity-20261019/evidence/verification-20261020-free-version.txt`。
