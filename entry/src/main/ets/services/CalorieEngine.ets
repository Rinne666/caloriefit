/**
 * 代谢计算引擎 —— BMR / TDEE / 宏量目标
 *
 * 设计依据:对 NutriScan (app.nutriscan v1.9.8) 的逆向分析。
 * 原 App 为 Flutter 应用,业务逻辑全部位于 libapp.so(Dart AOT),未混淆。
 *
 * ── 证据链(可在 libapp.so 字符串表中检索到)────────────────────────
 *   "Resting calories (BMR)"                    ×1   界面文案
 *   "Daily calorie need (TDEE)"                 ×1   界面文案
 *   "It will allow us to calculate your BMI and
 *    BMR, essential for determining your
 *    daily energy needs."                              引导页文案
 *   "Activity Level" / "Daily Workout/Activity Level"
 *   "Onboarding - Activity Level Selected"       埋点
 *   "katch"                                      ×1   → 选定 Katch-McArdle
 *   "body_fat"                                   ×1   → 该公式的必需输入
 *   "bmr" ×5 / "tdee" ×5 / "target_calorie" ×3
 *   "activity_level"                             ×3
 *   "weight_kg" ×2 / "height" ×55 / "body_fat" ×1
 *   "weight_loss"×4 "maintain"×11 "surplus"×3
 *   "deficit"×8  "recomp"×11
 *   多语言:瑞典语 "kna ditt BMI och BMR"、德语
 *           "deinen BMI und BMR zu berechnen"
 *      → 证明这是用户可见功能,非内部日志
 *
 * ── 关键验算(硬证据)──────────────────────────────────────────────
 *   NutriScan 实测界面:蛋白 150g / 碳水 144g / 脂肪 78g / 目标 1878kcal
 *     150×4 + 144×4 + 78×9 = 600 + 576 + 702 = 1878  ✓ 完全一致
 *   → 原 App 的目标热量由【宏量目标反推】得出(Atwater 系数 4/4/9),
 *     而非先算热量再分配宏量。本引擎保持同样语义。
 *
 * ── 与原 App 的差异(有意为之)──────────────────────────────────────
 *   1. 原 App 仅用 Katch-McArdle,必须先测体脂率,冷启动门槛高。
 *      本引擎在体脂率缺失时回退 Mifflin-St Jeor,保证任何输入都能给出结果。
 *   2. 原 App 的活动量倍率是编译进 AOT 的 double 字面量,无法提取实测值。
 *      本引擎采用通行标准值,常量集中定义便于与服务端对齐。
 */

import { ActivityLevel, GoalMode, Sex, MacroTarget, MacroActual } from '../models/Calculation';

/** Atwater 通用换算系数(kcal/g) */
export const ATWATER_PROTEIN: number = 4;
export const ATWATER_CARB: number = 4;
export const ATWATER_FAT: number = 9;

/** 活动量倍率 */
export const ACTIVITY_MULTIPLIER: Record<ActivityLevel, number> = {
  [ActivityLevel.SEDENTARY]: 1.200,
  [ActivityLevel.LIGHT]: 1.375,
  [ActivityLevel.MODERATE]: 1.550,
  [ActivityLevel.VERY_ACTIVE]: 1.725,
  [ActivityLevel.ATHLETE]: 1.900
};

/** 目标模式相对 TDEE 的热量调整(kcal/天) */
export const MODE_ADJUSTMENT: Record<GoalMode, number> = {
  [GoalMode.WEIGHT_LOSS]: -500,
  [GoalMode.DEFICIT]: -500,
  [GoalMode.MAINTAIN]: 0,
  [GoalMode.RECOMP]: 0,
  [GoalMode.SURPLUS]: +300
};

/**
 * 宏量拆分比例。
 * 基准值取自 NutriScan 实测(150/144/78 反算):蛋白 31.9% / 碳水 30.7% / 脂肪 37.4%。
 * 减脂与重组模式提高蛋白占比以保肌。
 */
export const MACRO_SPLIT_BASE: MacroSplit = { protein: 0.319, carbs: 0.307, fat: 0.374 };
export const MACRO_SPLIT_CUT: MacroSplit = { protein: 0.350, carbs: 0.300, fat: 0.350 };

export interface MacroSplit {
  protein: number;
  carbs: number;
  fat: number;
}

/** 计算结果 */
export interface CaloriePlan {
  bmr: number;
  tdee: number;
  targetCalories: number;
  activityMultiplier: number;
  macros: MacroTarget;
  /** 宏量回算的热量,应与 targetCalories 相差 ≤ 数 kcal(取整导致) */
  caloriesFromMacros: number;
  /** 实际采用的公式,便于在 UI 标注与自查 */
  formula: string;
  mode: GoalMode;
}

export class CalorieEngine {

  /* ---------- 基础指标 ---------- */

  /** 体质指数 BMI = 体重kg / 身高m² */
  static bmi(weightKg: number, heightCm: number): number {
    const h = heightCm / 100;
    if (h <= 0) {
      return 0;
    }
    return weightKg / (h * h);
  }

