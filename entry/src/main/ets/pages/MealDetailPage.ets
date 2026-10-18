/**
 * 餐食详情页 —— 对应 NutriScan 的「餐食卡片 → 餐食详情」跳转。
 *
 * 原版这一跳带 Hero 共享元素过渡（列表图 → 详情大图）。
 * 本 SDK 的 NavDestination 没有自定义 transition（见 HomeTabs 注释同源结论），
 * 所以只保留导航本身，过渡用统一的 300ms easeOut。
 *
 * ⚠ 根节点必须是 NavDestination：
 *   实测把普通 Column 组件放在 navDestination 的 @Builder 分支里，
 *   目标页内容节点挂不上树 —— 路由推得进去、返回键也出现，但画面全白且无异常。
 *   FoodEditPage 能正常工作正是因为它本身就渲染 NavDestination。
 */

import { FoodRepository } from '../repositories/FoodRepository';
import { FoodLog } from '../models/FoodLog';
import { ProfileRepository } from '../repositories/ProfileRepository';
import { DailySummaryService } from '../services/DailySummaryService';
import { MacroTarget } from '../models/Calculation';
import {
  color, fontSize, space, radius, layout,
  glass, glassGradient, glassShadow, toneVeil, pageGradient, primaryButtonGradient, buttonGlow
} from '../common/DesignTokens';
import { anim } from '../common/Motion';
import { MEAL_LABELS } from '../common/Constants';
import { formatNumber } from '../common/DateUtils';

class MealDetailParams {
  date: string = '';
  mealType: number = 0;

  constructor(date: string, mealType: number) {
    this.date = date;
    this.mealType = mealType;
  }
}

