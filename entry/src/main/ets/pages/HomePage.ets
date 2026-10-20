/**
 * 今日页：热量半环 + 摄入/剩余/目标 + 宏量条、餐食卡与活动概览。
 * 剩余预算 = 饮食预算 − 已摄入；活动消耗不返还饮食预算。
 */

import { DailySummaryService } from '../services/DailySummaryService';
import { anim } from '../common/Motion';
import { DailySummary } from '../models/DailySummary';
import { AnimatedRing } from '../components/AnimatedRing';
import { AnimatedNumber } from '../components/AnimatedNumber';
import { MetricCard } from '../components/MetricCard';
import { WeekSparkline } from '../components/WeekSparkline';
import { MacroRepository, MacroDayTotal, DayPoint } from '../repositories/MacroRepository';
import { FoodRepository } from '../repositories/FoodRepository';
import { FoodLog } from '../models/FoodLog';
import { ProfileRepository } from '../repositories/ProfileRepository';
import { MacroTarget } from '../models/Calculation';
import { MEAL_LABELS } from '../common/Constants';
import {
  color, fontSize, space, radius, layout,
  glass, glassShadow, buttonGlow, pageGradient, primaryButtonGradient
} from '../common/DesignTokens';
import { toDateKey, parseDateKey, formatNumber } from '../common/DateUtils';
import { CalorieService } from '../services/CalorieService';
import { Provenance } from '../services/MockContent';
import { showComingSoon } from '../components/ComingSoonPage';

@Component
export struct HomePage {
  @Consume('navStack') navStack: NavPathStack;
  @StorageLink('refreshTick') @Watch('reload') refreshTick: number = 0;
  @StorageLink('selectedDate') @Watch('reload') selectedDate: string = '';
  /** 页面内容入场开关，见 build() 末尾的 opacity/translate */
  @State private entered: boolean = false;
  @State private hintIndex: number = 0;
  private hintSwiperController: SwiperController = new SwiperController();

  enterPage(): void {
    this.entered = true;
  }

  @State summary: DailySummary | null = null;
  /** 当日宏量实际摄入 + 是否真的录过宏量（区分"没吃"与"吃了没记"） */
  @State macroDay: MacroDayTotal | null = null;
  /** 宏量目标，来自体征自动推导或手动覆盖；null 表示尚未设置体征 */
  @State macroTarget: MacroTarget | null = null;
  /** 近 7 日趋势 */
  @State trend: DayPoint[] = [];
  /** 当日餐食记录，供餐食卡片流使用 */
  @State foods: FoodLog[] = [];

  aboutToAppear(): void {
    this.reload();
  }

  reload(): void {
    this.loadData();
  }

  private async loadData(): Promise<void> {
    try {
      const s = await DailySummaryService.getSummary(this.selectedDate);
      this.summary = s;
    } catch (e) {
      // 数据库错误时保留旧数据
    }
    this.loadMacro();
  }

  private async loadMacro(): Promise<void> {
    // ArkTS 禁止 Promise.all 的解构声明（arkts-no-destruct-decls），
    // 这里顺序 await。三次都是本地 SQLite 查询，代价可忽略。
    try {
      this.macroDay = await MacroRepository.getDayTotal(this.selectedDate);
    } catch (e) {
      this.macroDay = null;
    }
    try {
      this.macroTarget = await ProfileRepository.getMacroTarget();
    } catch (e) {
      this.macroTarget = null;
    }
    try {
      this.trend = await MacroRepository.getTrend(this.weekStart(), this.selectedDate);
    } catch (e) {
      this.trend = [];
    }
    try {
      this.foods = await FoodRepository.getByDate(this.selectedDate);
    } catch (e) {
      this.foods = [];
    }
  }

  /* ---------------- 餐食卡片流（对应原版「餐食卡片 → 餐食详情」） ---------------- */

