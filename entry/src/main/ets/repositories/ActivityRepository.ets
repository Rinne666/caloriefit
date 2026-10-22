/**
 * 每日步数记录。setDailySteps 为按日期覆盖语义（非累加）。
 *
 * 两条写入路径：
 *   · setDailySteps   —— 用户手动填写/校正，source = MANUAL_SIMULATED
 *   · setSensorSteps  —— 传感器自动采集，source = SENSOR_PEDOMETER
 *
 * 优先级：手动值优先。传感器写入时会先看当天是不是已经有手动值，
 * 有就不覆盖 —— 否则用户刚校正完的数会被下一次传感器上报冲掉。
 */

import { relationalStore } from '@kit.ArkData';
import { Database } from '../database/Database';
import { DailyActivity, STEP_SOURCE_MANUAL, STEP_SOURCE_SENSOR } from '../models/DailyActivity';

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
      'source': STEP_SOURCE_MANUAL,
      'updated_at': Date.now()
    };
    const rows = await store.update(updateBucket, predicates);
    if (rows === 0) {
      const insertBucket: relationalStore.ValuesBucket = {
        'date': date,
        'steps': steps,
        'source': STEP_SOURCE_MANUAL,
        'updated_at': Date.now()
      };
      await store.insert(TABLE, insertBucket);
    }
  }

  /**
   * 写入传感器采集到的步数。
   *
   * 返回 true 表示确实写进去了；返回 false 表示当天已被用户手动校正，
   * 传感器值被丢弃（手动优先）。
   */
  static async setSensorSteps(date: string, steps: number): Promise<boolean> {
    const existing = await ActivityRepository.getByDate(date);
    if (existing !== null && existing.source === STEP_SOURCE_MANUAL) {
      return false;
    }
    const store = await Database.ensure();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('date', date);
    const updateBucket: relationalStore.ValuesBucket = {
      'steps': steps,
      'source': STEP_SOURCE_SENSOR,
      'updated_at': Date.now()
    };
    const rows = await store.update(updateBucket, predicates);
    if (rows === 0) {
      const insertBucket: relationalStore.ValuesBucket = {
        'date': date,
        'steps': steps,
        'source': STEP_SOURCE_SENSOR,
        'updated_at': Date.now()
      };
      await store.insert(TABLE, insertBucket);
    }
    return true;
  }

  /**
   * 清除手动覆盖，让传感器重新接管当天。
   * 直接删行 —— 下一次传感器上报会重新插入 source = SENSOR_PEDOMETER 的记录。
   */
  static async clearManualSteps(date: string): Promise<void> {
    const store = await Database.ensure();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('date', date);
    predicates.equalTo('source', STEP_SOURCE_MANUAL);
    await store.delete(predicates);
  }
}
