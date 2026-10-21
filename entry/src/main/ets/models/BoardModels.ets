/**
 * 黑板画布的数据模型。
 *
 * 对应设计方案「Core Data Models Specification」。
 *
 * ## 与既有模型的关系
 * `food_log` 里已经存了食物记录（名称、热量、宏量、贴纸路径）。
 * 黑板节点**不重复存这些内容**：
 *   · FOOD_STICKER 节点只存 `foodId` 和它的空间状态（位置/缩放/旋转/层级），
 *     展示时从 food_log 读内容 —— 这样改了食物记录，黑板上的贴纸立刻跟着变，
 *     不会出现「餐食卡显示 430 kcal、黑板贴纸还写着 380 kcal」的两处不同步。
 *   · STICKY_NOTE / DEMO_STICKER 节点没有对应的 food_log 记录，内容存在自己身上。
 *
 * ## 为什么用 @Observed
 * 拖拽时每个节点的位置都在变。如果整块黑板用 @State 存节点数组，
 * 一次拖拽会重建整棵子树，掉帧严重。
 * 用 @Observed + @ObjectLink 把每个节点拆成独立可观察对象，
 * 只有正在拖的那一个节点会刷新。
 */

/** 黑板节点类型 */
export enum BoardNodeType {
  /** 食物贴纸：关联一条 food_log 记录，内容从 food_log 读 */
  FOOD_STICKER = 0,
  /** 独立便签：自己带内容，可写碎碎念 */
  STICKY_NOTE = 1,
  /**
   * 内置示例贴纸。
   *
   * 设计方案要求首启就有 3 张示例美食贴纸，好让用户第一秒就能体验拖拽。
   * 但这些是**假数据**，不能进 food_log —— 否则「今日摄入」会被示例的热量污染，
   * 用户看到自己刚装的应用就显示吃了 1200 kcal，会以为算错了。
   * 所以示例节点单独一种类型：不计入热量，录下第一条真实记录后自动清掉。
   */
  DEMO_STICKER = 2
}

/** 便签纸样式（对应设计方案的 StickyPaperStyle） */
export enum StickyPaperStyle {
  /** 奶油黄 */
  CREAM_YELLOW = 0,
  /** 薄荷绿 */
  MINT_GREEN = 1,
  /** 樱花粉 */
  SAKURA_PINK = 2,
  /** 牛皮纸 */
  KRAFT_PAPER = 3,
  /** 黑板粉笔描边卡 */
  CHALK_CARD = 4
}

/** 顶部固定装饰（对应设计方案的 PinDecorationType） */
export enum PinDecorationType {
  /** 波点和纸胶带 */
  WASHI_TAPE_DOT = 0,
  /** 斜纹和纸胶带 */
  WASHI_TAPE_STRIPE = 1,
  /** 红色立体图钉 */
  RED_THUMB_TACK = 2,
  /** 无装饰 */
  NONE = 3
}

/** 黑板底纹主题（对应设计方案的 BoardThemeType） */
export enum BoardThemeType {
  /** 深灰绿教学黑板 */
  CHALKBOARD = 0,
  /** 暖棕软木留言板 */
  CORKBOARD = 1,
  /** 米白点阵手帐纸 */
  DOT_JOURNAL = 2
}

/** 黑板视图模式 */
export enum BoardViewMode {
  /** 自由画布：贴纸可拖拽/缩放/旋转 */
  FREE_CANVAS = 0,
  /** 结构化网格：按餐次分组，像素级规整 */
  STRUCTURED_GRID = 1
}

/**
 * 黑板上的一个节点。
 *
 * 位置坐标单位是 vp，原点是画布左上角。
 */
@Observed
export class BoardNodeModel {
  /** 数据库主键；未落库时为 0 */
  id: number = 0;
  /** 所属日期，YYYY-MM-DD */
  date: string = '';
  /** 节点类型 */
  nodeType: BoardNodeType = BoardNodeType.FOOD_STICKER;
  /** FOOD_STICKER 关联的 food_log.id；其余类型为 null */
  foodId: number | null = null;

  /* ---- 内容（FOOD_STICKER 加载时从 food_log 填；其余类型本身就存） ---- */
  /** 标题：食物名或便签标题 */
  title: string = '';
  /** 热量，千卡 */
  calories: number = 0;
  /** 蛋白质 g；null 表示未记录 */
  proteinGrams: number | null = null;
  /** 碳水 g */
  carbsGrams: number | null = null;
  /** 脂肪 g */
  fatGrams: number | null = null;
  /** 份量描述，如「4只 / 约220g」 */
  portionDesc: string = '';
  /** 餐次：0 早餐 1 午餐 2 晚餐 3 加餐（与 models/FoodLog 的 MealType 一致） */
  mealCategory: number = 3;
  /** 用餐时间，如 12:30 */
  timeStr: string = '';
  /** 心情 emoji */
  moodEmoji: string = '';
  /** 和谁吃 */
  companionText: string = '';
  /** 碎碎念 */
  memoText: string = '';
  /** AI 饭搭子点评 */
  aiAdvice: string = '';
  /** 贴纸图（base64 data URI 或沙箱相对路径） */
  stickerUri: string = '';

