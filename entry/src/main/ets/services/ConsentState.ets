/**
 * 隐私同意状态（同步判定，无副作用）。
 *
 * ## 为什么要单独成模块
 * 撤回同意要**先停计步采集**，而计步采集在读写时也要**校验同意态**。
 * 这会让 PrivacyConsentService 与 StepSensorService 互相 import —— 成环。
 * 所以把「同意没给 / 给了」的判定抽到这里，两边都只依赖它：
 *
 *   PrivacyConsentService ──▶ ConsentState ◀── StepSensorService
 *   PrivacyConsentService ──▶ StepSensorService（撤回时停采集）
 *
 * 这样依赖是单向的，不会成环。
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Compliance } from '../common/Compliance';

const PREFS_NAME: string = 'caloriefit_privacy';
const GENERAL_CONSENT_VERSION_KEY: string = 'privacy.general_consent_version';
const HEALTH_CONSENT_VERSION_KEY: string = 'privacy.health_consent_version';

/**
 * 隐私政策版本号。
 *
 * 单一来源在 common/Compliance.ets —— 隐私政策页展示的版本号与这里必须一致，
 * 否则会出现「页面显示一个版本、同意记录记的是另一个版本」。
 * 发布者填写法定主体、服务方和联系方式后，应同步更新该版本。
 */
export const PRIVACY_POLICY_VERSION: string = Compliance.POLICY_VERSION;

export class ConsentState {
  private static store(context: common.UIAbilityContext): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: PREFS_NAME });
  }

  /**
   * 用户是否已经对当前版本的隐私政策（一般 + 敏感健康信息）都点了同意。
   *
   * 读取失败一律按「未同意」处理 —— 宁可少采一点数据，
   * 也不能在用户没同意的情况下继续写。
   */
  static isAccepted(context: common.UIAbilityContext): boolean {
    try {
      const store = ConsentState.store(context);
      return store.getSync(GENERAL_CONSENT_VERSION_KEY, '') === PRIVACY_POLICY_VERSION &&
        store.getSync(HEALTH_CONSENT_VERSION_KEY, '') === PRIVACY_POLICY_VERSION;
    } catch (e) {
      return false;
    }
  }
}
