/**
 * 饮食记录的增删改查。排序固定 created_at DESC, id DESC（新增优先显示）。
 */

import { relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { Database } from '../database/Database';
import { FoodLog } from '../models/FoodLog';

const TABLE = 'food_log';

function mapRow(rs: relationalStore.ResultSet): FoodLog {
  return new FoodLog(
    rs.getLong(rs.getColumnIndex('id')),
    rs.getString(rs.getColumnIndex('date')),
    rs.getString(rs.getColumnIndex('name')),
    rs.getLong(rs.getColumnIndex('meal_type')),
    rs.getDouble(rs.getColumnIndex('weight_g')),
    rs.getDouble(rs.getColumnIndex('kcal_per_100g')),
    rs.getLong(rs.getColumnIndex('calories')),
    rs.getLong(rs.getColumnIndex('created_at')),
    rs.getLong(rs.getColumnIndex('updated_at'))
  );
}

export class FoodRepository {
  static async insert(log: FoodLog): Promise<number> {
    const store = await Database.ensure();
    const now = Date.now();
    const bucket: relationalStore.ValuesBucket = {
      'date': log.date,
      'name': log.name,
      'meal_type': log.mealType,
      'weight_g': log.weightG,
      'kcal_per_100g': log.kcalPer100g,
      'calories': log.calories,
      'created_at': now,
      'updated_at': now
    };
    const id = await store.insert(TABLE, bucket);
    log.createdAt = now;
    log.updatedAt = now;
    return id;
  }

  static async update(log: FoodLog): Promise<void> {
    const store = await Database.ensure();
    const bucket: relationalStore.ValuesBucket = {
      'date': log.date,
      'name': log.name,
      'meal_type': log.mealType,
      'weight_g': log.weightG,
      'kcal_per_100g': log.kcalPer100g,
      'calories': log.calories,
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

  static async getById(id: number): Promise<FoodLog | null> {
    const store = await Database.ensure();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    const resultSet = await store.query(predicates);
    let result: FoodLog | null = null;
    try {
      if (resultSet.goToNextRow()) {
        result = mapRow(resultSet);
      }
    } finally {
      resultSet.close();
    }
    return result;
  }

  static async getByDate(date: string): Promise<FoodLog[]> {
    const store = await Database.ensure();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('date', date)
      .orderByDesc('created_at')
      .orderByDesc('id');
    const resultSet = await store.query(predicates);
    const logs: FoodLog[] = [];
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
