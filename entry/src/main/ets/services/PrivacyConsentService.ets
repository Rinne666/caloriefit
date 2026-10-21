/**
 * 首次使用与敏感健康信息单独同意。
 * 隐私政策实质内容或发布者信息变更时必须递增版本，要求用户重新确认。
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ConsentState, PRIVACY_POLICY_VERSION as CONSENT_POLICY_VERSION } from './ConsentState';
import { StepSensorService } from './StepSensorService';

const PREFS_NAME: string = 'caloriefit_privacy';
const GENERAL_CONSENT_VERSION_KEY: string = 'privacy.general_consent_version';
const HEALTH_CONSENT_VERSION_KEY: string = 'privacy.health_consent_version';
const ACCEPTED_AT_KEY: string = 'privacy.accepted_at';

/**
 * 隐私政策版本号。
 *
 * 单一来源在 common/Compliance.ets —— 隐私政策页展示的版本号与这里必须一致，
 * 否则会出现「页面显示一个版本、同意记录记的是另一个版本」。
 * 发布者填写法定主体、服务方和联系方式后，应同步更新该版本。
 */
export const PRIVACY_POLICY_VERSION: string = CONSENT_POLICY_VERSION;

export class PrivacyConsentService {
  private static store(context: common.UIAbilityContext): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: PREFS_NAME });
  }

  static isAccepted(context: common.UIAbilityContext): boolean {
    return ConsentState.isAccepted(context);
  }

  static async accept(context: common.UIAbilityContext): Promise<void> {
    const store = PrivacyConsentService.store(context);
    store.putSync(GENERAL_CONSENT_VERSION_KEY, PRIVACY_POLICY_VERSION);
    store.putSync(HEALTH_CONSENT_VERSION_KEY, PRIVACY_POLICY_VERSION);
    store.putSync(ACCEPTED_AT_KEY, Date.now());
    await store.flush();
    AppStorage.setOrCreate<boolean>('privacyConsentAccepted', true);
  }

  /**
   * 撤回同意。
   *
   * **先停采集，再撤记录**：
   * 撤回之后如果计步传感器还在跑，它会继续把步数写回数据库 ——
   * 用户明明撤了同意，健康数据却还在增长。
   * 所以这里先让 StepSensorService 退订、停轮询、停落库定时器。
   */
  static async revoke(context: common.UIAbilityContext): Promise<void> {
    StepSensorService.stop();
    const store = PrivacyConsentService.store(context);
    store.deleteSync(GENERAL_CONSENT_VERSION_KEY);
    store.deleteSync(HEALTH_CONSENT_VERSION_KEY);
    store.deleteSync(ACCEPTED_AT_KEY);
    await store.flush();
    AppStorage.setOrCreate<boolean>('privacyConsentAccepted', false);
  }
}
