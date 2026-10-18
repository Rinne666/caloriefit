/**
 * V2 → V3 迁移：体征档案 + 宏量营养素
 *
 * 策略沿用 MigrationV1ToV2 的防御式做法 —— 逐列检查存在性后才 ALTER，
 * 不依赖 store.version，也不假设迁移只跑一次。
 * 中途失败可安全重入：已加的列会被跳过。
 *
 * 幂等保证：
 *   · 每一列 ALTER 前用 PRAGMA table_info 确认缺失
 *   · body_profile 用 CREATE TABLE IF NOT EXISTS + INSERT OR IGNORE
 *   · 不修改任何既有列的数据，故无需回填
 */

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  SQL_CREATE_BODY_PROFILE,
  SQL_INIT_BODY_PROFILE,
  SQL_ADD_FOOD_MACROS,
  SQL_ADD_SETTINGS_MACROS,
  SQL_INIT_SETTINGS_MACROS,
  SQL_DROP_FOOD_MACROS,
  SQL_DROP_SETTINGS_MACROS
} from './SchemaV3';

const DOMAIN = 0x0001;
const TAG = 'CalorieFitDB';

export async function migrateV2ToV3(store: relationalStore.RdbStore): Promise<void> {
  // 1. 体征档案表
  await store.executeSql(SQL_CREATE_BODY_PROFILE);
  await store.executeSql(SQL_INIT_BODY_PROFILE);
  hilog.info(DOMAIN, TAG, 'V3: body_profile ready');

  // 2. food_log 宏量三列
  await addColumnsIfMissing(store, 'food_log', SQL_ADD_FOOD_MACROS);
  hilog.info(DOMAIN, TAG, 'V3: food_log macro columns ready');

  // 3. app_settings 宏量目标
  await addColumnsIfMissing(store, 'app_settings', SQL_ADD_SETTINGS_MACROS);
  await store.executeSql(SQL_INIT_SETTINGS_MACROS);
  hilog.info(DOMAIN, TAG, 'V3: app_settings macro target ready');
}

/**
 * 逐条执行 ALTER，仅在该列确实缺失时才执行。
 * SQLite 的 ALTER TABLE ADD COLUMN 不支持 IF NOT EXISTS，
 * 重复执行会抛 duplicate column 错误，故必须先探测。
 */
async function addColumnsIfMissing(
  store: relationalStore.RdbStore,
  table: string,
  alters: string[]
): Promise<void> {
  const existing = await tableColumns(store, table);
  for (let i = 0; i < alters.length; i++) {
    const col = columnNameFromAlter(alters[i]);
    if (col.length === 0 || existing.includes(col)) {
      continue;
    }
    try {
      await store.executeSql(alters[i]);
      existing.push(col);
    } catch (e) {
      hilog.error(DOMAIN, TAG,
        'V3: ALTER failed on %{public}s.%{public}s', table, col);
      throw e;
    }
  }
}

/** 从 `ALTER TABLE t ADD COLUMN name TYPE` 中提取列名 */
function columnNameFromAlter(sql: string): string {
  const m = sql.match(/ADD\s+COLUMN\s+([A-Za-z_][A-Za-z0-9_]*)/i);
  return m ? m[1] : '';
}

async function tableColumns(
  store: relationalStore.RdbStore,
  table: string
): Promise<string[]> {
  const set = await store.querySql(`PRAGMA table_info(${table})`);
  const cols: string[] = [];
  try {
    while (set.goToNextRow()) {
      cols.push(set.getString(set.getColumnIndex('name')));
    }
  } finally {
    set.close();
  }
  return cols;
}

/**
 * 回滚 V3（仅供开发期调试使用）
 * DROP COLUMN 会丢失已录入的宏量数据，生产路径不应调用。
 */
export async function rollbackV3(store: relationalStore.RdbStore): Promise<void> {
  for (let i = 0; i < SQL_DROP_FOOD_MACROS.length; i++) {
    await store.executeSql(SQL_DROP_FOOD_MACROS[i]);
  }
  for (let i = 0; i < SQL_DROP_SETTINGS_MACROS.length; i++) {
    await store.executeSql(SQL_DROP_SETTINGS_MACROS[i]);
  }
  await store.executeSql('DROP TABLE IF EXISTS body_profile');
}
