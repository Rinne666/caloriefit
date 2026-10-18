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
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { THEME_PREF_KEY, ThemeMode } from '../common/DesignTokens';

const PREF_NAME = 'caloriefit_settings';

export class ThemeService {

  /** 从系统设置读回当前偏好，供 UI 初始化 */
  static async load(context: common.UIAbilityContext): Promise<ThemeMode> {
    try {
      const store = await context.getPreferences(context, { name: PREF_NAME });
      const raw = await store.get(THEME_PREF_KEY, ThemeMode.SYSTEM as string);
      const mode = (typeof raw === 'string' ? raw : ThemeMode.SYSTEM) as ThemeMode;
      AppStorage.setOrCreate<string>(THEME_PREF_KEY, mode);
      return mode;
    } catch (e) {
      AppStorage.setOrCreate<string>(THEME_PREF_KEY, ThemeMode.SYSTEM);
      return ThemeMode.SYSTEM;
    }
  }

  /** 保存偏好并立即应用。系统会随之重建对应资源目录下的颜色表 */
  static async apply(context: common.UIAbilityContext, mode: ThemeMode): Promise<boolean> {
    try {
      const store = await context.getPreferences(context, { name: PREF_NAME });
      await store.put(THEME_PREF_KEY, mode);
      await store.flush();
      AppStorage.setOrCreate<string>(THEME_PREF_KEY, mode);
      context.getApplicationContext().setColorMode(ThemeService.toColorMode(mode));
      return true;
    } catch (e) {
      return false;
    }
  }

  private static toColorMode(mode: ThemeMode): ConfigurationConstant.ColorMode {
    if (mode === ThemeMode.DARK) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    if (mode === ThemeMode.LIGHT) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  }
}
