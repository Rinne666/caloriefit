/**
 * 黑板自由画布的单元测试。
 *
 * 跑的是真实的生产代码：
 *   · `services/StickerMatting.ets` 的掩膜先验合成
 *   · `services/StickerProcessor.ets` 的端侧分割封装与内置矢量贴纸
 *   · `repositories/BoardRepository.ets` 的黑板节点落库与复制
 *   · `models/BoardModels.ets` 的模型与配色
 *
 * 为什么这几条必须单测：
 *   ① 端侧掩膜与模型轮廓「求交」是这轮新加的逻辑，
 *      判错的后果是**把食物整个抠空**（画面上只剩一块白纸），
 *      这种失败在截图上一眼能看出，但在数据上很难察觉。
 *   ② 贴纸的白边是「沿轮廓等距外扩」，
 *      宽度不均或压根没画出来，肉眼和 UI 树都看不出来，只能读像素。
 *   ③ 黑板节点的空间状态（位置/缩放/旋转/层级）要能落库再读回来，
 *      否则用户摆好的板子第二天就乱了。
 */

import { describe, it, expect, beforeAll } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { image } from '@kit.ImageKit';
import { Database } from '../../../main/ets/database/Database';
import { BoardRepository } from '../../../main/ets/repositories/BoardRepository';
import {
  BoardNodeModel,
  BoardNodeType,
  BoardThemeType,
  PinDecorationType,
  StickyPaperStyle,
  boardThemeColors,
  nodeTilt,
  paperColors
} from '../../../main/ets/models/BoardModels';
import { StickerMatting } from '../../../main/ets/services/StickerMatting';
import { PresetStickerKind, StickerProcessor } from '../../../main/ets/services/StickerProcessor';
import { FoodRegion } from '../../../main/ets/models/FoodSticker';

/** 单测专用日期，避免碰到真实数据 */
const TEST_DATE: string = '2026-03-20';

/** 读出整张图的 alpha 通道 */
async function alphaMap(pm: image.PixelMap): Promise<Uint8Array> {
  const info = await pm.getImageInfo();
  const w = info.size.width;
  const h = info.size.height;
  const buf = new ArrayBuffer(w * h * 4);
  await pm.readPixelsToBuffer(buf);
  const u8 = new Uint8Array(buf);
  const alpha = new Uint8Array(w * h);
  for (let i = 0, j = 3; i < alpha.length; i++, j += 4) {
    alpha[i] = u8[j];
  }
  return alpha;
}

/** 读出整张图的 RGB */
async function rgbMap(pm: image.PixelMap): Promise<Uint8Array> {
  const info = await pm.getImageInfo();
  const w = info.size.width;
  const h = info.size.height;
  const buf = new ArrayBuffer(w * h * 4);
  await pm.readPixelsToBuffer(buf);
  const u8 = new Uint8Array(buf);
  const rgb = new Uint8Array(w * h * 3);
  for (let i = 0, j = 0, k = 0; i < w * h; i++, j += 4, k += 3) {
    rgb[k] = u8[j];
    rgb[k + 1] = u8[j + 1];
    rgb[k + 2] = u8[j + 2];
  }
  return rgb;
}

/** 统计不透明像素数 */
function opaqueCount(alpha: Uint8Array): number {
  let n = 0;
  for (let i = 0; i < alpha.length; i++) {
    if (alpha[i] > 200) {
      n++;
    }
  }
  return n;
}

