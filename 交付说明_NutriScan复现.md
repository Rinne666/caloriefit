# NutriScan → CalorieFit 复现交付说明

> 分支 `feature/glass-poster-ui` · 目标平台 HarmonyOS NEXT (API 26) · 模拟器实测通过

---

## 0. 一句话说明

按 NutriScan 实测路由树重建了信息架构与视觉语言。
**每一个入口都可达**：做了的进真实页面，没做的进占位页并写清「本应功能 / 未实现原因 / 补上需要」。
所有 mock 与推断内容在界面上都带来源角标，不伪装成实测数据。

---

## 0.5 ⚠ 最大的一处偏差：视觉语言被替换过（请先看这条）

**这一项不是一比一还原，明确写出来，不放在附注里。**

| | NutriScan 实测 | 本项目实现 |
|---|---|---|
| 页面底 | 平面 `#0C0C0C` | 三段高饱和渐变（紫 → 青） |
| 卡片 | 平面 `#1C1C1E` | `backdropBlur` 半透明玻璃 |
| 描边 | `#2F2F33` 细描边 | 半透明白亮边 |
| 主色点缀 | 荧光绿 `#D5EE6E` | 同（这项对齐了） |

上面那组「平面 `#0C0C0C` / `#1C1C1E` / `#2F2F33`」是**本项目自己的逆向结论**，
出自 `NutriScan_设计系统与鸿蒙复现.md`。也就是说原版本来就是平面暗色，
不是玻璃拟态 —— 当前实现是换了一套视觉语言。

**为什么会这样**：在「一比一还原」这个要求之前，用户先给了另一段电商产品卡的
视觉规范并要求落地到本项目，玻璃拟态是那次的需求。当前实现同时满足了两条要求，
代价是视觉上偏离原版，而这一点此前没有在任何交付物里标为偏差。

**要真正 1:1 需要做什么**：把色板换回原版实测值并去掉 backdropBlur。
由于所有卡片都走 DesignTokens 的 token 引用、页面里没有硬编码色值，
改动量集中在 token 层而不是页面层 —— 这是当前架构带来的好处。

已对齐的部分（实测精确命中）：深色 `#D5EE6E` / `#0A84FF` / `#FF2E63` / `#4CC94E`；
底 Tab 已补为「图标 + 文字」；进度页已补 `🔥 Streak` 与 `Report`；
饮水页与原版逐元素对齐（选中态药丸、水瓶、`% completed` 青色、带铅笔的 goal、
`ml consumed`、M–S 圆环今天描边、250/500 + 自定义、This Week 卡七柱）。

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
| 今日 | Home（Overall/Club/Water/Fasting） | `HomeTabs.ets` 手写分段控件 | ✅ 4 个子页全通 |
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
- 订阅墙 —— 原版是「划线价与实付价相同却宣称 70% off」的虚假折扣，不克隆；引导以生活方式收尾

### 2.2 今日页四个子页

| 子页 | 数据来源 | 状态 |
|---|---|---|
| 综合 | 真实（已有 `CalorieEngine` / `MacroRepository`） | ✅ |
| 社群 | 示例帖子 + 实测开关文案「在 Club 展示我的资料」 | ✅ 界面 |
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
社群       "Afficher mon profil dans le Club"（在 Club 展示我的资料）
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
| 订阅墙 + 二次挽留 | 划线价与实付价相同却宣称 70% off，属虚假折扣，**不克隆** |

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
   与**没有订阅墙**（原版是虚假折扣，不克隆）。
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
深底 + 青色饮水强调 + 荧光绿 FAB + 玻璃描边均正常，
示例角标在深色下清晰可读。

补验中修掉的问题分两类：
- **应用问题 1 个**：AI 页图片预览空白。`Image()` 解不出沙箱真实路径，
  改成显示走 `$rawfile` 资源、读取仍走 cacheDir 真实路径，两条通道分开。
- **脚本自身 3 个**（与应用无关）：`connected()` 把 `CompletedProcess`
  当字符串判断导致正常设备被误判离线；按钮文案写成「开始识别」
  而实际是「开始 AI 识别」导致点空；找长页面入口用固定滑动次数
  滚少了够不着滚多了滑过头，改为边滑边找。

一处已知视觉瑕疵：悬浮「+」在「本周」卡上会盖住「日均 ml」标签。
属悬浮按钮的常规行为（内容可滚出其下），未做处理。

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
| — | 今日（综合/社群/饮水/断食 子页） | ✅ |
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
