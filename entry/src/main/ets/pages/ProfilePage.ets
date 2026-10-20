/**
 * 我的页：目标设置 + 数据来源说明 + 清空全部记录。
 */

import { common } from '@kit.AbilityKit';
import { anim } from '../common/Motion';
import { SettingsRepository } from '../repositories/SettingsRepository';
import { ProfileRepository } from '../repositories/ProfileRepository';
import { Database } from '../database/Database';
import { AppSettings } from '../models/AppSettings';
import { CalorieEngine } from '../services/CalorieEngine';
import {
  BodyProfile, Sex, ActivityLevel, GoalMode,
  activityLabel, modeLabel, sexLabel, MacroTarget
} from '../models/Calculation';
import {
  color, fontSize, space, radius, layout, ThemeMode, themeLabel, pageGradient,
  glass, glassGradient, glassShadow, toneVeil
} from '../common/DesignTokens';
import { ThemeService } from '../services/ThemeService';
import { DATA_SOURCE_LABEL } from '../common/Constants';
import { validateBudget, validateStepsGoal, validateMinutesGoal, validateActivityKcalGoal } from '../common/Validators';
import { YouEntry, Provenance } from '../services/MockContent';
import { setComingSoon, ComingSoonPage } from '../components/ComingSoonPage';
import { OnboardingPage } from './OnboardingPage';
import { PersonalDataService } from '../services/PersonalDataService';
import { PrivacyInventoryParams } from './PrivacyInventoryPage';

/**
 * 「我的」二级入口清单。
 *
 * status 三档直接对应交付要求：
 *   real  已实现，点进去是真实页面
 *   mock  有界面但内容是示例数据
 *   todo  原版有实现，本地无证据 / 无后端，指到 ComingSoon 占位
 *
 * 字段来源见 services/MockContent.ets 末尾的实测依据。
 */
const YOU_ENTRIES: YouEntry[] = [
  new YouEntry('all_meals', '全部餐食', '按日期查看所有饮食记录', 'FoodLog', 'real', Provenance.MEASURED),
  new YouEntry('activity_log', '运动记录', '按日期查看所有运动记录', 'ActivityLog', 'real', Provenance.MEASURED),
  new YouEntry('favourite', '收藏餐食', '常用餐食快速复用（实测 /api/v1/favourite_food_items）', 'ComingSoon',
    'todo', Provenance.INFERRED),
  new YouEntry('ask_yourself', '问你自己', '自然语言提问饮食记录', 'ComingSoon', 'todo', Provenance.INFERRED),
  new YouEntry('modify_macros', '修改宏量', '手动覆盖自动推导的宏量目标', 'ComingSoon', 'real', Provenance.MEASURED),
  new YouEntry('repeat_meals', '重复餐食', '设置常吃餐食的重复计划（实测 Edit repeat meal schedule）', 'ComingSoon',
    'todo', Provenance.INFERRED),
  new YouEntry('reminders', '提醒', '选择提醒类型与时间（实测 Choose Reminder Type）', 'ComingSoon',
    'todo', Provenance.INFERRED),
  new YouEntry('vacation', '假期模式', '最长可回溯 30 天，连胜不清零', 'ComingSoon', 'todo', Provenance.MEASURED),
  new YouEntry('customize', '自定义首页', '选择综合页要显示哪些卡片（实测 CustomizeHomeViewModel）', 'ComingSoon',
    'todo', Provenance.MEASURED)
];

@Component
export struct ProfilePage {
  @StorageLink('refreshTick') refreshTick: number = 0;
  @Consume('navStack') navStack: NavPathStack;
  /** 页面内容入场开关，见 build() 末尾的 opacity/translate */
  @State private entered: boolean = false;

  /** 未实现功能覆盖层是否展开（页内自持，见 build() 注释） */
  @State private csVisible: boolean = false;

  /** 重看引导的覆盖层 */
  @State private onboardingVisible: boolean = false;

  enterPage(): void {
    this.entered = true;
  }

  /**
   * 二级入口分发。
   *
   * modify_macros 标 real 但功能就在本页「每日目标设置」卡里，
   * 所以不跳页只提示；其余按 route 分发：真页面推真路由，
   * 没做的推 ComingSoon 占位。
   */
  private openYouEntry(e: YouEntry): void {
    if (e.id === 'modify_macros') {
      this.getUIContext().getPromptAction().showToast({ message: '宏量目标在本页「每日目标设置」中修改' });
      return;
    }
    if (e.route === 'FoodLog' || e.route === 'ActivityLog') {
      this.navStack.pushPathByName(e.route, new YouRouteParams(e.route));
      return;
    }
    setComingSoon(e.title, e.subtitle, '原版有实现，本地没有可复现的证据或后端',
      '抓包 / 补后端 / 补算法后即可替换为真实页面', e.provenance);
    this.csVisible = true;
  }

