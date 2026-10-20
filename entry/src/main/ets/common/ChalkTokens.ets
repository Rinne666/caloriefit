/**
 * 「今日黑板」专用色板 —— 卡通 / 粉笔 / 便签风格。
 *
 * 为什么单独开一个文件，不并进 DesignTokens：
 *   DesignTokens 是按 NutriScan 原版实测配色建的深色科技风体系，
 *   且所有颜色走资源限定符（浅色/深色两套）。黑板页是**另一种美术方向**
 *   —— 固定的木框墨绿黑板 + 彩色便签，不跟随系统深浅色切换。
 *   混进 DesignTokens 会污染那套资源限定符机制，所以独立成文件。
 *
 * 这里全部是硬编码色值，是有意为之：黑板要的就是「这块板子永远是这个颜色」。
 */

/** 黑板与木框 */
export class ChalkColors {
  /** 黑板板面 */
  static readonly BOARD: string = '#33503F';
  /** 板面内侧高光带，模拟黑板被擦过留下的痕迹 */
  static readonly BOARD_GLOW: string = '#3D5F4A';
  /** 木框 */
  static readonly FRAME: string = '#B98A5A';
  /** 木框暗边 */
  static readonly FRAME_DARK: string = '#8E663F';
  /** 粉笔字 */
  static readonly CHALK: string = '#F4F1E4';
  /** 粉笔字弱化色 */
  static readonly CHALK_DIM: string = '#C6CFC4';
  /** 粉笔槽（放粉笔的凹槽） */
  static readonly TRAY: string = '#A8794C';
}

/** 便签纸色板：明黄、樱粉、湖蓝、嫩绿、蜜橙 */
export class StickyColors {
  static readonly PALETTE: string[] = [
    '#FFE7A3', '#FFC9D6', '#BFE3F5', '#CCE9B6', '#FFD4B0'
  ];
  /** 卷角阴影色：每种便签配一个同色系深色 */
  static readonly FOLD: string[] = [
    '#E8C866', '#E0A2B4', '#9CC6DC', '#A9CC90', '#E0AE86'
  ];
}

/** 卡通元素 */
export class CartoonColors {
  /** 吉祥物猫身 */
  static readonly CAT: string = '#F5C77E';
  /** 猫耳内 */
  static readonly CAT_INNER: string = '#F2A0A0';
  /** 卡通描边 / 五官 */
  static readonly INK: string = '#2B2B2B';
  /** 贴纸白边 */
  static readonly STICKER_EDGE: string = '#FFFFFF';
}

/**
 * 便签歪斜角度（度）。
 * 用「记录 id 派生」而不是随机数，保证同一条记录每次渲染角度一致 ——
 * 刷新页面时便签不应该自己转个圈。
 */
export function stickyTilt(seed: number): number {
  const t = Math.abs(seed) % 7;      // 0~6
  return t - 3;                      // -3 ~ +3
}

/** 便签配色下标：同样由 seed 派生，保证同一条记录颜色稳定 */
export function stickyColorIndex(seed: number): number {
  return Math.abs(seed) % StickyColors.PALETTE.length;
}
