/**
 * 模拟运动数据源：从本地数据库读取手动设置的模拟步数。
 */

import { ActivityRepository } from '../repositories/ActivityRepository';
import { DailyActivity } from '../models/DailyActivity';
import { ActivityDataSource } from './ActivityDataSource';

export class MockActivityDataSource implements ActivityDataSource {
  async getDailyActivity(date: string): Promise<DailyActivity> {
    const activity = await ActivityRepository.getByDate(date);
    if (activity !== null) {
      return activity;
    }
    return new DailyActivity(date, 0, 'MANUAL_SIMULATED', 0);
  }
}
