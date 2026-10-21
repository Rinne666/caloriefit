/**
 * 食物抠图：把照片里的食物抠成**模切贴纸**（透明背景 + 沿轮廓的白边），供「今日黑板」便签使用。
 *
 * 为什么不是「按模型多边形裁一块」：
 *   模型给的十几个顶点只是粗略轮廓，直接填出来是「裁了一块照片」——
 *   盘沿、桌布还在里面，边缘是折线，看起来就是普通缩略图，不是 nosh 那种剪贴贴纸。
 *   抠图算法（颜色模型 + 边缘吸附 + 抗锯齿 + 白边）在 `services/StickerMatting.ets`，
 *   这里只负责取像素、调算法、裁剪、落盘。
 *
 * 整条链路纯本地、零新增网络调用，也不用让用户再配第二个模型服务。
 */

import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FoodRegion, StickerStore } from '../models/FoodSticker';
import { Database } from '../database/Database';
import { StickerMatting } from './StickerMatting';
import { StickerProcessor } from './StickerProcessor';

const DOMAIN = 0x0000;
const TAG = 'StickerCutout';

export class StickerCutoutService {
  /**
   * 贴纸的边长上限（像素）。
   *
   * 贴纸在便签上只有 74vp 宽，1024px 的原图纯属浪费：
   * 抠图要逐像素算颜色模型，1024×765 是 78 万次循环，实测慢到 AI 识别
   * 十几秒都出不来结果，用户会以为卡死。
   * 降到 640 边长后循环量降到约 1/2.5，肉眼看不出差别（贴纸本来就很小）。
   */
  private static readonly MAX_STICKER_SIDE: number = 640;

  /**
   * 白色模切边的宽度（像素），按贴纸尺寸取比例。
   * 太薄看不见（贴纸只有 74vp），太粗就把食物啃掉一圈。
   */
  private static readonly DIE_CUT_BORDER_RATIO: number = 0.03;
  private static readonly DIE_CUT_BORDER_MIN: number = 3;
  private static readonly DIE_CUT_BORDER_MAX: number = 8;

  /**
   * 抠出透明背景的食物贴纸。
   *
   * 步骤：
   *   1) Canvas 只做一件事：把原图铺开并读回标准格式像素（RGBA）
   *      —— 用它是为了拿到确定的像素格式，不参与任何遮罩计算
   *   2) `StickerMatting` 算出食物的 alpha（边界精修 + 抗锯齿）
   *   3) 沿轮廓加一圈白边（模切贴纸的纸边）
   *   4) 裁到贴纸实际范围，避免大片透明
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

    // 3) 先验 + 边缘精修，算出食物 alpha
    //    端侧分割（CoreVisionKit）可用时用它的主体掩膜给模型轮廓纠偏；
    //    模拟器/不支持的机型会直接返回 null，走纯模型先验。
    const visionMask = await StickerProcessor.segment(data, iw, ih);
    const prior = StickerMatting.buildPriorWithMask(iw, ih, region,
      visionMask === null ? null : visionMask.values, 128);
    const alpha = StickerMatting.matte(data, iw, ih, prior);

    // 4) 沿轮廓加白边（模切贴纸的纸边）
    const borderPx = StickerCutoutService.dieCutBorderPx(iw, ih);
    StickerMatting.applyDieCutEdge(data, iw, ih, alpha, borderPx);

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
    const box = StickerCutoutService.alphaBounds(data, iw, ih);
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

  /** 白色模切边的宽度：按画面短边取比例，夹在 3~8 像素之间 */
  private static dieCutBorderPx(w: number, h: number): number {
    const raw = Math.round(Math.min(w, h) * StickerCutoutService.DIE_CUT_BORDER_RATIO);
    if (raw < StickerCutoutService.DIE_CUT_BORDER_MIN) {
      return StickerCutoutService.DIE_CUT_BORDER_MIN;
    }
    if (raw > StickerCutoutService.DIE_CUT_BORDER_MAX) {
      return StickerCutoutService.DIE_CUT_BORDER_MAX;
    }
    return raw;
  }

