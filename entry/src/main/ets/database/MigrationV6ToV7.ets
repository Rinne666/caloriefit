/**
 * V6 → V7：建黑板节点表与黑板设置表。
 *
 * 用 `CREATE TABLE IF NOT EXISTS` 而不是 ALTER —— 这次是**新增表**，
 * 不是给既有表加列，V6 的任何表都不受影响。
 * 新建库与存量库走同一条路径，不存在「两套结构」的问题。
 *
 * 迁移放在一个事务里：两张表要么都建成功，要么都不建，
 * 不会出现「有 board_node 没有 board_setting」的半截状态。
 */

import { relationalStore } from '@kit.ArkData';
import { SQL_CREATE_ALL_V7, SQL_INIT_BOARD_SETTING } from './SchemaV7';

export async function migrateV6ToV7(store: relationalStore.RdbStore): Promise<void> {
  store.beginTransaction();
  try {
    for (let i = 0; i < SQL_CREATE_ALL_V7.length; i++) {
      await store.executeSql(SQL_CREATE_ALL_V7[i]);
    }
    // 单行设置表：首次插入默认主题与视图模式
    await store.executeSql(SQL_INIT_BOARD_SETTING);
    store.commit();
  } catch (_e) {
    store.rollBack();
    throw new Error('V6 to V7 board migration failed');
  }
}