  /**
   * 打开个人信息保护「双清单」。
   *
   * 工信部信管函〔2021〕292号要求把「已收集个人信息清单」和
   * 「第三方共享个人信息清单」在 APP 二级菜单中展示，应用市场把它列为
   * 上架要求，所以这两个入口挂在「数据与隐私」段里，紧邻「查看隐私政策」。
   */
  private openInventory(mode: string, title: string): void {
    this.navStack.pushPathByName('PrivacyInventory', new PrivacyInventoryParams(mode, title));
  }

  private statusBadge(status: string): string {
    if (status === 'real') {
      return '已实现';
    }
    if (status === 'mock') {
      return '示例';
    }
    return '未实现';
  }

  private statusColor(status: string): ResourceColor {
    if (status === 'real') {
      return color.macroOk;
    }
    if (status === 'mock') {
      return color.primary;
    }
    return color.textHint;
  }

  @State budgetInput: string = '1800';
  @State stepsGoalInput: string = '8000';
  @State minutesGoalInput: string = '30';
  @State activityKcalGoalInput: string = '300';

  /* 体征档案 */
  @State weightInput: string = '';
  @State heightInput: string = '';
  @State ageInput: string = '';
  /** 体脂率留空表示未知 → 引擎自动回退 Mifflin-St Jeor */
  @State bodyFatInput: string = '';
  @State sexIndex: number = -1;
  @State activityIndex: number = -1;
  @State goalIndex: number = -1;
  /** 实时预览：随输入变化 */
  @State previewTarget: number = 0;
  @State previewBmr: number = 0;
  @State previewTdee: number = 0;
  @State previewMacro: MacroTarget | null = null;

  private static readonly SEX_ORDER: Sex[] = [Sex.MALE, Sex.FEMALE];
  private static readonly ACTIVITY_ORDER: ActivityLevel[] = [
    ActivityLevel.SEDENTARY, ActivityLevel.LIGHT, ActivityLevel.MODERATE,
    ActivityLevel.VERY_ACTIVE, ActivityLevel.ATHLETE
  ];
  private static readonly GOAL_ORDER: GoalMode[] = [
    GoalMode.WEIGHT_LOSS, GoalMode.MAINTAIN, GoalMode.RECOMP,
    GoalMode.DEFICIT, GoalMode.SURPLUS
  ];

  aboutToAppear(): void {
    this.loadSettings();
    this.loadBodyProfile();
    this.loadTheme();
  }

  private static readonly THEME_ORDER: ThemeMode[] =
    [ThemeMode.SYSTEM, ThemeMode.LIGHT, ThemeMode.DARK];

  @State themeIndex: number = 0;

  private async loadTheme(): Promise<void> {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    const mode = await ThemeService.load(ctx as common.UIAbilityContext);
    const i = ProfilePage.THEME_ORDER.indexOf(mode);
    this.themeIndex = i >= 0 ? i : 0;
  }

  private async changeTheme(mode: ThemeMode): Promise<void> {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    const ok = await ThemeService.apply(ctx as common.UIAbilityContext, mode);
    this.getUIContext().getPromptAction().showToast({
      message: ok ? `外观已切换为${themeLabel(mode)}` : '切换失败，请重试'
    });
  }

  private async loadBodyProfile(): Promise<void> {
    try {
      const p = await ProfileRepository.getBodyProfile();
      this.weightInput = p.weightKg > 0 ? String(p.weightKg) : '';
      this.heightInput = p.heightCm > 0 ? String(p.heightCm) : '';
      this.ageInput = p.ageYears > 0 ? String(p.ageYears) : '';
      this.bodyFatInput = p.bodyFatRatio === null ? '' : (p.bodyFatRatio * 100).toFixed(1);
      this.sexIndex = ProfilePage.SEX_ORDER.indexOf(p.sex) >= 0
        ? ProfilePage.SEX_ORDER.indexOf(p.sex) : -1;
      this.activityIndex = ProfilePage.ACTIVITY_ORDER.indexOf(p.activity) >= 0
        ? ProfilePage.ACTIVITY_ORDER.indexOf(p.activity) : -1;
      this.goalIndex = ProfilePage.GOAL_ORDER.indexOf(p.mode) >= 0
        ? ProfilePage.GOAL_ORDER.indexOf(p.mode) : -1;
      this.recalcPreview();
    } catch (e) {
      // 保持默认值
    }
  }

