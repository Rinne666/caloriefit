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
  UNSPECIFIED = 'unspecified',
  MALE = 'male',
  FEMALE = 'female'
}

/**
 * 活动量等级
 * 原 App 引导页文案:"Activity Level" / "Daily Workout/Activity Level"
 */
export enum ActivityLevel {
  UNSPECIFIED = 'unspecified',
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
  UNSPECIFIED = 'unspecified',
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

  /** 空档案；不能用虚构体征为新用户预填健康数据。 */
  static defaults(): BodyProfile {
    return new BodyProfile(
      0, 0, 0, Sex.UNSPECIFIED, null,
      ActivityLevel.UNSPECIFIED, GoalMode.UNSPECIFIED, 0
    );
  }

  /** 体征和目标偏好齐全后才可推导热量目标。 */
  isComplete(): boolean {
    return this.weightKg > 0 && this.heightCm > 0 && this.ageYears > 0 &&
      this.sex !== Sex.UNSPECIFIED && this.activity !== ActivityLevel.UNSPECIFIED &&
      this.mode !== GoalMode.UNSPECIFIED;
  }
}

/**
 * 体脂率比率 → 百分比文本。
 *
 * **不能用 toFixed(1)**：它会产出 "22.0" 这种带尾零的串，而
 * `InputType.NUMBER_DECIMAL` 的输入框会把小数点吞掉 —— 实测
 * 体脂率 0.22 回显成 "220"、0.20 回显成 "200"、手动输入 22.5 变成 "225"。
 * 220 会被当成 220% 存回去（→ 2.2），超出合法范围后保存直接被拒；
 * 而 68.5kg 这种带小数的体重若被吞成 685，就是数据损坏。
 * 这里输出不带多余小数位的字符串：0.22 → "22"，0.225 → "22.5"。
 */
export function bodyFatPercentText(ratio: number | null): string {
  if (ratio === null) {
    return '';
  }
  return String(Math.round(ratio * 1000) / 10);
}

/**
 * 中文标签 —— 用函数而非 Record<K,V> 查表。
 *
 * ArkTS 不允许对字段做索引访问（arkts-no-props-by-index），
 * THEME_LABELS[a] 这类写法会直接编译失败，必须走函数调用。
 */
export function activityLabel(a: ActivityLevel): string {
  if (a === ActivityLevel.UNSPECIFIED) { return '未选择'; }
  if (a === ActivityLevel.SEDENTARY) { return '久坐'; }
  if (a === ActivityLevel.LIGHT) { return '轻度活动'; }
  if (a === ActivityLevel.VERY_ACTIVE) { return '高强度'; }
  if (a === ActivityLevel.ATHLETE) { return '运动员 / 重体力'; }
  return '中度活动';
}

export function modeLabel(g: GoalMode): string {
  if (g === GoalMode.UNSPECIFIED) { return '未选择'; }
  if (g === GoalMode.MAINTAIN) { return '维持'; }
  if (g === GoalMode.SURPLUS) { return '增重'; }
  if (g === GoalMode.DEFICIT) { return '控卡'; }
  if (g === GoalMode.RECOMP) { return '增肌减脂'; }
  return '减重';
}

export function sexLabel(s: Sex): string {
  if (s === Sex.UNSPECIFIED) { return '未选择'; }
  return s === Sex.MALE ? '男' : '女';
}
