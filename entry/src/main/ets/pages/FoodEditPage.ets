/**
 * 食物编辑页（NavDestination）：新增/编辑食物，输入校验、热量预计算、保存。
 */

import { FoodRepository } from '../repositories/FoodRepository';
import { FoodLog } from '../models/FoodLog';
import { color, fontSize, space, radius, layout } from '../common/DesignTokens';
import { formatNumber } from '../common/DateUtils';
import { CalorieService } from '../services/CalorieService';
import { validateFoodName, validateWeight, validateKcalPer100g } from '../common/Validators';
import { MEAL_LABELS } from '../common/Constants';

class FoodEditParams {
  mode: string = 'add';
  date: string = '';
  id: number = -1;
}

@Component
export struct FoodEditPage {
  @Consume('navStack') navStack: NavPathStack;
  @State mode: string = 'add';
  @State date: string = '';
  @State recordId: number = -1;
  @State name: string = '';
  @State mealType: number = 0;
  @State weightInput: string = '';
  @State kcalInput: string = '';
  @State ready: boolean = false;

  private buildParams(p: FoodEditParams | null | undefined): void {
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
      const log = await FoodRepository.getById(this.recordId);
      if (log !== null) {
        this.name = log.name;
        this.mealType = log.mealType;
        this.weightInput = log.weightG.toString();
        this.kcalInput = log.kcalPer100g.toString();
      }
      this.ready = true;
    } catch (e) {
      this.ready = true;
    }
  }

  private previewCalories(): number | null {
    const w = Number(this.weightInput);
    const k = Number(this.kcalInput);
    if (this.weightInput.trim().length === 0 || this.kcalInput.trim().length === 0) {
      return null;
    }
    if (!isFinite(w) || !isFinite(k)) {
      return null;
    }
    return CalorieService.foodCalories(w, k);
  }

  private bumpRefresh(): void {
    const cur = AppStorage.get<number>('refreshTick') ?? 0;
    AppStorage.setOrCreate<number>('refreshTick', cur + 1);
  }

  private async save(): Promise<void> {
    const nameP = validateFoodName(this.name);
    if (!nameP.ok) {
      this.getUIContext().getPromptAction().showToast({ message: nameP.message });
      return;
    }
    const weightP = validateWeight(this.weightInput);
    if (!weightP.ok) {
      this.getUIContext().getPromptAction().showToast({ message: weightP.message });
      return;
    }
    const kcalP = validateKcalPer100g(this.kcalInput);
    if (!kcalP.ok) {
      this.getUIContext().getPromptAction().showToast({ message: kcalP.message });
      return;
    }
    const calories = CalorieService.foodCalories(weightP.value, kcalP.value);
    try {
      if (this.mode === 'edit' && this.recordId > 0) {
        const log = await FoodRepository.getById(this.recordId);
        if (log === null) {
          this.getUIContext().getPromptAction().showToast({ message: '记录不存在' });
          return;
        }
        const updated = new FoodLog(log.id, log.date, this.name.trim(), this.mealType,
          weightP.value, kcalP.value, calories, log.createdAt, Date.now());
        await FoodRepository.update(updated);
      } else {
        const created = new FoodLog(0, this.date, this.name.trim(), this.mealType,
          weightP.value, kcalP.value, calories, 0, 0);
        await FoodRepository.insert(created);
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
      message: '确定删除这条饮食记录吗？',
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
      await FoodRepository.delete(this.recordId);
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
            // 食物名称
            Column({ space: space.xs }) {
              Text('食物名称')
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
              TextInput({ text: this.name, placeholder: '例如：米饭' })
                .height(layout.inputHeight)
                .fontSize(fontSize.body)
                .backgroundColor(color.surfaceMuted)
                .borderRadius(radius.medium)
                .maxLength(40)
                .onChange((value: string) => {
                  this.name = value;
                })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            // 用餐类型
            Column({ space: space.xs }) {
              Text('用餐类型')
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
              Row({ space: space.sm }) {
                ForEach(MEAL_LABELS, (label: string, index: number) => {
                  Text(label)
                    .fontSize(fontSize.body)
                    .fontColor(this.mealType === index ? color.onPrimary : color.textSecondary)
                    .backgroundColor(this.mealType === index ? color.primary : color.surfaceMuted)
                    .borderRadius(radius.pill)
                    .padding({ left: space.md, right: space.md, top: space.xs + 2, bottom: space.xs + 2 })
                    .onClick(() => {
                      this.mealType = index;
                    })
                }, (label: string) => label)
              }
              .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            // 重量与热量
            Row({ space: space.md }) {
              Column({ space: space.xs }) {
                Text('食用重量（g）')
                  .fontSize(fontSize.secondary)
                  .fontColor(color.textSecondary)
                TextInput({ text: this.weightInput, placeholder: '例如 150' })
                  .type(InputType.NUMBER_DECIMAL)
                  .height(layout.inputHeight)
                  .fontSize(fontSize.body)
                  .backgroundColor(color.surfaceMuted)
                  .borderRadius(radius.medium)
                  .onChange((value: string) => {
                    this.weightInput = value;
                  })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Column({ space: space.xs }) {
                Text('每100g热量（kcal）')
                  .fontSize(fontSize.secondary)
                  .fontColor(color.textSecondary)
                TextInput({ text: this.kcalInput, placeholder: '例如 130' })
                  .type(InputType.NUMBER_DECIMAL)
                  .height(layout.inputHeight)
                  .fontSize(fontSize.body)
                  .backgroundColor(color.surfaceMuted)
                  .borderRadius(radius.medium)
                  .onChange((value: string) => {
                    this.kcalInput = value;
                  })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')

            // 计算结果
            Column({ space: space.xs }) {
              Text('预计总热量')
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
              Text(this.previewCalories() !== null ? `${formatNumber(this.previewCalories()!)} kcal` : '—')
                .fontSize(fontSize.metric)
                .fontWeight(FontWeight.Bold)
                .fontColor(color.food)
            }
            .alignItems(HorizontalAlign.Start)
            .padding(layout.cardPadding)
            .backgroundColor(color.foodLight)
            .borderRadius(radius.card)
            .width('100%')

            // 保存
            Button(this.mode === 'edit' ? '保存修改' : '保存记录')
              .width('100%')
              .height(layout.buttonHeight)
              .fontSize(fontSize.body)
              .fontColor(color.onPrimary)
              .backgroundColor(color.primary)
              .borderRadius(radius.large)
              .onClick(() => {
                this.save();
              })

            // 删除（仅编辑模式）
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
    }
    .title(this.mode === 'edit' ? '编辑食物' : '新增食物')
    .backgroundColor(color.bg)
    .onReady((ctx: NavDestinationContext) => {
      const p = ctx.pathInfo.param as FoodEditParams | null | undefined;
      this.buildParams(p);
    })
  }
}