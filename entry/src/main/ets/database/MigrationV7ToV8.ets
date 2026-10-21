/**
 * V7 → V8：重建 board_node，放开 node_type 的取值范围。
 *
 * 目的：允许 node_type = 3（DEMO_NOTE，内置示例便签）。
 * SQLite 的 CHECK 约束不能 ALTER，只能重建表
 * （做法与 V4→V5 放宽 body_profile 的枚举约束同源）。
 *
 * 重入安全：已经是非旧约束的库直接跳过。
 */

import { relationalStore } from '@kit.ArkData';
import { SQL_CREATE_BOARD_NODE_V8, SQL_COPY_BOARD_NODE_V8 } from './SchemaV8';

/** 旧版示例便签的标题（用来识别它）。标题唯一且只有内置示例会用它。 */
const DEMO_NOTE_TITLE: string = '今天的小确幸';
/** 新的示例点评文案：描述功能，而不是替用户总结摄入 */
const DEMO_NOTE_ADVICE: string = '示例内容：记录三餐后，这里会显示属于你的建议';

export async function migrateV7ToV8(store: relationalStore.RdbStore): Promise<void> {
  const existingSql = await boardNodeTableSql(store);
  if (existingSql.length === 0) {
    // V6 及更早的库还没有 board_node —— V6→V7 会随后建出来（用的是新约束）。
    return;
  }
  const normalized = existingSql.toLowerCase();
  const alreadyNew = normalized.includes('node_type in (0, 1, 2, 3)');

  if (!alreadyNew) {
    store.beginTransaction();
    try {
      await store.executeSql('DROP TABLE IF EXISTS board_node_v8');
      await store.executeSql(SQL_CREATE_BOARD_NODE_V8);
      await store.executeSql(SQL_COPY_BOARD_NODE_V8);
      await store.executeSql('DROP TABLE board_node');
      await store.executeSql('ALTER TABLE board_node_v8 RENAME TO board_node');
      // 索引随旧表一起被删掉了，重建一次（名字相同，IF NOT EXISTS 兜底）
      await store.executeSql(
        'CREATE INDEX IF NOT EXISTS idx_board_node_date ON board_node(date)');
      store.commit();
    } catch (_e) {
      store.rollBack();
      throw new Error('V7 to V8 board-node migration failed');
    }
  }

  /**
   * 把旧的示例便签（存成普通 STICKY_NOTE）转成 DEMO_NOTE。
   *
   * 存量库里那条便签是 V7 时代的写法（node_type = 1），
   * 不转的话，老用户看到的还是「没有示例标记的普通便签」。
   * 识别靠标题 —— 目前还没有「新建便签」功能，
   * 库里所有 STICKY_NOTE 都是这条示例（或它的复制）。
   */
  try {
    await store.executeSql(
      `UPDATE board_node SET node_type = 3, ai_advice = ?
       WHERE node_type = 1 AND title = ?`,
      [DEMO_NOTE_ADVICE, DEMO_NOTE_TITLE]);
  } catch (_e) {
    // 转不动也不影响功能，只是老用户看不到示例标记
  }
}

async function boardNodeTableSql(store: relationalStore.RdbStore): Promise<string> {
  const result = await store.querySql(
    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'board_node'");
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
