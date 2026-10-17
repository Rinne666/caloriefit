/**
 * 每日模拟步数。setDailySteps 为按日期覆盖语义（非累加）。
 */

import { relationalStore } from '@kit.ArkData';
import { Database } from '../database/Database';
import { DailyActivity } from '../models/DailyActivity';

const TABLE = 'daily_activity';

export class ActivityRepository {
  static async getByDate(date: string): Promise<DailyActivity | null> {
    const store = await Database.ensure();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('date', date);
    const resultSet = await store.query(predicates);
    let result: DailyActivity | null = null;
    try {
      if (resultSet.goToNextRow()) {
        result = new DailyActivity(
          resultSet.getString(resultSet.getColumnIndex('date')),
          resultSet.getLong(resultSet.getColumnIndex('steps')),
          resultSet.getString(resultSet.getColumnIndex('source')),
          resultSet.getLong(resultSet.getColumnIndex('updated_at'))
        );
      }
    } finally {
      resultSet.close();
    }
    return result;
  }

  static async setDailySteps(date: string, steps: number): Promise<void> {
    const store = await Database.ensure();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('date', date);
    const updateBucket: relationalStore.ValuesBucket = {
      'steps': steps,
      'source': 'MANUAL_SIMULATED',
      'updated_at': Date.now()
    };
    const rows = await store.update(updateBucket, predicates);
    if (rows === 0) {
      const insertBucket: relationalStore.ValuesBucket = {
        'date': date,
        'steps': steps,
        'source': 'MANUAL_SIMULATED',
        'updated_at': Date.now()
      };
      await store.insert(TABLE, insertBucket);
    }
  }
}
