/**
 * 食物贴纸：AI 指出的食物在照片中的位置，以及抠图后贴纸文件的存放约定。
 *
 * 坐标一律归一化到 0~1（模型输出的是 0~1000 整数，解析时换算），
 * 这样贴纸区域与图片实际像素尺寸解耦 —— 换设备、换分辨率都不用重算，
 * 抠图时直接乘以画布宽高即可。
 */

/** 食物在原图中的区域 */
export class FoodRegion {
  /** 外接框左上角，归一化 0~1 */
  x: number;
  y: number;
  /** 外接框宽高，归一化 0~1 */
  w: number;
  h: number;
  /**
   * 轮廓多边形顶点，归一化 0~1，扁平数组 [x1,y1,x2,y2,...]。
   * null 表示模型没有给轮廓 —— 此时只有外接框可用。
   */
  polygon: number[] | null;

  constructor(x: number, y: number, w: number, h: number, polygon: number[] | null) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.polygon = polygon;
  }

  /** 是否带轮廓多边形 —— 有则抠图更贴近真实食物外形 */
  hasPolygon(): boolean {
    return this.polygon !== null && this.polygon.length >= 6;
  }
}

/** 贴纸文件在应用沙箱里的存放约定 */
export class StickerStore {
  /** 相对 filesDir 的目录名 */
  static readonly DIR: string = 'stickers';
  /** 文件扩展名 */
  static readonly EXT: string = '.png';
}