@Component
export struct MealDetailPage {
  @Consume('navStack') navStack: NavPathStack;
  @State private date: string = '';
  @State private mealType: number = 0;
  @State private items: FoodLog[] = [];
  @State private macroTarget: MacroTarget | null = null;
  /** 全天热量预算，用于算这一餐占比。MacroTarget 里只有克数，热量目标在 settings 里 */
  @State private budgetKcal: number = 1800;
  @State private ready: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    try {
      this.items = await FoodRepository.getByDate(this.date);
    } catch (e) {
      this.items = [];
    }
    try {
      this.macroTarget = await ProfileRepository.getMacroTarget();
    } catch (e) {
      this.macroTarget = null;
    }
    try {
      const s = await DailySummaryService.getSummary(this.date);
      this.budgetKcal = s !== null ? s.dailyCalorieBudget : 1800;
    } catch (e) {
      this.budgetKcal = 1800;
    }
    this.ready = true;
  }

  private mealItems(): FoodLog[] {
    const out: FoodLog[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].mealType === this.mealType) {
        out.push(this.items[i]);
      }
    }
    return out;
  }

  private totalKcal(): number {
    let sum = 0;
    const list = this.mealItems();
    for (let i = 0; i < list.length; i++) {
      sum += list[i].calories;
    }
    return sum;
  }

  private macroSum(field: string): number {
    let sum = 0;
    const list = this.mealItems();
    for (let i = 0; i < list.length; i++) {
      const v = field === 'protein' ? list[i].proteinG
        : (field === 'carbs' ? list[i].carbsG : list[i].fatG);
      sum += (v !== null ? (v as number) : 0);
    }
    return Math.round(sum);
  }

  /** 该餐占全天目标的比例，用于进度条 */
  private shareOf(target: number): number {
    if (!(target > 0)) {
      return 0;
    }
    return Math.max(0, Math.min(1, this.totalKcal() / target));
  }

  private goEdit(log: FoodLog): void {
    this.navStack.pushPathByName('FoodEdit',
      new FoodEditParams('edit', this.date, log.id));
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: space.md }) {
          if (this.ready && this.mealItems().length === 0) {
            Text('这一餐还没有记录')
              .fontSize(fontSize.body)
              .fontColor(color.textHint)
          } else {
            // 餐食卡头：大数字 + 该餐占全天目标的比例
            Column({ space: space.sm }) {
              Text(`${formatNumber(this.totalKcal())}`)
                .fontSize(fontSize.hero)
                .fontWeight(FontWeight.Bold)
                .fontColor(color.text)
              Text('kcal · ' + MEAL_LABELS[this.mealType])
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
                .width('100%')

              if (this.macroTarget !== null) {
                Row() {
                  Row()
                    .width('100%')
                    .height(8)
                    .borderRadius(4)
                    .backgroundColor(color.ringTrack)
                  Row()
                    .width(`${Math.round(this.shareOf(this.budgetKcal) * 100)}%`)
                    .height(8)
                    .borderRadius(4)
                    .backgroundColor(color.primary)
                    .animation({ duration: anim.dataMs, curve: anim.easeData })
                }
                .width('100%')
              }
            }
            .width('100%')
            .padding(layout.cardPadding)
            .linearGradient(glassGradient(toneVeil(`meal-${this.mealType}`)))
            .borderRadius(glass.cardRadius)
            .border({ width: glass.borderWidth, color: color.glassBorder })
            .backdropBlur(glass.blurRadius)
            .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
            .alignItems(HorizontalAlign.Start)

            // 本餐宏量合计
            Row({ space: space.sm }) {
              this.MacroChip('蛋白', this.macroSum('protein'), color.macroProtein)
              this.MacroChip('碳水', this.macroSum('carbs'), color.macroCarbs)
              this.MacroChip('脂肪', this.macroSum('fat'), color.macroFat)
            }
            .width('100%')

            // 明细列表
            Column({ space: space.sm }) {
              ForEach(this.mealItems(), (log: FoodLog) => {
                Row({ space: space.sm }) {
                  Column({ space: 2 }) {
                    Text(log.name)
                      .fontSize(fontSize.body)
                      .fontColor(color.text)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${log.grams}g × ${log.kcalPer100g}kcal/100g`)
                      .fontSize(fontSize.caption)
                      .fontColor(color.textHint)
                    if (log.hasMacros()) {
                      Text(`蛋白 ${Math.round(log.proteinG as number)}g · 碳水 ${
                        Math.round(log.carbsG as number)}g · 脂肪 ${Math.round(log.fatG as number)}g`)
                        .fontSize(fontSize.caption)
                        .fontColor(color.textSecondary)
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Text(`${formatNumber(log.calories)}`)
                    .fontSize(fontSize.body)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(color.text)
                }
                .width('100%')
                .padding(layout.cardPadding)
                .linearGradient(glassGradient(toneVeil(log.name)))
                .borderRadius(glass.cardRadius)
                .border({ width: glass.borderWidth, color: color.glassBorder })
                .onClick(() => {
                  this.goEdit(log);
                })
              }, (log: FoodLog) => log.id.toString())
            }
            .width('100%')

            Button('添加食物到这一餐')
              .width('100%')
              .height(layout.buttonHeight)
              .fontSize(fontSize.body)
              .fontColor(color.onPrimary)
              .linearGradient(primaryButtonGradient())
              .borderRadius(14)
              .shadow(buttonGlow())
              .onClick(() => {
                this.navStack.pushPathByName('FoodEdit',
                  new FoodEditParams('add', this.date, -1));
              })
          }
        }
        .width('100%')
        .padding(layout.pagePadding)
        .constraintSize({ minHeight: '100%' })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .backgroundColor(color.bg)
      .linearGradient(pageGradient())
    }
    .title('餐食详情')
    .backgroundColor(color.bg)
    .linearGradient(pageGradient())
    .onReady((ctx: NavDestinationContext) => {
      const p = ctx.pathInfo.param as MealDetailParams | null | undefined;
      if (p !== null && p !== undefined) {
        this.date = p.date;
        this.mealType = p.mealType;
      }
      this.load();
    })
  }

  @Builder
  MacroChip(label: string, value: number, chipColor: ResourceColor) {
    Column({ space: 2 }) {
      Text(`${value}`)
        .fontSize(fontSize.metric)
        .fontWeight(FontWeight.Bold)
        .fontColor(chipColor)
      Text(`${label} g`)
        .fontSize(fontSize.caption)
        .fontColor(color.textHint)
    }
    .layoutWeight(1)
    .padding(layout.cardPadding)
    .linearGradient(glassGradient(color.glassFill))
    .borderRadius(glass.cardRadius)
    .border({ width: glass.borderWidth, color: color.glassBorder })
    .backdropBlur(glass.blurRadius)
    .alignItems(HorizontalAlign.Start)
  }
}

/** 与 HomePage 导出的 FoodEditParams 结构一致 */
class FoodEditParams {
  mode: string = 'add';
  date: string = '';
  id: number = -1;

  constructor(mode: string, date: string, id: number) {
    this.mode = mode;
    this.date = date;
    this.id = id;
  }
}
