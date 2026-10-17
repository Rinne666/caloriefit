/**
 * 饮食记录
 */

export enum MealType {
  BREAKFAST = 0,
  LUNCH = 1,
  DINNER = 2,
  SNACK = 3
}

export class FoodLog {
  id: number;
  date: string;
  name: string;
  mealType: number;
  weightG: number;
  kcalPer100g: number;
  calories: number;
  createdAt: number;
  updatedAt: number;

  constructor(id: number, date: string, name: string, mealType: number,
    weightG: number, kcalPer100g: number, calories: number,
    createdAt: number, updatedAt: number) {
    this.id = id;
    this.date = date;
    this.name = name;
    this.mealType = mealType;
    this.weightG = weightG;
    this.kcalPer100g = kcalPer100g;
    this.calories = calories;
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
  }
}
