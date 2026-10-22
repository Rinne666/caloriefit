/**
 * 端侧主体分割（CoreVisionKit）与内置矢量美食贴纸生成。
 *
 * 对应设计方案「难点一：食物抠图与模切白边贴纸」。
 *
 * ## 为什么上端侧分割
 * 现在的抠图链路是「AI 模型的粗轮廓 → 本地颜色模型在边界带内精修」。
 * 颜色模型解决的是「边缘吸附到真实图像边缘」，但解决不了
 * 「模型框的位置本身偏了」——先验错了，后面再怎么精修也是歪的。
 *
 * CoreVisionKit 的 `subjectSegmentation` 给出的是**整幅图的主体掩膜**
 * （0~255 的软掩膜 + 主体外接框），与具体某个食物无关。
 * 它在本项目里的角色是**给先验纠偏**：把模型给的粗轮廓和端侧主体掩膜求交，
 * 求交结果明显不合理时（重叠太少）就退回原轮廓，绝不因为端侧结果把主体抠空。
 *
 * ## 降级
 * 端侧分割依赖 `SystemCapability.AI.Vision.SubjectSegmentation`，
 * **模拟器上没有 NPU，必然不支持**；部分低端真机也不支持。
 * 所以这里是「有就用、没有就退回原来的颜色模型抠图」，功能不受影响。
 *
 * ## 关于模切白边的两种做法
 * 设计方案给的是「OffscreenCanvas 沿 16 个极坐标方向偏移绘制 → source-in 染白」。
 * 本项目对**真实照片**没有采用它，而是用 `StickerMatting.applyDieCutEdge`
 * （倒角距离变换），原因：
 *   · 16 向偏移得到的是「多边形外扩」，边是折线，转角处宽度不均；
 *   · 距离变换得到的是「沿真实轮廓等距外扩」，边宽处处一致且抗锯齿。
 * 两者白边宽度不可比时，画布上的观感差距很明显。
 *
 * 但 16 向偏移在**内置矢量贴纸**上仍然好用：矢量稿的 alpha 本身就是干净剪影，
 * 偏移并集得到的白边圆润均匀。所以 `bakeDieCutBorder` 保留下来，用在预设贴纸上。
 */

import { subjectSegmentation } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;
const TAG = 'StickerProcessor';

/** 端侧分割给出的主体掩膜 */
export class SubjectMask {
  /** 掩膜宽（像素），与输入图一致 */
  width: number = 0;
  /** 掩膜高（像素） */
  height: number = 0;
  /** 前景概率 0~255，长度 = width * height */
  values: Uint8Array = new Uint8Array(0);
  /** 主体包围盒 [x0, y0, x1, y1]（像素）；整幅都是背景时为 null */
  bbox: number[] | null = null;

  constructor(width: number, height: number, values: Uint8Array, bbox: number[] | null) {
    this.width = width;
    this.height = height;
    this.values = values;
    this.bbox = bbox;
  }

  /** 前景占比 0~1 */
  coverage(): number {
    if (this.values.length === 0) {
      return 0;
    }
    let count = 0;
    for (let i = 0; i < this.values.length; i++) {
      if (this.values[i] >= 128) {
        count++;
      }
    }
    return count / this.values.length;
  }
}

/** 内置矢量美食贴纸的种类 */
export enum PresetStickerKind {
  /** 生煎包 */
  PAN_FRIED_BUN = 0,
  /** 牛油果吐司 */
  AVOCADO_TOAST = 1,
  /** 冰美式 */
  ICED_AMERICANO = 2
}

export class StickerProcessor {
  /**
   * 端侧分割是否已确认不可用。
   *
   * 不可用时后续直接跳过，不再重复 init —— 每次抠图都白等一次引擎初始化
   * 是纯粹的浪费（模拟器上每次要几百毫秒）。
   */
  private static visionUnavailable: boolean = false;