  private mealItems(mealType: number): FoodLog[] {
    const out: FoodLog[] = [];
    for (let i = 0; i < this.foods.length; i++) {
      if (this.foods[i].mealType === mealType) {
        out.push(this.foods[i]);
      }
    }
    return out;
  }

  private mealKcal(mealType: number): number {
    const list = this.mealItems(mealType);
    let sum = 0;
    for (let i = 0; i < list.length; i++) {
      sum += list[i].calories;
    }
    return sum;
  }

  private goMealDetail(mealType: number): void {
    this.navStack.pushPathByName('MealDetail',
      new MealDetailParams(this.selectedDate, mealType));
  }

  /** 只描述本地已支持的能力；本项目完全免费，不做任何试用或升级承诺。 */
  private tips(): string[] {
    return [
      '拍照识别后可核对食物与营养估算',
      '完善体征档案后计算每日营养目标',
      '饮水与断食记录保存在本机'
    ];
  }

  /** 本周一（周一为一周之首，与 WeekSparkline 的槽位对齐） */
  private weekStart(): string {
    const sel = parseDateKey(this.selectedDate);
    const dow = (sel.getDay() + 6) % 7;
    const monday = new Date(sel);
    monday.setDate(sel.getDate() - dow);
    return toDateKey(monday);
  }

  private goFoodEdit(): void {
    this.navStack.pushPathByName('FoodEdit', new FoodEditParams('add', this.selectedDate, -1));
  }

  private goActivityEdit(): void {
    this.navStack.pushPathByName('ActivityEdit', new ActivityEditParams('add', this.selectedDate, -1));
  }

  private consumedKcal(): number {
    return this.summary !== null ? this.summary.consumedKcal : 0;
  }

  private budgetKcal(): number {
    return this.summary !== null ? this.summary.dailyCalorieBudget : 1800;
  }

  private remainingOrOverKcal(): number {
    return Math.abs(this.budgetKcal() - this.consumedKcal());
  }

  private calorieRatio(): number {
    return Math.max(0, Math.min(1, this.consumedKcal() / Math.max(1, this.budgetKcal())));
  }

  private macroRatio(actual: number, target: number): string {
    if (target <= 0) {
      return '0%';
    }
    return `${Math.max(0, Math.min(100, Math.round(actual / target * 100)))}%`;
  }

  private macroFillColor(actual: number, target: number, tint: ResourceColor): ResourceColor {
    return target > 0 && actual > target ? color.danger : tint;
  }

  private mealEmoji(mealType: number): string {
    if (mealType === 0) {
      return '🍳';
    }
    if (mealType === 1) {
      return '🥗';
    }
    if (mealType === 2) {
      return '🍲';
    }
    return '🍎';
  }

  private mealPreviewName(mealType: number): string {
    const list = this.mealItems(mealType);
    return list.length > 0 ? list[0].name : '还没记录';
  }

