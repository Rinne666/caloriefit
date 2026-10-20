/**
 * 进度 Progress —— 对应 NutriScan 第三个底 Tab。
 *
 * 实测依据：
 *   · 筛选维度 Today / Week / 30 Days（字符串里有 "30 days"、"Last 30 Days Comparison"）
 *   · 字段 readiness_score / readiness_breakdown，接口 /api/v1/progress/readiness
 *   · 文案「Average NutriScore Last 30 Days」「Your protein target, last 30 days」
 *
 * 数据口径：热量与宏量是**真实**的，直接来自已有 food_log 聚合。
 * Readiness Score 与 NutriScore 的算法完全无证据 —— 这两块不给假数字，
 * 只给「未实现」入口，点进去是 ComingSoon。
 */

import { color, fontSize, space, radius, layout, glass, glassGradient, glassShadow, toneVeil } from '../common/DesignTokens';
import { anim } from '../common/Motion';
import { MacroRepository, DayPoint } from '../repositories/MacroRepository';
import { ProfileRepository } from '../repositories/ProfileRepository';
import { DailySummaryService } from '../services/DailySummaryService';
import { PROGRESS_RANGES, Provenance } from '../services/MockContent';
import { setComingSoon, ComingSoonPage } from '../components/ComingSoonPage';
import { toDateKey, parseDateKey, formatNumber } from '../common/DateUtils';
const DAY_LABELS: string[] = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

@Component
export struct ProgressPage {
  @Consume('navStack') navStack: NavPathStack;
  @StorageLink('selectedDate') @Watch('reload') selectedDate: string = '';
  @State private range: number = 1;
  @State private points: DayPoint[] = [];
  @State private targetKcal: number = 1800;
  @State private entered: boolean = false;
  /** 未实现功能覆盖层（页内自持，原因见 ProfilePage 同字段注释） */
  @State private csVisible: boolean = false;
  /** 连续记录天数（原版页头有 🔥 Streak） */
  @State private streakDays: number = 0;
  /** Report 导出的占位层 */
  @State private reportVisible: boolean = false;

  /**
   * 连续记录天数：从今天往回数，每天有饮食记录则累计。
   * 今天还没记不算断 —— 从昨天起算更符合用户直觉（早上还没吃早饭不该断签）。
   */
  private computeStreak(series: DayPoint[]): number {
    const recorded: Map<string, boolean> = new Map();
    for (let i = 0; i < series.length; i++) {
      recorded.set(series[i].date, series[i].kcal > 0);
    }
    let n = 0;
    let cursor = this.selectedDate;
    if (recorded.get(cursor) === true) {
      n = 1;
    }
    for (let i = 0; i < 60; i++) {
      const d = parseDateKey(cursor);
      d.setDate(d.getDate() - 1);
      cursor = toDateKey(d);
      if (recorded.get(cursor) === true) {
        n++;
      } else {
        break;
      }
    }
    return n;
  }

  enterView(): void {
    this.entered = true;
  }

  aboutToAppear(): void {
    this.reload();
  }

  reload(): void {
    this.loadData();
  }

  private async loadData(): Promise<void> {
    try {
      const s = await DailySummaryService.getSummary(this.selectedDate);
      this.targetKcal = s !== null ? s.dailyCalorieBudget : 1800;
    } catch (e) {
      this.targetKcal = 1800;
    }
    try {
      const n = this.rangeDays();
      const to = this.selectedDate;
      const from = this.shift(to, -(n - 1));
      this.points = await MacroRepository.getTrend(from, to);
    } catch (e) {
      this.points = [];
    }
    // 连胜要跨更长的窗口，不能只看出图区间 —— 切到「今天」时会误判成 0
    try {
      const to = this.selectedDate;
      const series = await MacroRepository.getTrend(this.shift(to, -59), to);
      this.streakDays = this.computeStreak(series);
    } catch (e) {
      this.streakDays = 0;
    }
  }

  private rangeDays(): number {
    if (this.range === 0) {
      return 1;
    }
    return this.range === 1 ? 7 : 30;
  }

  private shift(key: string, n: number): string {
    const d = parseDateKey(key);
    d.setDate(d.getDate() + n);
    return toDateKey(d);
  }

  private setRange(i: number): void {
    this.range = i;
    this.loadData();
  }

  private maxKcal(): number {
    let m = this.targetKcal;
    for (let i = 0; i < this.points.length; i++) {
      if (this.points[i].kcal > m) {
        m = this.points[i].kcal;
      }
    }
    return m <= 0 ? 1 : m;
  }