  /** 由当前输入重算 BMR/TDEE/目标/宏量，输入非法时清空预览 */
  private recalcPreview(): void {
    const w = parseFloat(this.weightInput);
    const h = parseFloat(this.heightInput);
    const a = parseFloat(this.ageInput);
    if (!(w > 0) || !(h > 0) || !(a > 0) || this.sexIndex < 0 ||
      this.activityIndex < 0 || this.goalIndex < 0) {
      this.previewBmr = 0;
      this.previewTdee = 0;
      this.previewTarget = 0;
      this.previewMacro = null;
      return;
    }
    const bfText = this.bodyFatInput.trim();
    const bfPct = bfText.length > 0 ? parseFloat(bfText) : NaN;
    const bf = isNaN(bfPct) ? null : bfPct / 100;
    if (bf !== null && !(bf > 0 && bf < 0.7)) {
      this.previewBmr = 0;
      this.previewTdee = 0;
      this.previewTarget = 0;
      this.previewMacro = null;
      return;
    }

    const plan = CalorieEngine.plan({
      weightKg: w, heightCm: h, ageYears: a,
      sex: ProfilePage.SEX_ORDER[this.sexIndex],
      bodyFatRatio: bf,
      activity: ProfilePage.ACTIVITY_ORDER[this.activityIndex],
      mode: ProfilePage.GOAL_ORDER[this.goalIndex]
    });
    this.previewBmr = plan.bmr;
    this.previewTdee = plan.tdee;
    this.previewTarget = plan.targetCalories;
    this.previewMacro = plan.macros;
  }

  private async saveBodyProfile(): Promise<void> {
    const w = parseFloat(this.weightInput);
    const h = parseFloat(this.heightInput);
    const a = parseFloat(this.ageInput);
    if (!(w > 0) || !(h > 0) || !(a > 0)) {
      this.getUIContext().getPromptAction().showToast({ message: '请填写有效的体重、身高和年龄' });
      return;
    }
    if (this.sexIndex < 0 || this.activityIndex < 0 || this.goalIndex < 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请完成性别、活动量和目标选择' });
      return;
    }
    const bfText = this.bodyFatInput.trim();
    let bf: number | null = null;
    if (bfText.length > 0) {
      const bfPct = parseFloat(bfText);
      if (isNaN(bfPct) || bfPct <= 0 || bfPct >= 70) {
        this.getUIContext().getPromptAction().showToast({ message: '体脂率需在 0~70 之间，或留空' });
        return;
      }
      bf = bfPct / 100;
    }

    const profile = new BodyProfile(
      w, h, a,
      ProfilePage.SEX_ORDER[this.sexIndex],
      bf,
      ProfilePage.ACTIVITY_ORDER[this.activityIndex],
      ProfilePage.GOAL_ORDER[this.goalIndex],
      Date.now()
    );
    const ok = await ProfileRepository.saveBodyProfile(profile);
    if (!ok) {
      this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试' });
      return;
    }
    // 目标热量随体征联动，交回自动模式
    await ProfileRepository.useAutoMacroTarget();
    // 把推导出的热量同步写入既有预算字段，保持首页口径一致
    try {
      const settings = new AppSettings(
        this.previewTarget,
        parseInt(this.stepsGoalInput) || 8000,
        parseInt(this.minutesGoalInput) || 30,
        parseInt(this.activityKcalGoalInput) || 300,
        0
      );
      await SettingsRepository.saveSettings(settings);
      AppStorage.setOrCreate<AppSettings>('appSettings', settings);
      this.budgetInput = String(this.previewTarget);
    } catch (e) {
      // 预算同步失败不阻断体征保存
    }
    this.bumpRefresh();
    this.getUIContext().getPromptAction().showToast({ message: '体征已保存，目标已重新计算' });
  }

  private async loadSettings(): Promise<void> {
    try {
      const stored = AppStorage.get<AppSettings>('appSettings');
      const settings: AppSettings = stored !== undefined ? stored : await SettingsRepository.getSettings();
      this.budgetInput = settings.dailyCalorieBudget.toString();
      this.stepsGoalInput = settings.stepsGoal.toString();
      this.minutesGoalInput = settings.exerciseMinutesGoal.toString();
      this.activityKcalGoalInput = settings.activityKcalGoal.toString();
    } catch (e) {
      // 保持默认值
    }
  }

  private bumpRefresh(): void {
    const cur = AppStorage.get<number>('refreshTick') ?? 0;
    AppStorage.setOrCreate<number>('refreshTick', cur + 1);
  }

