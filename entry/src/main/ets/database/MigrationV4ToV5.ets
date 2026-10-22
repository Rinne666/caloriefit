/**
 * V4 → V5：将空体征档案从虚构演示默认值迁移为未填写状态。
 *
 * 旧版 V3 初始化会写入 65 kg / 170 cm / 30 岁 / 男性，并把未选择枚举
 * 排除在 CHECK 约束之外。迁移只清除 updated_at=0 且整行恰好等于该
 * 初始化哨兵值的记录；真实保存过的用户档案保留原值和更新时间。
 *
 * Database.doInit 每次启动都会执行迁移链，因此新表约束已支持
 * unspecified 时直接跳过，旧表则事务性重建一次。
 */

import { relationalStore } from '@kit.ArkData';

const PROFILE_V5_DDL: string = `
CREATE TABLE body_profile_v5 (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  weight_kg REAL NOT NULL DEFAULT 0,
  height_cm INTEGER NOT NULL DEFAULT 0,
  age_years INTEGER NOT NULL DEFAULT 0,
  sex TEXT NOT NULL DEFAULT 'unspecified'
    CHECK (sex IN ('unspecified', 'male', 'female')),
  body_fat_ratio REAL
    CHECK (
      body_fat_ratio IS NULL OR
      (body_fat_ratio > 0 AND body_fat_ratio < 0.7)
    ),
  activity TEXT NOT NULL DEFAULT 'unspecified'
    CHECK (
      activity IN ('unspecified', 'sedentary', 'light', 'moderate', 'very_active', 'athlete')
    ),
  goal_mode TEXT NOT NULL DEFAULT 'unspecified'
    CHECK (
      goal_mode IN ('unspecified', 'weight_loss', 'maintain', 'surplus', 'deficit', 'recomp')
    ),
  updated_at INTEGER NOT NULL
)`;

export async function migrateV4ToV5(store: relationalStore.RdbStore): Promise<void> {
  const existingSql = await profileTableSql(store);
  if (existingSql.length === 0) {
    // V1/V2 数据库还没有体征表；V2→V3 随后会用新约束创建它。
    return;
  }

  const normalized = existingSql.toLowerCase();
  if (normalized.includes("sex in ('unspecified', 'male', 'female')") &&
    normalized.includes("activity in ('unspecified'") &&
    normalized.includes("goal_mode in ('unspecified'")) {
    return;
  }

  store.beginTransaction();
  try {
    await store.executeSql('DROP TABLE IF EXISTS body_profile_v5');
    await store.executeSql(PROFILE_V5_DDL);
    await store.executeSql(`
      INSERT INTO body_profile_v5
        (id, weight_kg, height_cm, age_years, sex, body_fat_ratio,
         activity, goal_mode, updated_at)
      SELECT id, weight_kg, height_cm, age_years, sex, body_fat_ratio,
             activity, goal_mode, updated_at
      FROM body_profile
    `);
    await store.executeSql(`
      UPDATE body_profile_v5
      SET weight_kg = 0,
          height_cm = 0,
          age_years = 0,
          sex = 'unspecified',
          activity = 'unspecified',
          goal_mode = 'unspecified'
      WHERE updated_at = 0
        AND weight_kg = 65
        AND height_cm = 170
        AND age_years = 30
        AND sex = 'male'
        AND body_fat_ratio IS NULL
        AND activity = 'moderate'
        AND goal_mode = 'weight_loss'
    `);
    await store.executeSql('DROP TABLE body_profile');
    await store.executeSql('ALTER TABLE body_profile_v5 RENAME TO body_profile');
    store.commit();
  } catch (_e) {
    store.rollBack();
    throw new Error('V4 to V5 body-profile migration failed');
  }
}

async function profileTableSql(store: relationalStore.RdbStore): Promise<string> {
  const result = await store.querySql(
    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'body_profile'");
  try {
    if (!result.goToFirstRow()) {
      return '';
    }
    const index = result.getColumnIndex('sql');
    return result.isColumnNull(index) ? '' : result.getString(index);
  } finally {
    result.close();
  }
}
