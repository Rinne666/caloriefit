/**
 * 代谢计算相关模型
 *
 * 对应 NutriScan 引导流程中的采集项(逆向证据见 services/CalorieEngine.ets 头注释):
 *   Daily Workout/Activity Level  → ActivityLevel
 *   weight / height / age / body_fat → BodyProfile
 *   weight_loss / maintain / surplus / deficit / recomp → GoalMode
 */

/** 性别 */
export enum Sex {
  MALE = 'male',
  FEMALE = 'female'
}

/**
 * 活动量等级
 * 原 App 引导页文案:"Activity Level" / "Daily Workout/Activity Level"
 */
export enum ActivityLevel {
  SEDENTARY = 'sedentary',
  LIGHT = 'light',
  MODERATE = 'moderate',
  VERY_ACTIVE = 'very_active',
  ATHLETE = 'athlete'
}

/**
 * 目标模式
 * 原 App 字符串命中:weight_loss / maintain / surplus / deficit / recomp
 */
export enum GoalMode {
  WEIGHT_LOSS = 'weight_loss',
  MAINTAIN = 'maintain',
  SURPLUS = 'surplus',
  DEFICIT = 'deficit',
  RECOMP = 'recomp'
}

/** 宏量目标(克) */
export interface MacroTarget {
  proteinG: number;
  carbsG: number;
  fatG: number;
}

/** 宏量实际摄入(克) */
export interface MacroActual {
  proteinG: number;
  carbsG: number;
  fatG: number;
}

/**
 * 体征档案
 *
 * bodyFatRatio 为 null 时,引擎自动回退 Mifflin-St Jeor 公式。
 * 这是与原 App 的有意差异:原 App 仅支持 Katch-McArdle,
 * 未测体脂的用户无法得到任何目标值。
 */
export class BodyProfile {
  weightKg: number;
  heightCm: number;
  ageYears: number;
  sex: Sex;
  bodyFatRatio: number | null;
  activity: ActivityLevel;
  mode: GoalMode;
  updatedAt: number;

  constructor(weightKg: number, heightCm: number, ageYears: number,
    sex: Sex, bodyFatRatio: number | null,
    activity: ActivityLevel, mode: GoalMode, updatedAt: number) {
    this.weightKg = weightKg;
    this.heightCm = heightCm;
    this.ageYears = ageYears;
    this.sex = sex;
    this.bodyFatRatio = bodyFatRatio;
    this.activity = activity;
    this.mode = mode;
    this.updatedAt = updatedAt;
  }

  /** 新用户默认值 */
  static defaults(): BodyProfile {
    return new BodyProfile(
      65, 170, 30, Sex.MALE, null,
      ActivityLevel.MODERATE, GoalMode.WEIGHT_LOSS, 0
    );
  }

  /** 是否已完成体征采集(至少可算出目标) */
  isComplete(): boolean {
    return this.weightKg > 0 && this.heightCm > 0 && this.ageYears > 0;
  }
}

/**
 * 中文标签 —— 用函数而非 Record<K,V> 查表。
 *
 * ArkTS 不允许对字段做索引访问（arkts-no-props-by-index），
 * THEME_LABELS[a] 这类写法会直接编译失败，必须走函数调用。
 */
export function activityLabel(a: ActivityLevel): string {
  if (a === ActivityLevel.SEDENTARY) { return '久坐'; }
  if (a === ActivityLevel.LIGHT) { return '轻度活动'; }
  if (a === ActivityLevel.VERY_ACTIVE) { return '高强度'; }
  if (a === ActivityLevel.ATHLETE) { return '运动员 / 重体力'; }
  return '中度活动';
}

export function modeLabel(g: GoalMode): string {
  if (g === GoalMode.MAINTAIN) { return '维持'; }
  if (g === GoalMode.SURPLUS) { return '增重'; }
  if (g === GoalMode.DEFICIT) { return '控卡'; }
  if (g === GoalMode.RECOMP) { return '增肌减脂'; }
  return '减重';
}

export function sexLabel(s: Sex): string {
  return s === Sex.MALE ? '男' : '女';
}