  /**
   * 端侧主体分割。
   *
   * @param rgba 输入图像素（长度 = w*h*4，RGBA）
   * @param w 宽（像素）
   * @param h 高（像素）
   * @returns 掩膜；端侧不可用 / 调用失败时返回 null，调用方退回原抠图路径
   */
  static async segment(rgba: Uint8ClampedArray, w: number, h: number): Promise<SubjectMask | null> {
    if (StickerProcessor.visionUnavailable) {
      return null;
    }
    let pixelMap: image.PixelMap | null = null;
    let engineReady: boolean = false;
    try {
      pixelMap = await StickerProcessor.toPixelMap(rgba, w, h);
      const visionInfo: subjectSegmentation.VisionInfo = {
        pixelMap: pixelMap
      };
      // 只取掩膜，不要前景图：前景图和原始像素是同一张图，
      // 我们本来就有像素，多输出一份纯属浪费一次编解码。
      const config: subjectSegmentation.SegmentationConfig = {
        maxCount: 1,
        enableSubjectForegroundImage: false
      };
      const ok: boolean = await subjectSegmentation.init();
      if (!ok) {
        StickerProcessor.visionUnavailable = true;
        hilog.info(DOMAIN, TAG, 'subjectSegmentation.init returned false, vision disabled');
        return null;
      }
      engineReady = true;
      const result: subjectSegmentation.SegmentationResult =
        await subjectSegmentation.doSegmentation(visionInfo, config);
      const mask = StickerProcessor.toMask(result, w, h);
      hilog.info(DOMAIN, TAG, 'segment done, coverage=%{public}d', mask === null ? -1 : Math.round(mask.coverage() * 100));
      return mask;
    } catch (e) {
      const err = e as BusinessError;
      // 200 = 运行超时，属于偶发，不永久禁用；
      // 其余（设备不支持、引擎异常）一律当作「这台机器没有端侧分割」。
      if (err.code !== 200) {
        StickerProcessor.visionUnavailable = true;
      }
      hilog.warn(DOMAIN, TAG, 'segment failed code=%{public}d msg=%{public}s', err.code, err.message);
      return null;
    } finally {
      if (engineReady) {
        try {
          await subjectSegmentation.release();
        } catch (_e) {
          // 释放失败不影响结果
        }
      }
      if (pixelMap !== null) {
        pixelMap.release();
      }
    }
  }

  /** 当前设备是否还会尝试端侧分割（调试用） */
  static visionEnabled(): boolean {
    return !StickerProcessor.visionUnavailable;
  }

