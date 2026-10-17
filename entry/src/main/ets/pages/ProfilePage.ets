/**
 * 我的页：目标设置 + 数据来源说明 + 清空全部记录。
 */

import { SettingsRepository } from '../repositories/SettingsRepository';
import { Database } from '../database/Database';
import { AppSettings } from '../models/AppSettings';
import { color, fontSize, space, radius, layout } from '../common/DesignTokens';
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

  aboutToAppear(): void {
    this.loadSettings();
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