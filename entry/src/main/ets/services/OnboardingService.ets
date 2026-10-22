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
import { SettingsRepository } from '../repositories/SettingsRepository';
import { AppSettings } from '../models/AppSettings';
import { CalorieEngine } from './CalorieEngine';
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
  /** 身体数据：体重/身高/年龄/性别/体脂率，首次打开时由用户手动填写 */
  BODY = 2,
  NOTIFY = 3,
  SUPPLEMENT = 4,
  LIFESTYLE = 5
}

export const ONBOARD_STEP_COUNT: number = 6;

/** 引导收集到的原始选择 */
export class OnboardDraft {
  goal: GoalMode = GoalMode.WEIGHT_LOSS;
  activity: ActivityLevel = ActivityLevel.MODERATE;
  /**
   * 体重 kg。0 表示未填 —— 引导**不编造**体征默认值，
   * 没填就不写库，由「我的 → 体征档案」补。
   */
  weightKg: number = 0;
  /** 身高 cm，0 表示未填 */
  heightCm: number = 0;
  /** 年龄 岁，0 表示未填 */
  ageYears: number = 0;
  /** 性别 */
  sex: Sex = Sex.UNSPECIFIED;
  /** 体脂率百分数；null 表示未填，引擎回退 Mifflin-St Jeor */
  bodyFatPct: number | null = null;
  /** 是否愿意服用补剂（实测引导语 "Can you take Nutritional Supplements?"） */
  supplements: boolean = false;
  /** 作息是否规律（实测分类 "Lifestyle & Feelings"） */
  routine: boolean = true;
  /** 每周外食次数档位：0=几乎不外食 1=偶尔 2=经常 */
  eatOut: number = 1;

  constructor() {
  }

  /** 必填项（体重/身高/年龄/性别）是否都填好了 */
  hasRequiredBodyData(): boolean {
    return this.weightKg > 0 && this.heightCm > 0 && this.ageYears > 0 &&
      this.sex !== Sex.UNSPECIFIED;
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
   * 写入策略：
   *   · goal_mode / activity 总是覆盖（引导问的就是这两项）；
   *   · 身体数据**只写用户真的填了的项**。没填的项保持原值，
   *     既不用虚构值糊弄过去，也不会把用户已有的档案抹成 0 ——
   *     「重看引导」不该清掉「我的 → 体征档案」里已填的内容。
   *
   * @param syncBudget 是否把推导出的目标热量同步为每日热量预算。
   *        只在**首次**引导时为 true：首次还没有用户设定的预算，
   *        同步后首页立刻反映用户填的体征；重看引导时不动预算，
   *        免得覆盖用户在「我的 → 每日目标设置」里自己调过的值。
   */
  static async applyToProfile(context: common.UIAbilityContext, draft: OnboardDraft,
    syncBudget: boolean): Promise<void> {
    try {
      const current: BodyProfile = await ProfileRepository.getBodyProfile();
      current.mode = draft.goal;
      current.activity = draft.activity;
      if (draft.weightKg > 0) {
        current.weightKg = draft.weightKg;
      }
      if (draft.heightCm > 0) {
        current.heightCm = draft.heightCm;
      }
      if (draft.ageYears > 0) {
        current.ageYears = draft.ageYears;
      }
      if (draft.sex !== Sex.UNSPECIFIED) {
        current.sex = draft.sex;
      }
      if (draft.bodyFatPct !== null) {
        current.bodyFatRatio = draft.bodyFatPct / 100;
      }
      await ProfileRepository.saveBodyProfile(current);

      if (syncBudget) {
        await OnboardingService.syncDerivedBudget(current);
      }
    } catch (e) {
      // 落库失败不阻断引导完成，用户仍可从「我的」里改
    }
  }

  /**
   * 把体征推导出的目标热量写进每日热量预算，让首页与宏量口径一致。
   *
   * 宏量目标本来就是按体征实时推导的（target_auto），预算却是一个独立
   * 字段，默认 1800。用户填完体征后若预算不动，首页会同时出现
   * 「按推导的宏量」和「1800 的热量目标」两套口径，自相矛盾。
   */
  private static async syncDerivedBudget(profile: BodyProfile): Promise<void> {
    if (!profile.isComplete()) {
      return;
    }
    try {
      const plan = CalorieEngine.plan({
        weightKg: profile.weightKg,
        heightCm: profile.heightCm,
        ageYears: profile.ageYears,
        sex: profile.sex,
        bodyFatRatio: profile.bodyFatRatio,
        activity: profile.activity,
        mode: profile.mode
      });
      if (plan.targetCalories <= 0) {
        return;
      }
      const settings: AppSettings = await SettingsRepository.getSettings();
      settings.dailyCalorieBudget = plan.targetCalories;
      await SettingsRepository.saveSettings(settings);
      AppStorage.setOrCreate<AppSettings>('appSettings', settings);
    } catch (e) {
      // 预算同步失败不阻断引导完成
    }
  }

  /** 引导不采集性别时的新档案保持未选择。 */
  static defaultSex(): Sex {
    return Sex.UNSPECIFIED;
  }
}
