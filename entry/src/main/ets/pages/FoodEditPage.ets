/**
 * 食物编辑页（NavDestination）：手动称重模式 / AI 整份估算模式 / 编辑模式。
 * AI 模式：直接编辑确认整份 kcal，重量字段不显示，保存时 entry_mode=1。
 */

import { FoodRepository } from '../repositories/FoodRepository';
import { FoodLog, FoodLogInput } from '../models/FoodLog';
import { color, fontSize, space, radius, layout, pageGradient } from '../common/DesignTokens';
import { formatNumber } from '../common/DateUtils';
import { CalorieService } from '../services/CalorieService';
import { AppDialogService } from '../services/AppDialogService';
import { validateFoodName, validateWeight, validateKcalPer100g } from '../common/Validators';
import { MEAL_LABELS } from '../common/Constants';

class FoodEditParams {
  mode: string = 'add';
  date: string = '';
  id: number = -1;
  name: string = '';
  calories: number = 0;
  aiConfidence: number = 0;
  aiNotes: string = '';
  /** V3：AI 模式透传的宏量估算（克）。手动模式为 null。 */
  proteinG: number | null = null;
  carbsG: number | null = null;
  fatG: number | null = null;
  /** V6：AI 模式透传的抠图贴纸路径（相对 filesDir）。手动模式为空串。 */
  stickerPath: string = '';
  /**
   * 新增时预置的餐次（0 早餐 / 1 午餐 / 2 晚餐 / 3 加餐）。
   * -1 = 不指定，沿用表单默认值。
   *
   * 2026-10-21 补：从「午餐」进入新增时，表单默认是早餐，
   * 保存后记录被记到早餐去（交付说明 §19 F02）。
   */
  mealType: number = -1;
}

/**
 * 宏量输入读取结果。
 * ArkTS 要求对象字面量对应显式声明的 interface，
 * 不能用内联对象类型（arkts-no-obj-literals-as-types）。
 */
class MacroInputResult {
  ok: boolean = false;
  proteinG: number | null = null;
  carbsG: number | null = null;
  fatG: number | null = null;
  message: string = '';

  constructor(ok: boolean, proteinG: number | null, carbsG: number | null,
    fatG: number | null, message: string) {
    this.ok = ok;
    this.proteinG = proteinG;
    this.carbsG = carbsG;
    this.fatG = fatG;
    this.message = message;
  }
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
  @State totalKcalInput: string = '';
  @State aiNotes: string = '';
  /** V3 宏量录入（克）。留空表示不记录，不以 0 冒充 */
  @State proteinInput: string = '';
  @State carbsInput: string = '';
  @State fatInput: string = '';
  @State ready: boolean = false;
  private aiConfidence: number = 0;
  /** V6：抠好的食物贴纸路径（相对 filesDir）。空串表示这条记录没有贴纸。 */
  @State private stickerPath: string = '';
  /** 编辑已有 AI 录入记录时为 true —— 决定表单用 AI 形态，但不影响路由 mode */
  @State private aiForm: boolean = false;

  private isAiMode(): boolean {
    return this.mode === 'ai';
  }

  /**
   * 表单是否用「AI 整份估算」形态。
   *
   * 与 `isAiMode()`（路由意图：从 AI 识别流程新建一条）**不是一回事**：
   *   · mode === 'ai' → 从 AI 识别页过来，记录还不存在
   *   · mode === 'edit' + aiForm → 编辑一条**已经存在**的 AI 录入记录
   *
   * 这两件事之前被混为一谈：loadRecord() 遇到 AI 记录时把 mode 改成 'ai'，
   * 结果「编辑食物」页的删除按钮（只在 mode === 'edit' 时显示）被藏掉了 ——
   * 用户从「全部餐食」点开一条 AI 记录，**删不掉它**，只能退回列表用行末那个
   * 很小的「删除」文字。表单形态与路由意图必须分开。
   */
  private useAiForm(): boolean {
    return this.mode === 'ai' || this.aiForm;
  }

