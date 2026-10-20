/**
 * 首页与运动页使用的当日汇总数据
 */

export class DailySummary {
  date: string;
  consumedKcal: number;
  burnedKcal: number;
  exerciseMinutes: number;
  steps: number;
  /**
   * 当日步数的来源：SENSOR_PEDOMETER / MANUAL_SIMULATED / 空(未采集)。
   * 首页的步数卡要显示来源角标，不能再写死「手动模拟」——
   * 步数早已改为计步传感器自动采集，写死会把真实来源标错。
   */
  stepSource: string;

  dailyCalorieBudget: number;
  stepsGoal: number;
  exerciseMinutesGoal: number;
  activityKcalGoal: number;

  constructor(date: string, consumedKcal: number, burnedKcal: number,
    exerciseMinutes: number, steps: number, dailyCalorieBudget: number,
    stepsGoal: number, exerciseMinutesGoal: number, activityKcalGoal: number,
    stepSource: string = '') {
    this.date = date;
    this.consumedKcal = consumedKcal;
    this.burnedKcal = burnedKcal;
    this.exerciseMinutes = exerciseMinutes;
    this.steps = steps;
    this.stepSource = stepSource;
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
