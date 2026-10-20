/**
 * 食物抠图：把照片里的食物抠成透明背景的贴纸，供「今日黑板」便签使用。
 *
 * 为什么用 Canvas 合成模式、而不是接一个分割模型：
 *   ArkUI 的 CanvasRenderingContext2D 支持 globalCompositeOperation='destination-out'
 *   （见 SDK ets/component/canvas.d.ts），把「保留区域」以外的像素擦成透明即可。
 *   整条链路纯本地、零新增网络调用，也不用让用户再配第二个模型服务。
 *
 * 抠图算法（三种区域形态统一用 even-odd 挖洞）：
 *   1) source-over 画原图 —— drawImage 铺满整个画布，顺带消掉 vp/px 单位差
 *   2) destination-out 填充「外部区域」，即 全图矩形 ⊖ 保留区域：
 *        · 有多边形：rect(全图) + 多边形路径，fill('evenodd')
 *        · 只有外接框：rect(全图) + rect(外接框)，fill('evenodd')
 *        · 都没有：rect(全图) + 中心椭圆，fill('evenodd')
 *   3) getPixelMap 读回 → 透明背景的食物图
 *
 * 已知边界：模型给的坐标可能不准，抠出来的贴纸会缺角或带背景。
 *   这是「AI 估算定位」的固有误差，界面侧用白边容器 + 投影掩盖；
 *   同时保留降级路径 —— 坐标缺失时用中心椭圆，至少能框住盘子中央。
 */

import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FoodRegion, StickerStore } from '../models/FoodSticker';
import { Database } from '../database/Database';

const DOMAIN = 0x0000;
const TAG = 'StickerCutout';

export class StickerCutoutService {
  /** 无坐标时的降级椭圆：半径占画面宽/高的比例 */
  private static readonly FALLBACK_RATIO_X: number = 0.36;
  private static readonly FALLBACK_RATIO_Y: number = 0.33;

  /**
   * 贴纸的边长上限（像素）。
   *
   * 贴纸在便签上只有 74vp 宽，1024px 的原图纯属浪费：
   * 抠图要逐像素写 alpha，1024×765 是 78 万次循环，实测慢到 AI 识别
   * 十几秒都出不来结果，用户会以为卡死。
   * 降到 640 边长后循环量降到约 1/2.5，肉眼看不出差别（贴纸本来就很小）。
   */
  private static readonly MAX_STICKER_SIDE: number = 640;

