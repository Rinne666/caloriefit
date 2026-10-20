/**
 * 华为账号（Account Kit）接入封装。
 *
 * ── 为什么不需要自建后端 ────────────────────────────────────────────
 * Account Kit 的 `HuaweiIDCredential` 直接带 `unionID` / `openID` 两个
 * **必选**字段，一键登录拿到的授权码无需再送服务端换 access token。
 * 本应用不建服务器、不做跨设备同步，只要账号标识就够了，因此整套登录
 * 可以在**纯本地**完成，维持「零自建后端」的定位。
 * 一旦将来要做云同步，就必须补一个能换 access token 的后端。
 *
 * ── 前置条件（不满足时登录必然失败，界面上要给出可执行的提示）──────────
 *   1. `module.json5` 的 metadata 里配了 `client_id`（AGC 控制台 → 项目
 *      设置 → 常规 → 应用的 client_id）。
 *   2. 应用**已签名**，且证书指纹与 AGC 里登记的一致。Account Kit 会校验
 *      包指纹，未签名的调试包会直接报 1001500001。
 *
 * 官方文档：
 *   https://developer.huawei.com/consumer/cn/doc/hms-guides/account-kit
 */

import { authentication } from '@kit.AccountKit';
import { util } from '@kit.ArkTS';
import { common, bundleManager } from '@kit.AbilityKit';
import { AccountSession } from '../models/AccountSession';
import { AccountRepository } from '../repositories/AccountRepository';

/** 账号相关错误码（Account Kit） */
export class AccountErrorCode {
  /** 未配置 client_id */
  static readonly NOT_CONFIGURED: number = -10001;
  /** 华为账号未登录 */
  static readonly NOT_LOGGED_IN: number = 1001502001;
  /** 未授权（应用未申请对应权限） */
  static readonly NOT_AUTHORIZED: number = 1001502002;
  /** 网络错误 */
  static readonly NETWORK_ERROR: number = 1001502005;
  /** 用户取消 */
  static readonly USER_CANCELED: number = 1001502012;
  /** 包指纹校验失败（通常是没签名或签名与 AGC 不一致） */
  static readonly FINGERPRINT_ERROR: number = 1001500001;
  /** 需要的 scopes / 权限未在 AGC 申请 */
  static readonly SCOPE_NOT_REQUESTED: number = 1001502014;
  /** 用户未同意协议 */
  static readonly AGREEMENT_NOT_ACCEPTED: number = 1005300001;
  /** 其他 */
  static readonly UNKNOWN: number = -1;
}

export class HuaweiAccountService {

  /** 错误码 → 界面文案。面向用户，不暴露原始错误对象。 */
  static errorText(code: number): string {
    if (code === AccountErrorCode.NOT_CONFIGURED) {
      return '尚未配置 client_id，无法登录。请在 AGC 控制台获取后填入 module.json5 的 metadata。';
    }
    if (code === AccountErrorCode.NOT_LOGGED_IN) {
      return '设备尚未登录华为账号，请先在系统设置中登录。';
    }
    if (code === AccountErrorCode.NOT_AUTHORIZED) {
      return '应用未获得账号授权，请检查 AGC 中的权限配置。';
    }
    if (code === AccountErrorCode.NETWORK_ERROR) {
      return '网络连接失败，请检查网络后重试。';
    }
    if (code === AccountErrorCode.USER_CANCELED) {
      return '已取消登录。';
    }
    if (code === AccountErrorCode.FINGERPRINT_ERROR) {
      return '签名校验未通过。Account Kit 要求已签名的包，且证书指纹与 AGC 登记一致。';
    }
    if (code === AccountErrorCode.SCOPE_NOT_REQUESTED) {
      return '所需的账号权限尚未在 AGC 申请通过。';
    }
    if (code === AccountErrorCode.AGREEMENT_NOT_ACCEPTED) {
      return '请先阅读并同意用户协议与隐私政策。';
    }
    return '登录失败，请稍后重试。';
  }

