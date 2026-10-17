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
      // 全新数据库：建 V2
      for (let i = 0; i < SQL_CREATE_ALL_V2.length; i++) {
        await store.executeSql(SQL_CREATE_ALL_V2[i]);
      }
      await store.executeSql(SQL_INIT_SETTINGS);
      hilog.info(DOMAIN, TAG, 'fresh V2 database created');
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
        hilog.info(DOMAIN, TAG, 'food_log already V2, skip migration');
      }
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
      store.commit();
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'clearAllRecords failed: %{public}s', err.message);
      store.rollBack();
      throw new Error(`clearAllRecords failed: ${err.message}`);
    }
  }
}