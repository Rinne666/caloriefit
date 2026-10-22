/**
 * API Key 凭证存储：默认会话内存；开启“记住”时使用 Asset Store Kit。
 * 安全存储不可用时抛出 SECURE_STORE_UNAVAILABLE，绝不降级为明文 Preferences。
 * AssetMap 为 Map<Tag, Value>，BYTES 类型 Tag（含 ALIAS/SECRET）的值必须为 Uint8Array。
 */

import asset from '@ohos.security.asset';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { AI_SECRET_ALIAS, AI_LEGACY_SECRET_ALIAS, AiErrorCode, AiError } from '../common/AiConstants';

export class AiCredentialStore {
  private static sessionKey: string | null = null;

  private static aliasBytes(): Uint8Array {
    const encoder = new util.TextEncoder();
    return encoder.encodeInto(AI_SECRET_ALIAS);
  }

  /**
   * 清理旧服务方（百炼）时代遗留的凭证别名。
   * 换服务方后新别名不再覆盖旧条目，不主动清掉就会在系统安全存储里留一份孤儿 Key。
   * 尽力而为：清理失败不影响本次保存结果。
   */
  private static async removeLegacyAlias(): Promise<void> {
    const encoder = new util.TextEncoder();
    const removeMap: asset.AssetMap = new Map();
    removeMap.set(asset.Tag.ALIAS, encoder.encodeInto(AI_LEGACY_SECRET_ALIAS));
    try {
      await asset.remove(removeMap);
    } catch (e) {
      const err = e as BusinessError;
      if (err.code !== asset.ErrorCode.NOT_FOUND) {
        console.warn(`legacy credential cleanup failed: ${err.code}`);
      }
    }
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
    if (!remember) {
      // 关闭记住时先删除磁盘凭证；删除失败就不谎报切换成功。
      await AiCredentialStore.forgetPersistedApiKey();
      AiCredentialStore.sessionKey = apiKey;
      return;
    }
    const encoder = new util.TextEncoder();
    const addMap: asset.AssetMap = new Map();
    addMap.set(asset.Tag.ALIAS, AiCredentialStore.aliasBytes());
    addMap.set(asset.Tag.SECRET, encoder.encodeInto(apiKey));
    try {
      await asset.add(addMap);
    } catch (e) {
      const err = e as BusinessError;
      if (err.code === asset.ErrorCode.DUPLICATED) {
        const queryMap: asset.AssetMap = new Map();
        queryMap.set(asset.Tag.ALIAS, AiCredentialStore.aliasBytes());
        const updateMap: asset.AssetMap = new Map();
        updateMap.set(asset.Tag.SECRET, encoder.encodeInto(apiKey));
        try {
          await asset.update(queryMap, updateMap);
        } catch (updateError) {
          const updateErr = updateError as BusinessError;
          throw new AiError(AiErrorCode.SECURE_STORE_UNAVAILABLE, updateErr.message);
        }
      } else {
        throw new AiError(AiErrorCode.SECURE_STORE_UNAVAILABLE, err.message);
      }
    }
    // 仅在安全存储操作成功后更新本会话凭证。
    AiCredentialStore.sessionKey = apiKey;
    await AiCredentialStore.removeLegacyAlias();
  }

  /** 删除持久化凭证，但保留当前会话中的密钥。 */
  static async forgetPersistedApiKey(): Promise<void> {
    try {
      const removeMap: asset.AssetMap = new Map();
      removeMap.set(asset.Tag.ALIAS, AiCredentialStore.aliasBytes());
      await asset.remove(removeMap);
    } catch (e) {
      const err = e as BusinessError;
      if (err.code !== asset.ErrorCode.NOT_FOUND) {
        throw new AiError(AiErrorCode.SECURE_STORE_UNAVAILABLE, err.message);
      }
    }
  }

  static async clearApiKey(): Promise<void> {
    await AiCredentialStore.forgetPersistedApiKey();
    AiCredentialStore.sessionKey = null;
  }

}
