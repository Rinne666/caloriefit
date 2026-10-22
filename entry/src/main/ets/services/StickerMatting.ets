/**
 * 食物抠图（matting）：把「食物」从照片里真正分离出来，做成 nosh 那种**模切贴纸**。
 *
 * 为什么不能直接拿模型的多边形当遮罩：
 *   多边形是模型用十几个顶点描述的**粗略轮廓**，直接填出来得到的是「按轮廓裁了一块照片」——
 *   盘沿、桌布、餐具还留在里面，边缘是折线，整体看起来就是一张普通缩略图，
 *   而不是 nosh 那种「食物被抠出来、浮在便签上」的剪贴贴纸。
 *
 * 这里的做法是「先验 + 边缘精修」：
 *   1. **先验**：模型给了轮廓就用轮廓，只有外接框就用圆角框，都没有就用中心椭圆
 *      （这三种降级路径和原来一致，保证没坐标时仍能出图）；
 *   2. **边界带**：用倒角距离变换求出「离先验边界 bandPx 以内」的像素；
 *   3. **颜色模型**：带内深处的像素当下��样本，带外的像素当背景样本，
 *      各建一份量化 RGB 直方图（5bit/通道）；
 *   4. **逐像素判别**：在边界带内算前景/背景的对数似然比，映射成前景概率；
 *   5. **联合双边滤波**：以原图为引导做 5×5 平滑，让边界吸附到真实的图像边缘上；
 *   6. **合成 alpha**：带内用 smoothstep(概率)，带外一律透明 —— 边界因此有抗锯齿。
 *
 * 为什么只在**边界带**里判别、不做全图迭代：
 *   试过 GrabCut 式的多轮迭代（全图重估颜色模型），结果在多食物照片上会发散 ——
 *   把主体整片抠没了（实测覆盖率从 0.6 掉到 0.006）。
 *   限制在边界带内改判，代价是「抠不到模型框错的那部分」，
 *   换来的是**永远不会把食物抠空、也不会在食物内部打出洞**。
 *
 * 纯本地计算，不新增任何网络请求，也不用让用户再配第二个模型服务。
 */

import { FoodRegion } from '../models/FoodSticker';

/** 每通道的量化级数（5bit → 32^3 = 32768 个颜色桶） */
const COLOR_BINS: number = 32;
const COLOR_SHIFT: number = 3;
/** 边界带宽度 = 区域最大内接距离 × 该比例 */
const BAND_RATIO: number = 0.12;
const BAND_MIN: number = 5;
const BAND_MAX: number = 28;
/** 联合双边滤波：颜色差容忍度与空间权重 */
const SIGMA_COLOR: number = 26.0;
const SIGMA_SPACE: number = 1.6;
/** 对数似然比的中点与陡峭度 */
const LLR_BIAS: number = 0.55;
const LLR_SHARPNESS: number = 3.2;
/** alpha 映射：低于 ALPHA_LO 判为背景，高于 ALPHA_LO+ALPHA_SPAN 判为前景 */
const ALPHA_LO: number = 0.30;
const ALPHA_SPAN: number = 0.22;
/** 小于最大连通块这个比例的碎块直接丢掉 */
const SMALL_COMPONENT_RATIO: number = 0.02;
const SMALL_COMPONENT_MIN: number = 24;

export class StickerMatting {
  /**
   * 构造先验掩膜：模型给了轮廓用轮廓，只有外接框用圆角框，都没有用中心椭圆。
   * 返回 0/1 的 Uint8Array（1 = 属于食物区域）。
   */
  static buildPrior(w: number, h: number, region: FoodRegion | null): Uint8Array {
    const mask = new Uint8Array(w * h);
    if (region === null) {
      StickerMatting.fillEllipse(mask, w, h, 0.36, 0.33);
      return mask;
    }
    if (region.hasPolygon()) {
      StickerMatting.fillPolygon(mask, w, h, region.polygon as number[]);
      return mask;
    }
    if (region.w > 0 && region.h > 0) {
      StickerMatting.fillRoundRect(mask, w, h, region.x, region.y, region.w, region.h);
      return mask;
    }
    StickerMatting.fillEllipse(mask, w, h, 0.36, 0.33);
    return mask;
  }

