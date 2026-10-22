/**
 * V7：黑板画布的表结构。
 *
 * ## board_node —— 黑板上的一个节点
 * 一张表同时承载三种节点，靠 `node_type` + `food_id` 区分：
 *   · FOOD_STICKER(0)：food_id 指向 food_log.id，内容（名称/热量/宏量/贴纸）
 *     **不在这里存**，展示时从 food_log 读 —— 改了记录黑板立刻跟着变。
 *   · STICKY_NOTE(1)：独立便签，food_id 为 NULL，内容存在本表。
 *   · DEMO_STICKER(2)：内置示例贴纸，food_id 为 NULL，不计入热量。
 *
 * ## board_setting —— 全局一份的黑板设置
 * 底纹主题与视图模式都是跨日期的，不属于某一天，所以单独一张单行表。
 */

export const SQL_CREATE_BOARD_NODE: string = `
CREATE TABLE IF NOT EXISTS board_node (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  node_type INTEGER NOT NULL
    CHECK (node_type IN (0, 1, 2)),
  food_id INTEGER,
  title TEXT NOT NULL DEFAULT '',
  calories INTEGER NOT NULL DEFAULT 0,
  protein_g REAL,
  carbs_g REAL,
  fat_g REAL,
  portion_desc TEXT NOT NULL DEFAULT '',
  meal_category INTEGER NOT NULL DEFAULT 3
    CHECK (meal_category BETWEEN 0 AND 3),
  time_str TEXT NOT NULL DEFAULT '',
  mood_emoji TEXT NOT NULL DEFAULT '',
  companion_text TEXT NOT NULL DEFAULT '',
  memo_text TEXT NOT NULL DEFAULT '',
  ai_advice TEXT NOT NULL DEFAULT '',
  sticker_uri TEXT NOT NULL DEFAULT '',
  paper_style INTEGER NOT NULL DEFAULT 0
    CHECK (paper_style BETWEEN 0 AND 4),
  pin_type INTEGER NOT NULL DEFAULT 0
    CHECK (pin_type BETWEEN 0 AND 3),
  pos_x REAL NOT NULL DEFAULT 0,
  pos_y REAL NOT NULL DEFAULT 0,
  scale REAL NOT NULL DEFAULT 1,
  rotation REAL NOT NULL DEFAULT 0,
  z_index INTEGER NOT NULL DEFAULT 0,
  is_flipped INTEGER NOT NULL DEFAULT 0
    CHECK (is_flipped IN (0, 1)),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)`;

export const SQL_CREATE_BOARD_SETTING: string = `
CREATE TABLE IF NOT EXISTS board_setting (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  theme INTEGER NOT NULL DEFAULT 0
    CHECK (theme BETWEEN 0 AND 2),
  view_mode INTEGER NOT NULL DEFAULT 0
    CHECK (view_mode BETWEEN 0 AND 1),
  updated_at INTEGER NOT NULL
)`;

export const SQL_CREATE_INDEX_BOARD_DATE: string =
  'CREATE INDEX IF NOT EXISTS idx_board_node_date ON board_node(date)';

export const SQL_CREATE_ALL_V7: string[] = [
  SQL_CREATE_BOARD_NODE,
  SQL_CREATE_BOARD_SETTING,
  SQL_CREATE_INDEX_BOARD_DATE
];

export const SQL_INIT_BOARD_SETTING: string =
  `INSERT OR IGNORE INTO board_setting
  (id, theme, view_mode, updated_at)
  VALUES (1, 0, 0, 0)`;
