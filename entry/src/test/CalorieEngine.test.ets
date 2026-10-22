/**
 * CalorieEngine 单元测试
 *
 * 重点覆盖:
 *   1. Atwater 反推的自洽性 —— 这是对 NutriScan 逆向的核心验算
 *      原 App 实测：蛋白 150g / 碳水 144g / 脂肪 78g / 目标 1878 kcal
 *      150×4 + 144×4 + 78×9 = 600 + 576 + 702 = 1878
 *   2. 双公式 BMR 切换 —— 有体脂走 Katch-McArdle，无体脂回退 Mifflin
 *   3. 目标热量下限保护 —— 不得低于 BMR
 *   4. 边界：体重 0、目标 0、比例夹取
 */

import { describe, it, expect } from '@ohos/hypium';
import { CalorieEngine, ATWATER_PROTEIN, ATWATER_CARB, ATWATER_FAT }
  from '../main/ets/services/CalorieEngine';
import { Sex, ActivityLevel, GoalMode, MacroTarget, MacroActual }
  from '../main/ets/models/Calculation';

export default function calorieEngineTest() {
  describe('CalorieEngine', () => {

    /* ---------- Atwater 换算 ---------- */

    it('atwaterCoefficients', 0, () => {
      expect(ATWATER_PROTEIN).assertEqual(4);
      expect(ATWATER_CARB).assertEqual(4);
      expect(ATWATER_FAT).assertEqual(9);
    });

    it('nutriscanReverseDerivation1878', 0, () => {
      // 对 NutriScan 实测界面的复算，这是本引擎与原 App 同口径的证据
      const m: MacroTarget = { proteinG: 150, carbsG: 144, fatG: 78 };
      const total = CalorieEngine.caloriesFromMacros(m);
      expect(total).assertEqual(1878);
    });

    it('caloriesFromMacrosMatchesManualArithmetic', 0, () => {
      const manual = 150 * 4 + 144 * 4 + 78 * 9;
      const engine = CalorieEngine.caloriesFromMacros(
        { proteinG: 150, carbsG: 144, fatG: 78 });
      expect(engine).assertEqual(manual);
    });

    it('zeroMacrosGivesZeroCalories', 0, () => {
      expect(CalorieEngine.caloriesFromMacros(
        { proteinG: 0, carbsG: 0, fatG: 0 })).assertEqual(0);
    });

    /* ---------- BMI ---------- */

    it('bmiKnownValue', 0, () => {
      // 70kg / 1.75m → 22.857...
      const v = CalorieEngine.bmi(70, 175);
      expect(Math.abs(v - 22.857) < 0.01).assertTrue();
    });

    it('bmiZeroHeightReturnsZero', 0, () => {
      expect(CalorieEngine.bmi(70, 0)).assertEqual(0);
    });

    /* ---------- BMR 双公式 ---------- */

    it('bmrUsesKatchMcArdleWhenBodyFatKnown', 0, () => {
      // 体脂率 0.20 → LBM = 70×0.8 = 56 → 370 + 21.6×56 = 1579.6
      const r = CalorieEngine.bmr(70, 175, 30, Sex.MALE, 0.20);
      expect(r.formula).assertEqual('Katch-McArdle');
      expect(Math.abs(r.value - (370 + 21.6 * 56)) < 0.001).assertTrue();
    });

    it('bmrFallsBackToMifflinWhenBodyFatNull', 0, () => {
      // 男：10×70 + 6.25×175 − 5×30 + 5 = 700 + 1093.75 − 150 + 5 = 1648.75
      const r = CalorieEngine.bmr(70, 175, 30, Sex.MALE, null);
      expect(r.formula).assertEqual('Mifflin-St Jeor');
      expect(Math.abs(r.value - 1648.75) < 0.001).assertTrue();
    });

    it('bmrFallsBackToMifflinWhenBodyFatOutOfRange', 0, () => {
      // 体脂率 0 或 >=0.7 都视为无效，必须回退而不是算出荒谬值
      const r0 = CalorieEngine.bmr(70, 175, 30, Sex.MALE, 0);
      const r7 = CalorieEngine.bmr(70, 175, 30, Sex.MALE, 0.7);
      expect(r0.formula).assertEqual('Mifflin-St Jeor');
      expect(r7.formula).assertEqual('Mifflin-St Jeor');
    });

    it('bmrFemaleUsesMinus161Offset', 0, () => {
      // 女：10×60 + 6.25×165 − 5×28 − 161 = 600 + 1031.25 − 140 − 161 = 1330.25
      const r = CalorieEngine.bmr(60, 165, 28, Sex.FEMALE, null);
      expect(Math.abs(r.value - 1330.25) < 0.001).assertTrue();
    });

    /* ---------- TDEE ---------- */

    it('tdeeAppliesActivityMultiplier', 0, () => {
      const t = CalorieEngine.tdee(1600, ActivityLevel.MODERATE);
      expect(Math.abs(t - 1600 * 1.55) < 0.001).assertTrue();
    });

    it('tdeeUnknownActivityFallsBackToSedentary', 0, () => {
      const bogus = 'not_a_level' as ActivityLevel;
      const t = CalorieEngine.tdee(1600, bogus);
      expect(Math.abs(t - 1600 * 1.2) < 0.001).assertTrue();
    });

    /* ---------- 目标热量与下限保护 ---------- */

    it('targetNeverBelowBmr', 0, () => {
      // 高活动量 + 减脂：TDEE 很高，但减 500 后不应低于 BMR
      const bmr = 1500;
      const t = CalorieEngine.targetCalories(bmr, ActivityLevel.ATHLETE, GoalMode.WEIGHT_LOSS);
      expect(t >= bmr).assertTrue();
    });

    it('maintainModeEqualsTdee', 0, () => {
      const bmr = 1600;
      const t = CalorieEngine.targetCalories(bmr, ActivityLevel.MODERATE, GoalMode.MAINTAIN);
      expect(Math.abs(t - Math.round(1600 * 1.55)) < 1).assertTrue();
    });

    /* ---------- 宏量分配 ---------- */

    it('allocatedMacrosStayCloseToTargetCalories', 0, () => {
      // 分配后按 Atwater 回算，应与目标热量接近（取整误差在数 kcal 内）
      for (const mode of [GoalMode.WEIGHT_LOSS, GoalMode.MAINTAIN,
      GoalMode.SURPLUS, GoalMode.DEFICIT, GoalMode.RECOMP]) {
        const target = 2000;
        const m = CalorieEngine.allocateMacros(target, mode);
        const back = CalorieEngine.caloriesFromMacros(m);
        expect(Math.abs(back - target) <= 10).assertTrue();
      }
    });

    it('cutModeAllocatesHigherProteinRatio', 0, () => {
      const cut = CalorieEngine.allocateMacros(2000, GoalMode.WEIGHT_LOSS);
      const maintain = CalorieEngine.allocateMacros(2000, GoalMode.MAINTAIN);
      expect(cut.proteinG > maintain.proteinG).assertTrue();
    });

    it('macrosFromKcalIsInverseOfCaloriesFromMacros', 0, () => {
      const m = CalorieEngine.macrosFromKcal(2000);
      const back = CalorieEngine.caloriesFromMacros(m);
      expect(Math.abs(back - 2000) <= 12).assertTrue();
    });

    /* ---------- 达标判定 ---------- */

    it('macroRatioClampsTo01', 0, () => {
      expect(CalorieEngine.macroRatio(50, 100)).assertEqual(0.5);
      expect(CalorieEngine.macroRatio(150, 100)).assertEqual(1);
      expect(CalorieEngine.macroRatio(-5, 100)).assertEqual(0);
      expect(CalorieEngine.macroRatio(50, 0)).assertEqual(0);
    });

    it('isOverDetectsAnyMacroExceeding', 0, () => {
      const t: MacroTarget = { proteinG: 150, carbsG: 144, fatG: 78 };
      const ok: MacroActual = { proteinG: 36, carbsG: 100, fatG: 34 };
      const overCarbs: MacroActual = { proteinG: 36, carbsG: 155, fatG: 34 };
      expect(CalorieEngine.isOver(ok, t)).assertFalse();
      expect(CalorieEngine.isOver(overCarbs, t)).assertTrue();
    });

    /* ---------- 份量换算 ---------- */

    it('gramsFromKcalIsInverseOfFoodCalories', 0, () => {
      // 200 kcal，500 kcal/100g → 40g
      const g = CalorieEngine.gramsFromKcal(200, 500);
      expect(g).assertEqual(40);
      expect(Math.round(g / 100 * 500)).assertEqual(200);
    });

    it('gramsFromKcalZeroDensityReturnsZero', 0, () => {
      expect(CalorieEngine.gramsFromKcal(200, 0)).assertEqual(0);
    });

    /* ---------- 一站式 ---------- */

    it('planIsInternallyConsistent', 0, () => {
      const p = CalorieEngine.plan({
        weightKg: 75, heightCm: 178, ageYears: 32,
        sex: Sex.MALE, bodyFatRatio: 0.22,
        activity: ActivityLevel.MODERATE, mode: GoalMode.WEIGHT_LOSS
      });
      expect(p.bmr > 0).assertTrue();
      expect(p.tdee > p.bmr).assertTrue();
      expect(p.targetCalories >= p.bmr).assertTrue();
      expect(Math.abs(p.caloriesFromMacros - p.targetCalories) <= 10).assertTrue();
    });
  });
}
