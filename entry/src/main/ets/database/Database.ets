/**
 * RDB 单例。只初始化一次，所有 Repository 使用同一实例。
 */

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DATABASE_NAME, DATABASE_VERSION } from '../common/Constants';
import { SQL_CREATE_ALL, SQL_INIT_SETTINGS } from './Schema';

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

  private static async doInit(context: Context): Promise<relationalStore.RdbStore> {
    const config: relationalStore.StoreConfig = {
      name: DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store = await relationalStore.getRdbStore(context, config);
    store.version = DATABASE_VERSION;
    for (let i = 0; i < SQL_CREATE_ALL.length; i++) {
      await store.executeSql(SQL_CREATE_ALL[i]);
    }
    await store.executeSql(SQL_INIT_SETTINGS);
    Database.store = store;
    hilog.info(DOMAIN, TAG, 'database initialized');
    return store;
  }

  static getStore(): relationalStore.RdbStore {
    if (Database.store === null) {
      throw new Error('Database not initialized yet');
    }
    return Database.store;
  }

  /** 清空全部业务记录（三张表，同一事务），app_settings 不删除 */
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
