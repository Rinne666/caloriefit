/**
 * 饮食页：按早餐/午餐/晚餐/加餐分组展示，支持新增、编辑、删除。
 */

import { FoodRepository } from '../repositories/FoodRepository';
import { anim } from '../common/Motion';
import { SettingsRepository } from '../repositories/SettingsRepository';
import { FoodLog } from '../models/FoodLog';
import { AppSettings } from '../models/AppSettings';
import { EmptyState } from '../components/EmptyState';
import {
  color, fontSize, space, radius, layout, pageGradient,
  toneVeil, glass, glassGradient, glassShadow, primaryButtonGradient, buttonGlow
} from '../common/DesignTokens';
import { displayDate, toDateKey, parseDateKey, isFutureDate, formatNumber } from '../common/DateUtils';
import { MEAL_LABELS } from '../common/Constants';

@Component
export struct FoodPage {
  @Consume('navStack') navStack: NavPathStack;
  @StorageLink('refreshTick') @Watch('reload') refreshTick: number = 0;
  @StorageLink('selectedDate') @Watch('reload') selectedDate: string = '';
  /** 页面内容入场开关，见 build() 末尾的 opacity/translate */
  @State private entered: boolean = false;

  /**
   * 当前被按住的记录 id，-1 表示没按。
   *
   * 为什么用 id 而不是布尔量：FoodRow 是本组件内的 @Builder，
   * 所有行共用同一个 this，一个布尔量会让「按一行、所有行一起缩」。
   * 同组件内的 @Builder 用 this 是安全的 —— 出问题的是跨组件的
   * @BuilderParam 插槽（实测会把 this 绑到宿主组件上）。
   */
  @State private pressedFoodId: number = -1;

  enterPage(): void {
    this.entered = true;
  }

