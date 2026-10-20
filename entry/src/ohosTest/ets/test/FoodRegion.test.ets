/**
 * 食物位置（foodRegion）解析的单元测试。
 *
 * 跑的是**真实的生产代码** `services/AiResponseParser.ets`。
 *
 * 这个字段是「把食物抠成轮廓贴纸」的输入，解析必须**容错且不打断识别**：
 * 模型给不出坐标、给了越界坐标、给了 0~1 而不是 0~1000 的尺度，
 * 都不该让整次识别失败 —— 拿不到坐标时抠图会退到中心椭圆。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AiResponseParser } from '../../../main/ets/services/AiResponseParser';

/**
 * 拼一个最小可用的识别响应，只额外覆盖 foodBox / foodPolygon。
 *
 * 热量取 125 —— 与下面这组宏量自洽：10×4 + 10×4 + 5×9 = 125。
 * 故意对齐：Atwater 一致性校验容差是 ±20%，若总热量写成 100，
 * 回算 125 会偏差 25%，宏量会被**正确地**判为不自洽而丢弃，
 * 那就不是「位置字段不影响其它字段」了。
 */
function resp(extra: string): string {
  return '{"foodName":"测试食物","estimatedTotalKcal":125,"confidence":0.8,' +
    '"notes":"n","proteinG":10,"carbsG":10,"fatG":5' + extra + '}';
}

export default function foodRegionTest() {
  describe('FoodRegionTest', () => {

    it('外接框_0到1000尺度_换算成归一化', 0, () => {
      const r = AiResponseParser.parseContent(
        resp(',"foodBox":{"x":100,"y":200,"width":300,"height":400}')
      ).foodRegion;
      expect(r !== null).assertTrue();
      expect(r!.x).assertEqual(0.1);
      expect(r!.y).assertEqual(0.2);
      expect(r!.w).assertEqual(0.3);
      expect(r!.h).assertEqual(0.4);
    });

    it('外接框_0到1尺度_原样保留', 0, () => {
      const r = AiResponseParser.parseContent(
        resp(',"foodBox":{"x":0.1,"y":0.2,"width":0.3,"height":0.4}')
      ).foodRegion;
      expect(r !== null).assertTrue();
      expect(r!.x).assertEqual(0.1);
      expect(r!.w).assertEqual(0.3);
    });

    it('缺少位置字段_返回空_不打断识别', 0, () => {
      const result = AiResponseParser.parseContent(resp(''));
      expect(result.foodName).assertEqual('测试食物');
      expect(result.estimatedTotalKcal).assertEqual(125);
      expect(result.foodRegion === null).assertTrue();
    });

    it('位置字段为null_返回空', 0, () => {
      const r = AiResponseParser.parseContent(resp(',"foodBox":null')).foodRegion;
      expect(r === null).assertTrue();
    });

    it('宽高为零_视为无效_返回空', 0, () => {
      const r = AiResponseParser.parseContent(
        resp(',"foodBox":{"x":100,"y":100,"width":0,"height":400}')
      ).foodRegion;
      expect(r === null).assertTrue();
    });

    it('坐标越界_视为无效_返回空', 0, () => {
      const r = AiResponseParser.parseContent(
        resp(',"foodBox":{"x":-5,"y":100,"width":300,"height":400}')
      ).foodRegion;
      expect(r === null).assertTrue();
    });

    it('多边形_解析为扁平顶点数组', 0, () => {
      const r = AiResponseParser.parseContent(
        resp(',"foodBox":{"x":100,"y":100,"width":500,"height":500},' +
          '"foodPolygon":[[100,100],[600,120],[580,600],[120,580]]')
      ).foodRegion;
      expect(r !== null).assertTrue();
      expect(r!.hasPolygon()).assertTrue();
      expect(r!.polygon!.length).assertEqual(8);
      expect(r!.polygon![0]).assertEqual(0.1);
      expect(r!.polygon![2]).assertEqual(0.6);
    });

    it('多边形_少于三点_丢弃_退回外接框', 0, () => {
      const r = AiResponseParser.parseContent(
        resp(',"foodBox":{"x":100,"y":100,"width":500,"height":500},' +
          '"foodPolygon":[[100,100],[200,200]]')
      ).foodRegion;
      expect(r !== null).assertTrue();
      expect(r!.hasPolygon()).assertFalse();
    });

    it('只有多边形_用其包围盒补出外接框', 0, () => {
      const r = AiResponseParser.parseContent(
        resp(',"foodPolygon":[[100,200],[500,200],[500,800],[100,800]]')
      ).foodRegion;
      expect(r !== null).assertTrue();
      expect(r!.x).assertEqual(0.1);
      expect(r!.y).assertEqual(0.2);
      // 0.6 - 0.2 = 0.39999999999999997，浮点不能直接 assertEqual
      expect(Math.abs(r!.w - 0.4) < 1e-9).assertTrue();
      expect(Math.abs(r!.h - 0.6) < 1e-9).assertTrue();
    });

    it('多边形_含非法点_跳过该点_不整体丢弃', 0, () => {
      const r = AiResponseParser.parseContent(
        resp(',"foodBox":{"x":100,"y":100,"width":500,"height":500},' +
          '"foodPolygon":[[100,100],["bad",200],[600,120],[580,600],[120,580]]')
      ).foodRegion;
      expect(r !== null).assertTrue();
      expect(r!.hasPolygon()).assertTrue();
      // 5 个点里 1 个非法被跳过，剩 4 个点 = 8 个坐标
      expect(r!.polygon!.length).assertEqual(8);
    });

    it('位置字段不影响其它字段解析', 0, () => {
      const result = AiResponseParser.parseContent(
        resp(',"foodBox":{"x":100,"y":100,"width":500,"height":500}')
      );
      expect(result.foodName).assertEqual('测试食物');
      expect(result.proteinG).assertEqual(10);
      expect(result.macrosConsistent).assertTrue();
    });

  });
}
