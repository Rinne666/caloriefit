/**
 * 热量计算、剩余预算、进度比例
 */

export class CalorieService {
  /** 食物总热量 = 重量g / 100 * 每100g热量，四舍五入为整数 */
  static foodCalories(weightG: number, kcalPer100g: number): number {
    return Math.round(weightG / 100 * kcalPer100g);
  }

  /** 剩余饮食预算，允许为负（超标） */
  static remainingBudget(budget: number, consumed: number): number {
    return budget - consumed;
  }

  /** 进度比例，上限 1。目标已由输入校验保证 > 0 */
  static progress(current: number, goal: number): number {
    if (goal <= 0) {
      return 0;
    }
    return Math.min(1, current / goal);
  }
}