  /**
   * 构造先验：模型轮廓/框/椭圆 **与端侧主体掩膜求交**。
   *
   * 为什么要求交而不是直接用端侧掩膜：
   *   端侧分割给的是「画面里最显著的主体」，模型给的是「用户问的那份食物」。
   *   两者可能根本不是同一个东西（一盘菜里，显著主体是盘子）。
   *   直接拿端侧掩膜当先验，会把模型圈定的食物整个丢掉。
   *
   *   求交 = 「模型认为在这」∧「端侧认为在这」，两头都认的位置才是主体。
   *   交集太小（说明两者根本对不上）就放弃端侧、退回纯模型先验，
   *   宁可少一点精度，也绝不把食物抠空。
   *
   * @param mask 端侧掩膜（0~255）；null 或不可用时走纯模型先验
   * @param threshold 掩膜二值化阈值
   */
  static buildPriorWithMask(w: number, h: number, region: FoodRegion | null,
    mask: Uint8Array | null, threshold: number): Uint8Array {
    const base = StickerMatting.buildPrior(w, h, region);
    if (mask === null) {
      return base;
    }
    const total = w * h;
    const n = Math.min(total, mask.length);
    let maskCount = 0;
    for (let i = 0; i < n; i++) {
      if (mask[i] >= threshold) {
        maskCount++;
      }
    }
    if (maskCount < 64) {
      return base;
    }
    const inter = new Uint8Array(total);
    let baseCount = 0;
    let interCount = 0;
    for (let i = 0; i < n; i++) {
      if (base[i] > 0) {
        baseCount++;
        if (mask[i] >= threshold) {
          inter[i] = 1;
          interCount++;
        }
      }
    }
    if (baseCount < 64) {
      return base;
    }
    // 交集相对模型轮廓的占比太低 → 端侧与模型明显不是同一个东西，放弃端侧
    if (interCount < baseCount * 0.35) {
      return base;
    }
    return inter;
  }