  private avgKcal(): number {
    if (this.points.length === 0) {
      return 0;
    }
    let sum = 0;
    for (let i = 0; i < this.points.length; i++) {
      sum += this.points[i].kcal;
    }
    return Math.round(sum / this.points.length);
  }

  private avgProtein(): number {
    if (this.points.length === 0) {
      return 0;
    }
    let sum = 0;
    for (let i = 0; i < this.points.length; i++) {
      sum += this.points[i].proteinG;
    }
    return Math.round(sum / this.points.length);
  }

  private onTargetDays(): number {
    let n = 0;
    for (let i = 0; i < this.points.length; i++) {
      if (this.targetKcal > 0 && this.points[i].kcal <= this.targetKcal) {
        n++;
      }
    }
    return n;
  }

  /** 按所选区间把数据对齐到连续槽位，缺的日子补 0（而不是不画） */
  private slots(): DayPoint[] {
    const n = this.rangeDays();
    const out: DayPoint[] = [];
    for (let i = 0; i < n; i++) {
      const key = this.shift(this.selectedDate, -(n - 1 - i));
      let found: DayPoint | null = null;
      for (let j = 0; j < this.points.length; j++) {
        if (this.points[j].date === key) {
          found = this.points[j];
          break;
        }
      }
      out.push(found !== null ? found as DayPoint
        : { date: key, kcal: 0, proteinG: 0, carbsG: 0, fatG: 0 });
    }
    return out;
  }

