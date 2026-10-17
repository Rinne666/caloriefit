/**
 * 运动页：活动热量/时长/步数进度 + 模拟步数设置 + 运动记录列表。
 * 活动热量只汇总运动记录，不依据步数推算，避免重复计算。
 */

import { ExerciseRepository } from '../repositories/ExerciseRepository';
import { ActivityRepository } from '../repositories/ActivityRepository';
import { SettingsRepository } from '../repositories/SettingsRepository';
import { ExerciseLog } from '../models/ExerciseLog';
import { AppSettings } from '../models/AppSettings';
import { MetricCard } from '../components/MetricCard';
import { EmptyState } from '../components/EmptyState';
import { color, fontSize, space, radius, layout } from '../common/DesignTokens';
import { displayDate, toDateKey, parseDateKey, isFutureDate, formatNumber } from '../common/DateUtils';
import { EXERCISE_LABELS } from '../common/Constants';
import { CalorieService } from '../services/CalorieService';
import { validateSteps } from '../common/Validators';

@Component
export struct ActivityPage {
  @Consume('navStack') navStack: NavPathStack;
  @StorageLink('refreshTick') @Watch('reload') refreshTick: number = 0;
  @StorageLink('selectedDate') @Watch('reload') selectedDate: string = '';
  @State exercises: ExerciseLog[] = [];
  @State steps: number = 0;
  @State stepsInput: string = '';
  @State settings: AppSettings | null = null;

  aboutToAppear(): void {
    this.reload();
  }

  reload(): void {
    this.loadData();
  }

  private async loadData(): Promise<void> {
    try {
      this.exercises = await ExerciseRepository.getByDate(this.selectedDate);
      const activity = await ActivityRepository.getByDate(this.selectedDate);
      this.steps = activity !== null ? activity.steps : 0;
      this.stepsInput = this.steps.toString();
      this.settings = await SettingsRepository.getSettings();
    } catch (e) {
      // 保留旧数据
    }
  }

  private burned(): number {
    let sum = 0;
    for (let i = 0; i < this.exercises.length; i++) {
      sum += this.exercises[i].caloriesBurned;
    }
    return sum;
  }

  private minutes(): number {
    let sum = 0;
    for (let i = 0; i < this.exercises.length; i++) {
      sum += this.exercises[i].durationMinutes;
    }
    return sum;
  }