  private touchFood(id: number, e: TouchEvent): void {
    if (e.type === TouchType.Down) {
      this.pressedFoodId = id;
    } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
      this.pressedFoodId = -1;
    }
  }

  @State foods: FoodLog[] = [];
  @State budget: number = 1800;

  aboutToAppear(): void {
    this.reload();
  }

  reload(): void {
    this.loadData();
  }

  private async loadData(): Promise<void> {
    try {
      this.foods = await FoodRepository.getByDate(this.selectedDate);
      const settings: AppSettings = await SettingsRepository.getSettings();
      this.budget = settings.dailyCalorieBudget;
    } catch (e) {
      // 保留旧数据
    }
  }

  private totalCalories(): number {
    let sum = 0;
    for (let i = 0; i < this.foods.length; i++) {
      sum += this.foods[i].calories;
    }
    return sum;
  }

  private mealFoods(mealType: number): FoodLog[] {
    const result: FoodLog[] = [];
    for (let i = 0; i < this.foods.length; i++) {
      if (this.foods[i].mealType === mealType) {
        result.push(this.foods[i]);
      }
    }
    return result;
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

  private confirmDelete(log: FoodLog): void {
    this.getUIContext().showAlertDialog({
      title: '删除记录',
      message: `确定删除「${log.name}」吗？`,
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

  private async doDelete(log: FoodLog): Promise<void> {
    try {
      await FoodRepository.delete(log.id);
      this.bumpRefresh();
      this.getUIContext().getPromptAction().showToast({ message: '已删除' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '删除失败，请重试' });
    }
  }

  private goEdit(log: FoodLog): void {
    this.navStack.pushPathByName('FoodEdit', new FoodEditParams('edit', this.selectedDate, log.id));
  }

  private goAdd(): void {
    this.navStack.pushPathByName('FoodEdit', new FoodEditParams('add', this.selectedDate, -1));
  }

  @Builder
  FoodRow(log: FoodLog) {
    Row({ space: space.sm }) {
      Column({ space: 2 }) {
        Row({ space: space.xs }) {
          if (log.entryMode === 1) {
            Text('AI')
              .fontSize(fontSize.caption)
              .fontColor(color.primary)
              .backgroundColor(color.primaryLight)
              .borderRadius(radius.small)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          }
          Text(log.name)
            .fontSize(fontSize.body)
            .fontColor(color.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(VerticalAlign.Center)
        Text(log.entryMode === 1 ? 'AI 整份估算' :
          `${log.grams}g × ${log.kcalPer100g}kcal/100g`)
          .fontSize(fontSize.caption)
          .fontColor(color.textHint)

        // V3：宏量摘要。有完整宏量才显示，不以 0 冒充
        if (log.hasMacros()) {
          Row({ space: space.xxs }) {
            Text(`蛋白 ${Math.round(log.proteinG as number)}g`)
              .fontSize(fontSize.caption)
              .fontColor(color.macroProtein)
            Text(`碳水 ${Math.round(log.carbsG as number)}g`)
              .fontSize(fontSize.caption)
              .fontColor(color.macroCarbs)
            Text(`脂肪 ${Math.round(log.fatG as number)}g`)
              .fontSize(fontSize.caption)
              .fontColor(color.macroFat)
          }
          .alignItems(VerticalAlign.Center)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(`${formatNumber(log.calories)} kcal`)
        .fontSize(fontSize.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(color.food)

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
    // 每条记录按名称哈希拿自己的情绪色调 —— 同一条永远是同一个色，
    // 同一餐里不同的食物则大概率不同。色块统一，排版统一，只有色调在变。
    .linearGradient({ angle: 135, colors: [[toneVeil(log.name), 0], [color.glassFill, 1]] })
    .borderRadius(radius.medium)
    .border({ width: 1, color: color.glassBorder })
    // 按压反馈：轻微缩放。幅度刻意压到 0.965 ——
    // 再大就变成"卡片在躲"，再小又感觉不到被点到。
    .scale({
      x: this.pressedFoodId === log.id ? anim.pressScale : 1,
      y: this.pressedFoodId === log.id ? anim.pressScale : 1
    })
    .animation({ duration: anim.pressMs, curve: anim.ease })
    .onTouch((e: TouchEvent) => {
      this.touchFood(log.id, e);
    })
    .onClick(() => {
      this.goEdit(log);
    })
  }

  build() {
    Scroll() {
      Column({ space: space.md }) {
        // 日期栏
        Row() {
          Text('饮食记录')
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

        // 每日摄入汇总卡
        Column() {
          Row() {
            Column({ space: 4 }) {
              Text(`${formatNumber(this.totalCalories())} / ${formatNumber(this.budget)} kcal`)
                .fontSize(fontSize.metric)
                .fontWeight(FontWeight.Bold)
                .fontColor(color.text)
              Text('已摄入 / 每日饮食预算')
                .fontSize(fontSize.caption)
                .fontColor(color.textHint)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
        }
        .width('100%')
        .padding(layout.cardPadding)
        .linearGradient({
          angle: 160,
          colors: [[toneVeil('budget'), 0], [color.glassFillStrong, 1]]
        })
        .borderRadius(glass.cardRadius)
        .border({ width: glass.borderWidth, color: color.glassBorder })
        .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))

        // AI 拍照识别入口
        Column() {
          Row({ space: space.sm }) {
            Text('📷')
              .fontSize(22)
            Column({ space: 2 }) {
              Text('AI 拍照识别')
                .fontSize(fontSize.body)
                .fontWeight(FontWeight.Medium)
                .fontColor(color.text)
              Text('拍一张照片，AI 估算整份热量')
                .fontSize(fontSize.caption)
                .fontColor(color.textHint)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text('›')
              .fontSize(fontSize.sectionTitle)
              .fontColor(color.textHint)
          }
          .width('100%')
          .onClick(() => {
            this.navStack.pushPathByName('AiRecognition',
              new AiRecognitionNavParams(this.selectedDate));
          })
        }
        .width('100%')
        .padding(layout.cardPadding)
        .linearGradient(glassGradient(toneVeil('ai')))
        .borderRadius(glass.cardRadius)
        .border({ width: glass.borderWidth, color: color.glassBorder })
        .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))

        if (this.foods.length === 0) {
          EmptyState({
            message: '今天还没有饮食记录',
            buttonText: '新增食物',
            onAction: () => {
              this.goAdd();
            }
          })
        } else {
          ForEach(MEAL_LABELS, (label: string, index: number) => {
            // 卡片外壳写在这里而不是抽成卡片组件：
            // 卡片本身就在 ForEach 里，需要带参的 builder，
            // 而 @BuilderParam 不支持柯里化，套一层只会更绕。
            // 层次与其余卡片完全一致。
            Column({ space: space.xs }) {
              Row() {
                Text(label)
                  .fontSize(fontSize.sectionTitle)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(color.text)
                  .layoutWeight(1)
                Text(`小计 ${formatNumber(this.mealSubtotal(index))} kcal`)
                  .fontSize(fontSize.secondary)
                  .fontColor(color.textHint)
              }
              .width('100%')

              if (this.mealFoods(index).length === 0) {
                Text('暂无记录')
                  .fontSize(fontSize.caption)
                  .fontColor(color.textHint)
                  .padding({ top: space.xs, bottom: space.xs })
              } else {
                ForEach(this.mealFoods(index), (log: FoodLog) => {
                  this.FoodRow(log)
                }, (log: FoodLog) => log.renderKey())
              }
            }
            .width('100%')
            .padding(layout.cardPadding)
            .linearGradient(glassGradient(toneVeil(label)))
            .borderRadius(glass.cardRadius)
            .border({ width: glass.borderWidth, color: color.glassBorder })
            .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
            .alignItems(HorizontalAlign.Start)
          }, (label: string) => label)
        }

        // 新增按钮
        Button('+ 新增食物')
          .width('100%')
          .height(layout.buttonHeight)
          .fontSize(fontSize.body)
          .fontColor(color.onPrimary)
          .linearGradient(primaryButtonGradient())
          .borderRadius(14)
          .shadow(buttonGlow())
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

  private mealSubtotal(mealType: number): number {
    const list = this.mealFoods(mealType);
    let sum = 0;
    for (let i = 0; i < list.length; i++) {
      sum += list[i].calories;
    }
    return sum;
  }
}

// 与 HomePage.ets 中的定义保持一致（ArkUI 不支持跨文件类型重导出，重复定义但结构相同）
class FoodEditParams {
  mode: string;
  date: string;
  id: number;

  constructor(mode: string, date: string, id: number) {
    this.mode = mode;
    this.date = date;
    this.id = id;
  }
}

// AI 识别页导航参数
class AiRecognitionNavParams {
  date: string;

  constructor(date: string) {
    this.date = date;
  }
}