  private async saveGoals(): Promise<void> {
    const pBudget = validateBudget(this.budgetInput);
    if (!pBudget.ok) {
      this.getUIContext().getPromptAction().showToast({ message: pBudget.message });
      return;
    }
    const pSteps = validateStepsGoal(this.stepsGoalInput);
    if (!pSteps.ok) {
      this.getUIContext().getPromptAction().showToast({ message: pSteps.message });
      return;
    }
    const pMinutes = validateMinutesGoal(this.minutesGoalInput);
    if (!pMinutes.ok) {
      this.getUIContext().getPromptAction().showToast({ message: pMinutes.message });
      return;
    }
    const pKcal = validateActivityKcalGoal(this.activityKcalGoalInput);
    if (!pKcal.ok) {
      this.getUIContext().getPromptAction().showToast({ message: pKcal.message });
      return;
    }
    try {
      const settings = new AppSettings(pBudget.value, pSteps.value, pMinutes.value, pKcal.value, 0);
      await SettingsRepository.saveSettings(settings);
      AppStorage.setOrCreate<AppSettings>('appSettings', settings);
      this.bumpRefresh();
      this.getUIContext().getPromptAction().showToast({ message: '目标已保存' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试' });
    }
  }

  private confirmClear(): void {
    this.getUIContext().showAlertDialog({
      title: '清空全部记录',
      message: '将删除所有日期的饮食、运动、步数、饮水和断食记录；身体档案与目标设置保留。此操作不可撤销。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清空',
        fontColor: color.danger,
        action: () => {
          this.doClear();
        }
      }
    });
  }

  private async doClear(): Promise<void> {
    try {
      await Database.clearAllRecords();
      this.bumpRefresh();
      this.getUIContext().getPromptAction().showToast({ message: '已清空全部记录' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '清空失败，请重试' });
    }
  }

  private confirmDeleteLocalData(): void {
    this.getUIContext().showAlertDialog({
      title: '删除健康数据和 AI 配置',
      message: '将删除身体档案、目标设置、饮食/运动/步数/饮水/断食记录、未完成的引导选择、AI 接口配置和 API Key，并撤回健康信息处理同意。外观偏好保留。此操作不可撤销。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: color.danger,
        action: () => {
          this.doDeleteLocalData();
        }
      }
    });
  }

