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

  disabledBg: ResourceColor;
  disabledText: ResourceColor;

  /** V3 宏量分色 */
  macroProtein: ResourceColor;
  macroCarbs: ResourceColor;
  macroFat: ResourceColor;
  macroOk: ResourceColor;
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

  disabledBg: $r('app.color.disabled_bg'),
  disabledText: $r('app.color.disabled_text'),

  macroProtein: $r('app.color.macro_protein'),
  macroCarbs: $r('app.color.macro_carbs'),
  macroFat: $r('app.color.macro_fat'),
  macroOk: $r('app.color.macro_ok')
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