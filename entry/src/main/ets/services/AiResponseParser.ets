/**
 * AI 响应解析：严格校验字段类型与取值范围，拒绝伪造数据。
 */

import { AiRecognitionResult } from '../models/AiRecognitionResult';
import { AiErrorCode, AiError } from '../common/AiConstants';

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
    const notes = notesObj.trim().slice(0, 500);

    return new AiRecognitionResult(foodName, kcal, confObj, notes);
  }
}