/**
 * V5 → V6：给 food_log 增加「贴纸路径」列。
 *
 * 用 ALTER TABLE ADD COLUMN 而不是重建表 —— 加可空列是 SQLite 最安全的迁移：
 * 不动既有行、不触碰 CHECK 约束、不需要重建索引，失败也可安全回滚。
 * 存量行的 sticker_path 为 NULL，语义正确（这些记录本来就没有贴纸）。
 *
 * 新建库同样走这条路径：V2 建表时并不包含该列，统一由本迁移补上，
 * 避免「新建库有列、存量库没列」两套结构。
 */

import { relationalStore } from '@kit.ArkData';

const COLUMN_NAME: string = 'sticker_path';

export async function migrateV5ToV6(store: relationalStore.RdbStore): Promise<void> {
  const cols = await foodLogColumns(store);
  if (cols.length === 0) {
    // food_log 还不存在（理论上不会发生：V2→V3 已建表），保守跳过，
    // 交给后续建表流程，避免在这里因缺表而中断整个迁移链。
    return;
  }
  if (cols.includes(COLUMN_NAME)) {
    return;
  }

  store.beginTransaction();
  try {
    await store.executeSql(`ALTER TABLE food_log ADD COLUMN ${COLUMN_NAME} TEXT`);
    store.commit();
  } catch (_e) {
    store.rollBack();
    throw new Error('V5 to V6 sticker_path migration failed');
  }
}

async function foodLogColumns(store: relationalStore.RdbStore): Promise<string[]> {
  const resultSet = await store.querySql('PRAGMA table_info(food_log)');
  const cols: string[] = [];
  try {
    while (resultSet.goToNextRow()) {
      cols.push(resultSet.getString(resultSet.getColumnIndex('name')));
    }
  } finally {
    resultSet.close();
  }
  return cols;
}
