/**
 * 全局目标设置
 */

export class AppSettings {
  dailyCalorieBudget: number;
  stepsGoal: number;
  exerciseMinutesGoal: number;
  activityKcalGoal: number;
  updatedAt: number;

  constructor(dailyCalorieBudget: number, stepsGoal: number,
    exerciseMinutesGoal: number, activityKcalGoal: number, updatedAt: number) {
    this.dailyCalorieBudget = dailyCalorieBudget;
    this.stepsGoal = stepsGoal;
    this.exerciseMinutesGoal = exerciseMinutesGoal;
    this.activityKcalGoal = activityKcalGoal;
    this.updatedAt = updatedAt;
  }
}
