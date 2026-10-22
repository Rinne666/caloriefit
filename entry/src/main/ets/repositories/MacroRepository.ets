/**
 * 宏量汇总与趋势查询
 *
 * V3 新增。存量记录的宏量列为 NULL，SUM 时按 0 处理，
 * 并用 SQL_HAS_MACRO_ON_DATE 区分"今天没吃"与"今天吃了但没记宏量"。
 */

import { Database } from '../database/Database';
import {
  SQL_SUM_MACROS_BY_DATE,
  SQL_KCAL_TREND,
  SQL_MACRO_TREND,
  SQL_HAS_MACRO_ON_DATE
} from '../database/SchemaV3';
import { MacroActual } from '../models/Calculation';

/** 单日宏量 + 是否真的录过宏量 */
export interface MacroDayTotal {
  actual: MacroActual;
  /** 该日是否存在 protein_g 非空的记录。false = 存量数据未记宏量 */
  hasMacroData: boolean;
}

/** 趋势序列中的一日 */
export interface DayPoint {
  date: string;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
}

export class MacroRepository {

  /** 某日宏量合计 */
  static async getDayTotal(date: string): Promise<MacroDayTotal> {
    const empty: MacroDayTotal = {
      actual: { proteinG: 0, carbsG: 0, fatG: 0 },
      hasMacroData: false
    };
    try {
      const store = Database.getStore();
      const rs = await store.querySql(SQL_SUM_MACROS_BY_DATE, [date]);
      let actual = empty.actual;
      try {
        if (rs.goToFirstRow()) {
          actual = {
            proteinG: rs.getDouble(rs.getColumnIndex('protein_g')),
            carbsG: rs.getDouble(rs.getColumnIndex('carbs_g')),
            fatG: rs.getDouble(rs.getColumnIndex('fat_g'))
          };
        }
      } finally {
        rs.close();
      }

      const hs = await store.querySql(SQL_HAS_MACRO_ON_DATE, [date]);
      let hasMacroData = false;
      try {
        if (hs.goToFirstRow()) {
          hasMacroData = hs.getDouble(hs.getColumnIndex('n')) > 0;
        }
      } finally {
        hs.close();
      }

      return { actual, hasMacroData };
    } catch (e) {
      return empty;
    }
  }

  /**
   * 指定区间的每日热量 + 宏量序列（升序）。
   * 不补零 —— 缺失日期不返回，由 UI 决定是否填充。
   */
  static async getTrend(from: string, to: string): Promise<DayPoint[]> {
    const out: DayPoint[] = [];
    try {
      const store = Database.getStore();

      const kr = await store.querySql(SQL_KCAL_TREND, [from, to]);
      const kcalByDate: Record<string, number> = {};
      try {
        while (kr.goToNextRow()) {
          kcalByDate[kr.getString(kr.getColumnIndex('date'))] =
            kr.getDouble(kr.getColumnIndex('total_kcal'));
        }
      } finally {
        kr.close();
      }

      const mr = await store.querySql(SQL_MACRO_TREND, [from, to]);
      try {
        while (mr.goToNextRow()) {
          const d = mr.getString(mr.getColumnIndex('date'));
          out.push({
            date: d,
            kcal: kcalByDate[d] ?? 0,
            proteinG: mr.getDouble(mr.getColumnIndex('protein_g')),
            carbsG: mr.getDouble(mr.getColumnIndex('carbs_g')),
            fatG: mr.getDouble(mr.getColumnIndex('fat_g'))
          });
        }
      } finally {
        mr.close();
      }
    } catch (e) {
      return out;
    }
    return out;
  }
}