  /**
   * 抠出透明背景的食物贴纸。
   *
   * 实现路线：**像素级写 alpha**，不用 Canvas 的合成模式。
   *
   * 为什么不用 globalCompositeOperation：
   *   SDK 文档列了 destination-out / destination-in，但实测两条都不生效 ——
   *   第一版用「填充外部区域 + destination-out 擦除」，第二版用
   *   「clip + destination-in」，两次的结果都是**原图原样保留**，
   *   贴纸等于没抠。所以不再赌 Canvas 的合成语义。
   *
   * 现在的做法：
   *   1) Canvas 只做一件事：把原图铺满并读回标准格式的像素（RGBA）
   *      —— 用它是为了拿到确定的像素格式，不参与任何遮罩计算
   *   2) 逐像素按「食物区域」决定 alpha：区域内 255，区域外 0
   *   3) 写回画布，再取回 PixelMap
   *
   * 遮罩形态：
   *   · 有轮廓多边形 → 扫描线填充（每行求交点、成对填区间），支持任意形状
   *   · 只有外接框   → 矩形区间
   *   · 都没有       → 中心椭圆（降级路径）
   *
   * @param source 原图
   * @param region 食物区域；null 时走中心椭圆降级
   */
  static async cutout(source: image.PixelMap, region: FoodRegion | null): Promise<image.PixelMap> {
    const info = await source.getImageInfo();
    const wPx = info.size.width;
    const hPx = info.size.height;
    if (wPx <= 0 || hPx <= 0) {
      throw new Error('cutout: invalid source size');
    }

    // Canvas 坐标单位是 vp，PixelMap 是像素 —— 先换算，否则画布缓冲尺寸会差一个密度倍数。
    const w = px2vp(wPx);
    const h = px2vp(hPx);

    const canvas = new OffscreenCanvas(w, h);
    const ctx = canvas.getContext('2d');
    if (ctx === undefined || ctx === null) {
      throw new Error('cutout: no 2d context');
    }

    // 1) 原图铺满画布（这一步只为了拿到标准格式像素）
    ctx.globalCompositeOperation = 'source-over';
    ctx.drawImage(source, 0, 0, w, h);

    // 2) 读回像素。ImageData 的 width/height 是真实像素，用它们做归一化计算，
    //    这样完全不依赖 vp/px 关系。
    const img = ctx.getImageData(0, 0, w, h);
    const iw = img.width;
    const ih = img.height;
    const data = img.data;
    hilog.info(DOMAIN, TAG, 'cutout src=%{public}d x %{public}d px, canvas=%{public}d x %{public}d vp, pixels=%{public}d x %{public}d',
      wPx, hPx, w, h, iw, ih);

    // 3) 全图先置为透明
    for (let i = 3; i < data.length; i += 4) {
      data[i] = 0;
    }

    // 4) 把保留区域内的 alpha 恢复为不透明
    if (region !== null && region.hasPolygon()) {
      StickerCutoutService.fillPolygon(data, iw, ih, region.polygon as number[]);
    } else if (region !== null) {
      StickerCutoutService.fillRoundRect(data, iw, ih,
        region.x, region.y, region.w, region.h);
    } else {
      StickerCutoutService.fillEllipse(data, iw, ih,
        StickerCutoutService.FALLBACK_RATIO_X, StickerCutoutService.FALLBACK_RATIO_Y);
    }

    // 5) 写回画布并取回（全尺寸带透明）
    ctx.putImageData(img, 0, 0);
    const full = ctx.getPixelMap(0, 0, w, h);
    const fullInfo = await full.getImageInfo();
    hilog.info(DOMAIN, TAG, 'cutout out=%{public}d x %{public}d px', fullInfo.size.width, fullInfo.size.height);
    if (fullInfo.size.width !== wPx || fullInfo.size.height !== hPx) {
      full.release();
      throw new Error(`cutout: size mismatch ${fullInfo.size.width}x${fullInfo.size.height} vs ${wPx}x${hPx}`);
    }

    // 6) 裁到食物实际范围。
    //    不裁的话贴纸是「原图尺寸 + 大片透明」，在便签里按 Contain 显示时
    //    食物只占中间一小块 —— 看着像缩略图，不像贴纸。
    const box = StickerCutoutService.alphaBounds(img);
    if (box === null) {
      full.release();
      throw new Error('cutout: empty region');
    }
    const cw = box[2] - box[0];
    const ch = box[3] - box[1];
    if (cw <= 0 || ch <= 0) {
      return full;
    }
    const cropped = await StickerCutoutService.cropPixelMap(full, box[0], box[1], cw, ch);
    full.release();
    return cropped;
  }

