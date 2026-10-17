/**
 * 全部建表、建索引 SQL 与 V1→V2 迁移 SQL。逐条执行。
 * V2 核心约束：entry_mode=0 必须有重量和每100g热量；entry_mode=1 二者必须为 NULL。
 */

// ---------- V2 全新建表 ----------

export const SQL_CREATE_APP_SETTINGS: string = `
CREATE TABLE IF NOT EXISTS app_settings (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  daily_calorie_budget INTEGER NOT NULL DEFAULT 1800,
  steps_goal INTEGER NOT NULL DEFAULT 8000,
  exercise_minutes_goal INTEGER NOT NULL DEFAULT 30,
  activity_kcal_goal INTEGER NOT NULL DEFAULT 300,
  updated_at INTEGER NOT NULL
)`;

export const SQL_CREATE_FOOD_LOG_V2: string = `
CREATE TABLE IF NOT EXISTS food_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  name TEXT NOT NULL,
  meal_type INTEGER NOT NULL
    CHECK (meal_type BETWEEN 0 AND 3),
  grams REAL,
  kcal_per_100g REAL,
  calories INTEGER NOT NULL
    CHECK (calories >= 0),
  entry_mode INTEGER NOT NULL DEFAULT 0
    CHECK (entry_mode IN (0, 1)),
  ai_confidence REAL
    CHECK (
      ai_confidence IS NULL OR
      (ai_confidence >= 0 AND ai_confidence <= 1)
    ),
  ai_notes TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  CHECK (
    (
      entry_mode = 0
      AND grams IS NOT NULL
      AND grams > 0
      AND kcal_per_100g IS NOT NULL
      AND kcal_per_100g >= 0
    )
    OR
    (
      entry_mode = 1
      AND grams IS NULL
      AND kcal_per_100g IS NULL
      AND calories > 0
    )
  )
)`;

export const SQL_CREATE_EXERCISE_LOG: string = `
CREATE TABLE IF NOT EXISTS exercise_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  type INTEGER NOT NULL CHECK(type BETWEEN 0 AND 4),
  duration_minutes INTEGER NOT NULL CHECK(duration_minutes > 0),
  calories_burned INTEGER NOT NULL CHECK(calories_burned >= 0),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)`;

export const SQL_CREATE_DAILY_ACTIVITY: string = `
CREATE TABLE IF NOT EXISTS daily_activity (
  date TEXT PRIMARY KEY NOT NULL,
  steps INTEGER NOT NULL DEFAULT 0 CHECK(steps >= 0),
  source TEXT NOT NULL DEFAULT 'MANUAL_SIMULATED',
  updated_at INTEGER NOT NULL
)`;

export const SQL_CREATE_INDEX_FOOD: string =
  'CREATE INDEX IF NOT EXISTS idx_food_date ON food_log(date)';

export const SQL_CREATE_INDEX_EXERCISE: string =
  'CREATE INDEX IF NOT EXISTS idx_exercise_date ON exercise_log(date)';

export const SQL_CREATE_ALL_V2: string[] = [
  SQL_CREATE_APP_SETTINGS,
  SQL_CREATE_FOOD_LOG_V2,
  SQL_CREATE_EXERCISE_LOG,
  SQL_CREATE_DAILY_ACTIVITY,
  SQL_CREATE_INDEX_FOOD,
  SQL_CREATE_INDEX_EXERCISE
];

export const SQL_INIT_SETTINGS: string =
  `INSERT OR IGNORE INTO app_settings
  (id, daily_calorie_budget, steps_goal, exercise_minutes_goal, activity_kcal_goal, updated_at)
  VALUES (1, 1800, 8000, 30, 300, 0)`;

// ---------- V1 → V2 迁移 ----------

export const SQL_MIGRATE_CREATE_V2_TEMP: string = `
CREATE TABLE food_log_v2 (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  name TEXT NOT NULL,
  meal_type INTEGER NOT NULL
    CHECK (meal_type BETWEEN 0 AND 3),
  grams REAL,
  kcal_per_100g REAL,
  calories INTEGER NOT NULL
    CHECK (calories >= 0),
  entry_mode INTEGER NOT NULL DEFAULT 0
    CHECK (entry_mode IN (0, 1)),
  ai_confidence REAL
    CHECK (
      ai_confidence IS NULL OR
      (ai_confidence >= 0 AND ai_confidence <= 1)
    ),
  ai_notes TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  CHECK (
    (
      entry_mode = 0
      AND grams IS NOT NULL
      AND grams > 0
      AND kcal_per_100g IS NOT NULL
      AND kcal_per_100g >= 0
    )
    OR
    (
      entry_mode = 1
      AND grams IS NULL
      AND kcal_per_100g IS NULL
      AND calories > 0
    )
  )
)`;

export const SQL_MIGRATE_COPY: string = `
INSERT INTO food_log_v2 (
  id, date, name, meal_type, grams, kcal_per_100g, calories,
  entry_mode, ai_confidence, ai_notes, created_at, updated_at
)
SELECT
  id, date, name, meal_type, grams, kcal_per_100g, calories,
  0, NULL, NULL, created_at, updated_at
FROM food_log`;

export const SQL_MIGRATE_STATS: string =
  `SELECT COUNT(*) AS record_count,
  COALESCE(SUM(calories), 0) AS total_kcal,
  COALESCE(MAX(id), 0) AS max_id FROM food_log`;

export const SQL_MIGRATE_STATS_V2: string =
  `SELECT COUNT(*) AS record_count,
  COALESCE(SUM(calories), 0) AS total_kcal,
  COALESCE(MAX(id), 0) AS max_id FROM food_log_v2`;

export const SQL_MIGRATE_DROP_OLD: string = 'DROP TABLE food_log';

export const SQL_MIGRATE_RENAME: string =
  'ALTER TABLE food_log_v2 RENAME TO food_log';

export const SQL_MIGRATE_RECREATE_INDEX: string =
  'CREATE INDEX idx_food_date ON food_log(date)';

export const SQL_READ_OLD_SEQUENCE: string =
  `SELECT COALESCE(
    (SELECT seq FROM sqlite_sequence WHERE name = 'food_log'),
    0
  ) AS last_sequence`;

export const SQL_INSERT_SEQUENCE: string =
  `INSERT INTO sqlite_sequence (name, seq)
  SELECT 'food_log', ?
  WHERE NOT EXISTS (
    SELECT 1 FROM sqlite_sequence WHERE name = 'food_log'
  )`;

export const SQL_FIX_SEQUENCE: string =
  `UPDATE sqlite_sequence
  SET seq = CASE WHEN seq < ? THEN ? ELSE seq END
  WHERE name = 'food_log'`;

export const SQL_TABLE_EXISTS: string =
  `SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?`;

export const SQL_TABLE_INFO: string = 'PRAGMA table_info(food_log)';
