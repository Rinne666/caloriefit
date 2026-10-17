/**
 * AI 识别结果与确认后的本地草稿
 */

export class AiRecognitionResult {
  foodName: string;
  estimatedTotalKcal: number | null;
  confidence: number;
  notes: string;

  constructor(foodName: string, estimatedTotalKcal: number | null,
    confidence: number, notes: string) {
    this.foodName = foodName;
    this.estimatedTotalKcal = estimatedTotalKcal;
    this.confidence = confidence;
    this.notes = notes;
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

  constructor(date: string, name: string, mealType: number,
    calories: number, aiConfidence: number, aiNotes: string) {
    this.date = date;
    this.name = name;
    this.mealType = mealType;
    this.calories = calories;
    this.aiConfidence = aiConfidence;
    this.aiNotes = aiNotes;
  }
}