  @Builder
  MacroMini(label: string, actual: number, target: number, tint: ResourceColor, available: boolean) {
    Column({ space: space.xs }) {
      Text(label)
        .fontSize(fontSize.caption)
        .fontColor(color.textSecondary)
        .maxLines(1)

      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(4)
          .borderRadius(2)
          .backgroundColor(color.ringTrack)

        Row()
          .width(available ? this.macroRatio(actual, target) : '0%')
          .height(4)
          .borderRadius(2)
          .backgroundColor(this.macroFillColor(actual, target, tint))
      }
      .width('100%')
      .height(4)

      Text(available ? `${Math.round(actual)}g / ${Math.round(target)}g` : '— / —')
        .fontSize(fontSize.caption)
        .fontColor(color.text)
        .maxLines(1)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  HintGlyph(index: number) {
    Stack({ alignContent: Alignment.Center }) {
      Row()
        .width(28)
        .height(28)
        .backgroundColor(color.surfaceMuted)
        .borderRadius(9)

      if (index === 0) {
        SymbolGlyph($r('sys.symbol.camera'))
          .fontSize(18)
          .fontColor([color.primary])
      } else if (index === 1) {
        SymbolGlyph($r('sys.symbol.person'))
          .fontSize(18)
          .fontColor([color.primary])
      } else {
        SymbolGlyph($r('sys.symbol.drop'))
          .fontSize(18)
          .fontColor([color.primary])
      }
    }
    .width(28)
    .height(28)
  }

  @Builder
  HintSlide(tip: string, index: number) {
    Row({ space: space.sm }) {
      this.HintGlyph(index)

      Text(tip)
        .fontSize(fontSize.secondary)
        .fontColor(color.text)
        .maxLines(2)
        .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([color.textHint])
    }
    .width('100%')
    .height(52)
    .padding({ left: 14, right: 14 })
    .backgroundColor(color.surface)
    .border({ width: 1, color: color.border })
    .borderRadius(16)
  }

  build() {
    Scroll() {
      Column({ space: space.md }) {
        // 对齐 NutriScan 的 Today's Count：薄荷色半环、三项热量和同卡宏量进度。
        Column({ space: space.sm }) {
          Row() {
            Text('今日热量')
              .fontSize(fontSize.sectionTitle)
              .fontWeight(FontWeight.Bold)
              .fontColor(color.text)
              .layoutWeight(1)

            Row({ space: 6 }) {
              Text('⚙︎')
                .fontSize(fontSize.secondary)
                .fontColor(color.textHint)
              Text('自定义')
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
            }
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(radius.pill)
            .onClick(() => {
              showComingSoon(
                '自定义首页',
                '选择综合页摘要卡片的显示内容与顺序',
                '当前版本还没有首页布局配置与本地保存能力。',
                '可调整卡片的布局模型、持久化设置、恢复默认操作和设置回归',
                Provenance.MOCK
              );
            })
          }
          .width('100%')

          Stack({ alignContent: Alignment.Top }) {
            AnimatedRing({
              // ProgressRing draws 0..360°; half the ratio fills a 180° gauge.
              ratio: this.calorieRatio() * 0.5,
              diameter: 128,
              stroke: 8,
              valueColor: this.consumedKcal() > this.budgetKcal() ? color.danger : color.calorieMint,
              trackColor: color.heroRingTrack
            })
              .width(128)
              .height(128)
              .rotate({ angle: 270 })
              .align(Alignment.Top)

            Row()
              .width('100%')
              .height(54)
              .backgroundColor(color.surface)
              // The UI tree placed this child at the Stack top despite .align(Bottom).
              // Offset it to the lower edge to reveal the reference's upper arc.
              .offset({ x: 0, y: 64 })

          Row() {
            Column({ space: 4 }) {
              AnimatedNumber({
                target: this.remainingOrOverKcal(),
                textSize: fontSize.metric,
                textColor: this.consumedKcal() > this.budgetKcal() ? color.danger : color.text
              })
              Text(this.consumedKcal() > this.budgetKcal() ? '超出 kcal' : '剩余 kcal')
                .fontSize(fontSize.caption)
                .fontColor(color.textSecondary)
            }
            .alignItems(HorizontalAlign.Center)
            .layoutWeight(1)

            Column({ space: 4 }) {
              AnimatedNumber({
                target: this.consumedKcal(),
                textSize: fontSize.metric,
                textColor: color.text
              })
              Text('已摄入 kcal')
                .fontSize(fontSize.caption)
                .fontColor(color.textSecondary)
            }
            .alignItems(HorizontalAlign.Center)
            .layoutWeight(1)

            Column({ space: 4 }) {
              AnimatedNumber({
                target: this.budgetKcal(),
                textSize: fontSize.metric,
                textColor: color.text
              })
              Text('目标 kcal')
                .fontSize(fontSize.caption)
                .fontColor(color.textSecondary)
            }
            .alignItems(HorizontalAlign.Center)
            .layoutWeight(1)
          }
          .width('100%')
          .height(54)
          // Center the calorie labels inside the half-ring instead of above it.
          .offset({ x: 0, y: 28 })
        }
        .width('100%')
        .height(96)
        .clip(true)

        Row({ space: space.md }) {
          this.MacroMini('蛋白质', this.macroDay !== null ? this.macroDay.actual.proteinG : 0,
            this.macroTarget !== null ? this.macroTarget.proteinG : 0, color.macroProtein,
            this.macroDay !== null && this.macroTarget !== null)
          this.MacroMini('碳水', this.macroDay !== null ? this.macroDay.actual.carbsG : 0,
            this.macroTarget !== null ? this.macroTarget.carbsG : 0, color.macroCarbs,
            this.macroDay !== null && this.macroTarget !== null)
          this.MacroMini('脂肪', this.macroDay !== null ? this.macroDay.actual.fatG : 0,
            this.macroTarget !== null ? this.macroTarget.fatG : 0, color.macroFat,
            this.macroDay !== null && this.macroTarget !== null)
        }
        .width('100%')

        if (this.macroTarget === null) {
          Text('完善体征资料后显示宏量目标')
            .fontSize(fontSize.caption)
            .fontColor(color.textHint)
            .width('100%')
        } else if (this.macroDay !== null && !this.macroDay.hasMacroData) {
          Text('今天的餐食尚无宏量记录')
            .fontSize(fontSize.caption)
            .fontColor(color.textHint)
            .width('100%')
        }
        }
        .padding(layout.cardPadding)
        .backgroundColor(color.surface)
        .borderRadius(glass.cardRadius)
        .border({ width: glass.borderWidth, color: color.glassBorder })
        .alignItems(HorizontalAlign.Center)
        .width('100%')

        // 单卡横向翻页 + 页点，对齐 NutriScan 首页提示卡结构。
        Swiper(this.hintSwiperController) {
          ForEach(this.tips(), (tip: string, index: number) => {
            this.HintSlide(tip, index)
          }, (tip: string, index: number) => `${index}-${tip}`)
        }
        .width('100%')
        .height(52)
        .indicator(false)
        .autoPlay(false)
        .loop(false)
        .onChange((index: number) => {
          this.hintIndex = index;
        })

        Row({ space: 8 }) {
          ForEach(this.tips(), (_tip: string, index: number) => {
            Circle()
              .width(this.hintIndex === index ? 8 : 6)
              .height(this.hintIndex === index ? 8 : 6)
              .fill(this.hintIndex === index ? color.textSecondary : color.glassBorder)
              .onClick(() => {
                this.hintSwiperController.changeIndex(index, true);
              })
          }, (_tip: string, index: number) => index.toString())
        }
        .width('100%')
        .height(12)
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: space.xs })

        // 横向餐食卡：只展示真实录入的名称与热量，不伪造原版截图中的食物照片。
        Column({ space: space.sm }) {
          Row() {
            Text('今日餐食')
              .fontSize(fontSize.sectionTitle)
              .fontWeight(FontWeight.Bold)
              .fontColor(color.text)
              .layoutWeight(1)

            Text('拍照识别食物  ›')
              .fontSize(fontSize.caption)
              .fontColor(color.primary)
              .onClick(() => {
                this.navStack.pushPathByName('AiRecognition',
                  new AiRecognitionNavParams(this.selectedDate));
              })
          }
          .width('100%')

          Scroll() {
            Row({ space: space.md }) {
              ForEach(MEAL_LABELS, (label: string, index: number) => {
                Column({ space: space.xs }) {
                  Column({ space: space.sm }) {
                    Text(this.mealEmoji(index))
                      .fontSize(34)
                    Text(this.mealItems(index).length === 0
                      ? '还没记录'
                      : this.mealPreviewName(index))
                      .fontSize(fontSize.body)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(color.text)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .width(140)
                  .height(140)
                  .padding(layout.cardPadding)
                  .backgroundColor(color.surfaceMuted)
                  .borderRadius(glass.cardRadius)
                  .alignItems(HorizontalAlign.Start)
                  .justifyContent(FlexAlign.Center)

                  Text(`${label} · ${this.mealItems(index).length === 0
                    ? '点击添加'
                    : `${this.mealItems(index).length} 项 · ${formatNumber(this.mealKcal(index))} kcal`}`)
                    .fontSize(fontSize.caption)
                    .fontColor(color.textSecondary)
                    .maxLines(1)
                }
                .width(140)
                .onClick(() => {
                  this.goMealDetail(index);
                })
              }, (label: string, index: number) => label + index)
            }
          }
          .width('100%')
          .height(150)
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
        }
        .width('100%')

        // 步数与运动时长
        Row({ space: space.md }) {
          Column() {
            MetricCard({
              title: '步数',
              valueText: formatNumber(this.summary !== null ? this.summary.steps : 0),
              unit: '步',
              progress: CalorieService.progress(
                this.summary !== null ? this.summary.steps : 0,
                this.summary !== null ? this.summary.stepsGoal : 8000),
              barColor: color.activity,
              sourceLabel: '手动模拟',
              goalText: `目标 ${formatNumber(this.summary !== null ? this.summary.stepsGoal : 8000)} 步`
            })
          }
          .layoutWeight(1)

          Column() {
            MetricCard({
              title: '运动时长',
              valueText: formatNumber(this.summary !== null ? this.summary.exerciseMinutes : 0),
              unit: '分钟',
              progress: CalorieService.progress(
                this.summary !== null ? this.summary.exerciseMinutes : 0,
                this.summary !== null ? this.summary.exerciseMinutesGoal : 30),
              barColor: color.activity,
              goalText: `目标 ${formatNumber(this.summary !== null ? this.summary.exerciseMinutesGoal : 30)} 分钟`
            })
          }
          .layoutWeight(1)
        }
        .alignItems(VerticalAlign.Top)
        .width('100%')

        // 快捷操作：一主一次。主按钮用渐变面 + 辉光投影做立体感，
        // 次按钮保持实色 —— 原型里只有 “Buy Now” 有阴影，正是这个意思。
        Row({ space: space.md }) {
          Button('记录饮食')
            .layoutWeight(1)
            .height(layout.buttonHeight)
            .fontSize(fontSize.body)
            .fontColor(color.onPrimary)
            .linearGradient(primaryButtonGradient())
            .borderRadius(14)
            .shadow(buttonGlow())
            .onClick(() => {
              this.goFoodEdit();
            })

          Button('记录运动')
            .layoutWeight(1)
            .height(layout.buttonHeight)
            .fontSize(fontSize.body)
            .fontColor('#FFFFFF')
            .backgroundColor(color.activity)
            .borderRadius(14)
            .shadow(glassShadow(12, 6))
            .onClick(() => {
              this.goActivityEdit();
            })
        }
        .width('100%')

        // 近 7 日趋势
        WeekSparkline({
          points: this.trend,
          targetKcal: this.summary !== null ? this.summary.dailyCalorieBudget : 1800,
          selectedDate: this.selectedDate
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

// 编辑页参数（在此定义，供编辑页 import，保证类型一致）
export class FoodEditParams {
  mode: string;
  date: string;
  id: number;

  constructor(mode: string, date: string, id: number) {
    this.mode = mode;
    this.date = date;
    this.id = id;
  }
}

/** AI 识别页路由参数，与 AiRecognitionPage 内部同名类结构一致 */
export class AiRecognitionNavParams {
  date: string = '';

  constructor(date: string) {
    this.date = date;
  }
}

/** 餐食详情路由参数，与 MealDetailPage 内部同名类结构一致 */
export class MealDetailParams {
  date: string = '';
  mealType: number = 0;

  constructor(date: string, mealType: number) {
    this.date = date;
    this.mealType = mealType;
  }
}

export class ActivityEditParams {
  mode: string;
  date: string;
  id: number;

  constructor(mode: string, date: string, id: number) {
    this.mode = mode;
    this.date = date;
    this.id = id;
  }
}
