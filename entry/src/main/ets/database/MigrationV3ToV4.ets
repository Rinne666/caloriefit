/**
 * V3 → V4 迁移：饮水 + 断食
 *
 * 沿用 V2→V3 的防御式做法：
 *   · 建表一律 CREATE TABLE IF NOT EXISTS
 *   · 加列前用 PRAGMA table_info 探测，不假设迁移只跑一次
 *   · 中途失败可安全重入
 *
 * 本次只有一张既有表需要加列（app_settings），
 * 两张新表都是 CREATE IF NOT EXISTS，不需要存在性探测。
 */

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  SQL_CREATE_WATER_LOG,
  SQL_CREATE_FASTING_LOG,
  SQL_ADD_SETTINGS_WATER
} from './SchemaV4';

const DOMAIN = 0x0001;
const TAG = 'CalorieFitDB';

export async function migrateV3ToV4(store: relationalStore.RdbStore): Promise<void> {
  await store.executeSql(SQL_CREATE_WATER_LOG);
  hilog.info(DOMAIN, TAG, 'V4: water_log ready');

  await store.executeSql(SQL_CREATE_FASTING_LOG);
  hilog.info(DOMAIN, TAG, 'V4: fasting_log ready');

  const existing = await tableColumns(store, 'app_settings');
  for (let i = 0; i < SQL_ADD_SETTINGS_WATER.length; i++) {
    const col = columnNameFromAlter(SQL_ADD_SETTINGS_WATER[i]);
    if (col.length === 0 || existing.includes(col)) {
      continue;
    }
    await store.executeSql(SQL_ADD_SETTINGS_WATER[i]);
  }
  hilog.info(DOMAIN, TAG, 'V4: app_settings water target ready');
}

async function tableColumns(store: relationalStore.RdbStore, table: string): Promise<string[]> {
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

/** 从 "ALTER TABLE t ADD COLUMN c ..." 里取出列名 c */
function columnNameFromAlter(sql: string): string {
  const parts = sql.trim().split(/\s+/);
  for (let i = 0; i < parts.length; i++) {
    if (parts[i].toUpperCase() === 'COLUMN' && i + 1 < parts.length) {
      return parts[i + 1];
    }
  }
  return '';
}
