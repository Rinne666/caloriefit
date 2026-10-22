/**
 * AI 识别结果与确认后的本地草稿
 */

import { FoodRegion } from './FoodSticker';

export class AiRecognitionResult {
  foodName: string;
  estimatedTotalKcal: number | null;
  confidence: number;
  notes: string;
  /** V3：三大宏量估算（克）。为 null 表示模型未给出或未通过一致性校验 */
  proteinG: number | null;
  carbsG: number | null;
  fatG: number | null;
  /**
   * 宏量与总热量的 Atwater 自洽性是否通过。
   * false 表示模型给的宏量回算热量与总热量偏差过大，已被丢弃（置 null）
   */
  macrosConsistent: boolean;
  /**
   * V6：模型给出的食物位置，用于把食物抠成透明背景贴纸。
   * null 表示模型没给坐标 —— 抠图会走中心椭圆降级，而不是不做。
   */
  foodRegion: FoodRegion | null;

  constructor(foodName: string, estimatedTotalKcal: number | null,
    confidence: number, notes: string,
    proteinG: number | null, carbsG: number | null, fatG: number | null,
    macrosConsistent: boolean, foodRegion: FoodRegion | null) {
    this.foodName = foodName;
    this.estimatedTotalKcal = estimatedTotalKcal;
    this.confidence = confidence;
    this.notes = notes;
    this.proteinG = proteinG;
    this.carbsG = carbsG;
    this.fatG = fatG;
    this.macrosConsistent = macrosConsistent;
    this.foodRegion = foodRegion;
  }

  /** 三者同时有值 */
  hasMacros(): boolean {
    return this.proteinG !== null && this.carbsG !== null && this.fatG !== null;
  }
}

/** 用户选择“使用结果并编辑”后传给 FoodEditPage 的草稿 */
export class AiFoodDraft {
  date: string;
  name: string;
  mealType: number;
  calories: number;
  aiConfidence: number;
  aiNotes: string;
  proteinG: number | null;
  carbsG: number | null;
  fatG: number | null;

  constructor(date: string, name: string, mealType: number,
    calories: number, aiConfidence: number, aiNotes: string,
    proteinG: number | null, carbsG: number | null, fatG: number | null) {
    this.date = date;
    this.name = name;
    this.mealType = mealType;
    this.calories = calories;
    this.aiConfidence = aiConfidence;
    this.aiNotes = aiNotes;
    this.proteinG = proteinG;
    this.carbsG = carbsG;
    this.fatG = fatG;
  }
}