  /**
   * 读取 module.json5 里配置的 client_id。
   *
   * 未配置时返回空串 —— 调用方据此给出明确提示，而不是让用户对着一个
   * 天书般的系统错误码发愣。
   */
  static async readClientId(): Promise<string> {
    try {
      // 必须同时带 GET_BUNDLE_INFO_WITH_METADATA —— 只给 HAP_MODULE 的话
      // 返回的 moduleInfo.metadata 是空的，client_id 永远读不到。
      const flags = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_HAP_MODULE |
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_METADATA;
      const info = await bundleManager.getBundleInfoForSelf(flags);
      if (info.hapModulesInfo.length === 0) {
        return '';
      }
      const metadata = info.hapModulesInfo[0].metadata;
      if (metadata === undefined || metadata.length === 0) {
        return '';
      }
      for (let i = 0; i < metadata.length; i++) {
        if (metadata[i].name === 'client_id') {
          const value = metadata[i].value as string;
          return value;
        }
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  /** 是否已具备登录的前置条件（client_id 已配） */
  static async isConfigured(): Promise<boolean> {
    const clientId = await HuaweiAccountService.readClientId();
    return clientId.length > 0 && clientId.indexOf('YOUR_') !== 0;
  }

  /**
   * 静默登录：设备已登录华为账号时直接拿凭证，不弹任何界面。
   *
   * 用于「重装应用 / 换机回来」的续登场景。未登录时返回 null（不是错误）。
   */
  static async silentLogin(context: common.UIAbilityContext): Promise<AccountSession | null> {
    if (!await HuaweiAccountService.isConfigured()) {
      return null;
    }
    try {
      const request = new authentication.HuaweiIDProvider().createLoginWithHuaweiIDRequest();
      // false = 已登录则直接返回，未登录也不弹登录页
      request.forceLogin = false;
      request.state = util.generateRandomUUID();
      const controller = new authentication.AuthenticationController(context);
      const response = await controller.executeRequest(request);
      // executeRequest 的静态返回类型是基类 AuthenticationResponse（空类），
      // 实际对象是派生类 LoginWithHuaweiIDResponse，带 data 字段。
      const loginResponse = response as authentication.LoginWithHuaweiIDResponse;
      const credential = loginResponse.data;
      if (credential === undefined || credential === null) {
        return null;
      }
      return HuaweiAccountService.toSession(credential);
    } catch (e) {
      // 静默登录失败一律当作「没登录」，不打扰用户
      return null;
    }
  }

  /**
   * 主动登录（走系统账号登录页）。
   *
   * 页面上的 `LoginWithHuaweiIDButton` 组件走的是官方 UI 通道；这个 API
   * 供不需要官方按钮的场景使用。
   */
  static async signIn(context: common.UIAbilityContext): Promise<AccountSession> {
    if (!await HuaweiAccountService.isConfigured()) {
      throw new Error(String(AccountErrorCode.NOT_CONFIGURED));
    }
    const request = new authentication.HuaweiIDProvider().createLoginWithHuaweiIDRequest();
    // true = 未登录时弹出华为账号登录页
    request.forceLogin = true;
    request.state = util.generateRandomUUID();
    const controller = new authentication.AuthenticationController(context);
    const response = await controller.executeRequest(request);
    const loginResponse = response as authentication.LoginWithHuaweiIDResponse;
    const credential = loginResponse.data;
    if (credential === undefined || credential === null) {
      throw new Error(String(AccountErrorCode.NOT_LOGGED_IN));
    }
    return HuaweiAccountService.toSession(credential);
  }

  /**
   * 退出登录：撤销本应用在账号侧的授权 + 清掉本机会话。
   *
   * 撤销授权是「主动收回」而不是「退出登录」—— 退出登录只清本地标识，
   * 用户在系统账号里仍然授权着本应用。两者都做，用户才真正拿回控制权。
   */
  static async signOut(context: common.UIAbilityContext): Promise<void> {
    try {
      const request = new authentication.HuaweiIDProvider().createCancelAuthorizationRequest();
      const controller = new authentication.AuthenticationController(context);
      await controller.executeRequest(request);
    } catch (e) {
      // 撤销失败不影响退出登录：本地会话照常清除
    }
    AccountRepository.clearSession(context);
  }

  /** 从凭证取出账号标识 */
  private static toSession(credential: authentication.LoginWithHuaweiIDCredential): AccountSession {
    return new AccountSession(credential.unionID, credential.openID, Date.now());
  }
}