  private async doDeleteLocalData(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    const failures: string[] = await PersonalDataService.deleteAllLocalData(
      host === undefined ? undefined : host as common.UIAbilityContext
    );
    try {
      const settings = await SettingsRepository.getSettings();
      AppStorage.setOrCreate<AppSettings>('appSettings', settings);
      await this.loadSettings();
      await this.loadBodyProfile();
    } catch (e) {
      failures.push('页面状态更新');
    }
    this.bumpRefresh();
    if (failures.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '数据已删除并撤回同意；继续使用需重新确认' });
    } else {
      this.getUIContext().getPromptAction().showToast({
        message: `部分数据未能删除：${failures.join('、')}，请重试`
      });
    }
  }

  build() {
    /**
     * 本页自持的未实现功能覆盖层。
     *
     * 刻意不用跨组件状态（AppStorage / NavPathStack）来弹这一层：
     * 实测走 NavPathStack 推同名目标页时目标内容永远挂不上树，
     * 走 AppStorage 跨组件同步也没生效 —— 两种跨组件通道都试过、都失败。
     * 而同一个 @Component 内部的 @State 一定可靠，所以改成页内持有。
     * 代价是每个有「未实现」入口的页都要自己挂一层，换来的是真的能用。
     */
    Stack() {
      Scroll() {
        Column({ space: space.md }) {
        Text('我的')
          .fontSize(fontSize.pageTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(color.text)
          .width('100%')

        // 外观
        Column({ space: space.md }) {
          Text('外观')
            .fontSize(fontSize.sectionTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.text)
            .width('100%')

          Row({ space: space.sm }) {
            ForEach(ProfilePage.THEME_ORDER, (m: ThemeMode, i: number) => {
              Text(themeLabel(m))
                .layoutWeight(1)
                .height(40)
                .textAlign(TextAlign.Center)
                .fontSize(fontSize.body)
                .fontColor(this.themeIndex === i ? color.onPrimary : color.textSecondary)
                .backgroundColor(this.themeIndex === i ? color.primary : color.glassFill)
                .borderRadius(radius.medium)
                .onClick(() => {
                  this.themeIndex = i;
                  this.changeTheme(m);
                })
            }, (m: ThemeMode) => m)
          }
          .width('100%')

          Text('深色主题沿用 NutriScan 实测色板（#0C0C0C / #1C1C1E / #2F2F33）；品牌色 #D5EE6E 也来自真机实测。')
            .fontSize(fontSize.caption)
            .fontColor(color.textHint)
            .width('100%')
        }
        .padding(layout.cardPadding)
        .linearGradient(glassGradient(color.glassFill))
        .borderRadius(glass.cardRadius)
        .border({ width: glass.borderWidth, color: color.glassBorder })
        .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        // 体征档案 —— 驱动 BMR/TDEE 与宏量目标
        Column({ space: space.md }) {
          Text('体征档案')
            .fontSize(fontSize.sectionTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.text)

          Text('用于自动计算基础代谢与每日目标，留空体脂率则使用 Mifflin-St Jeor 公式')
            .fontSize(fontSize.caption)
            .fontColor(color.textHint)
            .width('100%')

          Row({ space: space.sm }) {
            Column({ space: space.xs }) {
              Text('体重 kg')
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
              TextInput({ text: this.weightInput })
                .type(InputType.Number)
                .height(layout.inputHeight)
                .fontSize(fontSize.body)
                .backgroundColor(color.surfaceMuted)
                .borderRadius(radius.medium)
                .onChange((v: string) => {
                  this.weightInput = v;
                  this.recalcPreview();
                })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Column({ space: space.xs }) {
              Text('身高 cm')
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
              TextInput({ text: this.heightInput })
                .type(InputType.Number)
                .height(layout.inputHeight)
                .fontSize(fontSize.body)
                .backgroundColor(color.surfaceMuted)
                .borderRadius(radius.medium)
                .onChange((v: string) => {
                  this.heightInput = v;
                  this.recalcPreview();
                })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')

          Row({ space: space.sm }) {
            Column({ space: space.xs }) {
              Text('年龄')
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
              TextInput({ text: this.ageInput })
                .type(InputType.Number)
                .height(layout.inputHeight)
                .fontSize(fontSize.body)
                .backgroundColor(color.surfaceMuted)
                .borderRadius(radius.medium)
                .onChange((v: string) => {
                  this.ageInput = v;
                  this.recalcPreview();
                })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Column({ space: space.xs }) {
              Text('体脂率 %（可空）')
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
              TextInput({ text: this.bodyFatInput, placeholder: '未知' })
                .type(InputType.Number)
                .height(layout.inputHeight)
                .fontSize(fontSize.body)
                .backgroundColor(color.surfaceMuted)
                .borderRadius(radius.medium)
                .onChange((v: string) => {
                  this.bodyFatInput = v;
                  this.recalcPreview();
                })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')

          Column({ space: space.xs }) {
            Text('性别')
              .fontSize(fontSize.secondary)
              .fontColor(color.textSecondary)
            Row({ space: space.sm }) {
              ForEach(ProfilePage.SEX_ORDER, (s: Sex, i: number) => {
                Text(sexLabel(s))
                  .layoutWeight(1)
                  .height(40)
                  .textAlign(TextAlign.Center)
                  .fontSize(fontSize.body)
                  .fontColor(this.sexIndex === i ? color.onPrimary : color.textSecondary)
                  .backgroundColor(this.sexIndex === i ? color.primary : color.surfaceMuted)
                  .borderRadius(radius.medium)
                  .onClick(() => {
                    this.sexIndex = i;
                    this.recalcPreview();
                  })
              }, (s: Sex) => s)
            }
            .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Column({ space: space.xs }) {
            Text('活动量')
              .fontSize(fontSize.secondary)
              .fontColor(color.textSecondary)
            Column({ space: space.xxs }) {
              ForEach(ProfilePage.ACTIVITY_ORDER, (a: ActivityLevel, i: number) => {
                Row({ space: space.sm }) {
                  Radio({ value: a, group: 'act' })
                    .checked(this.activityIndex === i)
                    .onChange(() => {
                      this.activityIndex = i;
                      this.recalcPreview();
                    })
                  Text(activityLabel(a))
                    .fontSize(fontSize.body)
                    .fontColor(this.activityIndex === i ? color.text : color.textSecondary)
                }
                .width('100%')
                .padding({ top: 4, bottom: 4 })
                .onClick(() => {
                  this.activityIndex = i;
                  this.recalcPreview();
                })
              }, (a: ActivityLevel) => a)
            }
            .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Column({ space: space.xs }) {
            Text('目标')
              .fontSize(fontSize.secondary)
              .fontColor(color.textSecondary)
            Row({ space: space.xs }) {
              ForEach(ProfilePage.GOAL_ORDER, (g: GoalMode, i: number) => {
                Text(modeLabel(g))
                  .layoutWeight(1)
                  .height(36)
                  .textAlign(TextAlign.Center)
                  .fontSize(fontSize.secondary)
                  .fontColor(this.goalIndex === i ? color.onPrimary : color.textSecondary)
                  .backgroundColor(this.goalIndex === i ? color.primary : color.surfaceMuted)
                  .borderRadius(radius.small)
                  .onClick(() => {
                    this.goalIndex = i;
                    this.recalcPreview();
                  })
              }, (g: GoalMode) => g)
            }
            .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          // 实时预览
          if (this.previewTarget > 0) {
            Column({ space: space.xs }) {
              Row() {
                Text('基础代谢 BMR')
                  .fontSize(fontSize.secondary)
                  .fontColor(color.textSecondary)
                Blank()
                Text(`${this.previewBmr} kcal`)
                  .fontSize(fontSize.secondary)
                  .fontColor(color.text)
              }
              .width('100%')

              Row() {
                Text('每日消耗 TDEE')
                  .fontSize(fontSize.secondary)
                  .fontColor(color.textSecondary)
                Blank()
                Text(`${this.previewTdee} kcal`)
                  .fontSize(fontSize.secondary)
                  .fontColor(color.text)
              }
              .width('100%')

              Row() {
                Text('建议目标')
                  .fontSize(fontSize.body)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(color.text)
                Blank()
                Text(`${this.previewTarget} kcal`)
                  .fontSize(fontSize.body)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(color.primary)
              }
              .width('100%')

              if (this.previewMacro !== null) {
                Text(`蛋白 ${this.previewMacro.proteinG}g · 碳水 ${this.previewMacro.carbsG}g · 脂肪 ${this.previewMacro.fatG}g`)
                  .fontSize(fontSize.caption)
                  .fontColor(color.textHint)
                  .width('100%')
              }
            }
            .width('100%')
            .padding(space.sm)
            .backgroundColor(color.surfaceMuted)
            .borderRadius(radius.medium)
            .alignItems(HorizontalAlign.Start)
          }

          Button('保存体征并重算目标')
            .width('100%')
            .height(layout.buttonHeight)
            .fontSize(fontSize.body)
            .fontColor(color.onPrimary)
            .backgroundColor(color.primary)
            .borderRadius(radius.large)
            .onClick(() => {
              this.saveBodyProfile();
            })
        }
        .padding(layout.cardPadding)
        .linearGradient(glassGradient(color.glassFill))
        .borderRadius(glass.cardRadius)
        .border({ width: glass.borderWidth, color: color.glassBorder })
        .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        // 目标设置
        Column({ space: space.md }) {
          Text('每日目标设置')
            .fontSize(fontSize.sectionTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.text)

          Column({ space: space.xs }) {
            Text('每日饮食预算（kcal）')
              .fontSize(fontSize.secondary)
              .fontColor(color.textSecondary)
            TextInput({ text: this.budgetInput })
              .type(InputType.Number)
              .height(layout.inputHeight)
              .fontSize(fontSize.body)
              .backgroundColor(color.surfaceMuted)
              .borderRadius(radius.medium)
              .onChange((value: string) => {
                this.budgetInput = value;
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Column({ space: space.xs }) {
            Text('每日步数目标（步）')
              .fontSize(fontSize.secondary)
              .fontColor(color.textSecondary)
            TextInput({ text: this.stepsGoalInput })
              .type(InputType.Number)
              .height(layout.inputHeight)
              .fontSize(fontSize.body)
              .backgroundColor(color.surfaceMuted)
              .borderRadius(radius.medium)
              .onChange((value: string) => {
                this.stepsGoalInput = value;
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Column({ space: space.xs }) {
            Text('每日运动时长目标（分钟）')
              .fontSize(fontSize.secondary)
              .fontColor(color.textSecondary)
            TextInput({ text: this.minutesGoalInput })
              .type(InputType.Number)
              .height(layout.inputHeight)
              .fontSize(fontSize.body)
              .backgroundColor(color.surfaceMuted)
              .borderRadius(radius.medium)
              .onChange((value: string) => {
                this.minutesGoalInput = value;
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Column({ space: space.xs }) {
            Text('每日活动热量目标（kcal）')
              .fontSize(fontSize.secondary)
              .fontColor(color.textSecondary)
            TextInput({ text: this.activityKcalGoalInput })
              .type(InputType.Number)
              .height(layout.inputHeight)
              .fontSize(fontSize.body)
              .backgroundColor(color.surfaceMuted)
              .borderRadius(radius.medium)
              .onChange((value: string) => {
                this.activityKcalGoalInput = value;
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Button('保存目标')
            .width('100%')
            .height(layout.buttonHeight)
            .fontSize(fontSize.body)
            .fontColor(color.onPrimary)
            .backgroundColor(color.primary)
            .borderRadius(radius.large)
            .onClick(() => {
              this.saveGoals();
            })
        }
        .padding(layout.cardPadding)
        .linearGradient(glassGradient(color.glassFill))
        .borderRadius(glass.cardRadius)
        .border({ width: glass.borderWidth, color: color.glassBorder })
        .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
        .width('100%')

        // 记录与偏好：把二级功能集中在一处，保证任何入口都不是死路。
        // 饮食/运动记录是真实页面；其余原版有实现但本地无证据的，
        // 统一指到 ComingSoon 占位，入口本身先立起来。
        Column({ space: space.xs }) {
          Text('记录与偏好')
            .fontSize(fontSize.sectionTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.text)
            .width('100%')

          ForEach(YOU_ENTRIES, (e: YouEntry) => {            Row() {
              Column({ space: 2 }) {
                Text(e.title)
                  .fontSize(fontSize.body)
                  .fontColor(color.text)
                Text(e.subtitle)
                  .fontSize(fontSize.caption)
                  .fontColor(color.textHint)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.statusBadge(e.status))
                .fontSize(fontSize.caption)
                .fontColor(this.statusColor(e.status))
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor(color.glassFill)
                .borderRadius(radius.small)
              .margin({ right: 6 })

              Text('›')
                .fontSize(fontSize.sectionTitle)
                .fontColor(color.textHint)
            }
            .width('100%')
            .padding({ top: space.sm, bottom: space.sm })
            .onClick(() => {
              this.openYouEntry(e);
            })
          }, (e: YouEntry) => e.id)
          // 重看引导：走页内覆盖层（跨组件通道都试过，见 build() 注释）
          Row() {
            Column({ space: 2 }) {
              Text('重看引导流程')
                .fontSize(fontSize.body)
                .fontColor(color.text)
              Text('重新选择目标与活动量')
                .fontSize(fontSize.caption)
                .fontColor(color.textHint)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text('已实现')
              .fontSize(fontSize.caption)
              .fontColor(color.macroOk)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(color.glassFill)
              .borderRadius(radius.small)
              .margin({ right: 6 })

            Text('›')
              .fontSize(fontSize.sectionTitle)
              .fontColor(color.textHint)
          }
          .width('100%')
          .padding({ top: space.sm, bottom: space.sm })
          .onClick(() => {
            this.onboardingVisible = true;
          })
        }
        .width('100%')
        .padding(layout.cardPadding)
        .linearGradient(glassGradient(toneVeil('you-entries')))
        .borderRadius(glass.cardRadius)
        .border({ width: glass.borderWidth, color: color.glassBorder })
        .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
        .alignItems(HorizontalAlign.Start)

        // 数据来源
        Column({ space: space.xs }) {
          Text('数据来源')
            .fontSize(fontSize.sectionTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.text)
          Text(DATA_SOURCE_LABEL)
            .fontSize(fontSize.body)
            .fontColor(color.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(layout.cardPadding)
        .linearGradient(glassGradient(color.glassFill))
        .borderRadius(glass.cardRadius)
        .border({ width: glass.borderWidth, color: color.glassBorder })
        .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
        .width('100%')

        // 版本与授权
        Column({ space: space.xs }) {
          Text('版本与授权')
            .fontSize(fontSize.sectionTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.text)
          Text('CalorieFit 完全免费：无应用内购买、无订阅、无付费墙，所有已实现功能默认全部开放。')
            .fontSize(fontSize.body)
            .fontColor(color.textSecondary)
          Text('AI 食物识别使用你自己的 API Key，调用额度与费用由你的模型服务商决定，与本应用无关。')
            .fontSize(fontSize.caption)
            .fontColor(color.textHint)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(layout.cardPadding)
        .linearGradient(glassGradient(color.glassFill))
        .borderRadius(glass.cardRadius)
        .border({ width: glass.borderWidth, color: color.glassBorder })
        .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
        .width('100%')

        // AI 设置入口
        Row({ space: space.sm }) {
          Text('🤖')
            .fontSize(20)
          Column({ space: 2 }) {
            Text('AI 食物识别设置')
              .fontSize(fontSize.body)
              .fontWeight(FontWeight.Medium)
              .fontColor(color.text)
            Text('API Key、模型与演示模式')
              .fontSize(fontSize.caption)
              .fontColor(color.textHint)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text('›')
            .fontSize(fontSize.sectionTitle)
            .fontColor(color.textHint)
        }
        .padding(layout.cardPadding)
        .linearGradient(glassGradient(color.glassFill))
        .borderRadius(glass.cardRadius)
        .border({ width: glass.borderWidth, color: color.glassBorder })
        .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
        .width('100%')
        .onClick(() => {
          this.navStack.pushPathByName('AiSettings', new Object());
        })

        // 危险操作
        Button('清空全部记录')
          .width('100%')
          .height(layout.buttonHeight)
          .fontSize(fontSize.body)
          .fontColor(color.danger)
          .backgroundColor(color.dangerLight)
          .borderRadius(radius.large)
          .onClick(() => {
            this.confirmClear();
          })

        Text('删除本机健康档案、记录、AI 配置和 API Key，并撤回健康信息处理同意。')
          .fontSize(fontSize.caption)
          .fontColor(color.textHint)
          .width('100%')

        Button('查看隐私政策')
          .width('100%')
          .height(layout.buttonHeight)
          .fontSize(fontSize.body)
          .fontColor(color.primary)
          .backgroundColor(color.primaryLight)
          .borderRadius(radius.large)
          .onClick(() => {
            this.navStack.pushPathByName('PrivacyPolicy', new Object());
          })

        // 个人信息保护「双清单」：工信部 292 号文要求在二级菜单展示
        Button('已收集个人信息清单')
          .width('100%')
          .height(layout.buttonHeight)
          .fontSize(fontSize.body)
          .fontColor(color.primary)
          .backgroundColor(color.surfaceMuted)
          .borderRadius(radius.large)
          .onClick(() => {
            this.openInventory('collected', '已收集个人信息清单');
          })

        Button('第三方共享个人信息清单')
          .width('100%')
          .height(layout.buttonHeight)
          .fontSize(fontSize.body)
          .fontColor(color.primary)
          .backgroundColor(color.surfaceMuted)
          .borderRadius(radius.large)
          .onClick(() => {
            this.openInventory('shared', '第三方共享个人信息清单');
          })

        Button('删除数据并撤回同意')
          .width('100%')
          .height(layout.buttonHeight)
          .fontSize(fontSize.body)
          .fontColor(color.danger)
          .backgroundColor(color.dangerLight)
          .borderRadius(radius.large)
          .onClick(() => {
            this.confirmDeleteLocalData();
          })
      }
      .padding(layout.pagePadding)
      .constraintSize({ minHeight: '100%' })
      // 入场：300ms Fade + Slide，对齐 NutriScan 实测的 easeOut 转场。
      // 首帧 entered=false（透明 + 下移），onAppear 后翻 true 触发隐式动画。
      .opacity(this.entered ? 1 : 0)
      .translate({ x: 0, y: this.entered ? 0 : anim.enterShiftVp })
      .animation({ duration: anim.enterMs, curve: anim.ease })
      .onAppear(() => {
        this.enterPage();
      })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .backgroundColor(color.bg)
      .linearGradient(pageGradient())

      if (this.csVisible) {
        Stack({ alignContent: Alignment.TopStart }) {
          ComingSoonPage()

          Button('‹')
            .width(44)
            .height(44)
            .fontSize(26)
            .fontColor(color.text)
            .backgroundColor(Color.Transparent)
            .margin({ top: 46, left: 16 })
            .onClick(() => {
              this.csVisible = false;
            })
        }
        .width('100%')
        .height('100%')
      }

      // 重看引导：同样用页内覆盖层，不用 NavDestination。
      // 注意这是页内覆盖层，底 Tab 栏仍在它下面 —— 首启那次是全屏的，
      // 没有这个问题；「重看引导」属于次要入口，可接受。
      if (this.onboardingVisible) {
        Stack({ alignContent: Alignment.TopEnd }) {
          OnboardingPage({
            onDone: () => {
              this.onboardingVisible = false;
              // 引导改写了体征档案，重新读一遍把界面同步过来
              this.loadSettings();
              this.loadBodyProfile();
            }
          })

          Button('✕')
            .width(44)
            .height(44)
            .fontSize(20)
            .fontColor(color.text)
            .backgroundColor(Color.Transparent)
            .margin({ top: 46, right: 16 })
            .onClick(() => {
              this.onboardingVisible = false;
            })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }
}

/**
 * 「全部餐食」/「运动记录」的路由参数。
 *
 * NavPathStack 的 pushPathByName 第二参必须是对象，不能直接传字符串，
 * 所以这里包一层，只带一个 route 标识供目标页做标题显示。
 */
export class YouRouteParams {
  route: string;

  constructor(route: string) {
    this.route = route;
  }
}
