import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ThemeService } from '../services/ThemeService';
import { StepSensorService } from '../services/StepSensorService';

const DOMAIN = 0x0000;

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
      this.startStepSensor();
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
      ThemeService.restore(this.context);
  }

  /**
   * 静默启动计步采集。
   *
   * 传 `requestPermission = false`：**冷启动绝不弹权限框**。
   * 已授权就直接订阅计步传感器；没授权就置为 NEED_PERMISSION，
   * 等用户自己在运动页点「开启自动采集」再申请。
   * 传感器不可用（模拟器、老旧机型）也不影响主流程。
   */
  private startStepSensor(): void {
    StepSensorService.start(this.context, false).catch(() => {
      hilog.warn(DOMAIN, 'testTag', 'step sensor not started');
    });
  }
}
