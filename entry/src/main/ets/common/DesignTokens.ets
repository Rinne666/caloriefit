/**
 * CalorieFit Design Tokens
 * HarmonyOS ArkTS
 *
 * V3：颜色改为资源限定符引用（$r('app.color.*')），
 * 深浅两套值分别定义在 resources/base/element/color.json 与
 * resources/dark/element/color.json，由系统 ColorMode 自动切换。
 *
 * 这样做的收益：所有组件继续写 color.text / color.bg 不需要改一行，
 * 而系统切深色时整站自动换色。硬编码 hex 的旧写法做不到这点。
 *
 * 暗色值的来源：对 NutriScan (app.nutriscan v1.9.8) 真机截图做像素直方图
 * 实测得到，非设计稿推断。关键修正 —— 初判其为「纯黑 #000000」是错的，
 * 实测底色为 #0C0C0C（近黑带暖调）。
 */

// 颜色
export interface ColorTokens {
  primary: ResourceColor;
  primaryPressed: ResourceColor;
  primaryLight: ResourceColor;
  onPrimary: ResourceColor;

  food: ResourceColor;
  foodLight: ResourceColor;

  activity: ResourceColor;
  activityLight: ResourceColor;

  /** 首页热量环的薄荷色亮端，来自 NutriScan 实测配色 */
  calorieMint: ResourceColor;

  bg: ResourceColor;
  surface: ResourceColor;
  surfaceMuted: ResourceColor;

  text: ResourceColor;
  textSecondary: ResourceColor;
  textHint: ResourceColor;

  border: ResourceColor;
  divider: ResourceColor;
  ringTrack: ResourceColor;

  danger: ResourceColor;
  dangerLight: ResourceColor;
  /** 连胜/火焰类强调色；原为 premium 渐变副色，订阅入口删除后独立成通用强调色 */
  streakOrange: ResourceColor;

  disabledBg: ResourceColor;
  disabledText: ResourceColor;

  /** V3 宏量分色 */
  macroProtein: ResourceColor;
  macroCarbs: ResourceColor;
  macroFat: ResourceColor;
  macroOk: ResourceColor;

  /** 页面背景色标；各主题可分别配置，当前按平面底色使用 */
  pageDeep: ResourceColor;
  pageMid: ResourceColor;
  pageGlow: ResourceColor;

  /** 承接既有组件 API 的表面层；实际值为不透明纯色 */
  glassFill: ResourceColor;
  glassFillStrong: ResourceColor;
  glassBorder: ResourceColor;
  glassShadow: ResourceColor;

  /** 主视觉卡上的进度环轨道 */
  heroRingTrack: ResourceColor;

  /** 旧按钮辉光资源，当前保持透明 */
  btnGlow: ResourceColor;
}

export const color: ColorTokens = {
  primary: $r('app.color.primary'),
  primaryPressed: $r('app.color.primary_pressed'),
  primaryLight: $r('app.color.primary_light'),
  onPrimary: $r('app.color.on_primary'),

  food: $r('app.color.food'),
  foodLight: $r('app.color.food_light'),

  activity: $r('app.color.activity'),
  activityLight: $r('app.color.activity_light'),

  calorieMint: $r('app.color.calorie_mint'),

  bg: $r('app.color.bg'),
  surface: $r('app.color.surface'),
  surfaceMuted: $r('app.color.surface_muted'),

  text: $r('app.color.text'),
  textSecondary: $r('app.color.text_secondary'),
  textHint: $r('app.color.text_hint'),

  border: $r('app.color.border'),
  divider: $r('app.color.divider'),
  ringTrack: $r('app.color.ring_track'),

  danger: $r('app.color.danger'),
  dangerLight: $r('app.color.danger_light'),
  streakOrange: $r('app.color.streak_orange'),

  disabledBg: $r('app.color.disabled_bg'),
  disabledText: $r('app.color.disabled_text'),

  macroProtein: $r('app.color.macro_protein'),
  macroCarbs: $r('app.color.macro_carbs'),
  macroFat: $r('app.color.macro_fat'),
  macroOk: $r('app.color.macro_ok'),

  pageDeep: $r('app.color.page_deep'),
  pageMid: $r('app.color.page_mid'),
  pageGlow: $r('app.color.page_glow'),

  glassFill: $r('app.color.glass_fill'),
  glassFillStrong: $r('app.color.glass_fill_str'),
  glassBorder: $r('app.color.glass_border'),
  glassShadow: $r('app.color.glass_shadow'),

  heroRingTrack: $r('app.color.hero_ring_track'),

  btnGlow: $r('app.color.btn_glow')
};

// 字号：用于 fontSize()，单位 fp
export interface FontSizeTokens {
  hero: number;
  metric: number;
  pageTitle: number;
  sectionTitle: number;
  body: number;
  secondary: number;
  caption: number;
}

export const fontSize: FontSizeTokens = {
  hero: 36,
  metric: 26,
  pageTitle: 24,
  sectionTitle: 18,
  body: 16,
  secondary: 14,
  caption: 12
};

// 间距：单位 vp
export interface SpaceTokens {
  xxs: number;
  xs: number;
  sm: number;
  md: number;
  lg: number;
  xl: number;
  xxl: number;
  xxxl: number;
}

export const space: SpaceTokens = {
  xxs: 4,
  xs: 8,
  sm: 12,
  md: 16,
  lg: 20,
  xl: 24,
  xxl: 32,
  xxxl: 40
};

// 圆角：单位 vp
export interface RadiusTokens {
  small: number;
  medium: number;
  large: number;
  card: number;
  pill: number;
}

export const radius: RadiusTokens = {
  small: 8,
  medium: 12,
  large: 16,
  card: 20,
  pill: 999
};

