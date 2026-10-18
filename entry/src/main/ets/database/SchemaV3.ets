/**
 * Schema V3 —— 体征档案 + 宏量营养素
 *
 * 相对 V2 的增量:
 *   1. 新增 body_profile 表(单行,id=1):体重/身高/年龄/性别/体脂/活动量/目标模式
 *   2. food_log 增加 macro_g 聚合列(蛋白/碳水/脂肪),可空
 *   3. app_settings 增加宏量目标列 + 自动计算开关
 *
 * 设计约束:
 *   · 所有新增列均可空 —— V2 存量数据不伪造宏量,界面按"未记录"处理
 *   · 宏量目标可由体征自动推导,也可手动覆盖(manual 优先级高于 auto)
 *
 * 依据:对 NutriScan 的逆向分析(见 services/CalorieEngine.ets 头注释)。
 * 原 App 的宏量目标由 Atwater 系数反推得出,本项目保持同口径。
 */

// ---------- body_profile ----------

export const SQL_CREATE_BODY_PROFILE: string = `
CREATE TABLE IF NOT EXISTS body_profile (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  weight_kg REAL NOT NULL DEFAULT 65,
  height_cm INTEGER NOT NULL DEFAULT 170,
  age_years INTEGER NOT NULL DEFAULT 30,
  sex TEXT NOT NULL DEFAULT 'male'
    CHECK (sex IN ('male', 'female')),
  body_fat_ratio REAL
    CHECK (
      body_fat_ratio IS NULL OR
      (body_fat_ratio > 0 AND body_fat_ratio < 0.7)
    ),
  activity TEXT NOT NULL DEFAULT 'moderate'
    CHECK (
      activity IN ('sedentary', 'light', 'moderate', 'very_active', 'athlete')
    ),
  goal_mode TEXT NOT NULL DEFAULT 'weight_loss'
    CHECK (
      goal_mode IN ('weight_loss', 'maintain', 'surplus', 'deficit', 'recomp')
    ),
  updated_at INTEGER NOT NULL
)`;

export const SQL_INIT_BODY_PROFILE: string = `
INSERT OR IGNORE INTO body_profile
  (id, weight_kg, height_cm, age_years, sex, body_fat_ratio,
   activity, goal_mode, updated_at)
  VALUES (1, 65, 170, 30, 'male', NULL, 'moderate', 'weight_loss', 0)
`;

// ---------- food_log 宏量列(V2 → V3) ----------
// 用 ALTER TABLE 追加,SQLite 不支持 IF NOT EXISTS 列,故由迁移器做存在性检查后再执行。

export const SQL_ADD_FOOD_MACROS: string[] = [
  'ALTER TABLE food_log ADD COLUMN protein_g REAL',
  'ALTER TABLE food_log ADD COLUMN carbs_g REAL',
  'ALTER TABLE food_log ADD COLUMN fat_g REAL'
];

export const SQL_DROP_FOOD_MACROS: string[] = [
  'ALTER TABLE food_log DROP COLUMN protein_g',
  'ALTER TABLE food_log DROP COLUMN carbs_g',
  'ALTER TABLE food_log DROP COLUMN fat_g'
];

// ---------- app_settings 宏量目标(V2 → V3) ----------

export const SQL_ADD_SETTINGS_MACROS: string[] = [
  'ALTER TABLE app_settings ADD COLUMN target_protein_g INTEGER',
  'ALTER TABLE app_settings ADD COLUMN target_carbs_g INTEGER',
  'ALTER TABLE app_settings ADD COLUMN target_fat_g INTEGER',
  'ALTER TABLE app_settings ADD COLUMN target_auto INTEGER NOT NULL DEFAULT 1'
];

export const SQL_DROP_SETTINGS_MACROS: string[] = [
  'ALTER TABLE app_settings DROP COLUMN target_protein_g',
  'ALTER TABLE app_settings DROP COLUMN target_carbs_g',
  'ALTER TABLE app_settings DROP COLUMN target_fat_g',
  'ALTER TABLE app_settings DROP COLUMN target_auto'
];

export const SQL_INIT_SETTINGS_MACROS: string = `
UPDATE app_settings
SET target_auto = 1
WHERE id = 1 AND target_auto IS NULL
`;

// ---------- 读写语句 ----------

export const SQL_SELECT_BODY_PROFILE: string = `
SELECT weight_kg, height_cm, age_years, sex, body_fat_ratio,
       activity, goal_mode, updated_at
FROM body_profile
WHERE id = 1
`;

export const SQL_UPSERT_BODY_PROFILE: string = `
INSERT OR REPLACE INTO body_profile
  (id, weight_kg, height_cm, age_years, sex, body_fat_ratio,
   activity, goal_mode, updated_at)
VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?)
`;

export const SQL_SELECT_MACRO_TARGET: string = `
SELECT target_protein_g, target_carbs_g, target_fat_g, target_auto
FROM app_settings
WHERE id = 1
`;

export const SQL_UPDATE_MACRO_TARGET: string = `
UPDATE app_settings
SET target_protein_g = ?, target_carbs_g = ?, target_fat_g = ?,
    target_auto = ?, updated_at = ?
WHERE id = 1
`;

/**
 * 当日宏量汇总
 * COALESCE 兜底为 0:存量记录无宏量,视为 0 摄入,不会导致 SUM 返回 NULL
 */
export const SQL_SUM_MACROS_BY_DATE: string = `
SELECT
  COALESCE(SUM(protein_g), 0) AS protein_g,
  COALESCE(SUM(carbs_g), 0)   AS carbs_g,
  COALESCE(SUM(fat_g), 0)     AS fat_g
FROM food_log
WHERE date = ?
`;

/** 当日总热量(与既有 DailySummaryService 口径一致) */
export const SQL_SUM_KCAL_BY_DATE: string = `
SELECT COALESCE(SUM(calories), 0) AS total_kcal
FROM food_log
WHERE date = ?
`;

/**
 * 最近 N 天每日热量序列 —— 供首页周趋势图使用。
 * date 升序,缺失日期不补零,由调用方对齐。
 */
export const SQL_KCAL_TREND: string = `
SELECT date, COALESCE(SUM(calories), 0) AS total_kcal
FROM food_log
WHERE date >= ? AND date <= ?
GROUP BY date
ORDER BY date ASC
`;

/** 最近 N 天宏量序列 */
export const SQL_MACRO_TREND: string = `
SELECT date,
       COALESCE(SUM(protein_g), 0) AS protein_g,
       COALESCE(SUM(carbs_g), 0)   AS carbs_g,
       COALESCE(SUM(fat_g), 0)     AS fat_g
FROM food_log
WHERE date >= ? AND date <= ?
GROUP BY date
ORDER BY date ASC
`;

/** 该日是否有任何带宏量的记录 —— 决定 UI 是否显示"未记录宏量"提示 */
export const SQL_HAS_MACRO_ON_DATE: string = `
SELECT COUNT(*) AS n
FROM food_log
WHERE date = ? AND protein_g IS NOT NULL
`;
