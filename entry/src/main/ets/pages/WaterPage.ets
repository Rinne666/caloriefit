/**
 * 饮水 Water —— 今日页的个人饮水记录子页
 *
 * 布局按真机截图 1:1 还原的要素：
 *   左侧水瓶（水位随进度上涨） · 右上 "% completed" 用青色
 *   · 「goal 2,650 ml」带铅笔图标可手改 · 巨大的「N ml consumed」
 *   · 空态文案「No water logged yet — start with a glass.」
 *   · 周条 M–S，今天青色描边 · 快加 250 / 500 / 自定义
 *   · This Week 卡：Day Streak + Avg/Day + 七天柱图
 *
 * 数据是真的（V4 water_log 逐笔入库，可撤销最后一笔）。
 * 每日目标的自动公式（体重 × 35ml）是推断值，界面上标了「推断」。
 */

import { color, fontSize, space, radius, layout, glass, glassGradient, glassShadow, toneVeil } from '../common/DesignTokens';
import { anim } from '../common/Motion';
import { WaterRepository, WaterDayPoint } from '../repositories/WaterRepository';
import { ProfileRepository } from '../repositories/ProfileRepository';
import { WATER_QUICK_ML, waterTargetMl, WATER_ML_PER_KG, Provenance } from '../services/MockContent';
import { toDateKey, parseDateKey, formatNumber } from '../common/DateUtils';

const WEEK_LABELS: string[] = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const BOTTLE_W: number = 72;
const BOTTLE_H: number = 128;

@Component
export struct WaterPage {
  @StorageLink('selectedDate') @Watch('reload') selectedDate: string = '';
  @State private totalMl: number = 0;
  @State private targetMl: number = 0;
  @State private autoTarget: number = 0;
  @State private manualTarget: boolean = false;
  @State private week: WaterDayPoint[] = [];
  @State private filled: boolean = false;

  enterView(): void {
    this.filled = true;
  }

  aboutToAppear(): void {
    this.reload();
  }

  reload(): void {
    this.loadData();
  }

  private async loadData(): Promise<void> {
    try {
      this.totalMl = await WaterRepository.totalByDate(this.selectedDate);
      this.manualTarget = (await WaterRepository.getManualTarget()) !== null;
      this.targetMl = await WaterRepository.effectiveTarget(0);
      // effectiveTarget(0) 在无手动值时返回 0，这里用体重兜底
      if (!(this.targetMl > 0)) {
        const profile = await ProfileRepository.getBodyProfile();
        this.autoTarget = profile.weightKg > 0 ? waterTargetMl(profile.weightKg) : 0;
        this.targetMl = this.autoTarget;
      } else {
        this.autoTarget = this.targetMl;
      }
      const monday = this.monday();
      this.week = await WaterRepository.trend(monday, this.addDays(monday, 6));
    } catch (e) {
      this.totalMl = 0;
      this.week = [];
    }
  }

  private monday(): string {
    const sel = parseDateKey(this.selectedDate);
    const dow = (sel.getDay() + 6) % 7;
    const m = new Date(sel);
    m.setDate(sel.getDate() - dow);
    return toDateKey(m);
  }

  private addDays(key: string, n: number): string {
    const d = parseDateKey(key);
    d.setDate(d.getDate() + n);
    return toDateKey(d);
  }

  private ratio(): number {
    if (!(this.targetMl > 0)) {
      return 0;
    }
    return Math.max(0, Math.min(1, this.totalMl / this.targetMl));
  }

  private percentText(): string {
    return `${Math.round(this.ratio() * 100)}%`;
  }

  /** 连续达标天数：从今天往回数，达标即累计，断一天即止 */
  private streak(): number {
    const map: Map<string, number> = new Map();
    for (let i = 0; i < this.week.length; i++) {
      map.set(this.week[i].date, this.week[i].totalMl);
    }
    let n = 0;
    let cursor = this.selectedDate;
    // 今天还没达标不算断，从昨天开始往回数更符合直觉
    const todayMl = map.get(this.selectedDate) !== undefined ? map.get(this.selectedDate) as number : 0;
    if (todayMl >= this.targetMl && this.targetMl > 0) {
      n = 1;
    }
    for (let i = 0; i < 30; i++) {
      const prev = parseDateKey(cursor);
      prev.setDate(prev.getDate() - 1);
      cursor = toDateKey(prev);
      const v = map.has(cursor) ? map.get(cursor) as number : 0;
      if (this.targetMl > 0 && v >= this.targetMl) {
        n++;
      } else {
        break;
      }
    }
    return n;
  }

  private avgPerDay(): number {
    if (this.week.length === 0) {
      return 0;
    }
    let sum = 0;
    for (let i = 0; i < this.week.length; i++) {
      sum += this.week[i].totalMl;
    }
    return Math.round(sum / this.week.length);
  }

  private weekMax(): number {
    let m = this.targetMl;
    for (let i = 0; i < this.week.length; i++) {
      if (this.week[i].totalMl > m) {
        m = this.week[i].totalMl;
      }
    }
    return m <= 0 ? 1 : m;
  }

