/**
 * 断食数据访问。
 *
 * 对应 NutriScan 首页子页 Fasting（实测：方案名 16:8 / 18:6 / 20:4 / 14:10 / 12:12
 * 及自定义窗口，日志有「16:8 fast complete」）。
 *
 * 模型：每天最多一条「进行中」的断食记录，开始时写入 start_at / end_at，
 * 到达或手动结束时标 completed=1。只有一条未完成记录，可随时放弃重来。
 */

import { relationalStore } from '@kit.ArkData';
import { Database } from '../database/Database';
import {
  SQL_INSERT_FASTING,
  SQL_SELECT_ACTIVE_FASTING,
  SQL_COMPLETE_FASTING,
  SQL_CLEAR_ACTIVE_FASTING,
  SQL_FASTING_HISTORY
} from '../database/SchemaV4';

/** 当日进行中的断食窗口 */
export interface ActiveFasting {
  id: number;
  planId: string;
  startAt: number;
  endAt: number;
}

export interface FastingHistoryPoint {
  date: string;
  planId: string;
  completed: boolean;
}

export class FastingRepository {
  /** 开始一次断食；已有未完成记录时先清掉，避免一天开两条 */
  static async start(date: string, planId: string, startAt: number, endAt: number): Promise<void> {
    const store = Database.getStore();
    await store.executeSql(SQL_CLEAR_ACTIVE_FASTING, [date]);
    await store.executeSql(SQL_INSERT_FASTING, [date, planId, startAt, endAt]);
  }

  static async active(date: string): Promise<ActiveFasting | null> {
    const store = Database.getStore();
    const set = await store.querySql(SQL_SELECT_ACTIVE_FASTING, [date]);
    try {
      if (!set.goToNextRow()) {
        return null;
      }
      return {
        id: set.getLong(set.getColumnIndex('id')),
        planId: set.getString(set.getColumnIndex('plan_id')),
        startAt: set.getLong(set.getColumnIndex('start_at')),
        endAt: set.getLong(set.getColumnIndex('end_at'))
      };
    } finally {
      set.close();
    }
  }

  static async complete(id: number, endAt: number): Promise<void> {
    const store = Database.getStore();
    await store.executeSql(SQL_COMPLETE_FASTING, [endAt, id]);
  }

  /** 放弃当前断食窗口 */
  static async abandon(date: string): Promise<void> {
    const store = Database.getStore();
    await store.executeSql(SQL_CLEAR_ACTIVE_FASTING, [date]);
  }

  static async history(from: string, to: string): Promise<FastingHistoryPoint[]> {
    const store = Database.getStore();
    const set = await store.querySql(SQL_FASTING_HISTORY, [from, to]);
    const rows: FastingHistoryPoint[] = [];
    try {
      while (set.goToNextRow()) {
        rows.push({
          date: set.getString(set.getColumnIndex('date')),
          planId: set.getString(set.getColumnIndex('plan_id')),
          completed: set.getLong(set.getColumnIndex('completed')) === 1
        });
      }
    } finally {
      set.close();
    }
    return rows;
  }
}
