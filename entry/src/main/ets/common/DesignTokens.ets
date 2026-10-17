/**
 * CalorieFit Design Tokens V1.0
 * HarmonyOS ArkTS / Light Mode Only
 */

// 颜色
export interface ColorTokens {
  primary: string;
  primaryPressed: string;
  primaryLight: string;
  onPrimary: string;

  food: string;
  foodLight: string;

  activity: string;
  activityLight: string;

  bg: string;
  surface: string;
  surfaceMuted: string;

  text: string;
  textSecondary: string;
  textHint: string;

  border: string;
  divider: string;
  ringTrack: string;

  danger: string;
  dangerLight: string;

  disabledBg: string;
  disabledText: string;
}

export const color: ColorTokens = {
  primary: '#147A5E',
  primaryPressed: '#105E49',
  primaryLight: '#E7F5EF',
  onPrimary: '#FFFFFF',

  food: '#A85A1B',
  foodLight: '#FFF2E6',

  activity: '#1F6FCE',
  activityLight: '#EAF2FF',

  bg: '#F7F9F8',
  surface: '#FFFFFF',
  surfaceMuted: '#F0F4F2',

  text: '#1B2B24',
  textSecondary: '#5E6F68',
  textHint: '#6D7B73',

  border: '#E1E9E4',
  divider: '#E8EEEA',
  ringTrack: '#DFEAE3',

  danger: '#C33737',
  dangerLight: '#FFF0F0',

  disabledBg: '#E9EEEB',
  disabledText: '#7B8981'
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