export default function boardCanvasTest() {
  describe('BoardCanvasTest', () => {
    beforeAll(() => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const ctx = delegator.getAppContext().getApplicationContext();
      Database.ensure(ctx);
    });

    /* ---------------- 端侧掩膜与模型轮廓的合成 ---------------- */

    it('掩膜为null时先验等于纯模型先验', 0, () => {
      const w = 40;
      const h = 40;
      const region = new FoodRegion(0.25, 0.25, 0.5, 0.5, null);
      const a = StickerMatting.buildPrior(w, h, region);
      const b = StickerMatting.buildPriorWithMask(w, h, region, null, 128);
      let same = true;
      for (let i = 0; i < w * h; i++) {
        if (a[i] !== b[i]) {
          same = false;
          break;
        }
      }
      expect(same).assertTrue();
    });

    it('掩膜与模型轮廓一致时先验取交集', 0, () => {
      const w = 40;
      const h = 40;
      const region = new FoodRegion(0.25, 0.25, 0.5, 0.5, null);
      const base = StickerMatting.buildPrior(w, h, region);
      // 掩膜 = 模型先验的一半
      const mask = new Uint8Array(w * h);
      for (let i = 0; i < w * h; i++) {
        if (base[i] > 0 && i % 2 === 0) {
          mask[i] = 255;
        }
      }
      const merged = StickerMatting.buildPriorWithMask(w, h, region, mask, 128);
      let interCount = 0;
      for (let i = 0; i < w * h; i++) {
        if (merged[i] > 0) {
          interCount++;
          // 交集必须同时属于模型先验和掩膜
          expect(base[i] > 0).assertTrue();
          expect(mask[i] >= 128).assertTrue();
        }
      }
      // 交集应严格小于原轮廓（说明确实做了求交，而不是原样返回）
      let baseCount = 0;
      for (let i = 0; i < w * h; i++) {
        if (base[i] > 0) {
          baseCount++;
        }
      }
      expect(interCount > 0).assertTrue();
      expect(interCount < baseCount).assertTrue();
    });

    it('掩膜与模型轮廓完全不符时退回模型先验_不抠空', 0, () => {
      const w = 40;
      const h = 40;
      const region = new FoodRegion(0.0, 0.0, 0.3, 0.3, null);
      const base = StickerMatting.buildPrior(w, h, region);
      // 掩膜打在右下角，与模型轮廓毫无重叠
      const mask = new Uint8Array(w * h);
      for (let y = 30; y < 40; y++) {
        for (let x = 30; x < 40; x++) {
          mask[y * w + x] = 255;
        }
      }
      const merged = StickerMatting.buildPriorWithMask(w, h, region, mask, 128);
      let same = true;
      let count = 0;
      for (let i = 0; i < w * h; i++) {
        if (merged[i] > 0) {
          count++;
        }
        if (merged[i] !== base[i]) {
          same = false;
        }
      }
      expect(same).assertTrue();
      // 关键：先验不能被清空，否则抠图会抠出空白贴纸
      expect(count > 0).assertTrue();
    });

    it('掩膜几乎全空时退回模型先验', 0, () => {
      const w = 40;
      const h = 40;
      const region = new FoodRegion(0.25, 0.25, 0.5, 0.5, null);
      const base = StickerMatting.buildPrior(w, h, region);
      const mask = new Uint8Array(w * h);
      mask[0] = 255;
      const merged = StickerMatting.buildPriorWithMask(w, h, region, mask, 128);
      let same = true;
      for (let i = 0; i < w * h; i++) {
        if (merged[i] !== base[i]) {
          same = false;
        }
      }
      expect(same).assertTrue();
    });

    /* ---------------- 端侧分割的降级行为 ---------------- */

    it('端侧分割不可用时返回null而不是抛错', 0, async () => {
      // 模拟器没有 NPU，必然不支持主体分割。
      // 契约是：返回 null（调用方退回纯模型抠图），**不能抛异常打断识别流程**。
      const rgba = new Uint8ClampedArray(16 * 16 * 4);
      for (let i = 0; i < rgba.length; i += 4) {
        rgba[i] = 200;
        rgba[i + 1] = 100;
        rgba[i + 2] = 50;
        rgba[i + 3] = 255;
      }
      let result: Object | null = null;
      let threw = false;
      try {
        result = await StickerProcessor.segment(rgba, 16, 16);
      } catch (_e) {
        threw = true;
      }
      expect(threw).assertFalse();
      expect(result === null).assertTrue();
    });

    /* ---------------- 模型与配色 ---------------- */

    it('节点倾角由种子派生且稳定', 0, () => {
      const a = nodeTilt(7);
      const b = nodeTilt(7);
      expect(a).assertEqual(b);
      expect(a >= -2 && a <= 2).assertTrue();
    });

    it('便签配色与主题配色各自成套', 0, () => {
      const yellow = paperColors(StickyPaperStyle.CREAM_YELLOW);
      const mint = paperColors(StickyPaperStyle.MINT_GREEN);
      const kraft = paperColors(StickyPaperStyle.KRAFT_PAPER);
      expect(yellow.length).assertEqual(2);
      expect(yellow[0] !== mint[0]).assertTrue();
      expect(mint[0] !== kraft[0]).assertTrue();

      const chalk = boardThemeColors(BoardThemeType.CHALKBOARD);
      const cork = boardThemeColors(BoardThemeType.CORKBOARD);
      const dot = boardThemeColors(BoardThemeType.DOT_JOURNAL);
      expect(chalk.board !== cork.board).assertTrue();
      expect(cork.board !== dot.board).assertTrue();
      // 深色黑板的正文要是浅色，否则字看不见
      expect(chalk.text === '#F4F1E4').assertTrue();
    });

    /* ---------------- 黑板节点落库 ---------------- */

    it('便签节点落库后能原样读回', 0, async () => {
      await BoardRepository.clearByDate(TEST_DATE);
      const node = new BoardNodeModel();
      node.date = TEST_DATE;
      node.nodeType = BoardNodeType.STICKY_NOTE;
      node.foodId = null;
      node.title = '单元测试便签';
      node.calories = 321;
      node.moodEmoji = '🥳';
      node.companionText = '测试搭子';
      node.memoText = '这是一条碎碎念';
      node.x = 42;
      node.y = 77;
      node.scale = 1.35;
      node.rotation = 12;
      node.zIndex = 5;
      node.paperStyle = StickyPaperStyle.MINT_GREEN;
      node.pinType = PinDecorationType.RED_THUMB_TACK;
      const id = await BoardRepository.upsert(node);
      expect(id > 0).assertTrue();

      const nodes = await BoardRepository.getNodes(TEST_DATE);
      let found: BoardNodeModel | null = null;
      for (let i = 0; i < nodes.length; i++) {
        if (nodes[i].id === id) {
          found = nodes[i];
        }
      }
      expect(found !== null).assertTrue();
      const n = found as BoardNodeModel;
      expect(n.title).assertEqual('单元测试便签');
      expect(n.calories).assertEqual(321);
      expect(n.moodEmoji).assertEqual('🥳');
      expect(n.companionText).assertEqual('测试搭子');
      expect(n.memoText).assertEqual('这是一条碎碎念');
      expect(Math.round(n.x)).assertEqual(42);
      expect(Math.round(n.y)).assertEqual(77);
      expect(Math.round(n.scale * 100) / 100).assertEqual(1.35);
      expect(Math.round(n.rotation)).assertEqual(12);
      expect(n.zIndex).assertEqual(5);
      expect(n.paperStyle).assertEqual(StickyPaperStyle.MINT_GREEN);
      expect(n.pinType).assertEqual(PinDecorationType.RED_THUMB_TACK);
    });

    it('便签节点可以复制到指定日期', 0, async () => {
      await BoardRepository.clearByDate(TEST_DATE);
      const node = new BoardNodeModel();
      node.date = TEST_DATE;
      node.nodeType = BoardNodeType.STICKY_NOTE;
      node.foodId = null;
      node.title = '要被复制的便签';
      node.x = 10;
      node.y = 20;
      const id = await BoardRepository.upsert(node);

      const target = '2026-03-21';
      await BoardRepository.clearByDate(target);
      const newId = await BoardRepository.copyToDate(node, target);
      expect(newId > 0).assertTrue();
      expect(newId === id).assertFalse();

      const copied = await BoardRepository.getNodes(target);
      let hit: BoardNodeModel | null = null;
      for (let i = 0; i < copied.length; i++) {
        if (copied[i].id === newId) {
          hit = copied[i];
        }
      }
      expect(hit !== null).assertTrue();
      const c = hit as BoardNodeModel;
      expect(c.title).assertEqual('要被复制的便签');
      expect(c.date).assertEqual(target);
      await BoardRepository.clearByDate(target);
      await BoardRepository.clearByDate(TEST_DATE);
    });

    /* ---------------- 内置矢量美食贴纸 ---------------- */

    it('内置贴纸有内容_背景透明_带白色模切边', 0, async () => {
      const pm = await StickerProcessor.presetSticker(PresetStickerKind.PAN_FRIED_BUN, 256);
      try {
        const info = await pm.getImageInfo();
        const w = info.size.width;
        const h = info.size.height;
        expect(w > 0 && h > 0).assertTrue();
        const alpha = await alphaMap(pm);
        const rgb = await rgbMap(pm);

        // ① 有实际内容
        expect(opaqueCount(alpha) > 500).assertTrue();

        // ② 四角透明（背景是真透明的，不是白底）
        expect(alpha[0] < 20).assertTrue();
        expect(alpha[w - 1] < 20).assertTrue();
        expect(alpha[(h - 1) * w] < 20).assertTrue();
        expect(alpha[h * w - 1] < 20).assertTrue();

        // ③ 存在贴着轮廓的白色纸边：
        //    近白且不透明的像素，必须紧挨着透明像素
        let borderPixels = 0;
        for (let y = 1; y < h - 1; y++) {
          for (let x = 1; x < w - 1; x++) {
            const i = y * w + x;
            if (alpha[i] <= 200) {
              continue;
            }
            const p = i * 3;
            const nearWhite = rgb[p] > 230 && rgb[p + 1] > 230 && rgb[p + 2] > 230;
            if (!nearWhite) {
              continue;
            }
            const touchesOutside = alpha[i - 1] < 40 || alpha[i + 1] < 40 ||
              alpha[i - w] < 40 || alpha[i + w] < 40;
            if (touchesOutside) {
              borderPixels++;
            }
          }
        }
        expect(borderPixels > 50).assertTrue();
      } finally {
        pm.release();
      }
    });

    it('三种内置贴纸都能生成且互不相同', 0, async () => {
      const kinds: PresetStickerKind[] = [
        PresetStickerKind.PAN_FRIED_BUN,
        PresetStickerKind.AVOCADO_TOAST,
        PresetStickerKind.ICED_AMERICANO
      ];
      const sizes: number[] = [];
      for (let i = 0; i < kinds.length; i++) {
        const pm = await StickerProcessor.presetSticker(kinds[i], 256);
        try {
          const alpha = await alphaMap(pm);
          sizes.push(opaqueCount(alpha));
          expect(opaqueCount(alpha) > 500).assertTrue();
        } finally {
          pm.release();
        }
      }
      // 生煎包 / 吐司 / 咖啡的覆盖面积不应该完全一样
      expect(sizes[0] === sizes[1]).assertFalse();
      expect(sizes[1] === sizes[2]).assertFalse();
    });
  });
}
