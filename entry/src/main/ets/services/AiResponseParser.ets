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
import { FoodRegion } from '../models/FoodSticker';
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
      proteinG, carbsG, fatG, macrosConsistent,
      AiResponseParser.readFoodRegion(obj));
  }

  /**
   * 读取食物位置（V6）。
   *
   * 模型输出约定：
   *   foodBox     {"x":int,"y":int,"width":int,"height":int}，坐标 0~1000
   *   foodPolygon [[x,y],[x,y],...]，坐标 0~1000，至少 3 个点
   *
   * 位置是**增强字段**，解析失败不能打断识别流程，所以这里全部走「拿不到就 null」
   * 而不是抛错 —— 拿不到坐标时抠图会退到中心椭圆，而不是不生成贴纸。
   *
   * 坐标尺度做了容错：大于 1 视为 0~1000 尺度并除以 1000，
   * 否则当作已经是 0~1 的比例值。模型两种都出现过。
   */
  private static readFoodRegion(obj: Record<string, Object>): FoodRegion | null {
    let bx = 0;
    let by = 0;
    let bw = 0;
    let bh = 0;
    let hasBox = false;

    const boxObj = obj['foodBox'];
    if (boxObj !== null && boxObj !== undefined && !Array.isArray(boxObj)) {
      const bo = boxObj as Record<string, Object>;
      const rx = AiResponseParser.readRatio(bo['x']);
      const ry = AiResponseParser.readRatio(bo['y']);
      const rw = AiResponseParser.readRatio(bo['width']);
      const rh = AiResponseParser.readRatio(bo['height']);
      if (rx !== null && ry !== null && rw !== null && rh !== null && rw > 0 && rh > 0) {
        bx = rx;
        by = ry;
        bw = rw;
        bh = rh;
        hasBox = true;
      }
    }

    const polygon = AiResponseParser.readPolygon(obj['foodPolygon']);
    if (!hasBox && polygon === null) {
      return null;
    }
    // 没有外接框但有多边形时，用多边形的包围盒补一个，保证外接框始终可用。
    if (!hasBox && polygon !== null) {
      let minX = 1;
      let minY = 1;
      let maxX = 0;
      let maxY = 0;
      for (let i = 0; i + 1 < polygon.length; i += 2) {
        minX = Math.min(minX, polygon[i]);
        minY = Math.min(minY, polygon[i + 1]);
        maxX = Math.max(maxX, polygon[i]);
        maxY = Math.max(maxY, polygon[i + 1]);
      }
      bx = minX;
      by = minY;
      bw = maxX - minX;
      bh = maxY - minY;
      hasBox = true;
    }

    if (!hasBox) {
      return null;
    }
    return new FoodRegion(bx, by, bw, bh, polygon);
  }

  /** 读一个归一化坐标；返回 null 表示该字段不可用 */
  private static readRatio(v: Object): number | null {
    if (typeof v !== 'number' || !isFinite(v)) {
      return null;
    }
    if (v < 0 || v > 1000) {
      return null;
    }
    // 大于 1 视为 0~1000 尺度；否则当作已是 0~1 比例。
    return v > 1 ? v / 1000 : v;
  }

  /** 读轮廓顶点数组，压成扁平的 [x1,y1,x2,y2,...] */
  private static readPolygon(v: Object): number[] | null {
    if (v === null || v === undefined || !Array.isArray(v)) {
      return null;
    }
    const outer = v as Object[];
    const pts: number[] = [];
    for (let i = 0; i < outer.length; i++) {
      const item = outer[i];
      if (item === null || item === undefined || !Array.isArray(item)) {
        continue;
      }
      const pair = item as Object[];
      if (pair.length < 2) {
        continue;
      }
      const px = AiResponseParser.readRatio(pair[0]);
      const py = AiResponseParser.readRatio(pair[1]);
      if (px === null || py === null) {
        continue;
      }
      pts.push(px, py);
    }
    // 少于 3 个顶点构不成轮廓
    return pts.length >= 6 ? pts : null;
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