  /**
   * 核心：从 RGBA 像素 + 先验掩膜算出食物的 alpha（0~255）。
   *
   * @param rgba 原图像素（长度 = w*h*4）
   * @param prior 先验掩膜（0/1）
   */
  static matte(rgba: Uint8ClampedArray, w: number, h: number, prior: Uint8Array): Uint8Array {
    const total = w * h;
    const alpha = new Uint8Array(total);
    let priorCount = 0;
    for (let i = 0; i < total; i++) {
      if (prior[i] > 0) {
        priorCount++;
      }
    }
    if (priorCount === 0) {
      StickerMatting.fillEllipse(prior, w, h, 0.36, 0.33);
      for (let i = 0; i < total; i++) {
        prior[i] = prior[i] > 0 ? 1 : 0;
      }
      priorCount = Math.round(total * 0.38);
    }

    // 倒角距离变换：到最近前景 / 到最近背景
    const invPrior = new Uint8Array(total);
    for (let i = 0; i < total; i++) {
      invPrior[i] = prior[i] > 0 ? 0 : 1;
    }
    const dIn = StickerMatting.chamfer(prior, w, h);    // 外部点到前景的距离
    const dOut = StickerMatting.chamfer(invPrior, w, h); // 内部点到背景的距离

    let maxDist = 0;
    for (let i = 0; i < total; i++) {
      if (dIn[i] > maxDist) {
        maxDist = dIn[i];
      }
    }
    let bandPx = Math.round(maxDist * BAND_RATIO);
    if (bandPx < BAND_MIN) {
      bandPx = BAND_MIN;
    }
    if (bandPx > BAND_MAX) {
      bandPx = BAND_MAX;
    }

    // 三类像素：深处前景 / 边界带 / 远处背景
    const core = new Uint8Array(total);
    const outer = new Uint8Array(total);
    const band = new Uint8Array(total);
    let coreCount = 0;
    let outerCount = 0;
    for (let i = 0; i < total; i++) {
      if (prior[i] > 0) {
        if (dOut[i] >= bandPx) {
          core[i] = 1;
          coreCount++;
        } else {
          band[i] = 1;
        }
      } else if (dIn[i] >= bandPx) {
        outer[i] = 1;
        outerCount++;
      }
    }
    // 样本不够（区域太小）时不做精修，直接用先验
    if (coreCount < 64 || outerCount < 64) {
      for (let i = 0; i < total; i++) {
        alpha[i] = prior[i] > 0 ? 255 : 0;
      }
      return alpha;
    }

    // 颜色直方图
    const bins = COLOR_BINS * COLOR_BINS * COLOR_BINS;
    const fg = new Uint32Array(bins);
    const bg = new Uint32Array(bins);
    let fgTotal = 0;
    let bgTotal = 0;
    for (let i = 0; i < total; i++) {
      const p = i * 4;
      const bin = StickerMatting.colorBin(rgba[p], rgba[p + 1], rgba[p + 2]);
      if (core[i] > 0) {
        fg[bin]++;
        fgTotal++;
      } else if (outer[i] > 0) {
        bg[bin]++;
        bgTotal++;
      }
    }
    if (fgTotal === 0 || bgTotal === 0) {
      for (let i = 0; i < total; i++) {
        alpha[i] = prior[i] > 0 ? 255 : 0;
      }
      return alpha;
    }

    // 逐像素前景概率
    const prob = new Float32Array(total);
    for (let i = 0; i < total; i++) {
      const p = i * 4;
      const bin = StickerMatting.colorBin(rgba[p], rgba[p + 1], rgba[p + 2]);
      const fp = fg[bin] / fgTotal;
      const bp = bg[bin] / bgTotal;
      const llr = Math.log(fp) - Math.log(bp);
      prob[i] = 1.0 / (1.0 + Math.exp(-LLR_SHARPNESS * (llr - LLR_BIAS)));
    }

    // 联合双边滤波（只算边界带内的像素，其余保持原值）
    const spatial: number[] = [];
    for (let dy = -2; dy <= 2; dy++) {
      for (let dx = -2; dx <= 2; dx++) {
        spatial.push(Math.exp(-(dx * dx + dy * dy) / (2 * SIGMA_SPACE * SIGMA_SPACE)));
      }
    }
    const colorNorm = 2 * SIGMA_COLOR * SIGMA_COLOR;
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const i = y * w + x;
        if (band[i] === 0) {
          continue;
        }
        const p = i * 4;
        const cr = rgba[p];
        const cg = rgba[p + 1];
        const cb = rgba[p + 2];
        let sum = 0;
        let wsum = 0;
        for (let dy = -2; dy <= 2; dy++) {
          const ny = y + dy;
          if (ny < 0 || ny >= h) {
            continue;
          }
          for (let dx = -2; dx <= 2; dx++) {
            const nx = x + dx;
            if (nx < 0 || nx >= w) {
              continue;
            }
            const j = ny * w + nx;
            const q = j * 4;
            const dr = cr - rgba[q];
            const dg = cg - rgba[q + 1];
            const db = cb - rgba[q + 2];
            const d2 = dr * dr + dg * dg + db * db;
            const cw = Math.exp(-d2 / colorNorm);
            const wgt = spatial[(dy + 2) * 5 + (dx + 2)] * cw;
            sum += wgt * prob[j];
            wsum += wgt;
          }
        }
        if (wsum > 0) {
          prob[i] = sum / wsum;
        }
      }
    }

    // 合成 alpha：带内按概率 smoothstep（边界因此有抗锯齿）
    for (let i = 0; i < total; i++) {
      if (core[i] > 0) {
        alpha[i] = 255;
      } else if (band[i] > 0) {
        let t = (prob[i] - ALPHA_LO) / ALPHA_SPAN;
        if (t < 0) {
          t = 0;
        } else if (t > 1) {
          t = 1;
        }
        alpha[i] = Math.round(255 * t * t * (3 - 2 * t));
      } else {
        alpha[i] = 0;
      }
    }

    StickerMatting.fillHoles(alpha, w, h);
    StickerMatting.dropSmallComponents(alpha, w, h);
    return alpha;
  }

  /**
   * 白色模切边（die-cut edge）：nosh 那种剪贴贴纸的「白边」不是 UI 画的圆角容器，
   * 而是一条**贴着食物轮廓**的白色纸边。所以这里在像素层把轮廓外扩一圈填白。
   *
   * 做法：
   *   · solid = alpha ≥ 128 的「确定是食物」的像素；
   *   · 到 solid 的距离 ≤ borderPx 且不是实心的像素 = 纸边区域；
   *   · 纸边区域输出为「白色与食物原色按 alpha 混合」，alpha 记 255 ——
   *     这样食物的抗锯齿边缘仍然平滑地过渡到白纸上，而不是被硬切一刀。
   *
   * 直接改写 rgba（同时写 alpha 通道），调用方无需再处理。
   */
  static applyDieCutEdge(rgba: Uint8ClampedArray, w: number, h: number,
    alpha: Uint8Array, borderPx: number): void {
    const total = w * h;
    const solid = new Uint8Array(total);
    for (let i = 0; i < total; i++) {
      solid[i] = alpha[i] >= 128 ? 1 : 0;
    }
    const dist = StickerMatting.chamfer(solid, w, h);
    for (let i = 0; i < total; i++) {
      const p = i * 4;
      const a = alpha[i] / 255;
      if (alpha[i] < 250 && dist[i] <= borderPx) {
        // 纸边：白色与食物色按不透明度混合，边缘因此不会出现硬台阶
        rgba[p] = Math.round(255 * (1 - a) + rgba[p] * a);
        rgba[p + 1] = Math.round(255 * (1 - a) + rgba[p + 1] * a);
        rgba[p + 2] = Math.round(255 * (1 - a) + rgba[p + 2] * a);
        rgba[p + 3] = 255;
      } else {
        rgba[p + 3] = alpha[i];
      }
    }
  }

  /**
   * 到最近「置位像素」的距离（倒角距离变换，两遍扫描）。
   * 权重 1 / √2，是标准的 3-4 近似，误差在 4% 以内，够用来量边界带宽度。
   */
  private static chamfer(mask: Uint8Array, w: number, h: number): Float32Array {
    const total = w * h;
    const d = new Float32Array(total);
    const INF = 1e6;
    for (let i = 0; i < total; i++) {
      d[i] = mask[i] > 0 ? 0 : INF;
    }
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const i = y * w + x;
        let v = d[i];
        if (x > 0 && d[i - 1] + 1 < v) {
          v = d[i - 1] + 1;
        }
        if (y > 0 && d[i - w] + 1 < v) {
          v = d[i - w] + 1;
        }
        if (x > 0 && y > 0 && d[i - w - 1] + 1.4142 < v) {
          v = d[i - w - 1] + 1.4142;
        }
        if (x < w - 1 && y > 0 && d[i - w + 1] + 1.4142 < v) {
          v = d[i - w + 1] + 1.4142;
        }
        d[i] = v;
      }
    }
    for (let y = h - 1; y >= 0; y--) {
      for (let x = w - 1; x >= 0; x--) {
        const i = y * w + x;
        let v = d[i];
        if (x < w - 1 && d[i + 1] + 1 < v) {
          v = d[i + 1] + 1;
        }
        if (y < h - 1 && d[i + w] + 1 < v) {
          v = d[i + w] + 1;
        }
        if (x < w - 1 && y < h - 1 && d[i + w + 1] + 1.4142 < v) {
          v = d[i + w + 1] + 1.4142;
        }
        if (x > 0 && y < h - 1 && d[i + w - 1] + 1.4142 < v) {
          v = d[i + w - 1] + 1.4142;
        }
        d[i] = v;
      }
    }
    return d;
  }

  /** 量化 RGB 到颜色桶下标 */
  private static colorBin(r: number, g: number, b: number): number {
    const ri = (r >> COLOR_SHIFT) & (COLOR_BINS - 1);
    const gi = (g >> COLOR_SHIFT) & (COLOR_BINS - 1);
    const bi = (b >> COLOR_SHIFT) & (COLOR_BINS - 1);
    return (ri * COLOR_BINS + gi) * COLOR_BINS + bi;
  }

  /**
   * 填洞：被不透明像素完全包住的透明像素判为洞，填回不透明。
   * 做法是从画布边界对透明区做 flood fill，填不到的透明像素就是洞。
   */
  private static fillHoles(alpha: Uint8Array, w: number, h: number): void {
    const total = w * h;
    const outside = new Uint8Array(total);
    const stack = new Int32Array(total);
    let top = 0;
    for (let x = 0; x < w; x++) {
      let i = x;
      if (alpha[i] < 128 && outside[i] === 0) {
        outside[i] = 1;
        stack[top++] = i;
      }
      i = (h - 1) * w + x;
      if (alpha[i] < 128 && outside[i] === 0) {
        outside[i] = 1;
        stack[top++] = i;
      }
    }
    for (let y = 0; y < h; y++) {
      let i = y * w;
      if (alpha[i] < 128 && outside[i] === 0) {
        outside[i] = 1;
        stack[top++] = i;
      }
      i = y * w + (w - 1);
      if (alpha[i] < 128 && outside[i] === 0) {
        outside[i] = 1;
        stack[top++] = i;
      }
    }
    while (top > 0) {
      top--;
      const i = stack[top];
      const x = i % w;
      const y = (i - x) / w;
      if (x > 0) {
        const j = i - 1;
        if (alpha[j] < 128 && outside[j] === 0) {
          outside[j] = 1;
          stack[top++] = j;
        }
      }
      if (x < w - 1) {
        const j = i + 1;
        if (alpha[j] < 128 && outside[j] === 0) {
          outside[j] = 1;
          stack[top++] = j;
        }
      }
      if (y > 0) {
        const j = i - w;
        if (alpha[j] < 128 && outside[j] === 0) {
          outside[j] = 1;
          stack[top++] = j;
        }
      }
      if (y < h - 1) {
        const j = i + w;
        if (alpha[j] < 128 && outside[j] === 0) {
          outside[j] = 1;
          stack[top++] = j;
        }
      }
    }
    for (let i = 0; i < total; i++) {
      if (alpha[i] < 128 && outside[i] === 0) {
        alpha[i] = 255;
      }
    }
  }

  /**
   * 丢掉零散碎块（面积小于最大连通块的一小部分）。
   *
   * 注意**不能**只保留最大连通块 —— 一张图里有两三个食物时，
   * 只留最大的会把另外几个直接删掉。碎块用相对面积判定，
   * 保留阈值以下的小块、保留所有成规模的部分。
   */
  private static dropSmallComponents(alpha: Uint8Array, w: number, h: number): void {
    const total = w * h;
    const label = new Int32Array(total);
    const stack = new Int32Array(total);
    const areas: number[] = [];
    let current = 0;
    for (let seed = 0; seed < total; seed++) {
      if (alpha[seed] < 128 || label[seed] !== 0) {
        continue;
      }
      current++;
      let top = 0;
      let area = 0;
      stack[top++] = seed;
      label[seed] = current;
      while (top > 0) {
        top--;
        const i = stack[top];
        area++;
        const x = i % w;
        const y = (i - x) / w;
        if (x > 0) {
          const j = i - 1;
          if (alpha[j] >= 128 && label[j] === 0) {
            label[j] = current;
            stack[top++] = j;
          }
        }
        if (x < w - 1) {
          const j = i + 1;
          if (alpha[j] >= 128 && label[j] === 0) {
            label[j] = current;
            stack[top++] = j;
          }
        }
        if (y > 0) {
          const j = i - w;
          if (alpha[j] >= 128 && label[j] === 0) {
            label[j] = current;
            stack[top++] = j;
          }
        }
        if (y < h - 1) {
          const j = i + w;
          if (alpha[j] >= 128 && label[j] === 0) {
            label[j] = current;
            stack[top++] = j;
          }
        }
      }
      areas.push(area);
    }
    if (areas.length <= 1) {
      return;
    }
    let largest = 0;
    for (let i = 0; i < areas.length; i++) {
      if (areas[i] > largest) {
        largest = areas[i];
      }
    }
    const threshold = Math.max(SMALL_COMPONENT_MIN, Math.round(largest * SMALL_COMPONENT_RATIO));
    for (let i = 0; i < total; i++) {
      if (label[i] === 0) {
        continue;
      }
      if (areas[label[i] - 1] < threshold) {
        alpha[i] = 0;
      }
    }
  }

  /** 扫描线填充多边形（归一化 0~1 坐标） */
  private static fillPolygon(mask: Uint8Array, w: number, h: number, poly: number[]): void {
    const n = Math.floor(poly.length / 2);
    if (n < 3) {
      return;
    }
    const px: number[] = [];
    const py: number[] = [];
    let minY = h;
    let maxY = 0;
    for (let i = 0; i < n; i++) {
      const x = poly[i * 2] * w;
      const y = poly[i * 2 + 1] * h;
      px.push(x);
      py.push(y);
      if (y < minY) {
        minY = y;
      }
      if (y > maxY) {
        maxY = y;
      }
    }
    const yStart = Math.max(0, Math.floor(minY));
    const yEnd = Math.min(h - 1, Math.ceil(maxY));
    const xs: number[] = [];
    for (let y = yStart; y <= yEnd; y++) {
      const sy = y + 0.5;
      xs.length = 0;
      for (let i = 0; i < n; i++) {
        const j = (i + 1) % n;
        const y1 = py[i];
        const y2 = py[j];
        if ((y1 <= sy && y2 > sy) || (y2 <= sy && y1 > sy)) {
          const t = (sy - y1) / (y2 - y1);
          xs.push(px[i] + t * (px[j] - px[i]));
        }
      }
      if (xs.length < 2) {
        continue;
      }
      xs.sort((a: number, b: number) => a - b);
      for (let k = 0; k + 1 < xs.length; k += 2) {
        const x0 = Math.max(0, Math.round(xs[k]));
        const x1 = Math.min(w, Math.round(xs[k + 1]));
        for (let x = x0; x < x1; x++) {
          mask[y * w + x] = 1;
        }
      }
    }
  }

  /** 圆角矩形（归一化 0~1 坐标） */
  private static fillRoundRect(mask: Uint8Array, w: number, h: number,
    nx: number, ny: number, nw: number, nh: number): void {
    const x0 = Math.max(0, Math.round(nx * w));
    const y0 = Math.max(0, Math.round(ny * h));
    const x1 = Math.min(w, Math.round((nx + nw) * w));
    const y1 = Math.min(h, Math.round((ny + nh) * h));
    const r = Math.min(x1 - x0, y1 - y0) * 0.16;
    for (let y = y0; y < y1; y++) {
      const py = y + 0.5;
      for (let x = x0; x < x1; x++) {
        const px = x + 0.5;
        const dx = Math.max(x0 + r - px, 0, px - (x1 - r));
        const dy = Math.max(y0 + r - py, 0, py - (y1 - r));
        if (dx === 0 || dy === 0 || dx * dx + dy * dy <= r * r) {
          mask[y * w + x] = 1;
        }
      }
    }
  }

  /** 中心椭圆（降级路径） */
  private static fillEllipse(mask: Uint8Array, w: number, h: number,
    ratioX: number, ratioY: number): void {
    const cx = w / 2;
    const cy = h / 2;
    const rx = w * ratioX;
    const ry = h * ratioY;
    for (let y = 0; y < h; y++) {
      const dy = y + 0.5 - cy;
      const t = 1 - (dy * dy) / (ry * ry);
      if (t <= 0) {
        continue;
      }
      const half = rx * Math.sqrt(t);
      const x0 = Math.max(0, Math.round(cx - half));
      const x1 = Math.min(w, Math.round(cx + half));
      for (let x = x0; x < x1; x++) {
        mask[y * w + x] = 1;
      }
    }
  }
}
