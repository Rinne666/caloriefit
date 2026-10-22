/**
 * 合并四张表数据，生成 DailySummary。UI 层不直接执行 SQL。
 */

import { FoodRepository } from '../repositories/FoodRepository';
import { ExerciseRepository } from '../repositories/ExerciseRepository';
import { ActivityRepository } from '../repositories/ActivityRepository';
import { SettingsRepository } from '../repositories/SettingsRepository';
import { FoodLog } from '../models/FoodLog';
import { ExerciseLog } from '../models/ExerciseLog';
import { DailyActivity } from '../models/DailyActivity';
import { AppSettings } from '../models/AppSettings';
import { DailySummary } from '../models/DailySummary';
import { MockActivityDataSource } from './MockActivityDataSource';

export class DailySummaryService {
  static async getSummary(date: string): Promise<DailySummary> {
    const foods: FoodLog[] = await FoodRepository.getByDate(date);
    const exercises: ExerciseLog[] = await ExerciseRepository.getByDate(date);
    const activitySource = new MockActivityDataSource();
    const activity: DailyActivity = await activitySource.getDailyActivity(date);
    const settings: AppSettings = await SettingsRepository.getSettings();

    let consumed = 0;
    for (let i = 0; i < foods.length; i++) {
      consumed += foods[i].calories;
    }
    let burned = 0;
    let minutes = 0;
    for (let i = 0; i < exercises.length; i++) {
      burned += exercises[i].caloriesBurned;
      minutes += exercises[i].durationMinutes;
    }

    return new DailySummary(date, consumed, burned, minutes, activity.steps,
      settings.dailyCalorieBudget, settings.stepsGoal,
      settings.exerciseMinutesGoal, settings.activityKcalGoal,
      activity.source);
  }
}
