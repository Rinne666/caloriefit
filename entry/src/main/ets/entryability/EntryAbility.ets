import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { THEME_PREF_KEY, ThemeMode } from '../common/DesignTokens';

const DOMAIN = 0x0000;
const PREF_NAME = 'caloriefit_settings';

/** 把用户偏好映射到系统 ColorMode；SYSTEM 时交给系统跟随 */
function toColorMode(mode: ThemeMode): ConfigurationConstant.ColorMode {
  if (mode === ThemeMode.DARK) {
    return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }
  if (mode === ThemeMode.LIGHT) {
    return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }
  return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      this.restoreTheme();
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }

  /**
   * 恢复用户保存的主题偏好。
   *
   * V3 之前这里硬写 COLOR_MODE_LIGHT 强制浅色，导致 resources/dark 里的
   * 暗色资源永远不会被系统选中。改为读取偏好后交给资源限定符自动换色。
   *
   * 异步但不阻塞：loadContent 已完成，深色资源由系统按 ColorMode 加载。
   */
  private restoreTheme(): void {
    this.context.getApplicationContext()
      .getPreferences(this.context, { name: PREF_NAME })
      .then(async (store: preferences.Preferences) => {
        const raw = await store.get(THEME_PREF_KEY, ThemeMode.SYSTEM as string);
        const mode = (typeof raw === 'string' ? raw : ThemeMode.SYSTEM) as ThemeMode;
        AppStorage.setOrCreate<string>(THEME_PREF_KEY, mode);
        this.context.getApplicationContext().setColorMode(toColorMode(mode));
        hilog.info(DOMAIN, 'testTag', 'theme restored: %{public}s', mode);
      })
      .catch(() => {
        // 读取失败退回跟随系统，不阻断启动
        this.context.getApplicationContext()
          .setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      });
  }
}
