/**
 * AI 配置仓储：Preferences 持久化 baseUrl/modelName/rememberApiKey/演示模式，不保存密钥。
 */

import { preferences } from '@kit.ArkData';
import { Database } from '../database/Database';
import { AiConfig } from '../models/AiConfig';
import { AiConfigKeys, AiDefaults } from '../common/AiConstants';

export class AiConfigRepository {
  /** 演示模式为会话级开关：不落盘，重启后默认关闭（PM 决策） */
  private static sessionDemoMode: boolean = AiDefaults.DEMO_MODE;

  private static async getStore(): Promise<preferences.Preferences> {
    const context = Database.getAppContext();
    if (context === null) {
      throw new Error('app context unavailable');
    }
    return preferences.getPreferences(context, { name: AiConfigKeys.PREFS_NAME });
  }

  static async loadConfig(): Promise<AiConfig> {
    const prefs = await AiConfigRepository.getStore();
    const config = new AiConfig(
      (prefs.getSync(AiConfigKeys.BASE_URL, AiDefaults.BASE_URL) as string) ?? AiDefaults.BASE_URL,
      (prefs.getSync(AiConfigKeys.MODEL_NAME, AiDefaults.MODEL_NAME) as string) ?? AiDefaults.MODEL_NAME,
      (prefs.getSync(AiConfigKeys.REMEMBER_KEY, AiDefaults.REMEMBER_KEY) as boolean) ?? false
    );
    return config;
  }

  static async saveConfig(config: AiConfig): Promise<void> {
    const prefs = await AiConfigRepository.getStore();
    await prefs.putSync(AiConfigKeys.BASE_URL, config.baseUrl);
    await prefs.putSync(AiConfigKeys.MODEL_NAME, config.modelName);
    await prefs.putSync(AiConfigKeys.REMEMBER_KEY, config.rememberApiKey);
    await prefs.flush();
  }

  static isDemoMode(): boolean {
    return AiConfigRepository.sessionDemoMode;
  }

  static setDemoMode(enabled: boolean): void {
    AiConfigRepository.sessionDemoMode = enabled;
  }

  static async resetConfig(): Promise<void> {
    const prefs = await AiConfigRepository.getStore();
    await prefs.putSync(AiConfigKeys.BASE_URL, AiDefaults.BASE_URL);
    await prefs.putSync(AiConfigKeys.MODEL_NAME, AiDefaults.MODEL_NAME);
    await prefs.putSync(AiConfigKeys.REMEMBER_KEY, AiDefaults.REMEMBER_KEY);
    await prefs.flush();
  }
}