/**
 * 运动记录的增删改查
 */

import { relationalStore } from '@kit.ArkData';
import { Database } from '../database/Database';
import { ExerciseLog } from '../models/ExerciseLog';

const TABLE = 'exercise_log';

function mapRow(rs: relationalStore.ResultSet): ExerciseLog {
  return new ExerciseLog(
    rs.getLong(rs.getColumnIndex('id')),
    rs.getString(rs.getColumnIndex('date')),
    rs.getLong(rs.getColumnIndex('type')),
    rs.getLong(rs.getColumnIndex('duration_minutes')),
    rs.getLong(rs.getColumnIndex('calories_burned')),
    rs.getLong(rs.getColumnIndex('created_at')),
    rs.getLong(rs.getColumnIndex('updated_at'))
  );
}

export class ExerciseRepository {
  static async insert(log: ExerciseLog): Promise<number> {
    const store = await Database.ensure();
    const now = Date.now();
    const bucket: relationalStore.ValuesBucket = {
      'date': log.date,
      'type': log.type,
      'duration_minutes': log.durationMinutes,
      'calories_burned': log.caloriesBurned,
      'created_at': now,
      'updated_at': now
    };
    const id = await store.insert(TABLE, bucket);
    log.createdAt = now;
    log.updatedAt = now;
    return id;
  }

  static async update(log: ExerciseLog): Promise<void> {
    const store = await Database.ensure();
    const bucket: relationalStore.ValuesBucket = {
      'date': log.date,
      'type': log.type,
      'duration_minutes': log.durationMinutes,
      'calories_burned': log.caloriesBurned,
      'updated_at': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', log.id);
    await store.update(bucket, predicates);
  }

  static async delete(id: number): Promise<void> {
    const store = await Database.ensure();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    await store.delete(predicates);
  }

  static async getById(id: number): Promise<ExerciseLog | null> {
    const store = await Database.ensure();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    const resultSet = await store.query(predicates);
    let result: ExerciseLog | null = null;
    try {
      if (resultSet.goToNextRow()) {
        result = mapRow(resultSet);
      }
    } finally {
      resultSet.close();
    }
    return result;
  }

  static async getByDate(date: string): Promise<ExerciseLog[]> {
    const store = await Database.ensure();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('date', date)
      .orderByDesc('created_at')
      .orderByDesc('id');
    const resultSet = await store.query(predicates);
    const logs: ExerciseLog[] = [];
    try {
      while (resultSet.goToNextRow()) {
        logs.push(mapRow(resultSet));
      }
    } finally {
      resultSet.close();
    }
    return logs;
  }
}
