/**
 * V1 → V2 food_log 迁移。单事务：建临时表 → 复制 → 核验 → 替换 → 重建索引 → 恢复自增序列。
 * 迁移失败回滚，旧数据完整保留。
 */

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  SQL_MIGRATE_CREATE_V2_TEMP,
  SQL_MIGRATE_COPY,
  SQL_MIGRATE_STATS,
  SQL_MIGRATE_STATS_V2,
  SQL_MIGRATE_DROP_OLD,
  SQL_MIGRATE_RENAME,
  SQL_MIGRATE_RECREATE_INDEX,
  SQL_READ_OLD_SEQUENCE,
  SQL_INSERT_SEQUENCE,
  SQL_FIX_SEQUENCE
} from './Schema';

const DOMAIN = 0x0001;
const TAG = 'CalorieFitMigration';

interface MigrateStats {
  recordCount: number;
  totalKcal: number;
  maxId: number;
}

function readStats(rs: relationalStore.ResultSet): MigrateStats {
  const s: MigrateStats = {
    recordCount: rs.getLong(rs.getColumnIndex('record_count')),
    totalKcal: rs.getLong(rs.getColumnIndex('total_kcal')),
    maxId: rs.getLong(rs.getColumnIndex('max_id'))
  };
  return s;
}

export async function migrateFoodV1ToV2(store: relationalStore.RdbStore): Promise<void> {
  hilog.info(DOMAIN, TAG, 'start V1 to V2 migration');
  store.beginTransaction();
  try {
    // 读取旧自增序列（sqlite_sequence 可能不存在）
    let oldSequence = 0;
    try {
      const seqSet = await store.querySql(SQL_READ_OLD_SEQUENCE);
      try {
        if (seqSet.goToNextRow()) {
          oldSequence = seqSet.getLong(seqSet.getColumnIndex('last_sequence'));
        }
      } finally {
        seqSet.close();
      }
    } catch (e) {
      oldSequence = 0;
    }

    // 旧表统计
    const oldSet = await store.querySql(SQL_MIGRATE_STATS);
    let oldStats: MigrateStats;
    try {
      if (!oldSet.goToNextRow()) {
        throw new Error('failed to read old food_log stats');
      }
      oldStats = readStats(oldSet);
    } finally {
      oldSet.close();
    }

    // 建 V2 临时表并复制
    await store.executeSql(SQL_MIGRATE_CREATE_V2_TEMP);
    await store.executeSql(SQL_MIGRATE_COPY);

    // 新表统计与核验
    const newSet = await store.querySql(SQL_MIGRATE_STATS_V2);
    let newStats: MigrateStats;
    try {
      if (!newSet.goToNextRow()) {
        throw new Error('failed to read food_log_v2 stats');
      }
      newStats = readStats(newSet);
    } finally {
      newSet.close();
    }
    if (newStats.recordCount !== oldStats.recordCount ||
      newStats.totalKcal !== oldStats.totalKcal ||
      newStats.maxId !== oldStats.maxId) {
      throw new Error(`migration verify failed: old(${oldStats.recordCount},${oldStats.totalKcal},${oldStats.maxId}) new(${newStats.recordCount},${newStats.totalKcal},${newStats.maxId})`);
    }

    // 替换旧表并重建索引
    await store.executeSql(SQL_MIGRATE_DROP_OLD);
    await store.executeSql(SQL_MIGRATE_RENAME);
    await store.executeSql(SQL_MIGRATE_RECREATE_INDEX);

    // 恢复自增序列历史
    await store.executeSql(SQL_INSERT_SEQUENCE, [oldSequence]);
    await store.executeSql(SQL_FIX_SEQUENCE, [oldSequence, oldSequence]);

    store.commit();
    hilog.info(DOMAIN, TAG, 'migration committed: %{public}d records', oldStats.recordCount);
  } catch (e) {
    const err = e as BusinessError;
    hilog.error(DOMAIN, TAG, 'migration failed: %{public}s', err.message);
    store.rollBack();
    throw new Error(`V1 to V2 migration failed: ${err.message}`);
  }
}