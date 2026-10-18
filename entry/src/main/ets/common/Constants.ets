/**
 * CalorieFit 常量定义
 */

export interface Goals {
  dailyCalorieBudget: number;
  stepsGoal: number;
  exerciseMinutesGoal: number;
  activityKcalGoal: number;
}

export const DEFAULT_GOALS: Goals = {
  dailyCalorieBudget: 1800,
  stepsGoal: 8000,
  exerciseMinutesGoal: 30,
  activityKcalGoal: 300
};

export const DATABASE_NAME = 'caloriefit.db';
export const DATABASE_VERSION = 4;

/** Atwater 换算系数(kcal/g) —— 与 services/CalorieEngine.ets 保持一致 */
export const ATWATER_PROTEIN: number = 4;
export const ATWATER_CARB: number = 4;
export const ATWATER_FAT: number = 9;

/** 默认每日饮水目标(ml) */
export const DEFAULT_WATER_GOAL_ML: number = 2650;

export const MEAL_LABELS: string[] = [
  '早餐', '午餐', '晚餐', '加餐'
];

export const EXERCISE_LABELS: string[] = [
  '走路', '跑步', '骑行', '健身', '其他'
];

// 输入范围（与 Validators.ets 保持一致）
export interface Limits {
  foodNameMax: number;
  weightMax: number;
  kcalPer100gMax: number;
  durationMax: number;
  burnedMax: number;
  stepsMax: number;
  budgetMax: number;
  stepsGoalMax: number;
  minutesGoalMax: number;
  activityKcalGoalMax: number;
}

export const LIMITS: Limits = {
  foodNameMax: 40,
  weightMax: 10000,
  kcalPer100gMax: 2000,
  durationMax: 1440,
  burnedMax: 10000,
  stepsMax: 100000,
  budgetMax: 10000,
  stepsGoalMax: 100000,
  minutesGoalMax: 1440,
  activityKcalGoalMax: 10000
};

export const KIT_NAME = 'CalorieFit';
export const DATA_SOURCE_LABEL = '本地模拟数据';
