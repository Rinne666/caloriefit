/**
 * 饮水数据访问。
 *
 * 对应 NutriScan 首页子页 Water（实测：goal 可手改、快加 250/500 ml、
 * 周条 Day Streak + Avg/Day）。
 *
 * 目标值的优先级：手动覆盖 > 按体重自动推导。
 * 自动公式（体重 × 35 ml）是推断值，见 MockContent.WATER_ML_PER_KG 注释。
 */

import { relationalStore } from '@kit.ArkData';
import { Database } from '../database/Database';
import {
  SQL_INSERT_WATER,
  SQL_DELETE_LAST_WATER,
  SQL_SUM_WATER_BY_DATE,
  SQL_WATER_TREND,
  SQL_SELECT_WATER_TARGET,
  SQL_UPDATE_WATER_TARGET
} from '../database/SchemaV4';
import { waterTargetMl } from '../services/MockContent';

/** 近 N 日每日饮水，date 升序 */
export interface WaterDayPoint {
  date: string;
  totalMl: number;
}

export class WaterRepository {
  /** 写入一笔 */
  static async add(date: string, ml: number, nowMs: number): Promise<void> {
    const store = Database.getStore();
    await store.executeSql(SQL_INSERT_WATER, [date, Math.round(ml), nowMs]);
  }

  /** 撤销当日最后一笔（对应 UI 上的撤回） */
  static async undoLast(date: string): Promise<void> {
    const store = Database.getStore();
    await store.executeSql(SQL_DELETE_LAST_WATER, [date]);
  }

  static async totalByDate(date: string): Promise<number> {
    const store = Database.getStore();
    const set = await store.querySql(SQL_SUM_WATER_BY_DATE, [date]);
    try {
      if (!set.goToNextRow()) {
        return 0;
      }
      return set.getDouble(set.getColumnIndex('total_ml'));
    } finally {
      set.close();
    }
  }

  static async trend(from: string, to: string): Promise<WaterDayPoint[]> {
    const store = Database.getStore();
    const set = await store.querySql(SQL_WATER_TREND, [from, to]);
    const rows: WaterDayPoint[] = [];
    try {
      while (set.goToNextRow()) {
        rows.push({
          date: set.getString(set.getColumnIndex('date')),
          totalMl: set.getDouble(set.getColumnIndex('total_ml'))
        });
      }
    } finally {
      set.close();
    }
    return rows;
  }

  /** 手动设置每日目标；传 null 表示恢复自动推导 */
  static async setTarget(ml: number | null, nowMs: number): Promise<void> {
    const store = Database.getStore();
    await store.executeSql(SQL_UPDATE_WATER_TARGET, [ml, nowMs]);
  }

  /** 读手动目标；null = 未手动设置 */
  static async getManualTarget(): Promise<number | null> {
    const store = Database.getStore();
    const set = await store.querySql(SQL_SELECT_WATER_TARGET, []);
    try {
      if (!set.goToNextRow()) {
        return null;
      }
      if (set.isColumnNull(0)) {
        return null;
      }
      return set.getDouble(0);
    } finally {
      set.close();
    }
  }

  /** 最终生效目标：手动优先，其次按体重推导，都没有则 0 */
  static async effectiveTarget(weightKg: number): Promise<number> {
    const manual = await WaterRepository.getManualTarget();
    if (manual !== null && manual > 0) {
      return manual;
    }
    return waterTargetMl(weightKg);
  }
}
