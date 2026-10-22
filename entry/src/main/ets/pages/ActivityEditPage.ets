/**
 * 运动编辑页（NavDestination）：新增/编辑运动，输入校验及保存。
 */

import { ExerciseRepository } from '../repositories/ExerciseRepository';
import { ExerciseLog } from '../models/ExerciseLog';
import { color, fontSize, space, radius, layout, pageGradient } from '../common/DesignTokens';
import { formatNumber } from '../common/DateUtils';
import { validateDuration, validateBurned } from '../common/Validators';
import { EXERCISE_LABELS } from '../common/Constants';

class ActivityEditParams {
  mode: string = 'add';
  date: string = '';
  id: number = -1;
}

@Component
export struct ActivityEditPage {
  @Consume('navStack') navStack: NavPathStack;
  @State mode: string = 'add';
  @State date: string = '';
  @State recordId: number = -1;
  @State typeIndex: number = 0;
  @State durationInput: string = '';
  @State burnedInput: string = '';
  @State ready: boolean = false;
  private typeOptions: SelectOption[] = [];

  aboutToAppear(): void {
    for (let i = 0; i < EXERCISE_LABELS.length; i++) {
      const opt: SelectOption = { value: EXERCISE_LABELS[i] };
      this.typeOptions.push(opt);
    }
  }

  private buildParams(p: ActivityEditParams | null | undefined): void {
    if (p === null || p === undefined) {
      this.ready = true;
      return;
    }
    this.mode = typeof p.mode === 'string' ? p.mode : 'add';
    this.date = typeof p.date === 'string' ? p.date : '';
    this.recordId = typeof p.id === 'number' ? p.id : -1;
    if (this.mode === 'edit' && this.recordId > 0) {
      this.loadRecord();
    } else {
      this.ready = true;
    }
  }

  private async loadRecord(): Promise<void> {
    try {
      const log = await ExerciseRepository.getById(this.recordId);
      if (log !== null) {
        this.typeIndex = log.type;
        this.durationInput = log.durationMinutes.toString();
        this.burnedInput = log.caloriesBurned.toString();
      }
      this.ready = true;
    } catch (e) {
      this.ready = true;
    }
  }

  private bumpRefresh(): void {
    const cur = AppStorage.get<number>('refreshTick') ?? 0;
    AppStorage.setOrCreate<number>('refreshTick', cur + 1);
  }

  private async save(): Promise<void> {
    const dP = validateDuration(this.durationInput);
    if (!dP.ok) {
      this.getUIContext().getPromptAction().showToast({ message: dP.message });
      return;
    }
    const bP = validateBurned(this.burnedInput);
    if (!bP.ok) {
      this.getUIContext().getPromptAction().showToast({ message: bP.message });
      return;
    }
    try {
      if (this.mode === 'edit' && this.recordId > 0) {
        const log = await ExerciseRepository.getById(this.recordId);
        if (log === null) {
          this.getUIContext().getPromptAction().showToast({ message: '记录不存在' });
          return;
        }
        const updated = new ExerciseLog(log.id, log.date, this.typeIndex, dP.value,
          bP.value, log.createdAt, Date.now());
        await ExerciseRepository.update(updated);
      } else {
        const created = new ExerciseLog(0, this.date, this.typeIndex, dP.value, bP.value, 0, 0);
        await ExerciseRepository.insert(created);
      }
      this.bumpRefresh();
      this.getUIContext().getPromptAction().showToast({ message: '已保存' });
      this.navStack.pop();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试' });
    }
  }

  private confirmDelete(): void {
    this.getUIContext().showAlertDialog({
      title: '删除记录',
      message: '确定删除这条运动记录吗？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: color.danger,
        action: () => {
          this.doDelete();
        }
      }
    });
  }

  private async doDelete(): Promise<void> {
    try {
      await ExerciseRepository.delete(this.recordId);
      this.bumpRefresh();
      this.getUIContext().getPromptAction().showToast({ message: '已删除' });
      this.navStack.pop();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '删除失败，请重试' });
    }
  }

  build() {
    NavDestination() {
      Scroll() {
        if (this.ready) {
          Column({ space: space.md }) {
            // 运动类型
            Column({ space: space.xs }) {
              Text('运动类型')
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
              Select(this.typeOptions)
                .selected(this.typeIndex)
                .value(EXERCISE_LABELS[this.typeIndex])
                .fontColor(color.text)
                .font({ size: fontSize.body })
                .width('100%')
                .height(layout.inputHeight)
                .backgroundColor(color.surfaceMuted)
                .borderRadius(radius.medium)
                .onSelect((index: number) => {
                  this.typeIndex = index;
                })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            // 时长
            Column({ space: space.xs }) {
              Text('运动时长（分钟）')
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
              TextInput({ text: this.durationInput, placeholder: '例如 20' })
                .type(InputType.Number)
                .height(layout.inputHeight)
                .fontSize(fontSize.body)
                .backgroundColor(color.surfaceMuted)
                .borderRadius(radius.medium)
                .onChange((value: string) => {
                  this.durationInput = value;
                })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            // 消耗
            Column({ space: space.xs }) {
              Text('消耗热量（kcal）')
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
              TextInput({ text: this.burnedInput, placeholder: '例如 180' })
                .type(InputType.Number)
                .height(layout.inputHeight)
                .fontSize(fontSize.body)
                .backgroundColor(color.surfaceMuted)
                .borderRadius(radius.medium)
                .onChange((value: string) => {
                  this.burnedInput = value;
                })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            // 信息卡
            Column({ space: space.xs }) {
              Text('提示')
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
              Text(`本次将记录：${EXERCISE_LABELS[this.typeIndex]} ${this.durationInput} 分钟，消耗 ${this.burnedInput === '' ? '—' : formatNumber(Number(this.burnedInput))} kcal`)
                .fontSize(fontSize.body)
                .fontColor(color.activity)
            }
            .alignItems(HorizontalAlign.Start)
            .padding(layout.cardPadding)
            .backgroundColor(color.activityLight)
            .borderRadius(radius.card)
            .width('100%')

            Button(this.mode === 'edit' ? '保存修改' : '保存记录')
              .width('100%')
              .height(layout.buttonHeight)
              .fontSize(fontSize.body)
              .fontColor(color.onPrimary)
              .backgroundColor(color.activity)
              .borderRadius(radius.large)
              .onClick(() => {
                this.save();
              })

            if (this.mode === 'edit') {
              Button('删除记录')
                .width('100%')
                .height(layout.buttonHeight)
                .fontSize(fontSize.body)
                .fontColor(color.danger)
                .backgroundColor(color.dangerLight)
                .borderRadius(radius.large)
                .onClick(() => {
                  this.confirmDelete();
                })
            }
          }
          .padding(layout.pagePadding)
          .constraintSize({ minHeight: '100%' })
        }
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .backgroundColor(color.bg)
      .linearGradient(pageGradient())
    }
    .title(this.mode === 'edit' ? '编辑运动' : '新增运动')
    .backgroundColor(color.bg)
    .linearGradient(pageGradient())
    .onReady((ctx: NavDestinationContext) => {
      const p = ctx.pathInfo.param as ActivityEditParams | null | undefined;
      this.buildParams(p);
    })
  }
}