  private async addWater(ml: number): Promise<void> {
    try {
      await WaterRepository.add(this.selectedDate, ml, Date.now());
      await this.loadData();
      AppStorage.setOrCreate<number>('refreshTick', (AppStorage.get<number>('refreshTick') ?? 0) + 1);
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '记录失败' });
    }
  }

  private async undo(): Promise<void> {
    try {
      await WaterRepository.undoLast(this.selectedDate);
      await this.loadData();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '没有可撤销的记录' });
    }
  }

  private editTarget(): void {
    this.getUIContext().showTextPickerDialog({
      range: this.suggestTargets(),
      value: `${this.targetMl > 0 ? this.targetMl : 2000}`,
      onAccept: (value: TextPickerResult) => {
        // TextPickerResult.value 的类型是 string | string[]：
        // 单列选择器回 string，多列模式回数组。这里收窄成单值再解析，
        // 直接 parseInt(value.value, 10) 在多列下会把数组强转成 NaN。
        let raw: string = '';
        if (typeof value.value === 'string') {
          raw = value.value;
        } else {
          raw = value.value[0];
        }
        const v = parseInt(raw, 10);
        if (isFinite(v) && v > 0) {
          WaterRepository.setTarget(v, Date.now()).then(() => {
            this.loadData();
          });
        }
      }
    });
  }

  private suggestTargets(): string[] {
    const base = this.autoTarget > 0 ? this.autoTarget : 2000;
    return [`${base - 250}`, `${base}`, `${base + 250}`, `${base + 500}`];
  }

  build() {
    Scroll() {
      Column({ space: space.md }) {
        // 水瓶占左侧 42%，指标靠右对齐，复现原版横向分区。
        Row() {
          Column() {
            this.Bottle()
          }
          .width('42%')
          .alignItems(HorizontalAlign.Center)

          Column({ space: space.xs }) {
            Row({ space: space.xxs }) {
              Text(this.percentText())
                .fontSize(fontSize.metric)
                .fontWeight(FontWeight.Bold)
                .fontColor(color.waterAccent)
              Text('completed')
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
            }
            .width('100%')
            .justifyContent(FlexAlign.End)

            Row({ space: space.xxs }) {
              Text(this.targetMl > 0 ? `目标 ${formatNumber(this.targetMl)} ml` : '未设置饮水目标')
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
              Image($r('app.media.water_pencil'))
                .width(16)
                .height(16)
                .fillColor(color.text)
                .onClick(() => {
                  this.editTarget();
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.End)

            Row({ space: 2 }) {
              Text(`${formatNumber(this.totalMl)}`)
                .fontSize(46)
                .fontWeight(FontWeight.Bold)
                .fontColor(color.text)
              Text('ml consumed')
                .fontSize(fontSize.caption)
                .fontColor(color.textHint)
                .margin({ bottom: 8 })
            }
            .width('100%')
            .justifyContent(FlexAlign.End)
          }
          .width('58%')
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')

        Text(this.totalMl === 0 ? '还没有饮水记录 —— 先来一杯。' : '')
          .fontSize(fontSize.secondary)
          .fontColor(color.textHint)
          .width('100%')

        // 周条 M–S
        Row() {
          ForEach(WEEK_LABELS, (label: string, i: number) => {
            Column({ space: 4 }) {
              Stack({ alignContent: Alignment.Center }) {
                Circle()
                  .width(34)
                  .height(34)
                  .fill(this.dayTotal(i) >= this.targetMl && this.targetMl > 0
                    ? color.waterAccent : color.glassFill)
                Circle()
                  .width(34)
                  .height(34)
                  .stroke(this.isToday(i) ? color.waterAccent : color.glassBorder)
                  .strokeWidth(2)
                  .fill(Color.Transparent)
              }
              .width(34)
              .height(34)

              Text(label)
                .fontSize(fontSize.caption)
                .fontColor(this.isToday(i) ? color.waterAccent : color.textHint)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
          }, (label: string, i: number) => label + i)
        }
        .width('100%')

        // 快加
        Row({ space: space.md }) {
          ForEach(WATER_QUICK_ML, (ml: number) => {
            Column({ space: 2 }) {
              Text(`${ml}`)
                .fontSize(fontSize.sectionTitle)
                .fontWeight(FontWeight.Bold)
                .fontColor(color.text)
              Text('ml')
                .fontSize(fontSize.caption)
                .fontColor(color.textHint)
            }
            .width(64)
            .height(64)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(color.glassFill)
            .borderRadius(32)
            .border({ width: 1, color: color.glassBorder })
            .onClick(() => {
              this.addWater(ml);
            })
          }, (ml: number) => ml.toString())

          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.drop'))
              .fontSize(24)
              .fontColor([color.text])

            Stack({ alignContent: Alignment.Center }) {
              Circle()
                .width(16)
                .height(16)
                .fill(color.text)
              Text('+')
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(color.bg)
            }
            .width(16)
            .height(16)
            .offset({ x: 12, y: 12 })
          }
          .width(64)
          .height(64)
          .backgroundColor(color.glassFill)
          .borderRadius(32)
          .border({ width: 1, color: color.glassBorder })
          .onClick(() => {
            this.addWater(100);
          })

          Column() {
            Text('撤销')
              .fontSize(fontSize.caption)
              .fontColor(color.danger)
          }
          .width(48)
          .height(64)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.undo();
          })
        }
        .width('100%')

        Text('本周')
          .fontSize(fontSize.sectionTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(color.text)
          .width('100%')

        // This Week
        Column({ space: space.sm }) {
          Row() {
            Column({ space: 2 }) {
              Text(`${this.streak()}`)
                .fontSize(fontSize.metric)
                .fontWeight(FontWeight.Bold)
                .fontColor(color.text)
              Row({ space: 6 }) {
                Image($r('app.media.water_flame'))
                  .width(16)
                  .height(16)
                  .fillColor(color.streakOrange)
                Text('连续达标')
                  .fontSize(fontSize.caption)
                  .fontColor(color.textHint)
              }
            }
            .layoutWeight(1)

            Column({ space: 2 }) {
              Text(`${this.avgPerDay()}`)
                .fontSize(fontSize.metric)
                .fontWeight(FontWeight.Bold)
                .fontColor(color.text)
              Row({ space: 6 }) {
                Row({ space: 2 }) {
                  Column()
                    .width(3)
                    .height(6)
                    .backgroundColor(color.waterAccent)
                    .borderRadius(2)
                  Column()
                    .width(3)
                    .height(11)
                    .backgroundColor(color.waterAccent)
                    .borderRadius(2)
                  Column()
                    .width(3)
                    .height(16)
                    .backgroundColor(color.waterAccent)
                    .borderRadius(2)
                }
                .height(16)
                .alignItems(VerticalAlign.Bottom)
                Text('日均 ml')
                  .fontSize(fontSize.caption)
                  .fontColor(color.textHint)
              }
            }
            .layoutWeight(1)
          }
          .width('100%')

          Row() {
            ForEach(WEEK_LABELS, (label: string, i: number) => {
              Column({ space: 4 }) {
                Stack({ alignContent: Alignment.BottomStart }) {
                  Row()
                    .width(16)
                    .height(52)
                    .borderRadius(6)
                    .backgroundColor(color.ringTrack)
                  Row()
                    .width(16)
                    .height(this.filled ? Math.round(this.dayTotal(i) / this.weekMax() * 52) : 0)
                    .borderRadius(6)
                    .backgroundColor(color.waterAccent)
                    .animation({ duration: anim.dataMs, delay: i * anim.barStaggerMs, curve: anim.easeData })
                }
                .width(16)
                .height(52)

                Text(label)
                  .fontSize(fontSize.caption)
                  .fontColor(this.isToday(i) ? color.waterAccent : color.textHint)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Center)
            }, (label: string, i: number) => label + i)
          }
          .width('100%')
        }
        .width('100%')
        .padding(layout.cardPadding)
        .linearGradient(glassGradient(toneVeil('water-week')))
        .borderRadius(glass.cardRadius)
        .border({ width: glass.borderWidth, color: color.glassBorder })
        .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
        .alignItems(HorizontalAlign.Start)

        // 推断声明与撤销
        Row() {
          Text(this.manualTarget
            ? '目标已手动设置'
            : this.autoTarget > 0
              ? `目标按体重 × ${WATER_ML_PER_KG}ml 自动推导（推断）`
              : '请填写身体档案或手动设置目标')
            .fontSize(fontSize.caption)
            .fontColor(color.textHint)
            .layoutWeight(1)
        }
        .width('100%')
      }
      .padding(layout.pagePadding)
      .opacity(this.filled ? 1 : 0)
      .translate({ x: 0, y: this.filled ? 0 : anim.enterShiftVp })
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
  }

  @Builder
  Bottle() {
    Column({ space: 6 }) {
      // 瓶盖
      Row()
        .width(34)
        .height(12)
        .borderRadius(4)
        .backgroundColor(color.glassBorder)

      Stack({ alignContent: Alignment.Bottom }) {
        Row()
          .width(BOTTLE_W)
          .height(BOTTLE_H)
          .borderRadius(20)
          .border({ width: 2, color: color.glassBorder })
          .backgroundColor(Color.Transparent)

        Row()
          .width(BOTTLE_W - 8)
          .height(this.filled ? Math.max(0, Math.round((BOTTLE_H - 8) * this.ratio())) : 0)
          .borderRadius(16)
          .backgroundColor(color.waterAccent)
          .opacity(0.75)
          .animation({ duration: anim.dataMs, curve: anim.easeData })
      }
      .width(BOTTLE_W)
      .height(BOTTLE_H)
    }
    .alignItems(HorizontalAlign.Center)
  }

  private dayTotal(i: number): number {
    const d = parseDateKey(this.monday());
    d.setDate(d.getDate() + i);
    const key = toDateKey(d);
    for (let k = 0; k < this.week.length; k++) {
      if (this.week[k].date === key) {
        return this.week[k].totalMl;
      }
    }
    return 0;
  }

  private isToday(i: number): boolean {
    const d = parseDateKey(this.monday());
    d.setDate(d.getDate() + i);
    return toDateKey(d) === this.selectedDate;
  }
}
