/**
 * 饮食记录的增删改查（V2：entry_mode / AI 字段 / 可空重量）。
 * 排序固定 created_at DESC, id DESC（新增优先显示）。
 */

import { relationalStore } from '@kit.ArkData';
import { Database } from '../database/Database';
import { FoodLog, FoodLogInput } from '../models/FoodLog';
import { StickerCutoutService } from '../services/StickerCutoutService';

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

  // 宏量与录入模式无关，两种模式都可能有值，故在分支外读取。
  // 存量数据（V2 迁移上来）为 NULL，读出 null 而不是 0。
  let proteinG: number | null = null;
  let carbsG: number | null = null;
  let fatG: number | null = null;
  const pIdx = rs.getColumnIndex('protein_g');
  const cIdx = rs.getColumnIndex('carbs_g');
  const fIdx = rs.getColumnIndex('fat_g');
  if (pIdx >= 0 && rs.getColumnTypeSync(pIdx) !== relationalStore.ColumnType.NULL) {
    proteinG = rs.getDouble(pIdx);
  }
  if (cIdx >= 0 && rs.getColumnTypeSync(cIdx) !== relationalStore.ColumnType.NULL) {
    carbsG = rs.getDouble(cIdx);
  }
  if (fIdx >= 0 && rs.getColumnTypeSync(fIdx) !== relationalStore.ColumnType.NULL) {
    fatG = rs.getDouble(fIdx);
  }

  // V6：贴纸路径。存量行为 NULL（没有贴纸），不能当成空串 —— 空串会让
  // Image 去加载一个不存在的相对路径，getPixelMap 直接抛错。
  let stickerPath: string | null = null;
  const sIdx = rs.getColumnIndex('sticker_path');
  if (sIdx >= 0 && rs.getColumnTypeSync(sIdx) !== relationalStore.ColumnType.NULL) {
    stickerPath = rs.getString(sIdx);
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
    proteinG,
    carbsG,
    fatG,
    rs.getLong(rs.getColumnIndex('created_at')),
    rs.getLong(rs.getColumnIndex('updated_at')),
    stickerPath
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
      'protein_g': input.proteinG,
      'carbs_g': input.carbsG,
      'fat_g': input.fatG,
      'sticker_path': input.stickerPath,
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
      'protein_g': input.proteinG,
      'carbs_g': input.carbsG,
      'fat_g': input.fatG,
      'sticker_path': input.stickerPath,
      'updated_at': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    await store.update(bucket, predicates);
  }

  static async delete(id: number): Promise<void> {
    const store = await Database.ensure();
    // 先读出这一行的贴纸路径：删行之后贴纸 PNG 就没人引用了，
    // 不跟着删会变成孤儿文件一直躺在沙箱里。
    const existing = await FoodRepository.getById(id);
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    await store.delete(predicates);
    if (existing !== null && existing.stickerPath !== null) {
      await StickerCutoutService.remove(existing.stickerPath);
    }
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