/**
 * 运动页：活动热量/时长/步数进度 + 计步自动采集 + 运动记录列表。
 * 活动热量只汇总运动记录，不依据步数推算，避免重复计算。
 *
 * 步数有两个来源，主次分明：
 *   · 计步传感器（主）—— SensorId.PEDOMETER 的开机累计值做基线差值得到当日步数
 *   · 手动填写（次）—— 用户校正用。一旦当天被手动改过，传感器不再覆盖，
 *     除非用户点「恢复自动采集」。
 */

import { common } from '@kit.AbilityKit';
import { ExerciseRepository } from '../repositories/ExerciseRepository';
import { anim } from '../common/Motion';
import { ActivityRepository } from '../repositories/ActivityRepository';
import { SettingsRepository } from '../repositories/SettingsRepository';
import { ExerciseLog } from '../models/ExerciseLog';
import { AppSettings } from '../models/AppSettings';
import { MetricCard } from '../components/MetricCard';
import { EmptyState } from '../components/EmptyState';
import { StepSensorService, StepSensorStatus } from '../services/StepSensorService';
import { stepSourceLabel, STEP_SOURCE_MANUAL } from '../models/DailyActivity';
import {
  color, fontSize, space, radius, layout, pageGradient,
  toneVeil, glass, glassGradient, glassShadow
} from '../common/DesignTokens';
import { displayDate, toDateKey, parseDateKey, isFutureDate, formatNumber } from '../common/DateUtils';
import { EXERCISE_LABELS } from '../common/Constants';
import { CalorieService } from '../services/CalorieService';
import { validateSteps } from '../common/Validators';

@Component
export struct ActivityPage {
  @Consume('navStack') navStack: NavPathStack;
  @StorageLink('refreshTick') @Watch('reload') refreshTick: number = 0;
  @StorageLink('selectedDate') @Watch('reload') selectedDate: string = '';
  /** 页面内容入场开关，见 build() 末尾的 opacity/translate */
  @State private entered: boolean = false;

  /** 当前被按住的记录 id，-1 表示没按。用 id 而非布尔量，见 FoodPage 同名字段的注释 */
  @State private pressedExerciseId: number = -1;

  enterPage(): void {
    this.entered = true;
  }

