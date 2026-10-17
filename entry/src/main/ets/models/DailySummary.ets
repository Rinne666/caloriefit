/**
 * 首页与运动页使用的当日汇总数据
 */

export class DailySummary {
  date: string;
  consumedKcal: number;
  burnedKcal: number;
  exerciseMinutes: number;
  steps: number;

  dailyCalorieBudget: number;
  stepsGoal: number;
  exerciseMinutesGoal: number;
  activityKcalGoal: number;

  constructor(date: string, consumedKcal: number, burnedKcal: number,
    exerciseMinutes: number, steps: number, dailyCalorieBudget: number,
    stepsGoal: number, exerciseMinutesGoal: number, activityKcalGoal: number) {
    this.date = date;
    this.consumedKcal = consumedKcal;
    this.burnedKcal = burnedKcal;
    this.exerciseMinutes = exerciseMinutes;
    this.steps = steps;
    this.dailyCalorieBudget = dailyCalorieBudget;
    this.stepsGoal = stepsGoal;
    this.exerciseMinutesGoal = exerciseMinutesGoal;
    this.activityKcalGoal = activityKcalGoal;
  }

  /** 剩余饮食预算，允许为负（超标时显示超出） */
  remainingBudget(): number {
    return this.dailyCalorieBudget - this.consumedKcal;
  }
}
