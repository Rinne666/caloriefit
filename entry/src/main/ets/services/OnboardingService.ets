/**
 * 引导流程：完成态判定 + 引导结果的落库。
 *
 * 对应 NutriScan 实测路由：
 *     splash_screen ─> setup_screen ─> 目标选择 ─> 通知诱导 ─> 订阅墙 ─> 计划保存
 * 落库后即可直接驱动 BMR/TDEE/宏量目标（见 services/CalorieEngine.ets）。
 *
 * 两处**有意不复制**：
 *   · 语言选择 —— 本 App 只发中文，做一屏只能选自己，没有意义
 *   · 订阅墙   —— 本项目产品定位为**完全免费**：不设试用、不设升级入口、
 *                  没有应用内购买与订阅校验。原版那一屏还是「划线价与实付价
 *                  相同却宣称 70% off」的虚假折扣，更没有克隆价值。
 *                  引导以「生活方式」收尾。
 * 详见 交付说明_NutriScan复现.md §4。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ProfileRepository } from '../repositories/ProfileRepository';
import {
  BodyProfile, GoalMode, ActivityLevel, Sex
} from '../models/Calculation';

/** 引导完成标记的 preferences 键 */
export const ONBOARDING_DONE_KEY: string = 'caloriefit_onboarding_done';
/** 引导过程中暂存的选择 */
export const ONBOARDING_DRAFT_KEY: string = 'caloriefit_onboarding_draft';

/** 引导各步骤。顺序即展示顺序。 */
export enum OnboardStep {
  GOAL = 0,
  ACTIVITY = 1,
  NOTIFY = 2,
  SUPPLEMENT = 3,
  LIFESTYLE = 4
}

export const ONBOARD_STEP_COUNT: number = 5;

/** 引导收集到的原始选择 */
export class OnboardDraft {
  goal: GoalMode = GoalMode.WEIGHT_LOSS;
  activity: ActivityLevel = ActivityLevel.MODERATE;
  /** 是否愿意服用补剂（实测引导语 "Can you take Nutritional Supplements?"） */
  supplements: boolean = false;
  /** 作息是否规律（实测分类 "Lifestyle & Feelings"） */
  routine: boolean = true;
  /** 每周外食次数档位：0=几乎不外食 1=偶尔 2=经常 */
  eatOut: number = 1;

  constructor() {
  }
}

export class OnboardingService {
  private static store(context: common.UIAbilityContext): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: 'caloriefit_onboarding' });
  }

  static isDone(context: common.UIAbilityContext): boolean {
    try {
      const store = OnboardingService.store(context);
      return store.getSync(ONBOARDING_DONE_KEY, false) === true;
    } catch (e) {
      // 读不到就当作没做过 —— 引导是幂等的，多走一次只是体验差，不会出错
      return false;
    }
  }

  static markDone(context: common.UIAbilityContext): void {
    try {
      const store = OnboardingService.store(context);
      store.putSync(ONBOARDING_DONE_KEY, true);
      store.flush();
    } catch (e) {
      // 忽略：写失败只导致下次再走一遍引导
    }
  }

  /** 供「我的 → 重新看引导」用 */
  static reset(context: common.UIAbilityContext): void {
    try {
      const store = OnboardingService.store(context);
      store.deleteSync(ONBOARDING_DONE_KEY);
      store.flush();
    } catch (e) {
    }
  }

  /** 删除未完成引导中暂存的健康偏好，保留已完成标记。 */
  static clearDraft(context: common.UIAbilityContext): void {
    const store = OnboardingService.store(context);
    store.deleteSync(ONBOARDING_DRAFT_KEY);
    store.flush();
  }

  /**
   * 把引导结果写进体征档案。
   *
   * 只覆盖 goal_mode / activity 两项 —— 体重身高年龄在后续设置页补，
   * 不在这里编默认值糊弄过去。
   */
  static async applyToProfile(context: common.UIAbilityContext, draft: OnboardDraft): Promise<void> {
    try {
      const current: BodyProfile = await ProfileRepository.getBodyProfile();
      current.mode = draft.goal;
      current.activity = draft.activity;
      await ProfileRepository.saveBodyProfile(current);
    } catch (e) {
      // 落库失败不阻断引导完成，用户仍可从「我的」里改
    }
  }

  /** 引导不采集性别，因此新档案保持未选择。 */
  static defaultSex(): Sex {
    return Sex.UNSPECIFIED;
  }
}