  private showDatePicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date(2020, 0, 1),
      end: new Date(2100, 11, 31),
      selected: parseDateKey(this.selectedDate),
      onDateAccept: (value: Date) => {
        const key = toDateKey(value);
        if (isFutureDate(key)) {
          this.getUIContext().getPromptAction().showToast({ message: '不允许查看未来日期' });
          return;
        }
        AppStorage.setOrCreate<string>('selectedDate', key);
      }
    });
  }

  private bumpRefresh(): void {
    const cur = AppStorage.get<number>('refreshTick') ?? 0;
    AppStorage.setOrCreate<number>('refreshTick', cur + 1);
  }

  private async saveSteps(): Promise<void> {
    const p = validateSteps(this.stepsInput);
    if (!p.ok) {
      this.getUIContext().getPromptAction().showToast({ message: p.message });
      return;
    }
    try {
      await ActivityRepository.setDailySteps(this.selectedDate, p.value);
      this.bumpRefresh();
      this.getUIContext().getPromptAction().showToast({ message: '步数已保存' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试' });
    }
  }

  private confirmDelete(log: ExerciseLog): void {
    this.getUIContext().showAlertDialog({
      title: '删除记录',
      message: `确定删除这条「${EXERCISE_LABELS[log.type]}」记录吗？`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: color.danger,
        action: () => {
          this.doDelete(log);
        }
      }
    });
  }

  private async doDelete(log: ExerciseLog): Promise<void> {
    try {
      await ExerciseRepository.delete(log.id);
      this.bumpRefresh();
      this.getUIContext().getPromptAction().showToast({ message: '已删除' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '删除失败，请重试' });
    }
  }

  private goEdit(log: ExerciseLog): void {
    this.navStack.pushPathByName('ActivityEdit', new ActivityEditParams('edit', this.selectedDate, log.id));
  }

  private goAdd(): void {
    this.navStack.pushPathByName('ActivityEdit', new ActivityEditParams('add', this.selectedDate, -1));
  }

  build() {
    Scroll() {
      Column({ space: space.md }) {
        // 日期栏
        Row() {
          Text('运动')
            .fontSize(fontSize.pageTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.text)
            .layoutWeight(1)
          Text(displayDate(this.selectedDate))
            .fontSize(fontSize.secondary)
            .fontColor(color.textSecondary)
            .onClick(() => {
              this.showDatePicker();
            })
          Button('切换日期')
            .height(36)
            .fontSize(fontSize.secondary)
            .fontColor(color.primary)
            .backgroundColor(color.primaryLight)
            .borderRadius(radius.pill)
            .margin({ left: space.sm })
            .onClick(() => {
              this.showDatePicker();
            })
        }
        .width('100%')

        // 三个指标卡
        Column({ space: layout.cardGap }) {
          MetricCard({
            title: '活动热量',
            valueText: formatNumber(this.burned()),
            unit: 'kcal',
            progress: CalorieService.progress(this.burned(),
              this.settings !== null ? this.settings.activityKcalGoal : 300),
            barColor: color.activity,
            goalText: `目标 ${formatNumber(this.settings !== null ? this.settings.activityKcalGoal : 300)} kcal`
          })

          MetricCard({
            title: '运动时长',
            valueText: formatNumber(this.minutes()),
            unit: '分钟',
            progress: CalorieService.progress(this.minutes(),
              this.settings !== null ? this.settings.exerciseMinutesGoal : 30),
            barColor: color.activity,
            goalText: `目标 ${formatNumber(this.settings !== null ? this.settings.exerciseMinutesGoal : 30)} 分钟`
          })

          MetricCard({
            title: '步数（模拟）',
            valueText: formatNumber(this.steps),
            unit: '步',
            progress: CalorieService.progress(this.steps,
              this.settings !== null ? this.settings.stepsGoal : 8000),
            barColor: color.activity,
            goalText: `目标 ${formatNumber(this.settings !== null ? this.settings.stepsGoal : 8000)} 步`
          })
        }
        .width('100%')

        // 模拟步数设置
        Column({ space: space.sm }) {
          Text('设置当日累计步数')
            .fontSize(fontSize.sectionTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.text)
          Row({ space: space.sm }) {
            TextInput({ text: this.stepsInput, placeholder: '例如 6200' })
              .type(InputType.Number)
              .height(layout.inputHeight)
              .fontSize(fontSize.body)
              .backgroundColor(color.surfaceMuted)
              .borderRadius(radius.medium)
              .layoutWeight(1)
              .onChange((value: string) => {
                this.stepsInput = value;
              })
            Button('保存')
              .height(layout.buttonHeight)
              .fontSize(fontSize.body)
              .fontColor(color.onPrimary)
              .backgroundColor(color.activity)
              .borderRadius(radius.large)
              .onClick(() => {
                this.saveSteps();
              })
          }
          .width('100%')
          Text('步数为手动设置的模拟值（覆盖式保存），不代表真实传感器数据')
            .fontSize(fontSize.caption)
            .fontColor(color.textHint)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(layout.cardPadding)
        .backgroundColor(color.surface)
        .borderRadius(radius.card)
        .border({ width: layout.borderWidth, color: color.border })
        .width('100%')

        // 运动记录列表
        Column({ space: space.xs }) {
          Text('运动记录')
            .fontSize(fontSize.sectionTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.text)
            .width('100%')

          if (this.exercises.length === 0) {
            EmptyState({
              message: '今天还没有运动记录',
              buttonText: '',
              onAction: () => {
              }
            })
          } else {
            ForEach(this.exercises, (log: ExerciseLog) => {
              Row({ space: space.sm }) {
                Column({ space: 2 }) {
                  Text(EXERCISE_LABELS[log.type])
                    .fontSize(fontSize.body)
                    .fontColor(color.text)
                  Text(`${log.durationMinutes} 分钟`)
                    .fontSize(fontSize.caption)
                    .fontColor(color.textHint)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text(`${formatNumber(log.caloriesBurned)} kcal`)
                  .fontSize(fontSize.body)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(color.activity)

                Text('删除')
                  .fontSize(fontSize.caption)
                  .fontColor(color.danger)
                  .padding(8)
                  .onClick(() => {
                    this.confirmDelete(log);
                  })
              }
              .width('100%')
              .padding({ top: space.sm, bottom: space.sm })
              .onClick(() => {
                this.goEdit(log);
              })
            }, (log: ExerciseLog) => log.id.toString())
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding(layout.cardPadding)
        .backgroundColor(color.surface)
        .borderRadius(radius.card)
        .border({ width: layout.borderWidth, color: color.border })
        .width('100%')

        // 添加运动
        Button('+ 添加运动')
          .width('100%')
          .height(layout.buttonHeight)
          .fontSize(fontSize.body)
          .fontColor(color.onPrimary)
          .backgroundColor(color.activity)
          .borderRadius(radius.large)
          .onClick(() => {
            this.goAdd();
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

// 参数结构与 HomePage.ets 导出的 ActivityEditParams 一致
class ActivityEditParams {
  mode: string;
  date: string;
  id: number;

  constructor(mode: string, date: string, id: number) {
    this.mode = mode;
    this.date = date;
    this.id = id;
  }
}