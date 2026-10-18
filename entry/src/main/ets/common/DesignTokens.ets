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

  /** 饮水模块强调色（实测原版用青色系，与运动蓝区分开） */
  waterAccent: ResourceColor;

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

  /** V4 高饱和氛围底（页面级三段渐变） */
  pageDeep: ResourceColor;
  pageMid: ResourceColor;
  pageGlow: ResourceColor;

  /** V4 玻璃拟态层 */
  glassFill: ResourceColor;
  glassFillStrong: ResourceColor;
  glassBorder: ResourceColor;
  glassShadow: ResourceColor;

  /** V4 主视觉饱和双色调 */
  heroA: ResourceColor;
  heroB: ResourceColor;
  /** 主视觉卡上的进度环轨道；两套主题同值（主视觉恒为深色饱和底） */
  heroRingTrack: ResourceColor;

  /** V4 卡片情绪色调 veil（冰蓝 / 奶黄 / 金属灰 / 暖橙） */
  toneIceVeil: ResourceColor;
  toneCreamVeil: ResourceColor;
  toneSteelVeil: ResourceColor;
  toneAmberVeil: ResourceColor;

  /** V4 主按钮辉光 */
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

  waterAccent: $r('app.color.water_accent'),

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
  macroOk: $r('app.color.macro_ok'),

  pageDeep: $r('app.color.page_deep'),
  pageMid: $r('app.color.page_mid'),
  pageGlow: $r('app.color.page_glow'),

  glassFill: $r('app.color.glass_fill'),
  glassFillStrong: $r('app.color.glass_fill_str'),
  glassBorder: $r('app.color.glass_border'),
  glassShadow: $r('app.color.glass_shadow'),

  heroA: $r('app.color.hero_a'),
  heroB: $r('app.color.hero_b'),
  heroRingTrack: $r('app.color.hero_ring_track'),

  toneIceVeil: $r('app.color.tone_ice_veil'),
  toneCreamVeil: $r('app.color.tone_cream_veil'),
  toneSteelVeil: $r('app.color.tone_steel_veil'),
  toneAmberVeil: $r('app.color.tone_amber_veil'),

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
 * V4：高饱和背景 + 玻璃拟态卡片
 * ------------------------------------------------------------------
 * 这一版把视觉语言换成「海报式商品卡」：
 *   · 页面底改成高饱和三段渐变，负责情绪氛围
 *   · 卡片在半透明玻璃上叠一层情绪色调 veil，浮在氛围之上
 *   · 同一个页面里的卡片用不同色调，但字体/圆角/排版完全一致
 *
 * 两个关键决定：
 *
 * 1) 渐变与毛玻璃一律走函数，不在页面里手写字面量。
 *    渐变色标一旦散落到十几个页面，深浅色切换就会漏。
 *    现在改色只动 color.json，调角度只动这里。
 *
 * 2) 卡片色调由「内容哈希」决定，而不是随手在页面里挑。
 *    同一份数据永远得到同一个色调（重进页面不会变色），
 *    不同条目又大概率不同 —— 这正是「统一但不重复」的实现方式。
 *
 * 玻璃效果能看见的前提是卡片后面真的有东西可模糊，
 * 所以页面底色必须换成渐变而不是纯色，否则 backdropBlur 等于白做。
 * ================================================================== */

export interface GlassTokens {
  /** 背景模糊半径(vp)。过大会让文字边缘发糊，12~16 是实测可用区间 */
  blurRadius: number;
  /** 玻璃描边宽度 */
  borderWidth: number;
  /** 玻璃卡片圆角 */
  cardRadius: number;
  /** 投影模糊半径 */
  shadowRadius: number;
  /** 投影纵向偏移，制造「悬浮」感 */
  shadowOffsetY: number;
  /** 顶部高光条高度 */
  sheenHeight: number;
}

export const glass: GlassTokens = {
  blurRadius: 14,
  borderWidth: 1,
  cardRadius: 24,
  shadowRadius: 20,
  shadowOffsetY: 10,
  sheenHeight: 1
};

/** 情绪色调数量，与 tone_*_veil 资源一一对应 */
const TONE_COUNT: number = 4;

/**
 * 页面氛围底：三段渐变，135°（左上 → 右下）。
 * 页面级 Scroll / Tabs 统一用它，替代原来的纯色背景。
 */
export function pageGradient(): LinearGradientOptions {
  return {
    angle: 135,
    colors: [[color.pageDeep, 0], [color.pageMid, 0.58], [color.pageGlow, 1]]
  };
}

/**
 * 玻璃卡底色：色调 veil 从左上渗入，到右下退成纯玻璃。
 *
 * veil 自带 alpha（深色 0x4D / 浅色 0x38），所以它叠在页面渐变上
 * 只是「染色」，不会盖住背后的氛围 —— 这就是玻璃感而不是实色块。
 */
export function glassGradient(veil: ResourceColor): LinearGradientOptions {
  return {
    angle: 160,
    colors: [[veil, 0], [color.glassFill, 0.68], [color.glassFill, 1]]
  };
}

/** 主视觉卡：饱和双色调，160°。白字压在上面对比度最稳。 */
export function heroGradient(): LinearGradientOptions {
  return {
    angle: 160,
    colors: [[color.heroA, 0], [color.heroB, 1]]
  };
}

/** 主 CTA 按钮面：品牌色 → 按下色，配投影做出立体感 */
export function primaryButtonGradient(): LinearGradientOptions {
  return {
    angle: 90,
    colors: [[color.primary, 0], [color.primaryPressed, 1]]
  };
}

/** 玻璃投影。offsetY 为正 = 光从上方来，卡片浮在底板之上。 */
export function glassShadow(radiusV: number, offsetY: number): ShadowOptions {
  return {
    radius: radiusV,
    color: color.glassShadow,
    offsetX: 0,
    offsetY: offsetY
  };
}

/** 按钮辉光投影：比玻璃投影更紧更亮，让 CTA 在一片玻璃里先被看见 */
export function buttonGlow(): ShadowOptions {
  return {
    radius: 14,
    color: color.btnGlow,
    offsetX: 0,
    offsetY: 6
  };
}

/**
 * 字符串 → 稳定散列。
 * 只用于挑色调，不承担任何业务语义，因此不需要密码学强度。
 */
export function toneHash(key: string): number {
  let h: number = 0;
  for (let i = 0; i < key.length; i++) {
    h = (h * 31 + key.charCodeAt(i)) % 99991;
  }
  return h;
}

/**
 * 按 key 分配情绪色调（冰蓝 / 奶黄 / 金属灰 / 暖橙）。
 *
 * 用分支返回而不是数组下标，和上面的 themeLabel 同一个理由：
 * ArkTS 对索引访问的静态限制让数组下标写法不够稳，分支行为确定。
 */
export function toneVeil(key: string): ResourceColor {
  const idx: number = toneHash(key) % TONE_COUNT;
  if (idx === 0) {
    return color.toneIceVeil;
  }
  if (idx === 1) {
    return color.toneCreamVeil;
  }
  if (idx === 2) {
    return color.toneSteelVeil;
  }
  return color.toneAmberVeil;
}