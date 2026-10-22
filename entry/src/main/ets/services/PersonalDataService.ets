/**
 * 用户主动删除本地健康数据与 AI 凭证。
 * 数据库、Preferences、Asset Store 不能组成跨服务事务；每项都会尝试清除，
 * 并返回失败项，调用方不得在部分失败时提示删除成功。
 */

import { common } from '@kit.AbilityKit';
import { Database } from '../database/Database';
import { AiConfigRepository } from '../repositories/AiConfigRepository';
import { AiCredentialStore } from '../repositories/AiCredentialStore';
import { StepBaselineRepository } from '../repositories/StepBaselineRepository';
import { OnboardingService } from './OnboardingService';
import { PrivacyConsentService } from './PrivacyConsentService';
import { StickerCutoutService } from './StickerCutoutService';
import { StepSensorService } from './StepSensorService';

export class PersonalDataService {
  static async deleteAllLocalData(context: common.UIAbilityContext | undefined): Promise<string[]> {
    const failures: string[] = [];

    /**
     * 撤回同意前先停采集。
     *
     * 顺序很重要：先停传感器，再删数据。
     * 反过来的话，删除过程中传感器还在上报，会把步数又写回数据库，
     * 用户以为删干净了，实际库里又冒出行记录。
     */
    StepSensorService.stop();

    try {
      await Database.clearAllUserData();
    } catch (e) {
      failures.push('健康档案和记录');
    }

    /**
     * 生成出来的图片文件也要删。
     *
     * 只清数据库会留下两样东西：
     *   · 贴纸 PNG —— 用户照片的衍生图；
     *   · 分享海报 —— 里面有当天的饮食内容和便签碎碎念。
     */
    try {
      const leftover = await StickerCutoutService.clearGeneratedFiles();
      if (leftover.length > 0) {
        failures.push('生成的图片文件');
      }
    } catch (e) {
      failures.push('生成的图片文件');
    }

    try {
      await AiConfigRepository.resetConfig();
      AiConfigRepository.setDemoMode(false);
    } catch (e) {
      failures.push('AI 配置');
    }

    try {
      await AiCredentialStore.clearApiKey();
    } catch (e) {
      failures.push('API Key');
    }

    try {
      if (context === undefined) {
        throw new Error('ability context unavailable');
      }
      OnboardingService.clearDraft(context);
      OnboardingService.reset(context);
    } catch (e) {
      failures.push('引导选择');
    }

    try {
      if (context === undefined) {
        throw new Error('ability context unavailable');
      }
      await PrivacyConsentService.revoke(context);
    } catch (e) {
      failures.push('同意记录');
    }

    // 计步基线也要清掉：它虽然只是计数器偏移量，但带着"这个设备今天走过多少步"
    // 的信息，属于本机健康数据的一部分，不能在"删除全部数据"之后残留。
    try {
      if (context === undefined) {
        throw new Error('ability context unavailable');
      }
      await StepBaselineRepository.clear(context);
    } catch (e) {
      failures.push('计步基线');
    }

    return failures;
  }
}
