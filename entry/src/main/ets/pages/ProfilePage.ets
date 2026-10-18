/**
 * 我的页：目标设置 + 数据来源说明 + 清空全部记录。
 */

import { common } from '@kit.AbilityKit';
import { SettingsRepository } from '../repositories/SettingsRepository';import { ProfileRepository } from '../repositories/ProfileRepository';
import { Database } from '../database/Database';
import { AppSettings } from '../models/AppSettings';
import { CalorieEngine } from '../services/CalorieEngine';
import {
  BodyProfile, Sex, ActivityLevel, GoalMode,
  ACTIVITY_LABELS, MODE_LABELS, SEX_LABELS, MacroTarget
} from '../models/Calculation';
import { color, fontSize, space, radius, layout, ThemeMode, THEME_LABELS } from '../common/DesignTokens';
import { ThemeService } from '../services/ThemeService';
import { DATA_SOURCE_LABEL } from '../common/Constants';
import { validateBudget, validateStepsGoal, validateMinutesGoal, validateActivityKcalGoal } from '../common/Validators';

@Component
export struct ProfilePage {
  @StorageLink('refreshTick') refreshTick: number = 0;
  @Consume('navStack') navStack: NavPathStack;
  @State budgetInput: string = '1800';
  @State stepsGoalInput: string = '8000';
  @State minutesGoalInput: string = '30';
  @State activityKcalGoalInput: string = '300';

  /* 体征档案 */
  @State weightInput: string = '65';
  @State heightInput: string = '170';
  @State ageInput: string = '30';
  /** 体脂率留空表示未知 → 引擎自动回退 Mifflin-St Jeor */
  @State bodyFatInput: string = '';
  @State sexIndex: number = 0;
  @State activityIndex: number = 2;
  @State goalIndex: number = 0;
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
      message: ok ? `外观已切换为${THEME_LABELS[mode]}` : '切换失败，请重试'
    });
  }

  private async loadBodyProfile(): Promise<void> {
    try {
      const p = await ProfileRepository.getBodyProfile();
      this.weightInput = String(p.weightKg);
      this.heightInput = String(p.heightCm);
      this.ageInput = String(p.ageYears);
      this.bodyFatInput = p.bodyFatRatio === null ? '' : (p.bodyFatRatio * 100).toFixed(1);
      this.sexIndex = ProfilePage.SEX_ORDER.indexOf(p.sex) >= 0
        ? ProfilePage.SEX_ORDER.indexOf(p.sex) : 0;
      this.activityIndex = ProfilePage.ACTIVITY_ORDER.indexOf(p.activity) >= 0
        ? ProfilePage.ACTIVITY_ORDER.indexOf(p.activity) : 2;
      this.goalIndex = ProfilePage.GOAL_ORDER.indexOf(p.mode) >= 0
        ? ProfilePage.GOAL_ORDER.indexOf(p.mode) : 0;
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
    if (!(w > 0) || !(h > 0) || !(a > 0)) {
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
      message: '将删除所有日期的饮食、运动和步数记录，目标设置保留。此操作不可撤销。',
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

  build() {
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
              Text(THEME_LABELS[m])
                .layoutWeight(1)
                .height(40)
                .textAlign(TextAlign.Center)
                .fontSize(fontSize.body)
                .fontColor(this.themeIndex === i ? color.onPrimary : color.textSecondary)
                .backgroundColor(this.themeIndex === i ? color.primary : color.surfaceMuted)
                .borderRadius(radius.medium)
                .onClick(() => {
                  this.themeIndex = i;
                  this.changeTheme(m);
                })
            }, (m: ThemeMode) => m)
          }
          .width('100%')

          Text('深色配色取自 NutriScan 真机实测像素值：底色 #0C0C0C（非纯黑），品牌色 #D5EE6E')
            .fontSize(fontSize.caption)
            .fontColor(color.textHint)
            .width('100%')
        }
        .padding(layout.cardPadding)
        .backgroundColor(color.surface)
        .borderRadius(radius.card)
        .border({ width: layout.borderWidth, color: color.border })
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
              TextInput({ text: this.bodyFatInput })
                .type(InputType.Number)
                .height(layout.inputHeight)
                .fontSize(fontSize.body)
                .backgroundColor(color.surfaceMuted)
                .borderRadius(radius.medium)
                .placeholder('未知')
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
                Text(SEX_LABELS[s])
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
                    .selected(this.activityIndex === i)
                    .onChange(() => {
                      this.activityIndex = i;
                      this.recalcPreview();
                    })
                  Text(ACTIVITY_LABELS[a])
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
                Text(MODE_LABELS[g])
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
        .backgroundColor(color.surface)
        .borderRadius(radius.card)
        .border({ width: layout.borderWidth, color: color.border })
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
        .backgroundColor(color.surface)
        .borderRadius(radius.card)
        .border({ width: layout.borderWidth, color: color.border })
        .width('100%')

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
        .backgroundColor(color.surface)
        .borderRadius(radius.card)
        .border({ width: layout.borderWidth, color: color.border })
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
        .backgroundColor(color.surface)
        .borderRadius(radius.card)
        .border({ width: layout.borderWidth, color: color.border })
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
      }
      .padding(layout.pagePadding)
      .constraintSize({ minHeight: '100%' })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor(color.bg)
  }
}