  /* ---- 装饰 ---- */
  /** 便签纸样式 */
  paperStyle: StickyPaperStyle = StickyPaperStyle.CREAM_YELLOW;
  /** 顶部固定装饰 */
  pinType: PinDecorationType = PinDecorationType.WASHI_TAPE_DOT;

  /* ---- 空间状态 ---- */
  /** 画布 X 坐标（vp） */
  x: number = 0;
  /** 画布 Y 坐标（vp） */
  y: number = 0;
  /** 缩放 */
  scale: number = 1;
  /** 旋转角度（度） */
  rotation: number = 0;
  /** 叠放次序，越大越靠上 */
  zIndex: number = 0;
  /** 是否处于「翻到背面看便签」的状态 */
  isFlipped: boolean = false;

  /** 是否是贴纸类节点（贴纸 / 示例贴纸） */
  isSticker(): boolean {
    return this.nodeType === BoardNodeType.FOOD_STICKER ||
      this.nodeType === BoardNodeType.DEMO_STICKER;
  }

  /** 是否记录了完整宏量 */
  hasMacros(): boolean {
    return this.proteinGrams !== null && this.carbsGrams !== null && this.fatGrams !== null;
  }

  /** 是否有可展示的碎碎念 / 心情 / 和谁吃 */
  hasPersonalNote(): boolean {
    return this.memoText.length > 0 || this.moodEmoji.length > 0 || this.companionText.length > 0;
  }
}

/** 黑板设置（主题 + 视图模式），全局一份 */
export class BoardSetting {
  /** 底纹主题 */
  theme: BoardThemeType = BoardThemeType.CHALKBOARD;
  /** 视图模式 */
  viewMode: BoardViewMode = BoardViewMode.FREE_CANVAS;

  constructor(theme: BoardThemeType, viewMode: BoardViewMode) {
    this.theme = theme;
    this.viewMode = viewMode;
  }
}

/** 主题配色 */
export class BoardThemeColors {
  /** 板面底色 */
  board: string = '';
  /** 板面纹理色（点阵 / 颗粒 / 粉笔痕） */
  texture: string = '';
  /** 板面描边色 */
  border: string = '';
  /** 外框色 */
  frame: string = '';
  /** 板面上的正文色 */
  text: string = '';
  /** 板面上的次要文字色 */
  textDim: string = '';

  constructor(board: string, texture: string, border: string, frame: string,
    text: string, textDim: string) {
    this.board = board;
    this.texture = texture;
    this.border = border;
    this.frame = frame;
    this.text = text;
    this.textDim = textDim;
  }
}

/** 取主题配色 */
export function boardThemeColors(theme: BoardThemeType): BoardThemeColors {
  if (theme === BoardThemeType.CORKBOARD) {
    return new BoardThemeColors('#C89D7C', 'rgba(120, 78, 44, 0.18)', '#A87B58', '#8E663F', '#4A3220', '#6B4A2E');
  }
  if (theme === BoardThemeType.DOT_JOURNAL) {
    return new BoardThemeColors('#FAF7F0', 'rgba(120, 120, 130, 0.22)', '#E4DCCE', '#C9BFA9', '#3A3630', '#7A736A');
  }
  return new BoardThemeColors('#33503F', 'rgba(244, 241, 228, 0.16)', '#2A4234', '#B98A5A', '#F4F1E4', '#C6CFC4');
}

/** 便签纸配色：主色 + 折角暗色 */
export function paperColors(style: StickyPaperStyle): string[] {
  if (style === StickyPaperStyle.MINT_GREEN) {
    return ['#E2F6E9', '#BFE0CC'];
  }
  if (style === StickyPaperStyle.SAKURA_PINK) {
    return ['#FFE8F0', '#F2C3D4'];
  }
  if (style === StickyPaperStyle.KRAFT_PAPER) {
    return ['#F3E5D0', '#DCC7A6'];
  }
  if (style === StickyPaperStyle.CHALK_CARD) {
    return ['#2B3035', '#1C2024'];
  }
  return ['#FFF8C5', '#E8D68F'];
}

/**
 * 节点的自然倾角（度）。
 *
 * 用 id 派生而不是随机数：同一条记录每次渲染角度一致，
 * 刷新页面时贴纸不该自己转个圈。新节点没有 id 时用传入的种子。
 */
export function nodeTilt(seed: number): number {
  const t = Math.abs(seed) % 5;   // 0~4
  return t - 2;                   // -2 ~ +2
}

/** 节点的自然倾角（带种子，种子为 0 时给一个固定角度） */
export function nodeTiltWithSeed(seed: number): number {
  if (seed === 0) {
    return -2;
  }
  return nodeTilt(seed);
}
