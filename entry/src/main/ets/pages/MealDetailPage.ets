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
  /**
   * 记录更新广播。
   *
   * 这一页是**从编辑页返回**的：编辑页保存后广播 `refreshTick`，
   * 本页收到后必须重新读库 —— 否则小计、明细、营养汇总全是旧值
   * （2026-10-21 用户实测复现，交付说明 §19 F03）。
   */
  @StorageLink('refreshTick') @Watch('reload') refreshTick: number = 0;

  aboutToAppear(): void {
    this.load();
  }

  /** 重新读库 */
  private reload(): void {
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

  /**
   * 明细行里的份量描述。
   *
   * AI 整份估算的记录**没有重量和每 100g 热量**（那是手动称重模式才有的），
   * 直接拼出来就是「nullg × nullkcal/100g」
   * （2026-10-21 用户实测复现，交付说明 §19 F07）。
   * 按录入模式显示：AI 模式说「AI 整份估算」。
   */
  private portionText(log: FoodLog): string {
    if (log.entryMode === 1) {
      return 'AI 整份估算';
    }
    if (log.grams === null || log.kcalPer100g === null) {
      return '未记录份量';
    }
    return `${log.grams}g × ${log.kcalPer100g}kcal/100g`;
  }

  private goEdit(log: FoodLog): void {
    this.navStack.pushPathByName('FoodEdit',
      new FoodEditParams('edit', this.date, log.id));
  }

  /**
   * 新增一条到**当前这一餐**。
   *
   * 必须把餐次一起传过去 —— 新增表单默认是早餐，
   * 从午餐进去新增，结果会记到早餐去
   * （2026-10-21 用户实测复现，交付说明 §19 F02）。
   */
  private addToThisMeal(): void {
    this.navStack.pushPathByName('FoodEdit',
      new FoodEditParams('add', this.date, -1, this.mealType));
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: space.md }) {
          if (this.ready && this.mealItems().length === 0) {
            /**
             * 空态也要给**添加入口**。
             * 原来这里只有一行字，用户从「午餐 · 点击添加」进来发现没按钮，
             * 只能退回另找录入入口 —— 一条死路
             * （2026-10-21 用户实测复现，交付说明 §19 F01）。
             */
            Column({ space: space.md }) {
              Text('这一餐还没有记录')
                .fontSize(fontSize.body)
                .fontColor(color.textHint)
              Button(`添加食物到${MEAL_LABELS[this.mealType]}`)
                .width('100%')
                .height(layout.buttonHeight)
                .fontSize(fontSize.body)
                .fontColor(color.onPrimary)
                .linearGradient(primaryButtonGradient())
                .borderRadius(14)
                .shadow(buttonGlow())
                .onClick(() => {
                  this.addToThisMeal();
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
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
            .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
            .alignItems(HorizontalAlign.Start)

            // 本餐宏量合计
            Row({ space: space.sm }) {
              this.MacroChip('protein', '蛋白', color.macroProtein)
              this.MacroChip('carbs', '碳水', color.macroCarbs)
              this.MacroChip('fat', '脂肪', color.macroFat)
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
                    Text(this.portionText(log))
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
              }, (log: FoodLog) => log.renderKey())
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
                this.addToThisMeal();
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
    /**
     * 从编辑页返回时重新读库。
     *
     * `onWillAppear` 在目标页重新出现前触发（推入编辑页再 pop 回来就会走一次），
     * 配合 `refreshTick` 订阅，两条路都保证详情页显示的是最新数据。
     */
    .onWillAppear(() => {
      this.load();
    })
    .onReady((ctx: NavDestinationContext) => {
      const p = ctx.pathInfo.param as MealDetailParams | null | undefined;
      if (p !== null && p !== undefined) {
        this.date = p.date;
        this.mealType = p.mealType;
      }
      this.load();
    })
  }

  /**
   * 本餐的宏量合计卡片。
   *
   * ## 为什么**不能**把算好的数值当参数传进来
   * 原来写成 `this.MacroChip('蛋白', this.macroSum('protein'), 色)`。
   * `@Builder` 的值参数是**调用时按值捕获**的，而 ArkUI 的状态驱动更新
   * 只会重画「自己依赖到那个状态」的节点 ——
   * `this.items` 变了以后，明细列表（直接读 `log`）更新了，
   * 可这个 Builder 的参数还是第一次渲染时算出来的 0，
   * 于是出现「下面写着蛋白 10 g、上面汇总却是 0」的矛盾
   * （2026-10-21 用户实测复现，交付说明 §19 F04）。
   *
   * 改成只传「字段名」，**在 Builder 内部现算** ——
   * 这样 Builder 自己的子树就依赖了 `this.items`，
   * 状态一变它跟着重画。
   */
  @Builder
  MacroChip(field: string, label: string, chipColor: ResourceColor) {
    Column({ space: 2 }) {
      Text(`${this.macroSum(field)}`)
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
    .alignItems(HorizontalAlign.Start)
  }
}

/** 与 HomePage 导出的 FoodEditParams 结构一致（多一个 mealType） */
class FoodEditParams {
  mode: string = 'add';
  date: string = '';
  id: number = -1;
  /** 新增时要预置的餐次。-1 = 不指定（用表单默认值） */
  mealType: number = -1;

  constructor(mode: string, date: string, id: number, mealType: number = -1) {
    this.mode = mode;
    this.date = date;
    this.id = id;
    this.mealType = mealType;
  }
}
