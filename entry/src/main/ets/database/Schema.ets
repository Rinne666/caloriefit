/**
 * 全部建表、建索引 SQL。V1 只做幂等建表；升级结构必须走正式迁移流程。
 */

export const SQL_CREATE_APP_SETTINGS: string = `
CREATE TABLE IF NOT EXISTS app_settings (
  id INTEGER PRIMARY KEY CHECK(id = 1),
  daily_calorie_budget INTEGER NOT NULL CHECK(daily_calorie_budget >= 1),
  steps_goal INTEGER NOT NULL CHECK(steps_goal >= 1),
  exercise_minutes_goal INTEGER NOT NULL CHECK(exercise_minutes_goal >= 1),
  activity_kcal_goal INTEGER NOT NULL CHECK(activity_kcal_goal >= 1),
  updated_at INTEGER NOT NULL
)`;

export const SQL_CREATE_FOOD_LOG: string = `
CREATE TABLE IF NOT EXISTS food_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  name TEXT NOT NULL,
  meal_type INTEGER NOT NULL CHECK(meal_type BETWEEN 0 AND 3),
  weight_g REAL NOT NULL CHECK(weight_g > 0),
  kcal_per_100g REAL NOT NULL CHECK(kcal_per_100g >= 0),
  calories INTEGER NOT NULL CHECK(calories >= 0),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
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

export const SQL_CREATE_ALL: string[] = [
  SQL_CREATE_APP_SETTINGS,
  SQL_CREATE_FOOD_LOG,
  SQL_CREATE_EXERCISE_LOG,
  SQL_CREATE_DAILY_ACTIVITY,
  SQL_CREATE_INDEX_FOOD,
  SQL_CREATE_INDEX_EXERCISE
];

export const SQL_INIT_SETTINGS: string =
  `INSERT OR IGNORE INTO app_settings
  (id, daily_calorie_budget, steps_goal, exercise_minutes_goal, activity_kcal_goal, updated_at)
  VALUES (1, 1800, 8000, 30, 300, 0)`;
