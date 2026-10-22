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
    // 换了贴纸文件时，旧文件可能变成孤儿 —— 但要先确认没有别的记录还在用它。
    const previous = await FoodRepository.getById(id);
    if (previous !== null && previous.stickerPath !== null &&
      previous.stickerPath !== input.stickerPath) {
      try {
        const refs = await FoodRepository.countStickerReferences(previous.stickerPath);
        if (refs === 0) {
          await StickerCutoutService.remove(previous.stickerPath);
        }
      } catch (_e) {
        // 计数失败就不删：残留文件只是占点空间，误删会让还在用的贴纸变默认图。
      }
    }
  }

  static async delete(id: number): Promise<void> {
    const store = await Database.ensure();
    // 先读出这一行的贴纸路径：删行之后贴纸 PNG 就没人引用了，
    // 不跟着删会变成孤儿文件一直躺在沙箱里。
    const existing = await FoodRepository.getById(id);
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    await store.delete(predicates);
    // 黑板上的贴纸节点是这条记录的投影，记录没了节点也要没。
    // 这里用裸 SQL 而不是 import BoardRepository —— BoardRepository 要读
    // FoodRepository（贴纸节点的内容从 food_log 取），再互相 import 就成环了。
    try {
      await store.executeSql('DELETE FROM board_node WHERE food_id = ?', [id]);
    } catch (_e) {
      // 表还没建（V7 之前的老库）时忽略，不影响删除记录本身
    }
    if (existing !== null && existing.stickerPath !== null) {
      // 引用计数：复制一条记录时副本与原记录**共用同一个贴纸文件**，
      // 删掉任意一条都不能把文件带走 —— 否则原记录的贴纸会变成默认图。
      // 只有最后一个引用消失时，文件才真正成为孤儿，这时才删。
      let refs = 0;
      try {
        refs = await FoodRepository.countStickerReferences(existing.stickerPath);
      } catch (_e) {
        // 计数失败时保守处理：宁可留下一个孤儿文件，也不要误删还在用的贴纸。
        refs = 1;
      }
      if (refs === 0) {
        await StickerCutoutService.remove(existing.stickerPath);
      }
    }
  }

  /**
   * 还有多少条饮食记录在用这个贴纸文件。
   *
   * 复制记录（黑板「复制到今天」）会让两条记录指向同一个 PNG，
   * 删除时的判断依据就是这里的计数。
   */
  static async countStickerReferences(relPath: string): Promise<number> {
    if (relPath.length === 0) {
      return 0;
    }
    const store = await Database.ensure();
    const resultSet = await store.querySql(
      'SELECT COUNT(*) AS cnt FROM food_log WHERE sticker_path = ?', [relPath]);
    let count = 0;
    try {
      if (resultSet.goToNextRow()) {
        count = resultSet.getLong(resultSet.getColumnIndex('cnt'));
      }
    } finally {
      resultSet.close();
    }
    return count;
  }

  /**
   * 只改餐次（黑板分栏拖拽时用）。
   *
   * 贴纸落在哪个餐次分区，餐次就跟着变 —— 否则黑板说「这是午餐」、
   * 汇总却把它算进加餐，两处对不上。
   */
  static async updateMealType(id: number, mealType: number): Promise<void> {
    const store = await Database.ensure();
    const bucket: relationalStore.ValuesBucket = {
      'meal_type': mealType,
      'updated_at': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    await store.update(bucket, predicates);
  }

  static async getById(id: number): Promise<FoodLog | null> {    const store = await Database.ensure();
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