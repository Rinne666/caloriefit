/**
 * AI 响应解析：严格校验字段类型与取值范围，拒绝伪造数据。
 *
 * V3 新增宏量解析与 Atwater 一致性守卫：
 *   模型给的蛋白/碳水/脂肪按 4/4/9 回算，与总热量偏差超容差即判定不可信，
 *   三者整体置 null 并置 macrosConsistent=false，而不是照单全收。
 *   理由：VLM 对宏量的不确定度远高于总热量，放行不自洽数据会污染日汇总，
 *   用户看到「总热量 600 但宏量回算 900」只会认为 App 算错了。
 */

import { AiRecognitionResult } from '../models/AiRecognitionResult';
import {
  AiErrorCode, AiError,
  AI_MACRO_TOLERANCE, AI_MACRO_MAX_G
} from '../common/AiConstants';

export class AiResponseParser {
  static parseContent(content: string): AiRecognitionResult {
    let obj: Record<string, Object> | null = null;
    try {
      obj = JSON.parse(content) as Record<string, Object>;
    } catch (e) {
      throw new AiError(AiErrorCode.INVALID_RESPONSE, 'not json');
    }
    if (obj === null || Array.isArray(obj)) {
      throw new AiError(AiErrorCode.INVALID_RESPONSE, 'not object');
    }

    const foodNameObj = obj['foodName'];
    if (typeof foodNameObj !== 'string') {
      throw new AiError(AiErrorCode.INVALID_RESPONSE, 'foodName type');
    }
    const foodName = foodNameObj.trim();
    if (foodName.length < 1 || foodName.length > 40) {
      throw new AiError(AiErrorCode.INVALID_RESPONSE, 'foodName length');
    }

    const kcalObj = obj['estimatedTotalKcal'];
    let kcal: number | null = null;
    if (kcalObj !== null && kcalObj !== undefined) {
      if (typeof kcalObj !== 'number' || !isFinite(kcalObj) || !Number.isInteger(kcalObj)) {
        throw new AiError(AiErrorCode.INVALID_RESPONSE, 'kcal type');
      }
      if (kcalObj < 1 || kcalObj > 10000) {
        throw new AiError(AiErrorCode.INVALID_RESPONSE, 'kcal range');
      }
      kcal = kcalObj;
    }

    const confObj = obj['confidence'];
    if (typeof confObj !== 'number' || !isFinite(confObj) || confObj < 0 || confObj > 1) {
      throw new AiError(AiErrorCode.INVALID_RESPONSE, 'confidence type');
    }

    const notesObj = obj['notes'];
    if (typeof notesObj !== 'string') {
      throw new AiError(AiErrorCode.INVALID_RESPONSE, 'notes type');
    }
    let notes = notesObj.trim().slice(0, 500);

    // ---------- V3 宏量 ----------
    const p = AiResponseParser.readMacro(obj['proteinG']);
    const c = AiResponseParser.readMacro(obj['carbsG']);
    const f = AiResponseParser.readMacro(obj['fatG']);

    let proteinG = p;
    let carbsG = c;
    let fatG = f;
    let macrosConsistent = false;

    const allPresent = p !== null && c !== null && f !== null;
    if (allPresent && kcal !== null && kcal > 0) {
      const back = Math.round((p as number) * 4 + (c as number) * 4 + (f as number) * 9);
      const deviation = Math.abs(back - kcal) / kcal;
      if (deviation <= AI_MACRO_TOLERANCE) {
        macrosConsistent = true;
      } else {
        // 自洽性失败：丢弃宏量，但保留总热量（总热量是主要指标，更可靠）
        proteinG = null;
        carbsG = null;
        fatG = null;
        notes = (notes + ` 宏量与总热量偏差 ${Math.round(deviation * 100)}%，已忽略。`)
          .slice(0, 500);
      }
    }

    return new AiRecognitionResult(foodName, kcal, confObj, notes,
      proteinG, carbsG, fatG, macrosConsistent);
  }

  /**
   * 读取单个宏量字段。
   * 缺失 / null → null；非整数 / 负数 / 超上限 → null（视为模型幻觉，不抛错打断流程）。
   * 与 foodName/calories 的严格策略不同：宏量是增强字段，
   * 单个字段异常不应该让整次识别失败。
   */
  private static readMacro(v: Object): number | null {
    if (v === null || v === undefined) {
      return null;
    }
    if (typeof v !== 'number' || !isFinite(v)) {
      return null;
    }
    if (!Number.isInteger(v) || v < 0 || v > AI_MACRO_MAX_G) {
      return null;
    }
    return v;
  }
}