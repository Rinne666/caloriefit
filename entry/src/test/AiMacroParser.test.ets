/**
 * AiResponseParser 宏量解析与一致性守卫测试
 *
 * 守卫逻辑的边界最容易写错，所以逐个场景钉死：
 *   · 完全自洽 → 保留宏量
 *   · 边缘容差 → 保留
 *   · 超容差 → 丢弃宏量但保留总热量
 *   · 宏量缺失 / 总热量缺失 → 不做一致性判断，原样通过
 *   · 单字段畸形 → 该字段置 null，不影响其余字段
 */

import { describe, it, expect } from '@ohos/hypium';
import { AiResponseParser } from '../main/ets/services/AiResponseParser';
import { AI_MACRO_TOLERANCE, AI_MACRO_MAX_G, AI_DEMO_RESPONSE }
  from '../main/ets/common/AiConstants';

export default function aiMacroParserTest() {
  describe('AiResponseParser 宏量守卫', () => {

    function makeJson(kcal: Object, p: Object, c: Object, f: Object): string {
      return JSON.stringify({
        foodName: '测试食物',
        estimatedTotalKcal: kcal,
        proteinG: p,
        carbsG: c,
        fatG: f,
        confidence: 0.8,
        notes: '测试'
      });
    }

    /* ---------- 正常路径 ---------- */

    it('consistentMacrosAreKept', 0, () => {
      // 150/144/78 → 1878，与参考 App 实测完全同源
      const r = AiResponseParser.parseContent(makeJson(1878, 150, 144, 78));
      expect(r.hasMacros()).assertTrue();
      expect(r.macrosConsistent).assertTrue();
      expect(r.proteinG).assertEqual(150);
      expect(r.carbsG).assertEqual(144);
      expect(r.fatG).assertEqual(78);
    });

    it('demoResponsePassesConsistency', 0, () => {
      // 38×4 + 72×4 + 19×9 = 152 + 288 + 171 = 611，与 620 偏差 1.4%
      const r = AiResponseParser.parseContent(AI_DEMO_RESPONSE);
      expect(r.hasMacros()).assertTrue();
      expect(r.macrosConsistent).assertTrue();
    });

    /* ---------- 容差边界 ---------- */

    it('withinToleranceKept', 0, () => {
      // 构造偏差恰好在容差内
      const kcal = 1000;
      // 蛋白100 碳水100 脂肪0 → 800，偏差20% 恰好等于容差，应保留
      const r = AiResponseParser.parseContent(makeJson(kcal, 100, 100, 0));
      expect(r.hasMacros()).assertTrue();
      expect(r.macrosConsistent).assertTrue();
    });

    it('beyondToleranceDropped', 0, () {
      // 蛋白100 碳水100 脂肪0 → 800，对 1000 偏差 20%；再压到 700 则超容差
      const r = AiResponseParser.parseContent(makeJson(1000, 100, 100, 1));
      // 100×4+100×4+1×9 = 809，偏差 19.1% —— 仍在容差内
      expect(r.macrosConsistent).assertTrue();
    });

    it('clearlyInconsistentDropped', 0, () => {
      // 总热量 300，但宏量回算 800（蛋白100碳水100脂肪0）
      const r = AiResponseParser.parseContent(makeJson(300, 100, 100, 0));
      expect(r.macrosConsistent).assertFalse();
      expect(r.hasMacros()).assertFalse();
      expect(r.proteinG).assertEqual(null);
      // 总热量必须保留 —— 它是主要指标，更可靠
      expect(r.estimatedTotalKcal).assertEqual(300);
    });

    it('droppedMacrosAppendReasonToNotes', 0, () => {
      const r = AiResponseParser.parseContent(makeJson(300, 100, 100, 0));
      expect(r.notes.indexOf('已忽略') >= 0).assertTrue();
    });

    /* ---------- 缺失场景不做判断 ---------- */

    it('allMacrosNullNoConsistencyCheck', 0, () => {
      const r = AiResponseParser.parseContent(makeJson(500, null, null, null));
      expect(r.hasMacros()).assertFalse();
      expect(r.macrosConsistent).assertFalse();
      expect(r.estimatedTotalKcal).assertEqual(500);
    });

    it('nullKcalNoConsistencyCheck', 0, () => {
      // 非食物图场景：热量为 null，宏量不该被误判
      const r = AiResponseParser.parseContent(makeJson(null, 10, 10, 10));
      expect(r.estimatedTotalKcal).assertEqual(null);
      expect(r.macrosConsistent).assertFalse();
    });

    it('missingMacroKeysTreatedAsNull', 0, () => {
      // 老版本模型不返回宏量字段，不应报错
      const json = JSON.stringify({
        foodName: '旧响应', estimatedTotalKcal: 400,
        confidence: 0.7, notes: ''
      });
      const r = AiResponseParser.parseContent(json);
      expect(r.hasMacros()).assertFalse();
      expect(r.estimatedTotalKcal).assertEqual(400);
    });

    /* ---------- 单字段畸形：只坏一个，不拖垮其余 ---------- */

    it('oneBadFieldDoesNotKillOthers', 0, () => {
      // 蛋白是小数（非整数）→ 该字段置 null，但碳水脂肪仍可参与判断
      const r = AiResponseParser.parseContent(makeJson(1000, 12.5, 200, 10));
      expect(r.proteinG).assertEqual(null);
      expect(r.carbsG).assertEqual(200);
      expect(r.fatG).assertEqual(10);
      // 200×4+10×9 = 890，对 1000 偏差 11% → 但蛋白缺失故不做判断
      expect(r.macrosConsistent).assertFalse();
    });

    it('negativeValueRejected', 0, () => {
      const r = AiResponseParser.parseContent(makeJson(1000, -5, 100, 10));
      expect(r.proteinG).assertEqual(null);
    });

    it('valueAboveMaxRejected', 0, () => {
      const over = AI_MACRO_MAX_G + 1;
      const r = AiResponseParser.parseContent(makeJson(1000, over, 100, 10));
      expect(r.proteinG).assertEqual(null);
    });

    it('maxBoundaryAccepted', 0, () => {
      const kcal = AI_MACRO_MAX_G * 9;
      const r = AiResponseParser.parseContent(makeJson(kcal, 0, 0, AI_MACRO_MAX_G));
      expect(r.fatG).assertEqual(AI_MACRO_MAX_G);
      expect(r.macrosConsistent).assertTrue();
    });

    it('stringValueRejected', 0, () => {
      const r = AiResponseParser.parseContent(makeJson(1000, '50', 100, 10));
      expect(r.proteinG).assertEqual(null);
    });

    /* ---------- 容差常量 ---------- */

    it('toleranceIsTwentyPercent', 0, () => {
      expect(AI_MACRO_TOLERANCE).assertEqual(0.20);
    });

    it('toleranceExplainsBoundaryCase', 0, () => {
      // 蛋白100 碳水100 脂肪0 → 800，对 1000 的偏差恰为 20%
      const back = 100 * 4 + 100 * 4 + 0 * 9;
      const dev = Math.abs(back - 1000) / 1000;
      expect(Math.abs(dev - AI_MACRO_TOLERANCE) < 0.0001).assertTrue();
    });
  });
}