  private touchExercise(id: number, e: TouchEvent): void {
    if (e.type === TouchType.Down) {
      this.pressedExerciseId = id;
    } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
      this.pressedExerciseId = -1;
    }
  }

  @State exercises: ExerciseLog[] = [];
  @State steps: number = 0;
  @State stepsInput: string = '';
  @State settings: AppSettings | null = null;
  /** 当天步数的来源：SENSOR_PEDOMETER / MANUAL_SIMULATED / 空(未采集) */
  @State stepSource: string = '';
  /** 传感器状态机的可读描述 */
  @State sensorStatusText: string = '';
  /** 最近一次基线重建的原因 */
  @State sensorReason: string = '';

  aboutToAppear(): void {
    this.reload();
    StepSensorService.setListener(this.onSensorUpdate);
    this.tryStartSensor(false);
  }

  aboutToDisappear(): void {
    StepSensorService.setListener(null);
  }

  /**
   * 传感器上报回调。手动值优先 —— 已经被用户校正过的当天，
   * 不能被传感器上报冲掉显示值。
   */
  private onSensorUpdate: (steps: number) => void = (value: number) => {
    if (this.stepSource === STEP_SOURCE_MANUAL) {
      return;
    }
    this.steps = value;
    this.stepsInput = value.toString();
    this.sensorReason = StepSensorService.getLastReason();
  };

  /** 读取 Ability 上下文；拿不到就放弃传感器（不影响手动功能） */
  private abilityContext(): common.UIAbilityContext | null {
    const host = this.getUIContext().getHostContext();
    if (host === undefined) {
      return null;
    }
    return host as common.UIAbilityContext;
  }

  /**
   * 启动采集。requestPermission=true 才会弹权限框。
   * 页面首次进入传 false —— 冷启动弹权限框是骚扰，得用户自己点。
   */
  private async tryStartSensor(requestPermission: boolean): Promise<void> {
    const ctx = this.abilityContext();
    if (ctx === null) {
      this.sensorStatusText = '无法获取应用上下文';
      return;
    }
    const status = await StepSensorService.start(ctx, requestPermission);
    this.sensorStatusText = StepSensorService.getStatusDetail();
    if (status === StepSensorStatus.RUNNING) {
      this.sensorReason = StepSensorService.getLastReason();
    }
  }

  private reload(): void {
    this.loadData();
  }

  private async loadData(): Promise<void> {
    try {
      this.exercises = await ExerciseRepository.getByDate(this.selectedDate);
      const activity = await ActivityRepository.getByDate(this.selectedDate);
      this.steps = activity !== null ? activity.steps : 0;
      this.stepSource = activity !== null ? activity.source : '';
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
      this.steps = p.value;
      this.stepSource = STEP_SOURCE_MANUAL;
      this.bumpRefresh();
      this.getUIContext().getPromptAction().showToast({ message: '步数已保存，传感器将不再覆盖今天' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试' });
    }
  }

  /** 撤销手动覆盖，把当天交回给传感器 */
  private async restoreAutoSteps(): Promise<void> {
    try {
      await ActivityRepository.clearManualSteps(this.selectedDate);
      this.stepSource = '';
      this.steps = 0;
      this.stepsInput = '0';
      this.bumpRefresh();
      await this.tryStartSensor(true);
      this.getUIContext().getPromptAction().showToast({ message: '已恢复自动采集' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '恢复失败，请重试' });
    }
  }

  /**
   * 重新校准今日步数：把当前累计值当作今日零点。
   * 用户觉得今天数字明显不对时用（换机、换手、系统迁移都会让累计值对不上）。
   */
  private async recalibrateSteps(): Promise<void> {
    const ctx = this.abilityContext();
    if (ctx === null) {
      this.getUIContext().getPromptAction().showToast({ message: '无法获取应用上下文' });
      return;
    }
    const ok = await StepSensorService.recalibrate(ctx);
    if (ok) {
      this.steps = 0;
      this.stepsInput = '0';
      this.sensorReason = StepSensorService.getLastReason();
      this.bumpRefresh();
      this.getUIContext().getPromptAction().showToast({ message: '已重新校准，今日步数从 0 开始' });
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '读取传感器失败，请重试' });
    }
  }

  /** 传感器状态的短标签 */
  private sensorStatusLabel(): string {    const s = StepSensorService.getStatus();
    if (s === StepSensorStatus.RUNNING) {
      return '已开启';
    }
    if (s === StepSensorStatus.NEED_PERMISSION) {
      return '待授权';
    }
    if (s === StepSensorStatus.DENIED) {
      return '已拒绝';
    }
    if (s === StepSensorStatus.UNSUPPORTED) {
      return '设备不支持';
    }
    if (s === StepSensorStatus.ERROR) {
      return '异常';
    }
    return '未开启';
  }

  private sensorStatusColor(): ResourceColor {
    const s = StepSensorService.getStatus();
    if (s === StepSensorStatus.RUNNING) {
      return color.primary;
    }
    if (s === StepSensorStatus.ERROR || s === StepSensorStatus.DENIED) {
      return color.danger;
    }
    return color.textHint;
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
            title: '步数',
            valueText: formatNumber(this.steps),
            unit: '步',
            progress: CalorieService.progress(this.steps,
              this.settings !== null ? this.settings.stepsGoal : 8000),
            barColor: color.activity,
            sourceLabel: stepSourceLabel(this.stepSource),
            goalText: `目标 ${formatNumber(this.settings !== null ? this.settings.stepsGoal : 8000)} 步`
          })
        }
        .width('100%')

        // 步数采集：自动为主，手动为校正
        Column({ space: space.sm }) {
          Row({ space: space.sm }) {
            Text('自动采集')
              .fontSize(fontSize.sectionTitle)
              .fontWeight(FontWeight.Bold)
              .fontColor(color.text)
              .layoutWeight(1)
            Text(this.sensorStatusLabel())
              .fontSize(fontSize.caption)
              .fontColor(this.sensorStatusColor())
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .backgroundColor(color.surfaceMuted)
              .borderRadius(8)
          }
          .width('100%')

          Text('计步传感器给的是开机以来的累计步数，这里换算成当日步数；跨零点会按时间比例重新拆分基线。')
            .fontSize(fontSize.caption)
            .fontColor(color.textHint)
            .width('100%')

          if (this.sensorReason.length > 0) {
            Text(this.sensorReason)
              .fontSize(fontSize.caption)
              .fontColor(color.textHint)
              .width('100%')
          }

          if (this.stepSource === STEP_SOURCE_MANUAL) {
            Button('恢复自动采集')
              .width('100%')
              .height(layout.buttonHeight)
              .fontSize(fontSize.body)
              .fontColor(color.primary)
              .backgroundColor(color.primaryLight)
              .borderRadius(14)
              .onClick(() => {
                this.restoreAutoSteps();
              })
          } else if (StepSensorService.getStatus() === StepSensorStatus.RUNNING) {
            // 已经在采集了，这时再放「开启自动采集」是个骗人的死按钮。
            // 给一个真实存在的动作：把当前累计值当作今日零点，重新起算。
            Button('重新校准今日步数')
              .width('100%')
              .height(layout.buttonHeight)
              .fontSize(fontSize.body)
              .fontColor(color.primary)
              .backgroundColor(color.primaryLight)
              .borderRadius(14)
              .onClick(() => {
                this.recalibrateSteps();
              })
          } else {
            Button('开启自动采集')
              .width('100%')
              .height(layout.buttonHeight)
              .fontSize(fontSize.body)
              .fontColor('#FFFFFF')
              .backgroundColor(color.activity)
              .borderRadius(14)
              .shadow(glassShadow(12, 6))
              .onClick(() => {
                this.tryStartSensor(true);
              })
          }

          Divider()
            .color(color.border)
            .margin({ top: space.xs, bottom: space.xs })

          Text('手动校正')
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
              // 键盘上的「完成」直接保存，别让用户还得去够屏幕下方的按钮
              .onSubmit(() => {
                this.saveSteps();
              })
            Button('保存')
              .height(layout.buttonHeight)
              .fontSize(fontSize.body)
              .fontColor('#FFFFFF')
              .backgroundColor(color.activity)
              .borderRadius(14)
              .shadow(glassShadow(12, 6))
              .onClick(() => {
                this.saveSteps();
              })
          }
          .width('100%')
          Text('手动填写会覆盖当天的自动采集值；点「恢复自动采集」后由传感器重新接管。')
            .fontSize(fontSize.caption)
            .fontColor(color.textHint)
        }
        .width('100%')
        .padding(layout.cardPadding)
        .linearGradient(glassGradient(toneVeil('steps')))
        .borderRadius(glass.cardRadius)
        .border({ width: glass.borderWidth, color: color.glassBorder })
        .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
        .alignItems(HorizontalAlign.Start)

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
                  .fontColor(color.text)

                Text('删除')
                  .fontSize(fontSize.caption)
                  .fontColor(color.danger)
                  .padding(8)
                  .onClick(() => {
                    this.confirmDelete(log);
                  })
              }
              .width('100%')
              .padding({ top: space.sm, bottom: space.sm, left: space.sm, right: space.sm })
              // 运动类型决定色调：跑步永远同色，不同类型自动错开
              .linearGradient({
                angle: 135,
                colors: [[toneVeil(EXERCISE_LABELS[log.type]), 0], [color.glassFill, 1]]
              })
              .borderRadius(radius.medium)
              .border({ width: 1, color: color.glassBorder })
              .scale({
                x: this.pressedExerciseId === log.id ? anim.pressScale : 1,
                y: this.pressedExerciseId === log.id ? anim.pressScale : 1
              })
              .animation({ duration: anim.pressMs, curve: anim.ease })
              .onTouch((e: TouchEvent) => {
                this.touchExercise(log.id, e);
              })
              .onClick(() => {
                this.goEdit(log);
              })
            }, (log: ExerciseLog) => log.id.toString())
          }
        }
        .width('100%')
        .padding(layout.cardPadding)
        .linearGradient(glassGradient(toneVeil('exercise')))
        .borderRadius(glass.cardRadius)
        .border({ width: glass.borderWidth, color: color.glassBorder })
        .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
        .alignItems(HorizontalAlign.Start)

        // 添加运动
        Button('+ 添加运动')
          .width('100%')
          .height(layout.buttonHeight)
          .fontSize(fontSize.body)
          .fontColor('#FFFFFF')
          .backgroundColor(color.activity)
          .borderRadius(14)
          .shadow(glassShadow(12, 6))
          .onClick(() => {
            this.goAdd();
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
