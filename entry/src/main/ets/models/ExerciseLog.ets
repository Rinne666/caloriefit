/**
 * 运动记录
 */

export enum ExerciseType {
  WALK = 0,
  RUN = 1,
  RIDE = 2,
  FITNESS = 3,
  OTHER = 4
}

export class ExerciseLog {
  id: number;
  date: string;
  type: number;
  durationMinutes: number;
  caloriesBurned: number;
  createdAt: number;
  updatedAt: number;

  constructor(id: number, date: string, type: number, durationMinutes: number,
    caloriesBurned: number, createdAt: number, updatedAt: number) {
    this.id = id;
    this.date = date;
    this.type = type;
    this.durationMinutes = durationMinutes;
    this.caloriesBurned = caloriesBurned;
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
  }

  /**
   * 列表渲染用的 key。
   *
   * 理由与 FoodLog.renderKey() 一样：key 只用 id 的话，
   * 编辑过的记录会复用旧组件、继续显示旧内容。
   */
  renderKey(): string {
    return `${this.id}-${this.updatedAt}-${this.durationMinutes}-${this.caloriesBurned}-${this.type}`;
  }
}