  build() {
    // 本页自持的未实现功能覆盖层，理由见 ProfilePage 同处注释
    Stack() {
      Scroll() {
        Column({ space: space.md }) {
        Text('进度')
          .fontSize(fontSize.pageTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(color.text)
          .width('100%')

        /**
         * 页头：连胜 + Report。
         *
         * 原版 Progress 页头有「🔥 Streak: N days」与「Report」导出按钮
         * （实测 main_nav_04_Progress.png），此前这两项都缺。
         * Streak 是真数据（按近 30 天有无饮食记录往回数）；
         * Report 导出无对应实现，走未实现占位而不是留一个死按钮。
         */
        Row() {
          Text(`🔥 连续记录 ${this.streakDays} 天`)
            .fontSize(fontSize.secondary)
            .fontColor(color.text)

          Blank()

          Text('Report')
            .fontSize(fontSize.secondary)
            .fontColor(color.primary)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .backgroundColor(color.glassFill)
            .borderRadius(radius.pill)
            .onClick(() => {
              setComingSoon('Report 导出',
                '将一段时间的摄入与宏量记录整理为个人报告',
                '当前项目尚未实现报告生成与本地文件导出',
                '实现 PDF 或图片生成，并由用户自主保存到设备',
                Provenance.MEASURED);
              this.reportVisible = true;
            })
        }
        .width('100%')
        .padding({ top: space.sm, bottom: space.sm })

        // 筛选：今天 / 本周 / 近 30 天
        Row({ space: space.sm }) {
          ForEach(PROGRESS_RANGES, (label: string, i: number) => {
            Text(label)
              .fontSize(fontSize.secondary)
              .fontColor(this.range === i ? color.primary : color.textSecondary)
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .backgroundColor(this.range === i ? color.glassFill : Color.Transparent)
              .borderRadius(radius.pill)
              .onClick(() => {
                this.setRange(i);
              })
          }, (label: string, i: number) => label + i)
        }
        .width('100%')

        // 关键数字
        Row({ space: space.md }) {
          Column({ space: 2 }) {
            Text(`${formatNumber(this.avgKcal())}`)
              .fontSize(fontSize.metric)
              .fontWeight(FontWeight.Bold)
              .fontColor(color.text)
            Text('日均 kcal')
              .fontSize(fontSize.caption)
              .fontColor(color.textHint)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .padding(layout.cardPadding)
          .linearGradient(glassGradient(toneVeil('avg-kcal')))
          .borderRadius(glass.cardRadius)
          .border({ width: glass.borderWidth, color: color.glassBorder })

          Column({ space: 2 }) {
            Text(`${this.onTargetDays()}`)
              .fontSize(fontSize.metric)
              .fontWeight(FontWeight.Bold)
              .fontColor(color.text)
            Text('达标天数')
              .fontSize(fontSize.caption)
              .fontColor(color.textHint)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .padding(layout.cardPadding)
          .linearGradient(glassGradient(toneVeil('on-target')))
          .borderRadius(glass.cardRadius)
          .border({ width: glass.borderWidth, color: color.glassBorder })
        }
        .width('100%')

        // 柱状图
        Column({ space: space.sm }) {
          Text('热量摄入')
            .fontSize(fontSize.sectionTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.text)
            .width('100%')

          Row() {
            ForEach(this.slots(), (p: DayPoint, i: number) => {
              Stack({ alignContent: Alignment.BottomStart }) {
                Row()
                  .width(this.barWidth())
                  .height(88)
                  .borderRadius(4)
                  .backgroundColor(color.ringTrack)

                Row()
                  .width(this.barWidth())
                  // 零数据的日子不给最低高度：留 3px 残桩在视觉上等于
                  // 「这天吃了一点」，与实际「这天没记录」是两回事。
                  // 同 WeekSparkline 当初踩过的坑。
                  .height(p.kcal > 0
                    ? (this.entered ? Math.max(3, Math.round(p.kcal / this.maxKcal() * 88)) : 0)
                    : 0)
                  .borderRadius(4)
                  .backgroundColor(p.kcal > this.targetKcal && this.targetKcal > 0 ? color.danger : color.primary)
                  .animation({
                    duration: anim.dataMs,
                    delay: Math.min(20, i) * anim.barStaggerMs,
                    curve: anim.easeData
                  })
              }
              .width(this.barWidth())
              .height(88)
              .layoutWeight(1)
              .margin({ left: 2 })
            }, (p: DayPoint, i: number) => `${p.date}#${p.kcal}`)
          }
          .width('100%')

          Text(`目标线 ${formatNumber(this.targetKcal)} kcal · 蛋白日均 ${this.avgProtein()}g`)
            .fontSize(fontSize.caption)
            .fontColor(color.textHint)
            .width('100%')
        }
        .width('100%')
        .padding(layout.cardPadding)
        .linearGradient(glassGradient(toneVeil('progress-chart')))
        .borderRadius(glass.cardRadius)
        .border({ width: glass.borderWidth, color: color.glassBorder })
        .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
        .alignItems(HorizontalAlign.Start)

        // Readiness Score：算法无证据，不编数
        this.ScoreCard(
          'Readiness Score',
          'readiness_score',
          '接口 /api/v1/progress/readiness，配套 breakdown 字段',
          '需要服务端返回每日 readiness 数据，本地没有可复现的算法'
        )

        // NutriScore：同上
        this.ScoreCard(
          'NutriScore',
          'Average NutriScore Last 30 Days',
          '界面文案实测存在，但打分算法完全未知',
          '需要原始打分公式与权重，无法推断'
        )
      }
      .padding(layout.pagePadding)
      .opacity(this.entered ? 1 : 0)
      .translate({ x: 0, y: this.entered ? 0 : anim.enterShiftVp })
      .animation({ duration: anim.enterMs, curve: anim.ease })
      .onAppear(() => {
        this.enterView();
      })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor(color.bg)
    .linearGradient({ angle: 135, colors: [[color.pageDeep, 0], [color.pageMid, 1]] })

      if (this.reportVisible) {
        Stack({ alignContent: Alignment.TopStart }) {
          ComingSoonPage()

          Button('‹')
            .width(44)
            .height(44)
            .fontSize(26)
            .fontColor(color.text)
            .backgroundColor(Color.Transparent)
            .margin({ top: 46, left: 16 })
            .onClick(() => {
              this.reportVisible = false;
            })
        }
        .width('100%')
        .height('100%')
      }

      if (this.csVisible) {
        Stack({ alignContent: Alignment.TopStart }) {
          ComingSoonPage()

          Button('‹')
            .width(44)
            .height(44)
            .fontSize(26)
            .fontColor(color.text)
            .backgroundColor(Color.Transparent)
            .margin({ top: 46, left: 16 })
            .onClick(() => {
              this.csVisible = false;
            })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }

  private barWidth(): number {
    const n = this.rangeDays();
    return n <= 7 ? 18 : 6;
  }

  @Builder
  ScoreCard(title: string, evidence: string, blocker: string, needed: string) {
    Row() {
      Column({ space: 4 }) {
        Text(title)
          .fontSize(fontSize.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(color.text)
        Text(`证据：${evidence}`)
          .fontSize(fontSize.caption)
          .fontColor(color.textHint)
        Text(`缺：${needed}`)
          .fontSize(fontSize.caption)
          .fontColor(color.textHint)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('未实现 ›')
        .fontSize(fontSize.caption)
        .fontColor(color.textHint)
    }
    .width('100%')
    .padding(layout.cardPadding)
    .linearGradient(glassGradient(toneVeil(title)))
    .borderRadius(glass.cardRadius)
    .border({ width: glass.borderWidth, color: color.glassBorder })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      setComingSoon(title, '恢复生理状态的综合评分', blocker, needed, Provenance.INFERRED);
      this.csVisible = true;
    })
  }
}