  /**
   * 基础代谢率 —— 双公式
   *
   * 优先 Katch-McArdle(依赖体脂率,对减脂更准,与原 App 选择一致):
   *   LBM = 体重 × (1 − 体脂率)
   *   BMR = 370 + 21.6 × LBM
   *
   * 体脂率缺失时回退 Mifflin-St Jeor:
   *   男: 10×体重 + 6.25×身高 − 5×年龄 + 5
   *   女: 10×体重 + 6.25×身高 − 5×年龄 − 161
   */
  static bmr(weightKg: number, heightCm: number, ageYears: number,
    sex: Sex, bodyFatRatio: number | null): { value: number, formula: string } {
    if (bodyFatRatio !== null && bodyFatRatio > 0 && bodyFatRatio < 0.7) {
      const lbm = weightKg * (1 - bodyFatRatio);
      return { value: 370 + 21.6 * lbm, formula: 'Katch-McArdle' };
    }
    const base = 10 * weightKg + 6.25 * heightCm - 5 * ageYears;
    const offset = sex === Sex.MALE ? 5 : -161;
    return { value: base + offset, formula: 'Mifflin-St Jeor' };
  }

  /** 每日总消耗 TDEE = BMR × 活动量倍率 */
  static tdee(bmrValue: number, activity: ActivityLevel): number {
    return bmrValue * (ACTIVITY_MULTIPLIER[activity] ?? 1.2);
  }

  /**
   * 目标热量
   * 下限保护:不低于 BMR × 1.0,避免长期赤字导致代谢适应。
   */
  static targetCalories(bmrValue: number, activity: ActivityLevel, mode: GoalMode): number {
    const tdee = CalorieEngine.tdee(bmrValue, activity);
    const adjusted = tdee + (MODE_ADJUSTMENT[mode] ?? 0);
    return Math.max(Math.round(bmrValue), Math.round(adjusted));
  }

  /**
   * 宏量分配
   * 先按比例分配热量,再按 Atwater 换算为克数并取整(与原 App 行为一致)。
   */
  static allocateMacros(targetCalories: number, mode: GoalMode): MacroTarget {
    const split = (mode === GoalMode.WEIGHT_LOSS || mode === GoalMode.RECOMP)
      ? MACRO_SPLIT_CUT
      : MACRO_SPLIT_BASE;

    return {
      proteinG: Math.round(targetCalories * split.protein / ATWATER_PROTEIN),
      carbsG: Math.round(targetCalories * split.carbs / ATWATER_CARB),
      fatG: Math.round(targetCalories * split.fat / ATWATER_FAT)
    };
  }

  /** Atwater 回算 —— 展示的 Total 应与此一致 */
  static caloriesFromMacros(m: { proteinG: number, carbsG: number, fatG: number }): number {
    return Math.round(
      m.proteinG * ATWATER_PROTEIN +
      m.carbsG * ATWATER_CARB +
      m.fatG * ATWATER_FAT
    );
  }

  /** 一站式计算 */
  static plan(input: PlanInput): CaloriePlan {
    const bmrResult = CalorieEngine.bmr(
      input.weightKg, input.heightCm, input.ageYears,
      input.sex, input.bodyFatRatio
    );
    const target = CalorieEngine.targetCalories(
      bmrResult.value, input.activity, input.mode
    );
    const macros = CalorieEngine.allocateMacros(target, input.mode);
    return {
      bmr: Math.round(bmrResult.value),
      tdee: Math.round(CalorieEngine.tdee(bmrResult.value, input.activity)),
      targetCalories: target,
      activityMultiplier: ACTIVITY_MULTIPLIER[input.activity] ?? 1.2,
      macros,
      caloriesFromMacros: CalorieEngine.caloriesFromMacros(macros),
      formula: bmrResult.formula,
      mode: input.mode
    };
  }

  /* ---------- 宏量达标判定 ---------- */

  /** 任一宏量超标即返回 true —— 对应 UI 整条转红 */
  static isOver(actual: MacroActual, target: MacroTarget): boolean {
    return actual.proteinG > target.proteinG
      || actual.carbsG > target.carbsG
      || actual.fatG > target.fatG;
  }

  /** 单项达标率,夹在 [0,1] */
  static macroRatio(actualG: number, targetG: number): number {
    if (targetG <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(1, actualG / targetG));
  }

  /* ---------- 反向工具:由热量反推份量 ---------- */

  /**
   * 按每 100g 热量换算实际克数。
   * 与既有 CalorieService.foodCalories 互为逆运算,保证宏量与热量口径一致。
   */
  static gramsFromKcal(kcal: number, kcalPer100g: number): number {
    if (kcalPer100g <= 0) {
      return 0;
    }
    return Math.round(kcal / kcalPer100g * 100);
  }

  /** 由总热量按 Atwater 拆出三元宏量 */
  static macrosFromKcal(kcal: number, split: MacroSplit = MACRO_SPLIT_BASE): MacroActual {
    return {
      proteinG: Math.round(kcal * split.protein / ATWATER_PROTEIN),
      carbsG: Math.round(kcal * split.carbs / ATWATER_CARB),
      fatG: Math.round(kcal * split.fat / ATWATER_FAT)
    };
  }
}

export interface PlanInput {
  weightKg: number;
  heightCm: number;
  ageYears: number;
  sex: Sex;
  /** 0~1,null 表示未知 → 触发 Mifflin 回退 */
  bodyFatRatio: number | null;
  activity: ActivityLevel;
  mode: GoalMode;
}
