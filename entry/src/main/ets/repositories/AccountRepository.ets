/**
 * 账号会话的本地持久化。
 *
 * 与既有 Repository 的约定一致：失败返回默认值而非抛异常，界面不会因
 * 数据库/配置异常白屏。
 *
 * 存的是 UnionID / OpenID —— 账号标识符，不是访问令牌：
 *   · 不是密钥，不能用于调用任何接口；
 *   · 退出登录时一并清掉（与「我的 → 删除数据并撤回同意」一致）。
 * 真正的 access token 不在本机保存 —— 本应用没有服务端，也就没有需要
 * 用 token 换取服务端资源的地方。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AccountSession } from '../models/AccountSession';

const PREFS_NAME: string = 'caloriefit_account';
const UNION_ID_KEY: string = 'account.union_id';
const OPEN_ID_KEY: string = 'account.open_id';
const LOGIN_AT_KEY: string = 'account.login_at';

export class AccountRepository {
  private static store(context: common.UIAbilityContext): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: PREFS_NAME });
  }

  /** 读取本机会话；未登录返回 null */
  static getSession(context: common.UIAbilityContext): AccountSession | null {
    try {
      const store = AccountRepository.store(context);
      const unionId = store.getSync(UNION_ID_KEY, '') as string;
      const openId = store.getSync(OPEN_ID_KEY, '') as string;
      if (unionId.length === 0 || openId.length === 0) {
        return null;
      }
      const loginAt = store.getSync(LOGIN_AT_KEY, 0) as number;
      return new AccountSession(unionId, openId, loginAt);
    } catch (e) {
      return null;
    }
  }

  /** 写入会话 */
  static saveSession(context: common.UIAbilityContext, session: AccountSession): void {
    try {
      const store = AccountRepository.store(context);
      store.putSync(UNION_ID_KEY, session.unionId);
      store.putSync(OPEN_ID_KEY, session.openId);
      store.putSync(LOGIN_AT_KEY, session.loginAt);
      store.flush();
    } catch (e) {
      // 写失败只是下次要重新登录，不阻断流程
    }
  }

  /** 清除会话（退出登录） */
  static clearSession(context: common.UIAbilityContext): void {
    try {
      const store = AccountRepository.store(context);
      store.deleteSync(UNION_ID_KEY);
      store.deleteSync(OPEN_ID_KEY);
      store.deleteSync(LOGIN_AT_KEY);
      store.flush();
    } catch (e) {
    }
  }
}