  /** 扫描 alpha 通道，求出实际不透明区域的包围盒 [x0,y0,x1,y1]；全透明返回 null */
  private static alphaBounds(data: Uint8ClampedArray, w: number, h: number): number[] | null {
    let x0 = w;
    let y0 = h;
    let x1 = -1;
    let y1 = -1;
    for (let y = 0; y < h; y++) {
      let idx = (y * w) * 4 + 3;
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

  /**
   * 取内置矢量美食贴纸的文件（相对 filesDir 的路径），没有就生成一次。
   *
   * 只生成一次、存成文件而不是每次现画：
   *   · 现画要跑 3 次 OffscreenCanvas 合成，开黑板时白等几百毫秒；
   *   · 现画还要把 base64 存进数据库，每天一个示例就是几十 KB。
   * 存成 PNG 文件后，示例节点只存一个相对路径，
   * 展示时再转 data URI —— 和真实照片贴纸走同一条路。
   */
  /**
   * 取内置矢量美食贴纸的文件（相对 filesDir 的路径），没有就生成。
   *
   * 文件名**保持稳定**（preset_0/1/2.png）：黑板节点里存的就是这个路径，
   * 换了名字就得连数据库一起改，旧节点会指向不存在的文件。
   * 改画法时靠 `PRESET_VERSION` 失效：版本对不上就把旧图删掉重画，
   * 于是**已铺在板子上的示例也会跟着更新**，不用动数据。
   *
   * 只生成一次、存成文件而不是每次现画：
   *   · 现画要跑 3 次 OffscreenCanvas 合成，开黑板时白等几百毫秒；
   *   · 现画还要把 base64 存进数据库，每天一个示例就是几十 KB。
   * 存成 PNG 文件后，示例节点只存一个相对路径，
   * 展示时再转 data URI —— 和真实照片贴纸走同一条路。
   */
  static async ensurePresetSticker(kind: number): Promise<string> {
    const rel = `${StickerStore.DIR}/preset_${kind}${StickerStore.EXT}`;
    const abs = StickerCutoutService.absolutePath(rel);
    await StickerCutoutService.ensurePresetVersion();
    if (fileIo.accessSync(abs)) {
      return rel;
    }
    return StickerCutoutService.generatePreset(kind);
  }

  /**
   * 内置贴纸的画法版本。
   *
   * 改了画法就 +1。版本对不上时把旧的 preset_*.png 全删掉，
   * 下次用到会重新画 —— 这样板子上已经贴着的示例也会变成新画法。
   */
  private static readonly PRESET_VERSION: number = 2;

  /**
   * 校验并按需失效内置贴纸文件。
   *
   * 每次读板子都会调一次：版本对不上就把旧图删掉，
   * 于是**已经铺在板子上的示例也会更新成新画法**，不用动数据库。
   */
  static async ensurePresetVersion(): Promise<void> {
    const versionPath = StickerCutoutService.absolutePath(
      `${StickerStore.DIR}/preset_version.bin`);
    let current = 0;
    try {
      if (fileIo.accessSync(versionPath)) {
        const file = await fileIo.open(versionPath, fileIo.OpenMode.READ_ONLY);
        try {
          const buf = new ArrayBuffer(4);
          // fileIo.read 返回的是**读到的字节数**，不是 {bytesRead, buffer}
          const read = await fileIo.read(file.fd, buf);
          if (read > 0) {
            current = new Uint8Array(buf, 0, 1)[0];
          }
        } finally {
          fileIo.closeSync(file);
        }
      }
    } catch (_e) {
      current = 0;
    }
    if (current === StickerCutoutService.PRESET_VERSION) {
      return;
    }
    hilog.info(DOMAIN, TAG, 'preset art version %{public}d -> %{public}d, regenerating',
      current, StickerCutoutService.PRESET_VERSION);
    // 版本变了：旧图作废，并立刻重画，
    // 否则板子上已经引用这些路径的示例会变成「贴纸不见了」。
    for (let kind = 0; kind < 3; kind++) {
      const old = StickerCutoutService.absolutePath(
        `${StickerStore.DIR}/preset_${kind}${StickerStore.EXT}`);
      try {
        if (fileIo.accessSync(old)) {
          await fileIo.unlink(old);
        }
      } catch (_e) {
        // 删不掉就下次重画时覆盖
      }
    }
    for (let kind = 0; kind < 3; kind++) {
      try {
        await StickerCutoutService.generatePreset(kind);
      } catch (_e) {
        // 画不出来就少一张，板子上会缺一块，但不影响其它功能
      }
    }
    try {
      const file = await fileIo.open(versionPath,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        // fileIo.write 只收 ArrayBuffer 或 string，不收 Uint8Array
        const one = new ArrayBuffer(1);
        new Uint8Array(one)[0] = StickerCutoutService.PRESET_VERSION;
        await fileIo.write(file.fd, one);
      } finally {
        fileIo.closeSync(file);
      }
    } catch (_e) {
      // 标记写不进去也不影响功能，只是下次会再删一次
    }
  }

  /** 画一张内置贴纸并存成文件 */
  private static async generatePreset(kind: number): Promise<string> {
    const pixelMap = await StickerProcessor.presetSticker(kind, 256);
    try {
      return await StickerCutoutService.savePng(pixelMap, `preset_${kind}`);
    } finally {
      pixelMap.release();
    }
  }

  /** 把字节数组转成可直接喂给 Image 的 data URI */
  static toDataUri(pngBuffer: ArrayBuffer): string {
    const helper = new util.Base64Helper();
    const b64 = helper.encodeToStringSync(new Uint8Array(pngBuffer));
    return `data:image/png;base64,${b64}`;
  }
}
