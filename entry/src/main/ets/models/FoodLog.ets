/**
 * FoodLog V2：支持手动称重（entryMode 0）与 AI 整份估算（entryMode 1）两种录入模式。
 */

export enum MealType {
  BREAKFAST = 0,
  LUNCH = 1,
  DINNER = 2,
  SNACK = 3
}

export enum FoodEntryMode {
  MANUAL_WEIGHT = 0,
  AI_TOTAL = 1
}

export class FoodLog {
  id: number;
  date: string;
  name: string;
  mealType: number;
  grams: number | null;
  kcalPer100g: number | null;
  calories: number;
  entryMode: number;
  aiConfidence: number | null;
  aiNotes: string | null;
  /**
   * V3 宏量营养素（克）。两种录入模式都可有值。
   * 手动称重：用户按包装标签填写
   * AI 识别：由模型估算，经 Atwater 一致性校验后写入
   * null 表示未记录 —— 不参与汇总，不以 0 冒充
   */
  proteinG: number | null;
  carbsG: number | null;
  fatG: number | null;
  createdAt: number;
  updatedAt: number;

  constructor(id: number, date: string, name: string, mealType: number,
    grams: number | null, kcalPer100g: number | null, calories: number,
    entryMode: number, aiConfidence: number | null, aiNotes: string | null,
    proteinG: number | null, carbsG: number | null, fatG: number | null,
    createdAt: number, updatedAt: number) {
    this.id = id;
    this.date = date;
    this.name = name;
    this.mealType = mealType;
    this.grams = grams;
    this.kcalPer100g = kcalPer100g;
    this.calories = calories;
    this.entryMode = entryMode;
    this.aiConfidence = aiConfidence;
    this.aiNotes = aiNotes;
    this.proteinG = proteinG;
    this.carbsG = carbsG;
    this.fatG = fatG;
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
  }

  /** 是否记录了完整宏量（三者同时有值） */
  hasMacros(): boolean {
    return this.proteinG !== null && this.carbsG !== null && this.fatG !== null;
  }

  /** 宏量按 Atwater 回算的热量；未记录宏量时返回 0 */
  macroCalories(): number {
    if (!this.hasMacros()) {
      return 0;
    }
    return Math.round(
      (this.proteinG as number) * 4 +
      (this.carbsG as number) * 4 +
      (this.fatG as number) * 9
    );
  }
}

/** 编辑页构造的入库输入，不含 id/createdAt/updatedAt */
export class FoodLogInput {
  date: string;
  name: string;
  mealType: number;
  grams: number | null;
  kcalPer100g: number | null;
  calories: number;
  entryMode: number;
  aiConfidence: number | null;
  aiNotes: string | null;
  proteinG: number | null;
  carbsG: number | null;
  fatG: number | null;

  constructor(date: string, name: string, mealType: number,
    grams: number | null, kcalPer100g: number | null, calories: number,
    entryMode: number, aiConfidence: number | null, aiNotes: string | null,
    proteinG: number | null, carbsG: number | null, fatG: number | null) {
    this.date = date;
    this.name = name;
    this.mealType = mealType;
    this.grams = grams;
    this.kcalPer100g = kcalPer100g;
    this.calories = calories;
    this.entryMode = entryMode;
    this.aiConfidence = aiConfidence;
    this.aiNotes = aiNotes;
    this.proteinG = proteinG;
    this.carbsG = carbsG;
    this.fatG = fatG;
  }
}