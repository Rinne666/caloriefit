/**
 * 今日黑板 —— 当日饮食记录的「黑板 + 便签墙」主视图。
 *
 * 布局参考 nosh（小红书《求一个免费的热量记录App》里那款）：
 *   ① 顶部横排日期胶囊条，当前日期高亮，可点选切换
 *   ② 「摄入 / 目标」大数字 + 剩余额度
 *   ③ 食物贴纸卡片横向流（这里用便签形态：胶带 + 歪斜 + 卷边）
 *   ④ 右下角一只卡通猫
 *
 * 与旧版「今日热量半环卡」的关系：半环卡已迁到「进度」页顶部，
 * 今日页第一屏完全交给黑板 —— 这就是「当日黑板为主体」。
 *
 * 数据口径：摄入与预算来自 DailySummaryService，与首页/进度页同一份，
 * 不另算一套。便签内容直接来自当日 food_log。
 */

import { ChalkColors } from '../common/ChalkTokens';
import { StickyNoteCard } from './StickyNoteCard';
import { FoodLog } from '../models/FoodLog';
import { DailySummary } from '../models/DailySummary';
import { FoodRepository } from '../repositories/FoodRepository';
import { MacroRepository, MacroDayTotal } from '../repositories/MacroRepository';
import { DailySummaryService } from '../services/DailySummaryService';
import { StickerCutoutService } from '../services/StickerCutoutService';
import { toDateKey, parseDateKey } from '../common/DateUtils';
import { MEAL_LABELS } from '../common/Constants';
import { stickyTilt, stickyColorIndex } from '../common/ChalkTokens';

/** 日期胶囊上的一项 */
class DateChip {
  key: string = '';
  /** 日，如 21 */
  day: string = '';
  /** 星期，如 三 */
  week: string = '';

  constructor(key: string, day: string, week: string) {
    this.key = key;
    this.day = day;
    this.week = week;
  }
}

const WEEK_LABELS: string[] = ['一', '二', '三', '四', '五', '六', '日'];

@Component
export struct BlackboardView {
  /**
   * 数据刷新广播。写库方（编辑页、全部餐食页）bumpRefresh() 之后，
   * 黑板必须跟着重载 —— 否则保存完记录回到今日页会出现
   * 「今日餐食」已显示新条目、黑板却还是旧数据的两处不同步。
   */
  @StorageLink('refreshTick') @Watch('reload') refreshTick: number = 0;
  /** 选中的日期。外部改动时黑板同步重建胶囊条并重载 */
  @StorageLink('selectedDate') @Watch('onDateChanged') selectedDate: string = '';
  @State summary: DailySummary | null = null;
  @State logs: FoodLog[] = [];
  /** 当日宏量合计（粉笔字那一行用） */
  @State macroDay: MacroDayTotal | null = null;
  /** 与 logs 同下标的贴纸 data URI；空串表示该条没有贴纸 */
  @State stickerUris: string[] = [];
  @State chips: DateChip[] = [];

  aboutToAppear(): void {
    this.buildChips();
    this.reload();
  }

  /** 外部改了日期：重建胶囊条并重载 */
  private onDateChanged(): void {
    this.buildChips();
    this.reload();
  }

  /** 最近 7 天（含今天），按周一为一周之首 */
  private buildChips(): void {
    const out: DateChip[] = [];
    const base = this.selectedDate !== '' ? parseDateKey(this.selectedDate) : new Date();
    const dow = (base.getDay() + 6) % 7;
    const monday = new Date(base);
    monday.setDate(base.getDate() - dow);
    // 从本周一排到周日；整周都是过去或今天，不含未来
    for (let i = 0; i < 7; i++) {
      const d = new Date(monday);
      d.setDate(monday.getDate() + i);
      const key = toDateKey(d);
      const today = toDateKey(new Date());
      if (key > today) {
        continue;
      }
      out.push(new DateChip(key, d.getDate().toString(), WEEK_LABELS[i]));
    }
    this.chips = out;
  }

  private async reload(): Promise<void> {
    const picked = AppStorage.get<string>('selectedDate');
    const date = picked !== undefined && picked !== null && picked.length > 0
      ? picked : toDateKey(new Date());
    try {
      this.summary = await DailySummaryService.getSummary(date);
      this.macroDay = await MacroRepository.getDayTotal(date);
      const logs = await FoodRepository.getByDate(date);
      const uris: string[] = [];
      for (let i = 0; i < logs.length; i++) {
        const log = logs[i];
        if (log.stickerPath !== null) {
          uris.push(await StickerCutoutService.loadDataUri(log.stickerPath));
        } else {
          uris.push('');
        }
      }
      this.logs = logs;
      this.stickerUris = uris;
    } catch (_e) {
      this.logs = [];
      this.stickerUris = [];
    }
  }

  private consumed(): number {
    return this.summary !== null ? this.summary.consumedKcal : 0;
  }

  private budget(): number {
    return this.summary !== null ? this.summary.dailyCalorieBudget : 0;
  }

  private remaining(): number {
    const left = this.budget() - this.consumed();
    return left > 0 ? left : 0;
  }

  private overBudget(): boolean {
    return this.consumed() > this.budget();
  }

  private macroText(): string {
    if (this.summary === null) {
      return '';
    }
    const m = this.macroDay;
    if (m === null) {
      return '';
    }
    return `蛋白 ${Math.round(m.actual.proteinG)}g · 碳水 ${Math.round(m.actual.carbsG)}g · 脂肪 ${Math.round(m.actual.fatG)}g`;
  }

