/**
 * 体征档案与宏量目标 —— Repository
 *
 * UI 层不直接碰 SQL。与既有 Repository 保持同样的约定：
 *   · 失败返回默认值而非抛异常，保证界面不会因数据库异常白屏
 *   · 写操作后由调用方负责 refreshTick 广播
 */

import { relationalStore } from '@kit.ArkData';
import { Database } from '../database/Database';
import {
  SQL_SELECT_BODY_PROFILE,
  SQL_UPSERT_BODY_PROFILE,
  SQL_SELECT_MACRO_TARGET,
  SQL_UPDATE_MACRO_TARGET
} from '../database/SchemaV3';
import {
  BodyProfile, Sex, ActivityLevel, GoalMode, MacroTarget
} from '../models/Calculation';
import { CalorieEngine } from '../services/CalorieEngine';

export class ProfileRepository {

  /* ---------- 体征档案 ---------- */

  static async getBodyProfile(): Promise<BodyProfile> {
    const dflt = BodyProfile.defaults();
    try {
      const store = Database.getStore();
      const rs = await store.querySql(SQL_SELECT_BODY_PROFILE);
      try {
        if (!rs.goToFirstRow()) {
          return dflt;
        }
        return new BodyProfile(
          rs.getDouble(rs.getColumnIndex('weight_kg')),
          rs.getDouble(rs.getColumnIndex('height_cm')),
          rs.getDouble(rs.getColumnIndex('age_years')),
          rs.getString(rs.getColumnIndex('sex')) as Sex,
          rs.isColumnNull(rs.getColumnIndex('body_fat_ratio'))
            ? null
            : rs.getDouble(rs.getColumnIndex('body_fat_ratio')),
          rs.getString(rs.getColumnIndex('activity')) as ActivityLevel,
          rs.getString(rs.getColumnIndex('goal_mode')) as GoalMode,
          rs.getDouble(rs.getColumnIndex('updated_at'))
        );
      } finally {
        rs.close();
      }
    } catch (e) {
      return dflt;
    }
  }

  static async saveBodyProfile(p: BodyProfile): Promise<boolean> {
    try {
      const store = Database.getStore();
      await store.executeSql(SQL_UPSERT_BODY_PROFILE,
        [p.weightKg, p.heightCm, p.ageYears, p.sex,
         p.bodyFatRatio, p.activity, p.mode, Date.now()]);
      return true;
    } catch (e) {
      return false;
    }
  }

  /* ---------- 宏量目标 ---------- */

  /**
   * 读取宏量目标。
   * target_auto = true 时按体征现算，不信任库里的旧值 —— 体征变了目标就该变。
   * 若已手动覆盖（target_auto = false），返回库中存量。
   */
  static async getMacroTarget(): Promise<MacroTarget | null> {
    try {
      const profile = await ProfileRepository.getBodyProfile();
      const store = Database.getStore();
      const rs = await store.querySql(SQL_SELECT_MACRO_TARGET);
      try {
        const auto = !rs.goToFirstRow()
          ? true
          : rs.getDouble(rs.getColumnIndex('target_auto')) === 1;

        if (auto) {
          if (!profile.isComplete()) {
            return null;
          }
          const plan = CalorieEngine.plan({
            weightKg: profile.weightKg,
            heightCm: profile.heightCm,
            ageYears: profile.ageYears,
            sex: profile.sex,
            bodyFatRatio: profile.bodyFatRatio,
            activity: profile.activity,
            mode: profile.mode
          });
          return plan.macros;
        }
        if (!rs.goToFirstRow()) {
          return null;
        }
        return {
          proteinG: rs.getDouble(rs.getColumnIndex('target_protein_g')),
          carbsG: rs.getDouble(rs.getColumnIndex('target_carbs_g')),
          fatG: rs.getDouble(rs.getColumnIndex('target_fat_g'))
        };
      } finally {
        rs.close();
      }
    } catch (e) {
      return null;
    }
  }

  /** 手动覆盖宏量目标（自动模式关闭） */
  static async saveMacroTarget(m: MacroTarget): Promise<boolean> {
    try {
      const store = Database.getStore();
      await store.executeSql(SQL_UPDATE_MACRO_TARGET,
        [m.proteinG, m.carbsG, m.fatG, 0, Date.now()]);
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 交回自动模式：清空手动值，目标由体征推导 */
  static async useAutoMacroTarget(): Promise<boolean> {
    try {
      const store = Database.getStore();
      await store.executeSql(SQL_UPDATE_MACRO_TARGET,
        [null, null, null, 1, Date.now()]);
      return true;
    } catch (e) {
      return false;
    }
  }
}