  private applyParams(p: FoodEditParams): void {
    this.mode = typeof p.mode === 'string' ? p.mode : 'add';
    this.date = typeof p.date === 'string' ? p.date : '';
    this.recordId = typeof p.id === 'number' ? p.id : -1;
    // 新增时带上调用方指定的餐次（从「午餐」进来就预置午餐）
    if (typeof p.mealType === 'number' && p.mealType >= 0 && p.mealType <= 3) {
      this.mealType = p.mealType;
    }
    if (this.mode === 'ai') {
      this.name = typeof p.name === 'string' ? p.name : '';
      this.totalKcalInput = typeof p.calories === 'number' && p.calories > 0 ?
        p.calories.toString() : '';
      this.aiConfidence = typeof p.aiConfidence === 'number' ? p.aiConfidence : 0;
      this.aiNotes = typeof p.aiNotes === 'string' ? p.aiNotes : '';
      // AI 估算的宏量预填，允许用户覆盖
      this.proteinInput = typeof p.proteinG === 'number' ? String(p.proteinG) : '';
      this.carbsInput = typeof p.carbsG === 'number' ? String(p.carbsG) : '';
      this.fatInput = typeof p.fatG === 'number' ? String(p.fatG) : '';
      this.stickerPath = typeof p.stickerPath === 'string' ? p.stickerPath : '';
      this.ready = true;
    } else if (this.mode === 'edit' && this.recordId > 0) {
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
        if (log.entryMode === 1) {
          // 只切换**表单形态**，不改 mode —— mode 决定标题、删除按钮与
          // 「保存后要 pop 几层」，改成 'ai' 会把编辑态的删除入口弄没。
          this.aiForm = true;
          this.totalKcalInput = log.calories.toString();
          this.aiConfidence = log.aiConfidence !== null ? log.aiConfidence : 0;
          this.aiNotes = log.aiNotes !== null ? log.aiNotes : '';
          this.stickerPath = log.stickerPath !== null ? log.stickerPath : '';
        } else {
          this.weightInput = log.grams !== null ? log.grams.toString() : '';
          this.kcalInput = log.kcalPer100g !== null ? log.kcalPer100g.toString() : '';
        }
        // 宏量与模式无关，两种都回填
        this.proteinInput = log.proteinG !== null ? String(log.proteinG) : '';
        this.carbsInput = log.carbsG !== null ? String(log.carbsG) : '';
        this.fatInput = log.fatG !== null ? String(log.fatG) : '';
      }
      this.ready = true;
    } catch (e) {
      this.ready = true;
    }
  }

  /**
   * 读取宏量输入。三项要么全空（不记录），要么全为 0-999 的整数。
   * 部分填写视为录入不完整，返回 null 交由调用方提示，避免写入半套数据。
   */
  private readMacros(): MacroInputResult {
    const texts: string[] = [this.proteinInput.trim(), this.carbsInput.trim(),
      this.fatInput.trim()];
    let filled = 0;
    for (let i = 0; i < texts.length; i++) {
      if (texts[i].length > 0) {
        filled++;
      }
    }
    if (filled === 0) {
      return new MacroInputResult(true, null, null, null, '');
    }
    if (filled < 3) {
      return new MacroInputResult(false, null, null, null,
        '请把蛋白质、碳水、脂肪三项都填上，或三项都留空');
    }
    const vals: number[] = [];
    for (let i = 0; i < 3; i++) {
      const v = parseFloat(texts[i]);
      if (isNaN(v) || !Number.isInteger(v) || v < 0 || v > 999) {
        return new MacroInputResult(false, null, null, null,
          '宏量需为 0-999 的整数（克）');
      }
      vals.push(v);
    }
    return new MacroInputResult(true, vals[0], vals[1], vals[2], '');
  }

  /** 宏量按 Atwater 回算的热量，用于与总热量做一致性提示 */
  private macroPreviewKcal(): number | null {
    const m = this.readMacros();
    if (!m.ok || m.proteinG === null) {
      return null;
    }
    return Math.round(
      (m.proteinG as number) * 4 + (m.carbsG as number) * 4 + (m.fatG as number) * 9);
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
    try {
      if (this.useAiForm()) {
        // AI 整份估算模式
        const kcal = Number(this.totalKcalInput);
        if (this.totalKcalInput.trim().length === 0 || !isFinite(kcal) ||
          !Number.isInteger(kcal) || kcal < 1 || kcal > 10000) {
          this.getUIContext().getPromptAction().showToast({ message: '整份热量需为 1-10000 的整数' });
          return;
        }
        const macros = this.readMacros();
        if (!macros.ok) {
          this.getUIContext().getPromptAction().showToast({ message: macros.message });
          return;
        }
        const input = new FoodLogInput(this.date, this.name.trim(), this.mealType,
          null, null, kcal, 1, this.aiConfidence, this.aiNotes.length > 0 ? this.aiNotes : null,
          macros.proteinG, macros.carbsG, macros.fatG,
          this.stickerPath.length > 0 ? this.stickerPath : null);
        if (this.recordId > 0) {
          await FoodRepository.update(this.recordId, input);
        } else {
          await FoodRepository.insert(input);
        }
      } else {
        // 手动称重模式
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
        const macros = this.readMacros();
        if (!macros.ok) {
          this.getUIContext().getPromptAction().showToast({ message: macros.message });
          return;
        }
        const input = new FoodLogInput(this.date, this.name.trim(), this.mealType,
          weightP.value, kcalP.value, calories, 0, null, null,
          macros.proteinG, macros.carbsG, macros.fatG,
          this.stickerPath.length > 0 ? this.stickerPath : null);
        if (this.mode === 'edit' && this.recordId > 0) {
          await FoodRepository.update(this.recordId, input);
        } else {
          await FoodRepository.insert(input);
        }
      }
      this.bumpRefresh();
      AppDialogService.toast('已保存');
      // AI 模式保存后需要同时关闭 AI 识别页
      if (this.isAiMode()) {
        this.navStack.pop();
      }
      this.navStack.pop();
    } catch (e) {
      AppDialogService.toast('保存失败，请重试');
    }
  }

  private confirmDelete(): void {
    AppDialogService.confirm('删除记录', '确定删除这条饮食记录吗？', '删除', () => {
      this.doDelete();
    });
  }

  private async doDelete(): Promise<void> {
    try {
      await FoodRepository.delete(this.recordId);
      this.bumpRefresh();
      AppDialogService.toast('已删除');
      this.navStack.pop();
    } catch (e) {
      AppDialogService.toast('删除失败，请重试');
    }
  }

  @Builder
  MealTypeChips() {
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

  /**
   * 三大宏量录入表单（克）。
   *
   * 两种录入模式**共用**这一个表单：
   * 手动称重和 AI 整份估算都有蛋白/碳水/脂肪三个数，
   * AI 模式还常常已经给好了估算值让用户核对。
   * 原来它只出现在手动分支里，AI 模式的用户根本看不到、改不了。
   */
  @Builder
  MacroForm() {
    Column({ space: space.xs }) {
      Text('三大宏量（克，可留空）')
        .fontSize(fontSize.secondary)
        .fontColor(color.textSecondary)
        .width('100%')

      Row({ space: space.xxs }) {
        TextInput({ text: this.proteinInput, placeholder: '蛋白' })
          .type(InputType.Number)
          .height(layout.inputHeight)
          .fontSize(fontSize.body)
          .backgroundColor(color.surfaceMuted)
          .borderRadius(radius.medium)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.proteinInput = v;
          })

        TextInput({ text: this.carbsInput, placeholder: '碳水' })
          .type(InputType.Number)
          .height(layout.inputHeight)
          .fontSize(fontSize.body)
          .backgroundColor(color.surfaceMuted)
          .borderRadius(radius.medium)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.carbsInput = v;
          })

        TextInput({ text: this.fatInput, placeholder: '脂肪' })
          .type(InputType.Number)
          .height(layout.inputHeight)
          .fontSize(fontSize.body)
          .backgroundColor(color.surfaceMuted)
          .borderRadius(radius.medium)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.fatInput = v;
          })
      }
      .width('100%')

      if (this.macroPreviewKcal() !== null) {
        Text(`按蛋白4/碳水4/脂肪9 回算 ≈ ${this.macroPreviewKcal()} kcal`)
          .fontSize(fontSize.caption)
          .fontColor(color.textHint)
          .width('100%')
      } else {
        Text('三项都填才会记录宏量，留空则不参与每日汇总')
          .fontSize(fontSize.caption)
          .fontColor(color.textHint)
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(layout.cardPadding)
    .backgroundColor(color.surfaceMuted)
    .borderRadius(radius.card)
    .width('100%')
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
              this.MealTypeChips()
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            if (this.useAiForm()) {
              // AI 整份热量
              Column({ space: space.xs }) {
                Row({ space: space.sm }) {
                  Text('AI 估算')
                    .fontSize(fontSize.caption)
                    .fontColor(color.primary)
                    .backgroundColor(color.primaryLight)
                    .borderRadius(radius.pill)
                    .padding({ left: space.sm, right: space.sm, top: 4, bottom: 4 })
                  Text('可直接修改为你确认的热量')
                    .fontSize(fontSize.caption)
                    .fontColor(color.textHint)
                }
                .width('100%')

                TextInput({ text: this.totalKcalInput, placeholder: '例如 620' })
                  .type(InputType.Number)
                  .height(layout.inputHeight)
                  .fontSize(fontSize.body)
                  .backgroundColor(color.primaryLight)
                  .borderRadius(radius.medium)
                  .onChange((value: string) => {
                    this.totalKcalInput = value;
                  })

                if (this.aiNotes.length > 0) {
                  Text(this.aiNotes)
                    .fontSize(fontSize.secondary)
                    .fontColor(color.textSecondary)
                }
                Text('AI 估算仅为参考，请核对后保存')
                  .fontSize(fontSize.caption)
                  .fontColor(color.textHint)
              }
              .alignItems(HorizontalAlign.Start)
              .padding(layout.cardPadding)
              .backgroundColor(color.primaryLight)
              .borderRadius(radius.card)
              .width('100%')
            } else {
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
            }

            /**
             * 宏量表单：**两种录入模式共用**。
             *
             * 原来它被写在手动录入分支里，于是 AI 模式（`useAiForm()` 为真）
             * 根本看不到这三个输入框 —— AI 已经估出了 38/72/19 g，
             * 用户却**没法核对、也没法改**
             * （2026-10-21 用户实测复现，交付说明 §19 F08）。
             */
            this.MacroForm()

            // 保存
            Button(this.mode === 'edit' ? '保存修改' : (this.useAiForm() ? '确认保存' : '保存记录'))
              .width('100%')
              .height(layout.buttonHeight)
              .fontSize(fontSize.body)
              .fontColor(color.onPrimary)
              .backgroundColor(this.isAiMode() ? color.primary : color.primary)
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
      .linearGradient(pageGradient())
    }
    .title(this.isAiMode() ? 'AI 估算结果' : (this.mode === 'edit' ? '编辑食物' : '新增食物'))
    .backgroundColor(color.bg)
    .linearGradient(pageGradient())
    .onReady((ctx: NavDestinationContext) => {
      const p = ctx.pathInfo.param as FoodEditParams | null | undefined;
      if (p !== null && p !== undefined) {
        this.applyParams(p);
      } else {
        this.ready = true;
      }
    })
  }
}