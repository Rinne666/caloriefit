/**
 * 目标设置的读写
 */

import { relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { Database } from '../database/Database';
import { AppSettings } from '../models/AppSettings';
import { DEFAULT_GOALS } from '../common/Constants';

const TABLE = 'app_settings';

export class SettingsRepository {
  static async getSettings(): Promise<AppSettings> {
    const store = await Database.ensure();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', 1);
    const resultSet = await store.query(predicates);
    let settings: AppSettings;
    try {
      if (resultSet.goToNextRow()) {
        settings = new AppSettings(
          resultSet.getLong(resultSet.getColumnIndex('daily_calorie_budget')),
          resultSet.getLong(resultSet.getColumnIndex('steps_goal')),
          resultSet.getLong(resultSet.getColumnIndex('exercise_minutes_goal')),
          resultSet.getLong(resultSet.getColumnIndex('activity_kcal_goal')),
          resultSet.getLong(resultSet.getColumnIndex('updated_at'))
        );
      } else {
        settings = new AppSettings(DEFAULT_GOALS.dailyCalorieBudget,
          DEFAULT_GOALS.stepsGoal, DEFAULT_GOALS.exerciseMinutesGoal,
          DEFAULT_GOALS.activityKcalGoal, 0);
      }
    } finally {
      resultSet.close();
    }
    return settings;
  }

  static async saveSettings(settings: AppSettings): Promise<void> {
    const store = await Database.ensure();
    const now = Date.now();
    const bucket: relationalStore.ValuesBucket = {
      'daily_calorie_budget': settings.dailyCalorieBudget,
      'steps_goal': settings.stepsGoal,
      'exercise_minutes_goal': settings.exerciseMinutesGoal,
      'activity_kcal_goal': settings.activityKcalGoal,
      'updated_at': now
    };
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', 1);
    const rows = await store.update(bucket, predicates);
    if (rows === 0) {
      // 默认行不存在（理论上 INIT 已插入），强制补插
      const insertBucket: relationalStore.ValuesBucket = {
        'id': 1,
        'daily_calorie_budget': settings.dailyCalorieBudget,
        'steps_goal': settings.stepsGoal,
        'exercise_minutes_goal': settings.exerciseMinutesGoal,
        'activity_kcal_goal': settings.activityKcalGoal,
        'updated_at': now
      };
      await store.insert(TABLE, insertBucket);
    }
    settings.updatedAt = now;
  }
}
