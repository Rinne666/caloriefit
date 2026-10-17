/**
 * 饮食记录的增删改查（V2：entry_mode / AI 字段 / 可空重量）。
 * 排序固定 created_at DESC, id DESC（新增优先显示）。
 */

import { relationalStore } from '@kit.ArkData';
import { Database } from '../database/Database';
import { FoodLog, FoodLogInput } from '../models/FoodLog';

const TABLE = 'food_log';

function mapRow(rs: relationalStore.ResultSet): FoodLog {
  const entryMode = rs.getLong(rs.getColumnIndex('entry_mode'));
  let grams: number | null = null;
  let kcalPer100g: number | null = null;
  let aiConfidence: number | null = null;
  let aiNotes: string | null = null;
  if (entryMode === 0) {
    grams = rs.getDouble(rs.getColumnIndex('grams'));
    kcalPer100g = rs.getDouble(rs.getColumnIndex('kcal_per_100g'));
  } else {
    const confIdx = rs.getColumnIndex('ai_confidence');
    const notesIdx = rs.getColumnIndex('ai_notes');
    if (rs.getColumnTypeSync(confIdx) !== relationalStore.ColumnType.NULL) {
      aiConfidence = rs.getDouble(confIdx);
    }
    if (rs.getColumnTypeSync(notesIdx) !== relationalStore.ColumnType.NULL) {
      aiNotes = rs.getString(notesIdx);
    }
  }
  return new FoodLog(
    rs.getLong(rs.getColumnIndex('id')),
    rs.getString(rs.getColumnIndex('date')),
    rs.getString(rs.getColumnIndex('name')),
    rs.getLong(rs.getColumnIndex('meal_type')),
    grams,
    kcalPer100g,
    rs.getLong(rs.getColumnIndex('calories')),
    entryMode,
    aiConfidence,
    aiNotes,
    rs.getLong(rs.getColumnIndex('created_at')),
    rs.getLong(rs.getColumnIndex('updated_at'))
  );
}

export class FoodRepository {
  /** 手动模式重新计算热量；AI 模式直接保存确认的总热量 */
  static async insert(input: FoodLogInput): Promise<number> {
    const store = await Database.ensure();
    const now = Date.now();
    const bucket: relationalStore.ValuesBucket = {
      'date': input.date,
      'name': input.name,
      'meal_type': input.mealType,
      'grams': input.grams,
      'kcal_per_100g': input.kcalPer100g,
      'calories': input.calories,
      'entry_mode': input.entryMode,
      'ai_confidence': input.aiConfidence,
      'ai_notes': input.aiNotes,
      'created_at': now,
      'updated_at': now
    };
    return store.insert(TABLE, bucket);
  }

  static async update(id: number, input: FoodLogInput): Promise<void> {
    const store = await Database.ensure();
    const bucket: relationalStore.ValuesBucket = {
      'date': input.date,
      'name': input.name,
      'meal_type': input.mealType,
      'grams': input.grams,
      'kcal_per_100g': input.kcalPer100g,
      'calories': input.calories,
      'entry_mode': input.entryMode,
      'ai_confidence': input.aiConfidence,
      'ai_notes': input.aiNotes,
      'updated_at': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
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