  /** 扫描 alpha 通道，求出实际不透明区域的包围盒 [x0,y0,x1,y1]；全透明返回 null */
  private static alphaBounds(img: ImageData): number[] | null {
    const data = img.data;
    const w = img.width;
    const h = img.height;
    let x0 = w;
    let y0 = h;
    let x1 = -1;
    let y1 = -1;
    for (let y = 0; y < h; y++) {
      let idx = y * w * 4 + 3;
      for (let x = 0; x < w; x++) {
        if (data[idx] > 8) {
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
        idx += 4;
      }
    }
    if (x1 < 0) {
      return null;
    }
    return [x0, y0, x1 + 1, y1 + 1];
  }

  /**
   * 把 PixelMap 的一块区域裁出来，输出尺寸与源区域像素一致。
   *
   * 走 canvas 的 9 参数 drawImage：源矩形与目标矩形都用 vp，
   * 换算后两边同尺度，裁剪不会错位。
   */
  private static async cropPixelMap(src: image.PixelMap,
    x: number, y: number, w: number, h: number): Promise<image.PixelMap> {
    const sx = px2vp(x);
    const sy = px2vp(y);
    const sw = px2vp(w);
    const sh = px2vp(h);
    const canvas = new OffscreenCanvas(sw, sh);
    const ctx = canvas.getContext('2d');
    if (ctx === undefined || ctx === null) {
      throw new Error('crop: no 2d context');
    }
    ctx.globalCompositeOperation = 'source-over';
    ctx.drawImage(src, sx, sy, sw, sh, 0, 0, sw, sh);
    return ctx.getPixelMap(0, 0, sw, sh);
  }

  /**
   * 把**圆角矩形**区域内的 alpha 置为不透明（坐标为归一化 0~1）。
   *
   * 为什么用圆角而不是硬矩形：抠完会裁到包围盒，硬矩形裁完就是一张
   * 普通矩形照片，边缘一点透明都没有，看着像缩略图而不像贴纸。
   * 圆角让四角保持透明，配合 UI 上的白边容器和投影就是剪贴贴纸的样子。
   */
  private static fillRoundRect(data: Uint8ClampedArray, w: number, h: number,
    nx: number, ny: number, nw: number, nh: number): void {
    const x0 = Math.max(0, Math.round(nx * w));
    const y0 = Math.max(0, Math.round(ny * h));
    const x1 = Math.min(w, Math.round((nx + nw) * w));
    const y1 = Math.min(h, Math.round((ny + nh) * h));
    const r = Math.min(x1 - x0, y1 - y0) * 0.16;
    for (let y = y0; y < y1; y++) {
      const py = y + 0.5;
      let idx = (y * w + x0) * 4 + 3;
      for (let x = x0; x < x1; x++) {
        const px = x + 0.5;
        // 圆角矩形的有符号距离：只有四角需要额外判定
        const dx = Math.max(x0 + r - px, 0, px - (x1 - r));
        const dy = Math.max(y0 + r - py, 0, py - (y1 - r));
        if (dx === 0 || dy === 0 || dx * dx + dy * dy <= r * r) {
          data[idx] = 255;
        }
        idx += 4;
      }
    }
  }

  /** 把中心椭圆内的 alpha 置为不透明（半径为画面宽/高的比例） */
  private static fillEllipse(data: Uint8ClampedArray, w: number, h: number,
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
      let idx = (y * w + x0) * 4 + 3;
      for (let x = x0; x < x1; x++) {
        data[idx] = 255;
        idx += 4;
      }
    }
  }

