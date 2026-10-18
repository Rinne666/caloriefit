/**
 * RDB 单例。首次初始化时按真实表结构检测版本：
 * 无 food_log → 建 V2；有 V1 表（无 entry_mode）→ 迁移；已是 V2 → 跳过。
 */

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DATABASE_NAME, DATABASE_VERSION } from '../common/Constants';
import {
  SQL_CREATE_ALL_V2,
  SQL_INIT_SETTINGS,
  SQL_TABLE_EXISTS,
  SQL_TABLE_INFO
} from './Schema';
import { migrateFoodV1ToV2 } from './MigrationV1ToV2';
import { migrateV2ToV3 } from './MigrationV2ToV3';
import { migrateV3ToV4 } from './MigrationV3ToV4';

const DOMAIN = 0x0001;
const TAG = 'CalorieFitDB';

export class Database {
  private static store: relationalStore.RdbStore | null = null;
  private static appContext: Context | null = null;
  private static initPromise: Promise<relationalStore.RdbStore> | null = null;

  /** 首次调用需提供应用上下文，后续可无参调用 */
  static async ensure(context?: Context): Promise<relationalStore.RdbStore> {
    if (Database.store !== null) {
      return Database.store;
    }
    if (context !== undefined) {
      Database.appContext = context;
    }
    if (Database.appContext === null) {
      throw new Error('Database not initialized: context required on first call');
    }
    if (Database.initPromise === null) {
      Database.initPromise = Database.doInit(Database.appContext);
    }
    return Database.initPromise;
  }

  private static async tableExists(store: relationalStore.RdbStore, name: string): Promise<boolean> {
    const set = await store.querySql(SQL_TABLE_EXISTS, [name]);
    let exists = false;
    try {
      exists = set.goToNextRow();
    } finally {
      set.close();
    }
    return exists;
  }

  private static async tableColumns(store: relationalStore.RdbStore, table: string): Promise<string[]> {
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

  private static async doInit(context: Context): Promise<relationalStore.RdbStore> {
    const config: relationalStore.StoreConfig = {
      name: DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store = await relationalStore.getRdbStore(context, config);

    const hasFood = await Database.tableExists(store, 'food_log');
    if (!hasFood) {
      // 全新数据库：建 V2 结构后直接升到 V3
      for (let i = 0; i < SQL_CREATE_ALL_V2.length; i++) {
        await store.executeSql(SQL_CREATE_ALL_V2[i]);
      }
      await store.executeSql(SQL_INIT_SETTINGS);
      await migrateV2ToV3(store);
      hilog.info(DOMAIN, TAG, 'fresh database created at V3');
    } else {
      const cols = await Database.tableColumns(store, 'food_log');
      if (!cols.includes('entry_mode')) {
        // V1 库：迁移
        await migrateFoodV1ToV2(store);
      } else if (!cols.includes('ai_notes') || !cols.includes('ai_confidence')) {
        // 结构不完整，拒绝初始化，保留原库
        throw new Error('food_log table has incomplete V2 structure');
      } else {
        // 已是 V2：补写版本号（处理迁移提交后、写版本前退出的情况）
        hilog.info(DOMAIN, TAG, 'food_log already V2, skip V1->V2 migration');
      }
      // V2 → V3 对全量路径统一执行，内部逐列探测，重入安全
      await migrateV2ToV3(store);
      // V3 → V4 同样全量执行：两张新表 CREATE IF NOT EXISTS，
      // app_settings 加列前逐列探测，重复跑不会炸
      await migrateV3ToV4(store);
    }
    store.version = DATABASE_VERSION;
    Database.store = store;
    return store;
  }

  static getStore(): relationalStore.RdbStore {
    if (Database.store === null) {
      throw new Error('Database not initialized yet');
    }
    return Database.store;
  }

  static getAppContext(): Context | null {
    return Database.appContext;
  }

  /** 清空全部业务记录（三张表，同一事务），app_settings 与 AI 配置不删除 */
  static async clearAllRecords(): Promise<void> {
    const store = Database.getStore();
    store.beginTransaction();
    try {
      await store.executeSql('DELETE FROM food_log');
      await store.executeSql('DELETE FROM exercise_log');
      await store.executeSql('DELETE FROM daily_activity');
      // V4 新增的两张表也属于「业务记录」，清空时要一并处理，
      // 否则点完「清空全部记录」后饮水/断食还留着旧数据，
      // 用户会以为没清成功。
      await store.executeSql('DELETE FROM water_log');
      await store.executeSql('DELETE FROM fasting_log');
      store.commit();
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'clearAllRecords failed: %{public}s', err.message);
      store.rollBack();
      throw new Error(`clearAllRecords failed: ${err.message}`);
    }
  }
}