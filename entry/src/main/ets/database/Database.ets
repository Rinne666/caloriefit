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
import { migrateV4ToV5 } from './MigrationV4ToV5';
import { migrateV5ToV6 } from './MigrationV5ToV6';
import { migrateV6ToV7 } from './MigrationV6ToV7';

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
      // 先扩展旧 body_profile 的 CHECK 约束，再执行含空档案初始化的 V2→V3。
      // 否则已删除档案的旧库会尝试把 unspecified 插入旧约束而启动失败。
      await migrateV4ToV5(store);
      // V2 → V3 对全量路径统一执行，内部逐列探测，重入安全
      await migrateV2ToV3(store);
    }
    // V3 → V4 也覆盖全新库，确保饮水/断食表与饮水目标列存在。
    // 这两张表的功能已下线，但结构保留（见 SchemaV4 头部说明）。
    await migrateV3ToV4(store);
    // V4 → V5 移除旧初始化写入的虚构体征，并允许未填写枚举值。
    await migrateV4ToV5(store);
    // V5 → V6 增加食物贴纸路径列（新增库与存量库走同一条路径）。
    await migrateV5ToV6(store);
    // V6 → V7 建黑板画布的节点表与设置表。
    await migrateV6ToV7(store);
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

  /** 清空饮食/运动/步数记录；保留身体档案、目标设置和 AI 配置 */
  static async clearAllRecords(): Promise<void> {
    const store = Database.getStore();
    store.beginTransaction();
    try {
      await store.executeSql('DELETE FROM food_log');
      await store.executeSql('DELETE FROM exercise_log');
      await store.executeSql('DELETE FROM daily_activity');
      // V4 新增的两张表也属于「业务记录」，清空时要一并处理，
      // 否则点完「清空全部记录」后已下线的饮水/断食表还留着旧数据，
      // 用户会以为没清成功。
      await store.executeSql('DELETE FROM water_log');
      await store.executeSql('DELETE FROM fasting_log');
      // 黑板节点是饮食记录的投影，记录清了节点也必须跟着清，
      // 否则黑板上会留下一堆指向已删记录的孤儿贴纸。
      await store.executeSql('DELETE FROM board_node');
      store.commit();
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'clearAllRecords failed: %{public}s', err.message);
      store.rollBack();
      throw new Error(`clearAllRecords failed: ${err.message}`);
    }
  }

  /** 删除全部健康记录、身体档案和目标设置，在同一数据库事务中完成。 */
  static async clearAllUserData(): Promise<void> {
    const store = Database.getStore();
    store.beginTransaction();
    try {
      await store.executeSql('DELETE FROM food_log');
      await store.executeSql('DELETE FROM exercise_log');
      await store.executeSql('DELETE FROM daily_activity');
      await store.executeSql('DELETE FROM water_log');
      await store.executeSql('DELETE FROM fasting_log');
      await store.executeSql('DELETE FROM body_profile');
      await store.executeSql('DELETE FROM app_settings');
      await store.executeSql('DELETE FROM board_node');
      await store.executeSql('DELETE FROM board_setting');
      store.commit();
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'clearAllUserData failed: %{public}s', err.message);
      store.rollBack();
      throw new Error(`clearAllUserData failed: ${err.message}`);
    }
  }
}