  /**
   * 扫描线填充多边形。
   *
   * 每条水平扫描线求出与多边形各边的交点，按 x 排序后成对填充区间 ——
   * 偶奇规则。复杂度 O(H × 边数 + 填充面积)，比逐像素做点在多边形内判定快得多。
   */
  private static fillPolygon(data: Uint8ClampedArray, w: number, h: number,
    poly: number[]): void {
    const n = poly.length / 2;
    if (n < 3) {
      return;
    }
    // 顶点转像素坐标
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
        let idx = (y * w + x0) * 4 + 3;
        for (let x = x0; x < x1; x++) {
          data[idx] = 255;
          idx += 4;
        }
      }
    }
  }

  /**
   * 从图片 URI 直接抠出贴纸，省掉调用方自己解 PixelMap 的样板。
   * URI 可以是相册选图的临时授权路径 —— 在当前页内读取是有效的，
   * 所以抠图必须在**识别当页**完成，不要把 URI 带到别的页面再用。
   */
  static async cutoutFromUri(uri: string, region: FoodRegion | null): Promise<image.PixelMap> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const source = image.createImageSource(file.fd);
      if (source === undefined || source === null) {
        throw new Error('cutout: no image source');
      }
      try {
        // 先降采样再抠 —— 逐像素循环的规模直接决定识别要等多久。
        const info = await source.getImageInfo();
        const maxSide = Math.max(info.size.width, info.size.height);
        let desiredSize: image.Size | undefined = undefined;
        if (maxSide > StickerCutoutService.MAX_STICKER_SIDE) {
          const scale = StickerCutoutService.MAX_STICKER_SIDE / maxSide;
          desiredSize = {
            width: Math.max(1, Math.round(info.size.width * scale)),
            height: Math.max(1, Math.round(info.size.height * scale))
          };
        }
        const pixelMap = await source.createPixelMap({ desiredSize: desiredSize });
        try {
          return await StickerCutoutService.cutout(pixelMap, region);
        } finally {
          pixelMap.release();
        }
      } finally {
        source.release();
      }
    } finally {
      fileIo.closeSync(file);
    }
  }

  /**
   * 把贴纸写成 PNG 存进应用沙箱，返回相对 filesDir 的路径。
   * 相对路径存库，filesDir 绝对路径在运行时拼 —— 换机/换沙箱路径不影响数据。
   */
  static async savePng(pixelMap: image.PixelMap, baseName: string): Promise<string> {
    const packer = image.createImagePacker();
    try {
      // ArkTS 要求对象字面量对应显式声明的 interface（arkts-no-obj-literals-as-types）
      const opts: image.PackingOption = { format: 'image/png', quality: 100 };
      const packed = await packer.packToData(pixelMap, opts);
      const rel = `${StickerStore.DIR}/${baseName}${StickerStore.EXT}`;
      const abs = StickerCutoutService.absolutePath(rel);
      await StickerCutoutService.ensureDir();
      const file = await fileIo.open(abs,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        // File 接口只有 fd/path，没有 write 方法 —— 要走 fileIo.write(fd, buffer)
        await fileIo.write(file.fd, packed);
      } finally {
        fileIo.closeSync(file);
      }
      return rel;
    } finally {
      packer.release();
    }
  }

  /** 读回贴纸；文件不存在或损坏时返回 null，不抛错打断列表渲染 */
  static async load(relPath: string): Promise<image.PixelMap | null> {
    if (relPath.length === 0) {
      return null;
    }
    const abs = StickerCutoutService.absolutePath(relPath);
    try {
      if (!fileIo.accessSync(abs)) {
        return null;
      }
      const file = await fileIo.open(abs, fileIo.OpenMode.READ_ONLY);
      try {
        const source = image.createImageSource(file.fd);
        if (source === undefined || source === null) {
          return null;
        }
        try {
          return await source.createPixelMap();
        } finally {
          source.release();
        }
      } finally {
        fileIo.closeSync(file);
      }
    } catch (_e) {
      return null;
    }
  }

  /** 删除贴纸文件；失败不抛错（数据库记录已删，残留文件只是浪费空间） */
  static async remove(relPath: string): Promise<void> {
    if (relPath.length === 0) {
      return;
    }
    try {
      const abs = StickerCutoutService.absolutePath(relPath);
      if (fileIo.accessSync(abs)) {
        await fileIo.unlink(abs);
      }
    } catch (_e) {
      // 忽略：贴纸是缓存性质的数据，删不掉不影响功能。
    }
  }

  /**
   * 读回贴纸并转成可直接喂给 ArkUI Image 的 base64 data URI。
   *
   * 为什么要转：ArkUI 的 Image 解不了沙箱里的真实文件路径（实测是空白图），
   * 只有 data URI / rawfile 两种形式能用。所以贴纸落盘是为了持久化，
   * 显示时一律转成 data URI。
   */
  static async loadDataUri(relPath: string): Promise<string> {
    const pixelMap = await StickerCutoutService.load(relPath);
    if (pixelMap === null) {
      return '';
    }
    try {
      const packer = image.createImagePacker();
      try {
        const opts: image.PackingOption = { format: 'image/png', quality: 100 };
        const png = await packer.packToData(pixelMap, opts);
        return StickerCutoutService.toDataUri(png);
      } finally {
        packer.release();
      }
    } finally {
      pixelMap.release();
    }
  }

  /** 相对路径 → filesDir 下的绝对路径 */
  static absolutePath(relPath: string): string {
    const ctx = Database.getAppContext();
    if (ctx === null) {
      return relPath;
    }
    return `${ctx.filesDir}/${relPath}`;
  }

  private static async ensureDir(): Promise<void> {
    const dir = StickerCutoutService.absolutePath(StickerStore.DIR);
    if (!fileIo.accessSync(dir)) {
      await fileIo.mkdir(dir, true);
    }
  }

  /** 生成一个不冲突的贴纸文件名 */
  static newBaseName(): string {
    return `${Date.now()}_${Math.floor(Math.random() * 100000)}`;
  }

  /** 把字节数组转成可直接喂给 Image 的 data URI */
  static toDataUri(pngBuffer: ArrayBuffer): string {
    const helper = new util.Base64Helper();
    const b64 = helper.encodeToStringSync(new Uint8Array(pngBuffer));
    return `data:image/png;base64,${b64}`;
  }
}