// 页面与组件尺寸：单位 vp
export interface LayoutTokens {
  pagePadding: number;
  topBarHeight: number;
  bottomTabHeight: number;

  cardPadding: number;
  cardGap: number;

  buttonHeight: number;
  inputHeight: number;
  listRowMinHeight: number;

  ringSize: number;
  ringStroke: number;
  progressHeight: number;

  iconSize: number;
  borderWidth: number;

  minTouchSize: number;
}

export const layout: LayoutTokens = {
  pagePadding: 16,
  topBarHeight: 56,
  bottomTabHeight: 60,

  cardPadding: 16,
  cardGap: 12,

  buttonHeight: 48,
  inputHeight: 48,
  listRowMinHeight: 68,

  ringSize: 168,
  ringStroke: 12,
  progressHeight: 8,

  iconSize: 22,
  borderWidth: 1,

  minTouchSize: 44
};


/* ==================================================================
 * V3：主题模式
 * ------------------------------------------------------------------
 * 深浅切换已改由 HarmonyOS 资源限定符接管（见文件头说明），
 * 这里只负责「用户选择跟随系统 / 强制浅色 / 强制深色」这一层偏好。
 *
 * 为什么不保留代码里的 darkColor：
 *   资源限定符是系统级方案，切换即时生效、不需要重渲染任何组件；
 *   代码里维护两套 palette 则需要手动触发刷新，且极易漏掉某个组件。
 * ================================================================== */

export enum ThemeMode {
  SYSTEM = 'system',
  LIGHT = 'light',
  DARK = 'dark'
}

export const THEME_PREF_KEY: string = 'caloriefit_theme';

/**
 * 中文标签用函数而非 Record<K,V>。
 * ArkTS 不支持对字段做索引访问（arkts-no-props-by-index），
 * THEME_LABELS[mode] 这类写法编译不过，必须走函数调用。
 */
export function themeLabel(m: ThemeMode): string {
  if (m === ThemeMode.LIGHT) { return '浅色'; }
  if (m === ThemeMode.DARK) { return '深色'; }
  return '跟随系统';
}

/** 尺寸微调：暗色下靠描边而非阴影分层，故卡片圆角略增 */
export interface DarkLayoutTokens {
  borderWidth: number;
  cardRadius: number;
  gap: number;
  pagePadding: number;
}

export const darkLayout: DarkLayoutTokens = {
  borderWidth: 1,
  cardRadius: 22,
  gap: 12,
  pagePadding: 16
};

/** 动效参数 */
export interface MotionTokens {
  durationFast: number;
  durationBase: number;
  durationSlow: number;
  curveEaseOut: Curve;
}

/**
 * 动效参数。
 * 取自 NutriScan 的 libapp.so 代码证据：PageRouteBuilder + Hero +
 * FadeTransition + SlideTransition + Curves.easeOut，
 * 原 App 页面转场实测约 300ms。
 */
export const motion: MotionTokens = {
  durationFast: 150,
  durationBase: 300,
  durationSlow: 450,
  curveEaseOut: Curve.EaseOut
};


/* ==================================================================
 * 平面材质兼容层
 * ------------------------------------------------------------------
 * 保留这些旧函数名以减少组件 API 改动；页面、卡片和按钮现在
 * 分别解析为主题色标中的平面纯色。深色主题对应 NutriScan 实测色板。
 * ================================================================== */

export interface GlassTokens {
  /** 卡片描边宽度 */
  borderWidth: number;
  /** 卡片圆角 */
  cardRadius: number;
  /** 兼容旧投影 API 的模糊半径 */
  shadowRadius: number;
  /** 兼容旧投影 API 的纵向偏移 */
  shadowOffsetY: number;
  /** 顶部高光条高度 */
  sheenHeight: number;
}

export const glass: GlassTokens = {
  borderWidth: 1,
  cardRadius: 24,
  shadowRadius: 20,
  shadowOffsetY: 10,
  sheenHeight: 1
};

/**
 * 页面背景保留渐变 API，三个色标取同一个底色，确保组件为纯色显示。
 */
export function pageGradient(): LinearGradientOptions {
  return {
    angle: 135,
    colors: [[color.bg, 0], [color.bg, 0.58], [color.bg, 1]]
  };
}

/**
 * 保留旧卡片 API；无论传入何种装饰色，都返回当前主题的纯色卡面。
 */
export function glassGradient(_veil: ResourceColor): LinearGradientOptions {
  return {
    angle: 160,
    colors: [[color.surface, 0], [color.surface, 1]]
  };
}

/** 主视觉卡也使用主题表面色，不额外加渐变。 */
export function heroGradient(): LinearGradientOptions {
  return {
    angle: 160,
    colors: [[color.surface, 0], [color.surface, 1]]
  };
}

/** 主 CTA 按钮保留渐变 API，两个色标使用同一品牌色。 */
export function primaryButtonGradient(): LinearGradientOptions {
  return {
    angle: 90,
    colors: [[color.primary, 0], [color.primary, 1]]
  };
}

/** 保留旧投影 API；主题资源将其设为透明，使卡片保持平面。 */
export function glassShadow(radiusV: number, offsetY: number): ShadowOptions {
  return {
    radius: radiusV,
    color: color.glassShadow,
    offsetX: 0,
    offsetY: offsetY
  };
}

/** 保留旧按钮光晕 API；主题资源将其设为透明。 */
export function buttonGlow(): ShadowOptions {
  return {
    radius: 14,
    color: color.btnGlow,
    offsetX: 0,
    offsetY: 6
  };
}

/**
 * 保留旧组件 API；卡片统一使用当前主题的表面色。
 */
export function toneVeil(_key: string): ResourceColor {
  return color.surface;
}