  private mealLabel(mealType: number): string {
    return mealType >= 0 && mealType < MEAL_LABELS.length ? MEAL_LABELS[mealType] : '加餐';
  }

  private stickerAt(index: number): string {
    return index < this.stickerUris.length ? this.stickerUris[index] : '';
  }

  private selectDate(key: string): void {
    if (key === this.selectedDate) {
      return;
    }
    // 只改 AppStorage 即可 —— @StorageLink('selectedDate') 的 @Watch 会
    // 触发 onDateChanged（重建胶囊条 + 重载）。这里再手动调一遍就是重复加载。
    AppStorage.setOrCreate<string>('selectedDate', key);
  }

  build() {
    Column({ space: 10 }) {
      this.DateStrip()
      this.Board()
    }
    .width('100%')
  }

  /** nosh 式横排日期胶囊条 */
  @Builder
  DateStrip() {
    Row({ space: 6 }) {
      ForEach(this.chips, (chip: DateChip) => {
        Column({ space: 1 }) {
          Text(chip.day)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(chip.key === this.selectedDate ? '#1E2A22' : ChalkColors.CHALK)
          Text(chip.week)
            .fontSize(10)
            .fontColor(chip.key === this.selectedDate ? '#1E2A22' : ChalkColors.CHALK_DIM)
        }
        .width(36)
        .height(46)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(chip.key === this.selectedDate ? '#D5EE6E' : 'transparent')
        .borderRadius(18)
        .onClick(() => this.selectDate(chip.key))
      }, (chip: DateChip) => chip.key)
    }
    .width('100%')
    .padding({ left: 4, right: 4 })
  }

  /** 木框 + 板面 */
  @Builder
  Board() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        this.Header()
        if (this.logs.length === 0) {
          this.EmptyBoard()
        } else {
          this.Notes()
        }
      }
      .padding({ left: 14, right: 14, top: 14, bottom: 14 })
      .width('100%')
      .backgroundColor(ChalkColors.BOARD)
      .borderRadius(12)
      // 板面被擦过的浅色痕
      .linearGradient({
        angle: 120,
        colors: [[ChalkColors.BOARD, 0], [ChalkColors.BOARD_GLOW, 0.45], [ChalkColors.BOARD, 1]]
      })

      // 卡通猫趴在右下角
      Image($r('app.media.mascot_cat'))
        .width(66)
        .height(66)
        .objectFit(ImageFit.Contain)
        .margin({ right: 8, bottom: 6 })

      // 粉笔槽
      Row() {
        Column()
          .width(26).height(8).backgroundColor('#F4F1E4').borderRadius(5)
          .rotate({ angle: -6 })
        Column()
          .width(26).height(8).backgroundColor('#FFD97D').borderRadius(5)
          .rotate({ angle: 4 })
          .margin({ left: 7 })
      }
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .backgroundColor(ChalkColors.TRAY)
      .borderRadius(6)
      .margin({ right: 80, bottom: 10 })
    }
    .width('100%')
    .padding(9)
    .backgroundColor(ChalkColors.FRAME)
    .borderRadius(18)
    .shadow({ radius: 16, color: '#66000000', offsetX: 0, offsetY: 8 })
  }

  /** 板面顶部：粉笔字写的当日摄入 */
  @Builder
  Header() {
    Row() {
      Column({ space: 2 }) {
        Text('今日摄入')
          .fontSize(13)
          .fontColor(ChalkColors.CHALK_DIM)
        Row({ space: 4 }) {
          Text(`${this.consumed()}`)
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.overBudget() ? '#FFB3B3' : ChalkColors.CHALK)
          Text(`/ ${this.budget()} kcal`)
            .fontSize(14)
            .fontColor(ChalkColors.CHALK_DIM)
            .margin({ top: 12 })
        }
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      Column({ space: 2 }) {
        Text(this.overBudget() ? '已超出' : '还可以吃')
          .fontSize(12)
          .fontColor(ChalkColors.CHALK_DIM)
        Text(`${this.remaining()}`)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.overBudget() ? '#FFB3B3' : '#BFE3F5')
        Text('kcal')
          .fontSize(11)
          .fontColor(ChalkColors.CHALK_DIM)
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')

    if (this.macroText().length > 0) {
      Text(this.macroText())
        .fontSize(12)
        .fontColor(ChalkColors.CHALK_DIM)
        .width('100%')
        .margin({ top: 6 })
    }
  }

  /** 便签墙：横向滚动，贴近 nosh 的卡片流 */
  @Builder
  Notes() {
    Scroll() {
      Row({ space: 10 }) {
        ForEach(this.logs, (log: FoodLog, index: number) => {
          StickyNoteCard({
            name: log.name,
            kcal: log.calories,
            mealLabel: this.mealLabel(log.mealType),
            stickerUri: this.stickerAt(index),
            colorIndex: stickyColorIndex(log.id),
            tilt: stickyTilt(log.id)
          })
        }, (log: FoodLog) => log.id.toString())
      }
      .padding({ right: 26, bottom: 8 })
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .margin({ top: 12 })
  }

  /** 空态：黑板上还什么都没有 */
  @Builder
  EmptyBoard() {
    Column({ space: 8 }) {
      Text('黑板还是空的')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(ChalkColors.CHALK)
      Text('拍一张食物，抠出轮廓贴到这里来')
        .fontSize(13)
        .fontColor(ChalkColors.CHALK_DIM)
      Text('今天记了 0 条')
        .fontSize(12)
        .fontColor(ChalkColors.CHALK_DIM)
        .margin({ top: 4 })
    }
    .width('100%')
    .padding({ top: 26, bottom: 26 })
    .alignItems(HorizontalAlign.Center)
  }
}
