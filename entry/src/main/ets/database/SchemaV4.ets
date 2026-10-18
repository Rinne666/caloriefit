/**
 * Schema V4 —— 饮水 Water + 断食 Fasting
 *
 * 对齐 NutriScan 首页子页 Water / Fasting（见 services/MockContent.ets 头注释
 * 的实测证据来源）。
 *
 * 相对 V3 的增量:
 *   1. 新增 water_log 表:逐笔记录,支持撤销最后一笔
 *   2. 新增 fasting_log 表:按天记录断食窗口,含完成标记
 *   3. app_settings 增加 water_target_ml(可空)——
 *      为空表示按体重自动推导,有值表示用户手动改过(对应 UI 上的铅笔图标)
 *
 * 设计约束:
 *   · 逐笔存而不是只存当日合计 —— 原版有 250/500ml 快捷加，
 *     撤销最后一笔是这类交互的必需能力，只存合计就丢了顺序信息
 *   · 饮水目标可空,不写死默认值：NULL = 自动,数值 = 手动覆盖
 */

/* ---------- water_log ---------- */

export const SQL_CREATE_WATER_LOG: string = `
CREATE TABLE IF NOT EXISTS water_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  ml INTEGER NOT NULL
    CHECK (ml > 0 AND ml <= 5000),
  created_at INTEGER NOT NULL
)
`;

export const SQL_DROP_WATER_LOG: string = 'DROP TABLE IF EXISTS water_log';

/* ---------- fasting_log ---------- */

export const SQL_CREATE_FASTING_LOG: string = `
CREATE TABLE IF NOT EXISTS fasting_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  plan_id TEXT NOT NULL,
  start_at INTEGER NOT NULL,
  end_at INTEGER NOT NULL,
  completed INTEGER NOT NULL DEFAULT 0
    CHECK (completed IN (0, 1))
)
`;

export const SQL_DROP_FASTING_LOG: string = 'DROP TABLE IF EXISTS fasting_log';

/* ---------- app_settings 饮水目标（V3 → V4） ---------- */

export const SQL_ADD_SETTINGS_WATER: string[] = [
  'ALTER TABLE app_settings ADD COLUMN water_target_ml INTEGER'
];

export const SQL_DROP_SETTINGS_WATER: string[] = [
  'ALTER TABLE app_settings DROP COLUMN water_target_ml'
];

/* ---------- 读写语句 ---------- */

export const SQL_INSERT_WATER: string = `
INSERT INTO water_log (date, ml, created_at)
VALUES (?, ?, ?)
`;

export const SQL_DELETE_LAST_WATER: string = `
DELETE FROM water_log
WHERE id = (SELECT id FROM water_log WHERE date = ? ORDER BY id DESC LIMIT 1)
`;

export const SQL_SUM_WATER_BY_DATE: string = `
SELECT COALESCE(SUM(ml), 0) AS total_ml
FROM water_log
WHERE date = ?
`;

export const SQL_WATER_TREND: string = `
SELECT date, COALESCE(SUM(ml), 0) AS total_ml
FROM water_log
WHERE date >= ? AND date <= ?
GROUP BY date
ORDER BY date ASC
`;

export const SQL_SELECT_WATER_TARGET: string = `
SELECT water_target_ml FROM app_settings WHERE id = 1
`;

export const SQL_UPDATE_WATER_TARGET: string = `
UPDATE app_settings SET water_target_ml = ?, updated_at = ? WHERE id = 1
`;

export const SQL_INSERT_FASTING: string = `
INSERT INTO fasting_log (date, plan_id, start_at, end_at, completed)
VALUES (?, ?, ?, ?, 0)
`;

export const SQL_SELECT_ACTIVE_FASTING: string = `
SELECT id, plan_id, start_at, end_at
FROM fasting_log
WHERE date = ? AND completed = 0
ORDER BY id DESC
LIMIT 1
`;

export const SQL_COMPLETE_FASTING: string = `
UPDATE fasting_log SET completed = 1, end_at = ? WHERE id = ?
`;

export const SQL_CLEAR_ACTIVE_FASTING: string = `
DELETE FROM fasting_log WHERE date = ? AND completed = 0
`;

export const SQL_FASTING_HISTORY: string = `
SELECT date, plan_id, completed FROM fasting_log
WHERE date >= ? AND date <= ?
ORDER BY date ASC
`;
