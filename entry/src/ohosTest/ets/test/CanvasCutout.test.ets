/**
 * 食物抠图的**像素级**单元测试。
 *
 * 跑的是真实的生产代码 `services/StickerCutoutService.ets`。
 *
 * 为什么必须做像素级断言：
 *   抠图前两版（Canvas 合成模式 destination-out / destination-in）在设备上
 *   **看起来都跑通了** —— 尺寸对、贴纸生成了、UI 树里也有 Image 节点，
 *   但肉眼看截图才发现：贴纸里还是完整原图，背景根本没被抠掉。
 *   也就是说「流程跑通」不等于「效果正确」，只有直接读 alpha 通道才能判定。
 *
 * 当前实现的产出约定：
 *   · alpha 遮罩把「食物区域」外置为透明
 *   · 之后裁到实际不透明区域的包围盒，所以输出尺寸 = 保留区域尺寸（不是原图尺寸）
 *   · 外接框走**圆角矩形**（四角透明，贴纸感），多边形走真实轮廓
 */

import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { image } from '@kit.ImageKit';
import { StickerCutoutService } from '../../../main/ets/services/StickerCutoutService';
import { FoodRegion } from '../../../main/ets/models/FoodSticker';

/** 读出整张图的 alpha 通道（RGBA / BGRA 的 alpha 都在第 4 字节） */
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

function at(alpha: Uint8Array, w: number, x: number, y: number): number {
  return alpha[y * w + x];
}

async function loadSample(): Promise<image.PixelMap> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  const ctx = delegator.getAppContext().getApplicationContext();
  const bytes = await ctx.resourceManager.getRawFileContent('sample_meal.jpg');
  const buf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  const source = image.createImageSource(buf);
  return source.createPixelMap();
}

export default function canvasCutoutTest() {
  describe('CanvasCutoutTest', () => {

    it('外接框_裁剪到保留区域尺寸', 0, async () => {
      const src = await loadSample();
      try {
        const info = await src.getImageInfo();
        const region = new FoodRegion(0, 0, 0.5, 1, null);
        const out = await StickerCutoutService.cutout(src, region);
        try {
          const outInfo = await out.getImageInfo();
          // 输出应是保留区域的大小，而不是原图大小
          expect(Math.abs(outInfo.size.width - info.size.width * 0.5) < 6).assertTrue();
          expect(Math.abs(outInfo.size.height - info.size.height) < 6).assertTrue();
        } finally {
          out.release();
        }
      } finally {
        src.release();
      }
    });

    it('外接框_圆角透明_中心不透明', 0, async () => {
      const src = await loadSample();
      try {
        const region = new FoodRegion(0.25, 0.25, 0.5, 0.5, null);
        const out = await StickerCutoutService.cutout(src, region);
        try {
          const info = await out.getImageInfo();
          const alpha = await alphaMap(out);
          const w = info.size.width;
          const h = info.size.height;
          // 圆角：左上角被挖空
          expect(at(alpha, w, 1, 1) < 50).assertTrue();
          // 中心保留
          expect(at(alpha, w, Math.floor(w / 2), Math.floor(h / 2)) > 200).assertTrue();
        } finally {
          out.release();
        }
      } finally {
        src.release();
      }
    });

    it('多边形_内部不透明_尺寸贴合轮廓', 0, async () => {
      const src = await loadSample();
      try {
        const info = await src.getImageInfo();
        // 中心一个小方块
        const poly: number[] = [0.4, 0.4, 0.6, 0.4, 0.6, 0.6, 0.4, 0.6];
        const region = new FoodRegion(0.4, 0.4, 0.2, 0.2, poly);
        const out = await StickerCutoutService.cutout(src, region);
        try {
          const outInfo = await out.getImageInfo();
          const alpha = await alphaMap(out);
          const w = outInfo.size.width;
          const h = outInfo.size.height;
          // 输出贴合多边形范围，而不是原图
          expect(Math.abs(w - info.size.width * 0.2) < 6).assertTrue();
          expect(Math.abs(h - info.size.height * 0.2) < 6).assertTrue();
          // 多边形内部不透明
          expect(at(alpha, w, Math.floor(w / 2), Math.floor(h / 2)) > 200).assertTrue();
        } finally {
          out.release();
        }
      } finally {
        src.release();
      }
    });

    it('无坐标降级_中心保留_四周透明', 0, async () => {
      const src = await loadSample();
      try {
        const out = await StickerCutoutService.cutout(src, null);
        try {
          const info = await out.getImageInfo();
          const alpha = await alphaMap(out);
          const w = info.size.width;
          const h = info.size.height;
          expect(at(alpha, w, Math.floor(w / 2), Math.floor(h / 2)) > 200).assertTrue();
          // 椭圆降级下，包围盒的角上必然是透明的
          expect(at(alpha, w, 1, 1) < 50).assertTrue();
        } finally {
          out.release();
        }
      } finally {
        src.release();
      }
    });

  });
}
