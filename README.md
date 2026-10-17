# CalorieFit 卡路里管家

HarmonyOS 原生（ArkTS / API 26）卡路里与运动目标管理 App。由 ChatGPT 担任产品经理（调研/选型/视觉/开发文档），本工作区为工程实现与调试产物。

## 技术栈

- **语言/UI**：ArkTS + ArkUI（声明式），Stage 模型
- **SDK**：HarmonyOS 26.0.0（API 26），compatibleSdkVersion `26.0.0`
- **存储**：ArkData RDB（`caloriefit.db`，4 张表：app_settings / food_log / exercise_log / daily_activity）
- **三方依赖**：0
- **运动数据**：本地模拟（`MockActivityDataSource`，预留 `ActivityDataSource` 接口接 Health Service Kit）

## 功能（MVP V1.0）

- 今日：热量进度环（摄入/预算/剩余）、活动消耗、步数与运动时长进度、快捷记录
- 饮食：早/午/晚/加餐分组记录，重量 × 每100g热量自动计算，增删改
- 运动：手动运动记录（类型/时长/消耗）、模拟步数（覆盖式保存）
- 我的：四项目标设置、清空全部记录（事务 + 二次确认）
- 全部数据本地持久化；仅浅色模式

## 目录结构

```
entry/src/main/ets/
├── entryability/EntryAbility.ets   # 入口，固定浅色模式
├── pages/                          # Index(唯一@Entry) + 4 Tab页 + 2 编辑页(NavDestination)
├── components/                     # CalorieRing / MetricCard / EmptyState
├── common/                         # DesignTokens / Constants / DateUtils / Validators
├── models/                         # 5 个数据模型
├── database/                       # Database(RDB单例) / Schema(建表SQL)
├── repositories/                   # 4 个 Repository（UI 层不直接碰 SQL）
└── services/                       # CalorieService / DailySummaryService / 数据源接口
```

## 构建与部署

```bash
# 构建（DevEco Studio 26 自带 hvigor）
export DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk"
"C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw" \
  --mode module -p product=default -p buildMode=debug assembleHap --no-daemon

# 安装到模拟器（本机模拟器接受未签名 HAP）
hdc install -r entry/build/default/outputs/default/entry-default-unsigned.hap
hdc shell aa start -b com.rinne.caloriefit -a EntryAbility
```

## 验收状态（2026-10-17）

GPT 第 2 步定义的 7 条 MVP 验收标准全部实测通过（截图见 `screenshots/`）：
四 Tab 切换 ✅ / 195 kcal 计算 ✅ / 增删同步 ✅ / 运动汇总 ✅ / 77.5% 进度 ✅ / 目标全局一致 ✅ / 重启持久化 ✅

## 产品经理对话

设计方案与验收由 ChatGPT 提供：https://chatgpt.com/c/6ad30864-bca4-83ee-b1ad-ccdab3fc490b
