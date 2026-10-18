/**
 * 今日页：热量进度环 + 摄入/消耗/预算数字 + 步数与运动时长卡片 + 快捷操作。
 * 剩余预算 = 饮食预算 − 已摄入；活动消耗单独显示，不返还饮食预算。
 */

import { DailySummaryService } from '../services/DailySummaryService';
import { anim } from '../common/Motion';
import { DailySummary } from '../models/DailySummary';
import { CalorieRing } from '../components/CalorieRing';
import { AnimatedNumber } from '../components/AnimatedNumber';
import { MetricCard } from '../components/MetricCard';
import { MacroPanel } from '../components/MacroBar';
import { WeekSparkline } from '../components/WeekSparkline';
import { MacroRepository, MacroDayTotal, DayPoint } from '../repositories/MacroRepository';
import { ProfileRepository } from '../repositories/ProfileRepository';
import { MacroTarget } from '../models/Calculation';
import {
  color, fontSize, space, radius, layout,
  glass, glassGradient, glassShadow, buttonGlow, toneVeil,
  pageGradient, heroGradient, primaryButtonGradient
} from '../common/DesignTokens';
import { displayDate, toDateKey, parseDateKey, isFutureDate, formatNumber } from '../common/DateUtils';
import { CalorieService } from '../services/CalorieService';

@Component
export struct HomePage {
  @Consume('navStack') navStack: NavPathStack;
  @StorageLink('refreshTick') @Watch('reload') refreshTick: number = 0;
  @StorageLink('selectedDate') @Watch('reload') selectedDate: string = '';
  /** 页面内容入场开关，见 build() 末尾的 opacity/translate */
  @State private entered: boolean = false;

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
  }

  /** 本周一（周一为一周之首，与 WeekSparkline 的槽位对齐） */
  private weekStart(): string {
    const sel = parseDateKey(this.selectedDate);
    const dow = (sel.getDay() + 6) % 7;
    const monday = new Date(sel);
    monday.setDate(sel.getDate() - dow);
    return toDateKey(monday);
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

  private goFoodEdit(): void {
    this.navStack.pushPathByName('FoodEdit', new FoodEditParams('add', this.selectedDate, -1));
  }

  private goActivityEdit(): void {
    this.navStack.pushPathByName('ActivityEdit', new ActivityEditParams('add', this.selectedDate, -1));
  }

  build() {
    Scroll() {
      Column({ space: space.md }) {
        // 顶部：日期 + 切换
        Row() {
          Text(displayDate(this.selectedDate))
            .fontSize(fontSize.pageTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.text)
            .layoutWeight(1)
          Button('切换日期')
            .height(36)
            .fontSize(fontSize.secondary)
            .fontColor(color.primary)
            .backgroundColor(color.primaryLight)
            .borderRadius(radius.pill)
            .onClick(() => {
              this.showDatePicker();
            })
        }
        .width('100%')

        // 主视觉卡：整页唯一的高饱和色块。
        // 原型里的「居中大图」在这个 App 里没有对应物 —— 热量环本身就是主图，
        // 所以让它占据卡片正中，其余信息退到上下两行。
        // 文字一律用白：这张卡在浅色主题下也是深色饱和底，白字两种主题都成立。
        Column({ space: space.lg }) {
          Text('今日热量预算')
            .fontSize(fontSize.secondary)
            .fontColor('#CCFFFFFF')

          CalorieRing({
            consumed: this.summary !== null ? this.summary.consumedKcal : 0,
            budget: this.summary !== null ? this.summary.dailyCalorieBudget : 1800,
            onHero: true
          })

          Row() {
            Column({ space: 4 }) {
              AnimatedNumber({
                target: this.summary !== null ? this.summary.consumedKcal : 0,
                textSize: fontSize.metric,
                textColor: '#FFFFFF'
              })
              Text('已摄入 kcal')
                .fontSize(fontSize.caption)
                .fontColor('#B3FFFFFF')
            }
            .alignItems(HorizontalAlign.Center)
            .layoutWeight(1)

            Column({ space: 4 }) {
              AnimatedNumber({
                target: this.summary !== null ? this.summary.burnedKcal : 0,
                textSize: fontSize.metric,
                textColor: '#FFFFFF'
              })
              Text('活动消耗 kcal')
                .fontSize(fontSize.caption)
                .fontColor('#B3FFFFFF')
            }
            .alignItems(HorizontalAlign.Center)
            .layoutWeight(1)

            Column({ space: 4 }) {
              AnimatedNumber({
                target: this.summary !== null ? this.summary.dailyCalorieBudget : 1800,
                textSize: fontSize.metric,
                textColor: '#FFFFFF'
              })
              Text('饮食预算 kcal')
                .fontSize(fontSize.caption)
                .fontColor('#B3FFFFFF')
            }
            .alignItems(HorizontalAlign.Center)
            .layoutWeight(1)
          }
          .width('100%')
        }
        .padding(layout.cardPadding)
        .linearGradient(heroGradient())
        .borderRadius(glass.cardRadius)
        .border({ width: glass.borderWidth, color: color.glassBorder })
        .shadow(glassShadow(glass.shadowRadius + 6, glass.shadowOffsetY + 4))
        .alignItems(HorizontalAlign.Center)
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

        // 宏量营养素：仅在已设置体征（目标可推导）时显示
        if (this.macroTarget !== null && this.macroDay !== null) {
          MacroPanel({
            actualProtein: this.macroDay.actual.proteinG,
            actualCarbs: this.macroDay.actual.carbsG,
            actualFat: this.macroDay.actual.fatG,
            targetProtein: this.macroTarget.proteinG,
            targetCarbs: this.macroTarget.carbsG,
            targetFat: this.macroTarget.fatG
          })

          if (!this.macroDay.hasMacroData) {
            Text('今天的记录还没有宏量数据，去「饮食」页补录或用 AI 拍照识别')
              .fontSize(fontSize.caption)
              .fontColor(color.textHint)
              .width('100%')
          }
        } else {
          // 未设体征时给出明确引导，而不是静默隐藏
          Column({ space: 6 }) {
            Text('设置体征，自动算出你的热量与宏量目标')
              .fontSize(fontSize.body)
              .fontColor(color.text)
            Text('体重、身高、年龄、活动量 → BMR/TDEE → 每日目标')
              .fontSize(fontSize.caption)
              .fontColor(color.textHint)
          }
          .width('100%')
          .padding(layout.cardPadding)
          .linearGradient({
            angle: 160,
            colors: [[toneVeil('onboard'), 0], [color.glassFillStrong, 1]]
          })
          .borderRadius(glass.cardRadius)
          .border({ width: glass.borderWidth, color: color.glassBorder })
          .backdropBlur(glass.blurRadius)
          .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
          .alignItems(HorizontalAlign.Start)
        }
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