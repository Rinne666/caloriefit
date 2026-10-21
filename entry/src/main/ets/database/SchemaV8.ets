/**
 * V8：黑板节点表放开 `node_type` 的取值范围。
 *
 * ## 为什么要改表结构
 * `board_node.node_type` 原本是 `CHECK (node_type IN (0, 1, 2))`：
 *   0 FOOD_STICKER / 1 STICKY_NOTE / 2 DEMO_STICKER
 * 2026-10-21 新增 3 DEMO_NOTE（内置示例便签，见 models/BoardModels.ets），
 * SQLite 的 CHECK 约束**不能直接 ALTER**，只能重建表。
 *
 * ## 重建的做法（与 V4→V5 放宽 body_profile 约束同源）
 * 建新表 → 拷数据 → 删旧表 → 改名。放在一个事务里，
 * 不会出现「表建了一半」的中间态。
 */

export const SQL_CREATE_BOARD_NODE_V8: string = `
CREATE TABLE board_node_v8 (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  node_type INTEGER NOT NULL
    CHECK (node_type IN (0, 1, 2, 3)),
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

/** 拷贝列顺序与 V8 表结构一一对应 */
export const SQL_COPY_BOARD_NODE_V8: string = `
  INSERT INTO board_node_v8
    (id, date, node_type, food_id, title, calories, protein_g, carbs_g, fat_g,
     portion_desc, meal_category, time_str, mood_emoji, companion_text, memo_text,
     ai_advice, sticker_uri, paper_style, pin_type, pos_x, pos_y, scale, rotation,
     z_index, is_flipped, created_at, updated_at)
  SELECT id, date, node_type, food_id, title, calories, protein_g, carbs_g, fat_g,
         portion_desc, meal_category, time_str, mood_emoji, companion_text, memo_text,
         ai_advice, sticker_uri, paper_style, pin_type, pos_x, pos_y, scale, rotation,
         z_index, is_flipped, created_at, updated_at
  FROM board_node
`;
