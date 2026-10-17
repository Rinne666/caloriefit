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
  createdAt: number;
  updatedAt: number;

  constructor(id: number, date: string, name: string, mealType: number,
    grams: number | null, kcalPer100g: number | null, calories: number,
    entryMode: number, aiConfidence: number | null, aiNotes: string | null,
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
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
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

  constructor(date: string, name: string, mealType: number,
    grams: number | null, kcalPer100g: number | null, calories: number,
    entryMode: number, aiConfidence: number | null, aiNotes: string | null) {
    this.date = date;
    this.name = name;
    this.mealType = mealType;
    this.grams = grams;
    this.kcalPer100g = kcalPer100g;
    this.calories = calories;
    this.entryMode = entryMode;
    this.aiConfidence = aiConfidence;
    this.aiNotes = aiNotes;
  }
}