  /**
   * 把分割结果整理成掩膜。
   *
   * `mattingList` 文档写的是「与原图尺寸对应的 1 维数组」，但不同上游版本
   * 可能给 0~255 的概率，也可能给 0~1 的归一化值，长度也可能是 w*h 或 w*h*4。
   * 这里三种情况都兜住，兜不住就返回 null（调用方走原路径）。
   */
  private static toMask(result: subjectSegmentation.SegmentationResult,
    w: number, h: number): SubjectMask | null {
    const list = result.fullSubject.mattingList;
    const total = w * h;
    let stride = 1;
    if (list.length >= total * 4) {
      stride = 4;
    } else if (list.length < total) {
      return null;
    }
    let maxValue = 0;
    for (let i = 0; i < total; i++) {
      const v = list[i * stride];
      if (v > maxValue) {
        maxValue = v;
      }
    }
    // 归一化到 0~255
    const scale = maxValue <= 1 ? 255 : 1;
    const values = new Uint8Array(total);
    let x0 = w;
    let y0 = h;
    let x1 = -1;
    let y1 = -1;
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const i = y * w + x;
        let v = list[i * stride] * scale;
        if (v < 0) {
          v = 0;
        } else if (v > 255) {
          v = 255;
        }
        values[i] = v;
        if (v >= 128) {
          if (x < x0) {
            x0 = x;
          }
          if (x > x1) {
            x1 = x;
          }
          if (y < y0) {
            y0 = y;
          }
          if (y > y1) {
            y1 = y;
          }
        }
      }
    }
    const bbox = x1 < 0 ? null : [x0, y0, x1 + 1, y1 + 1];
    return new SubjectMask(w, h, values, bbox);
  }

  /** RGBA 像素 → PixelMap（RGBA_8888），端侧分割只认这个格式 */
  private static async toPixelMap(rgba: Uint8ClampedArray, w: number, h: number): Promise<image.PixelMap> {
    const byteLength = w * h * 4;
    const buffer = StickerProcessor.toArrayBuffer(rgba, byteLength);
    // 嵌套对象字面量要显式声明类型，否则 ArkTS 报 arkts-no-structural-typing
    const size: image.Size = { width: w, height: h };
    const options: image.InitializationOptions = {
      size: size,
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: false
    };
    return image.createPixelMapFromPixels(buffer, options);
  }

  /**
   * 取 RGBA 数据对应的 ArrayBuffer。
   *
   * 直接拷一份，理由有二：
   *   1. `createPixelMapFromPixels` 会严格校验 buffer 长度与 size 是否匹配，
   *      多一个字节都会抛 7600206；而 `Uint8ClampedArray.buffer` 的实际长度
   *      未必等于 w*h*4（可能是更大缓冲区的一个视图）。
   *   2. 少一次「判断再决定用不用原 buffer」的分支，代码更短。
   * 640×480 的 RGBA 是 1.2MB，一次拷贝几毫秒，相对端侧分割可以忽略。
   */
  private static toArrayBuffer(data: Uint8ClampedArray, byteLength: number): ArrayBuffer {
    const out: ArrayBuffer = new ArrayBuffer(byteLength);
    const view: Uint8Array = new Uint8Array(out);
    for (let i = 0; i < byteLength; i++) {
      view[i] = data[i];
    }
    return out;
  }

  /* ------------------------------------------------------------------ */
  /* 内置矢量美食贴纸                                                     */
  /* ------------------------------------------------------------------ */

  /**
   * 生成一张内置的矢量美食贴纸（透明背景 + 模切白边）。
   *
   * 用途：黑板首次打开时的示例节点。没有真实照片也能立刻体验
   * 拖拽 / 缩放 / 旋转 / 一键规整，不必先拍照。
   */
  static async presetSticker(kind: number, sidePx: number): Promise<image.PixelMap> {
    // 画布单位是 vp，像素是 vp × 密度。先把「想要多少像素」换算成画布尺寸。
    const vpPerPx: number = px2vp(1);
    const side: number = sidePx * vpPerPx;
    const canvas = new OffscreenCanvas(side, side);
    const ctx = canvas.getContext('2d');
    if (ctx === undefined || ctx === null) {
      throw new Error('presetSticker: no 2d context');
    }
    ctx.clearRect(0, 0, side, side);
    if (kind === PresetStickerKind.AVOCADO_TOAST) {
      StickerProcessor.drawAvocadoToast(ctx, side);
    } else if (kind === PresetStickerKind.ICED_AMERICANO) {
      StickerProcessor.drawIcedAmericano(ctx, side);
    } else {
      StickerProcessor.drawPanFriedBun(ctx, side);
    }
    // 模切白边：16 向极坐标偏移 → source-in 染白 → 垫在原画下面
    return StickerProcessor.bakeDieCutBorder(canvas, side, 6 * vpPerPx);
  }

  /** 内置贴纸直接转成 ArkUI Image 能吃的 base64 data URI */
  static async presetStickerDataUri(kind: number, sidePx: number): Promise<string> {
    const pixelMap = await StickerProcessor.presetSticker(kind, sidePx);
    try {
      const packer = image.createImagePacker();
      try {
        const opts: image.PackingOption = { format: 'image/png', quality: 100 };
        const packed = await packer.packToData(pixelMap, opts);
        return StickerProcessor.toDataUri(packed);
      } finally {
        packer.release();
      }
    } finally {
      pixelMap.release();
    }
  }

  /**
   * 模切白边合成（设计方案里的 16 向极坐标偏移法）。
   *
   * 步骤：
   *   1. 把原画沿 16 个极坐标方向各偏移一次 → 得到偏移并集；
   *   2. `source-in` + 填充纯白 → 并集被染成白色剪影；
   *   3. 最终画布先画白色剪影、再画原画 → 原画周围留出一圈白纸边。
   *
   * 注意：`OffscreenCanvas` 上没有 `getPixelMap`，取内容要用
   * `transferToImageBitmap()`；`getPixelMap` 是 **2D 上下文** 上的方法。
   */
  static async bakeDieCutBorder(source: OffscreenCanvas, side: number, borderVp: number): Promise<image.PixelMap> {
    const settings = new RenderingContextSettings(true);
    const art: ImageBitmap = source.transferToImageBitmap();

    const silhouette = new OffscreenCanvas(side, side);
    const sctx = silhouette.getContext('2d', settings);
    if (sctx === undefined || sctx === null) {
      art.close();
      throw new Error('bakeDieCutBorder: no 2d context');
    }
    const steps = 16;
    for (let i = 0; i < steps; i++) {
      const angle: number = (i * 2 * Math.PI) / steps;
      const dx: number = Math.cos(angle) * borderVp;
      const dy: number = Math.sin(angle) * borderVp;
      sctx.drawImage(art, dx, dy, side, side);
    }
    sctx.globalCompositeOperation = 'source-in';
    sctx.fillStyle = '#FFFFFF';
    sctx.fillRect(0, 0, side, side);
    const silhouetteBitmap: ImageBitmap = silhouette.transferToImageBitmap();

    const out = new OffscreenCanvas(side, side);
    const octx = out.getContext('2d', settings);
    if (octx === undefined || octx === null) {
      art.close();
      silhouetteBitmap.close();
      throw new Error('bakeDieCutBorder: no output context');
    }
    octx.globalCompositeOperation = 'source-over';
    octx.drawImage(silhouetteBitmap, 0, 0, side, side);
    octx.drawImage(art, 0, 0, side, side);
    const result: image.PixelMap = octx.getPixelMap(0, 0, side, side);

    art.close();
    silhouetteBitmap.close();
    return result;
  }

  /* --------------------------- 矢量绘制 ------------------------------- */

  /**
   * 画椭圆。
   *
   * 两个坑叠在一起，所以干脆绕开：
   *   ① ArkUI 的 2D 上下文虽然声明了 `ellipse()` / `roundRect()`，
   *      但运行时的实现与声明不完全一致，踩到就是「方法不存在」直接抛异常；
   *   ② 用 `scale` + `arc` 凑椭圆也不行 —— ArkUI 的路径实现不保证
   *      「加点时按当时的变换存坐标」，还原变换后再 fill 会画到错的位置
   *      （实测生煎包画出来是左上角一块扇形）。
   * 所以这里直接用 48 段折线逼近椭圆：只用 moveTo/lineTo/closePath，
   * 所有实现都支持，48 段在 256px 下看不出棱角。
   */
  private static ellipse(ctx: OffscreenCanvasRenderingContext2D,
    cx: number, cy: number, rx: number, ry: number): void {
    // beginPath 不能省：省了路径会跨次累积，
    // 而 ArkUI 是在**填充时**才把当前变换套到路径点上，
    // 于是上一轮（在别的变换下加的）点会被二次变换甩到别处 ——
    // 实测牛油果吐司的第三片牛油果飞到了吐司外面。
    ctx.beginPath();
    const steps = 48;
    for (let i = 0; i <= steps; i++) {
      const a = (i / steps) * Math.PI * 2;
      const x = cx + Math.cos(a) * rx;
      const y = cy + Math.sin(a) * ry;
      if (i === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.closePath();
  }

  /** 画圆角矩形（同样避开 roundRect） */
  private static roundRectPath(ctx: OffscreenCanvasRenderingContext2D,
    x: number, y: number, w: number, h: number, r: number): void {
    const radius = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + radius, y);
    ctx.lineTo(x + w - radius, y);
    ctx.arc(x + w - radius, y + radius, radius, -Math.PI / 2, 0);
    ctx.lineTo(x + w, y + h - radius);
    ctx.arc(x + w - radius, y + h - radius, radius, 0, Math.PI / 2);
    ctx.lineTo(x + radius, y + h);
    ctx.arc(x + radius, y + h - radius, radius, Math.PI / 2, Math.PI);
    ctx.lineTo(x, y + radius);
    ctx.arc(x + radius, y + radius, radius, Math.PI, Math.PI * 1.5);
    ctx.closePath();
  }

  /** 生煎包：底部焦脆金黄，顶部白胖带褶 */
  private static drawPanFriedBun(ctx: OffscreenCanvasRenderingContext2D, s: number): void {
    const cx = s * 0.5;
    const cy = s * 0.55;
    const rx = s * 0.34;
    const ry = s * 0.29;

    // 落地阴影
    ctx.save();
    ctx.fillStyle = 'rgba(60, 40, 20, 0.16)';
    StickerProcessor.ellipse(ctx, cx, cy + ry * 0.86, rx * 0.95, ry * 0.20);
    ctx.fill();
    ctx.restore();

    // 面皮主体
    ctx.save();
    StickerProcessor.ellipse(ctx, cx, cy, rx, ry);
    ctx.fillStyle = '#F7E6C6';
    ctx.fill();
    ctx.clip();
    // 底部脆底
    const crust = ctx.createLinearGradient(0, cy, 0, cy + ry);
    crust.addColorStop(0, 'rgba(206, 141, 66, 0)');
    crust.addColorStop(0.45, '#CE8D42');
    crust.addColorStop(1, '#B9722C');
    ctx.fillStyle = crust;
    ctx.fillRect(cx - rx, cy - ry * 0.2, rx * 2, ry * 1.4);
    // 脆底上的煎纹
    ctx.strokeStyle = 'rgba(120, 70, 24, 0.28)';
    ctx.lineWidth = s * 0.012;
    for (let i = 0; i < 5; i++) {
      const y = cy + ry * (0.28 + i * 0.14);
      ctx.beginPath();
      ctx.moveTo(cx - rx * 0.9, y);
      ctx.lineTo(cx + rx * 0.9, y - ry * 0.06);
      ctx.stroke();
    }
    ctx.restore();

    // 顶部收口褶
    ctx.save();
    ctx.strokeStyle = '#E2C79B';
    ctx.lineWidth = s * 0.022;
    ctx.lineCap = 'round';
    for (let i = 0; i < 5; i++) {
      const t = (i - 2) * 0.26;
      ctx.beginPath();
      ctx.moveTo(cx + rx * t * 0.25, cy - ry * 0.86);
      ctx.quadraticCurveTo(cx + rx * t * 0.55, cy - ry * 0.42, cx + rx * t, cy + ry * 0.06);
      ctx.stroke();
    }
    ctx.restore();

    // 高光
    ctx.save();
    ctx.fillStyle = 'rgba(255, 255, 255, 0.55)';
    StickerProcessor.ellipse(ctx, cx - rx * 0.34, cy - ry * 0.52, rx * 0.22, ry * 0.12);
    ctx.fill();
    ctx.restore();
  }

  /** 牛油果滑蛋吐司 */
  private static drawAvocadoToast(ctx: OffscreenCanvasRenderingContext2D, s: number): void {
    const x = s * 0.24;
    const y = s * 0.26;
    const w = s * 0.52;
    const h = s * 0.5;

    ctx.save();
    ctx.fillStyle = 'rgba(60, 40, 20, 0.16)';
    StickerProcessor.ellipse(ctx, s * 0.5, y + h + s * 0.02, w * 0.46, s * 0.045);
    ctx.fill();
    ctx.restore();

    // 吐司外壳
    ctx.save();
    StickerProcessor.roundRectPath(ctx, x, y, w, h, s * 0.055);
    ctx.fillStyle = '#C98B4B';
    ctx.fill();
    ctx.clip();
    // 内瓤
    StickerProcessor.roundRectPath(ctx, x + s * 0.035, y + s * 0.035, w - s * 0.07, h - s * 0.07, s * 0.04);
    ctx.fillStyle = '#F4E3C0';
    ctx.fill();
    ctx.restore();

    // 牛油果扇形片
    const avColors: string[] = ['#8CC463', '#79B455', '#6BA249'];
    for (let i = 0; i < 3; i++) {
      ctx.save();
      ctx.translate(x + w * (0.22 + i * 0.17), y + h * 0.46);
      ctx.rotate(-0.5 + i * 0.12);
      StickerProcessor.ellipse(ctx, 0, 0, w * 0.13, h * 0.19);
      ctx.fillStyle = avColors[i];
      ctx.fill();
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.55)';
      ctx.lineWidth = s * 0.008;
      ctx.stroke();
      ctx.restore();
    }

    // 溏心蛋
    ctx.save();
    ctx.beginPath();
    ctx.arc(x + w * 0.74, y + h * 0.34, s * 0.105, 0, Math.PI * 2);
    ctx.fillStyle = '#FFFBF2';
    ctx.fill();
    ctx.beginPath();
    ctx.arc(x + w * 0.74, y + h * 0.34, s * 0.052, 0, Math.PI * 2);
    ctx.fillStyle = '#F0B93F';
    ctx.fill();
    ctx.restore();

    // 黑胡椒
    ctx.save();
    ctx.fillStyle = 'rgba(50, 35, 20, 0.7)';
    for (let i = 0; i < 7; i++) {
      const a = i * 1.31;
      const r = s * 0.09;
      ctx.beginPath();
      ctx.arc(x + w * 0.74 + Math.cos(a) * r, y + h * 0.34 + Math.sin(a) * r, s * 0.006, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  /** 冰美式 */
  private static drawIcedAmericano(ctx: OffscreenCanvasRenderingContext2D, s: number): void {
    const x = s * 0.34;
    const y = s * 0.18;
    const w = s * 0.32;
    const h = s * 0.66;

    // 杯体
    ctx.save();
    StickerProcessor.roundRectPath(ctx, x, y, w, h, s * 0.035);
    ctx.fillStyle = 'rgba(255, 255, 255, 0.16)';
    ctx.fill();
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.78)';
    ctx.lineWidth = s * 0.016;
    ctx.stroke();
    ctx.clip();
    // 咖啡
    const coffee = ctx.createLinearGradient(0, y + h * 0.28, 0, y + h);
    coffee.addColorStop(0, '#6B3F24');
    coffee.addColorStop(1, '#3B2114');
    ctx.fillStyle = coffee;
    ctx.fillRect(x, y + h * 0.28, w, h);
    // 冰块
    ctx.fillStyle = 'rgba(255, 255, 255, 0.30)';
    ctx.save();
    ctx.translate(x + w * 0.32, y + h * 0.42);
    ctx.rotate(0.35);
    ctx.fillRect(-s * 0.05, -s * 0.05, s * 0.1, s * 0.1);
    ctx.restore();
    ctx.save();
    ctx.translate(x + w * 0.68, y + h * 0.55);
    ctx.rotate(-0.25);
    ctx.fillRect(-s * 0.045, -s * 0.045, s * 0.09, s * 0.09);
    ctx.restore();
    // 顶层奶泡
    ctx.fillStyle = '#B27A46';
    ctx.fillRect(x, y + h * 0.28, w, s * 0.03);
    ctx.restore();

    // 吸管
    ctx.save();
    ctx.translate(x + w * 0.58, y + h * 0.12);
    ctx.rotate(0.22);
    StickerProcessor.roundRectPath(ctx, -s * 0.022, -s * 0.22, s * 0.044, s * 0.42, s * 0.022);
    ctx.fillStyle = '#E8556D';
    ctx.fill();
    ctx.restore();

    // 杯口高光
    ctx.save();
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.85)';
    ctx.lineWidth = s * 0.018;
    StickerProcessor.roundRectPath(ctx, x, y, w, h, s * 0.035);
    ctx.stroke();
    ctx.restore();
  }

  /**
   * 字节数组 → base64 data URI。
   *
   * 刻意不 import StickerCutoutService 来复用它那一份：
   * StickerCutoutService 要 import 本文件（端侧分割主路径），
   * 再互相 import 就成了循环依赖。这里各写一份 base64 转换，
   * 代价只有三行，换来模块边界干净。
   */
  private static toDataUri(pngBuffer: ArrayBuffer): string {
    const helper = new util.Base64Helper();
    const b64 = helper.encodeToStringSync(new Uint8Array(pngBuffer));
    return `data:image/png;base64,${b64}`;
  }
}
