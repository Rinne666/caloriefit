/**
 * 主题偏好：跟随系统 / 浅色 / 深色
 *
 * V3 新增。此前 EntryAbility 硬写 COLOR_MODE_LIGHT 强制浅色，
 * resources/dark 下的暗色资源永远不会被系统选中。
 *
 * 分工：
 *   · 具体色值 —— 由 resources/{base,dark}/element/color.json 资源限定符负责
 *   · 本服务只负责「用户选哪一种」的偏好持久化，并把 ColorMode 告诉系统
 *
 * 这样组件不需要任何 useDark 判断，切主题也不会漏掉某个页面。
 *
 * ArkTS 约束（相对 TS 的额外限制）：
 *   · preferences.getPreferences 是模块级函数，不是 Context 的方法
 *   · ConfigurationConstant 需从 @kit.AbilityKit 显式导入
 *   · catch 分支不能用 any / unknown
 */

import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { THEME_PREF_KEY, ThemeMode } from '../common/DesignTokens';

const PREF_NAME = 'caloriefit_settings';

function toColorMode(mode: ThemeMode): ConfigurationConstant.ColorMode {
  if (mode === ThemeMode.DARK) {
    return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }
  if (mode === ThemeMode.LIGHT) {
    return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }
  return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
}

/** 把任意存储值收敛成合法的 ThemeMode，缺失/脏数据回到 NutriScan 深色基线 */
function normalize(v: preferences.ValueType): ThemeMode {
  if (typeof v !== 'string') {
    return ThemeMode.DARK;
  }
  if (v === ThemeMode.LIGHT || v === ThemeMode.DARK || v === ThemeMode.SYSTEM) {
    return v as ThemeMode;
  }
  return ThemeMode.DARK;
}

export class ThemeService {

  /** 从系统设置读回当前偏好，供 UI 初始化 */
  static async load(ctx: common.UIAbilityContext): Promise<ThemeMode> {
    try {
      const store = await preferences.getPreferences(ctx, { name: PREF_NAME });
      // NutriScan 的默认界面是暗色；用户可在「我的 → 外观」显式选择另外两种模式。
      const mode = normalize(await store.get(THEME_PREF_KEY, ThemeMode.DARK as string));
      AppStorage.setOrCreate<string>(THEME_PREF_KEY, mode);
      return mode;
    } catch (e) {
      AppStorage.setOrCreate<string>(THEME_PREF_KEY, ThemeMode.DARK);
      return ThemeMode.DARK;
    }
  }

  /** 保存偏好并立即应用到当前 UIAbility。系统随之重建对应资源目录下的颜色表 */
  static async apply(ctx: common.UIAbilityContext, mode: ThemeMode): Promise<boolean> {
    try {
      const store = await preferences.getPreferences(ctx, { name: PREF_NAME });
      await store.put(THEME_PREF_KEY, mode);
      await store.flush();
      AppStorage.setOrCreate<string>(THEME_PREF_KEY, mode);
      ctx.setColorMode(toColorMode(mode));
      return true;
    } catch (e) {
      return false;
    }
  }

  /**
   * 供 EntryAbility 在页面加载完成后调用。
   * UIAbility 的模式优先级高于 ApplicationContext；必须设置 AbilityContext，
   * 否则冷启动可能仍按设备浅色模式解析资源，直到用户手动切换主题。
   */
  static async restore(ctx: common.UIAbilityContext): Promise<void> {
    try {
      const store = await preferences.getPreferences(ctx, { name: PREF_NAME });
      const mode = normalize(await store.get(THEME_PREF_KEY, ThemeMode.DARK as string));
      AppStorage.setOrCreate<string>(THEME_PREF_KEY, mode);
      ctx.setColorMode(toColorMode(mode));
    } catch (e) {
      ctx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    }
  }
}
