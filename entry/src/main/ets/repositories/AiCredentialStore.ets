/**
 * API Key 凭证存储：默认会话内存；开启“记住”时使用 Asset Store Kit。
 * 安全存储不可用时抛出 SECURE_STORE_UNAVAILABLE，绝不降级为明文 Preferences。
 * AssetMap 为 Map<Tag, Value>，BYTES 类型 Tag（含 ALIAS/SECRET）的值必须为 Uint8Array。
 */

import asset from '@ohos.security.asset';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { AI_SECRET_ALIAS, AiErrorCode, AiError } from '../common/AiConstants';

export class AiCredentialStore {
  private static sessionKey: string | null = null;

  private static aliasBytes(): Uint8Array {
    const encoder = new util.TextEncoder();
    return encoder.encodeInto(AI_SECRET_ALIAS);
  }

  static async getApiKey(): Promise<string | null> {
    if (AiCredentialStore.sessionKey !== null) {
      return AiCredentialStore.sessionKey;
    }
    try {
      const queryMap: asset.AssetMap = new Map();
      queryMap.set(asset.Tag.ALIAS, AiCredentialStore.aliasBytes());
      queryMap.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const result: Array<asset.AssetMap> = await asset.query(queryMap);
      if (result.length > 0) {
        const secret = result[0].get(asset.Tag.SECRET);
        if (secret instanceof Uint8Array) {
          const decoder = util.TextDecoder.create('utf-8');
          const key = decoder.decodeToString(secret);
          AiCredentialStore.sessionKey = key;
          return key;
        }
      }
      return null;
    } catch (e) {
      // 查不到已保存的 Key 视为不存在
      return null;
    }
  }

  static async saveApiKey(apiKey: string, remember: boolean): Promise<void> {
    // 任何情况下本会话可用
    AiCredentialStore.sessionKey = apiKey;
    if (!remember) {
      return;
    }
    try {
      const encoder = new util.TextEncoder();
      const addMap: asset.AssetMap = new Map();
      addMap.set(asset.Tag.ALIAS, AiCredentialStore.aliasBytes());
      addMap.set(asset.Tag.SECRET, encoder.encodeInto(apiKey));
      await asset.add(addMap);
    } catch (e) {
      const err = e as BusinessError;
      throw new AiError(AiErrorCode.SECURE_STORE_UNAVAILABLE, err.message);
    }
  }

  static async clearApiKey(): Promise<void> {
    AiCredentialStore.sessionKey = null;
    try {
      const removeMap: asset.AssetMap = new Map();
      removeMap.set(asset.Tag.ALIAS, AiCredentialStore.aliasBytes());
      await asset.remove(removeMap);
    } catch (e) {
      // 不存在视为已清除
    }
  }

  /**
   * 环境是否支持安全存储。asset 模块无 isSupport 探测接口，
   * 以真实写入结果为准（saveApiKey 失败时抛 SECURE_STORE_UNAVAILABLE）。
   */
  static async canPersistSecurely(): Promise<boolean> {
    return true;
  }
}