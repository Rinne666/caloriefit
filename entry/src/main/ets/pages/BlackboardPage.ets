/**
 * 今日黑板 —— 把当天的饮食记录画成一面「黑板 + 便签墙」。
 *
 * 形态参考：每条饮食记录 = 一张便签，便签上是抠出来的食物贴纸 + 名称 + 热量；
 * 板面顶部用粉笔字写当日摄入与剩余额度，右下角蹲一只卡通猫。
 *
 * 与现有页面的关系：
 *   这是一个**独立页面**，从首页进入，不替换首页的综合页。
 *   首页与其它页面沿用 NutriScan 实测的深色科技风（见 DesignTokens），
 *   黑板页是另一种美术方向（卡通 / 粉笔 / 便签），两者并存而不是互相覆盖。
 *
 * 数据口径：
 *   摄入与预算来自 DailySummaryService，与首页同一份口径，不另算一套。
 */

import { ChalkColors, stickyTilt, stickyColorIndex } from '../common/ChalkTokens';
import { StickyNoteCard } from '../components/StickyNoteCard';
import { FoodLog } from '../models/FoodLog';
import { DailySummary } from '../models/DailySummary';
import { FoodRepository } from '../repositories/FoodRepository';
import { DailySummaryService } from '../services/DailySummaryService';
import { StickerCutoutService } from '../services/StickerCutoutService';
import { toDateKey } from '../common/DateUtils';
import { MEAL_LABELS } from '../common/Constants';

@Component
export struct BlackboardPage {
  @Consume('navStack') navStack: NavPathStack;
  @State summary: DailySummary | null = null;
  @State logs: FoodLog[] = [];
  /** 与 logs 同下标的贴纸 data URI；空串表示该条没有贴纸 */
  @State stickerUris: string[] = [];
  @State loading: boolean = true;

  aboutToAppear(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    // 跟随首页选中的日期（AppStorage 'selectedDate'），不是写死「今天」。
    // 首页有日期选择器，用户切到哪天，黑板就该展示哪天的便签墙 ——
    // 否则「今天没有记录」会误导成「什么都没记」。
    const picked = AppStorage.get<string>('selectedDate');
    const date = picked !== undefined && picked !== null && picked.length > 0
      ? picked : toDateKey(new Date());
    try {
      this.summary = await DailySummaryService.getSummary(date);
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
      // 读库失败按空态渲染，不让整页崩掉
      this.logs = [];
      this.stickerUris = [];
    }
    this.loading = false;
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

  private mealLabel(mealType: number): string {
    return mealType >= 0 && mealType < MEAL_LABELS.length ? MEAL_LABELS[mealType] : '加餐';
  }

  /** 取第 index 条记录的贴纸 URI */
  private stickerAt(index: number): string {
    return index < this.stickerUris.length ? this.stickerUris[index] : '';
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 12 }) {
          this.Board()
        }
        .padding({ left: 14, right: 14, top: 12, bottom: 24 })
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .backgroundColor('#1C2721')
    }
    .title('今日黑板')
    .backgroundColor('#1C2721')
    .onReady(() => {
      this.reload();
    })
  }

  @Builder
  Board() {
    // 板面与吉祥物、粉笔槽叠在一起。
    // 注意：**不要**给板面加 margin 来给吉祥物让位 —— Stack 里的 margin 会把
    // 子元素挤出父容器，整块黑板随之溢出屏幕（实测左侧文字被裁掉）。
    // 正确做法是把吉祥物直接叠在板面右下角。
    Stack({ alignContent: Alignment.BottomEnd }) {
      // 木框 + 板面
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
        .width(70)
        .height(70)
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
      .margin({ right: 84, bottom: 10 })
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
    .margin({ bottom: 12 })
  }

  /** 便签墙 */
  @Builder
  Notes() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.logs, (log: FoodLog, index: number) => {
        StickyNoteCard({
          name: log.name,
          kcal: log.calories,
          mealLabel: this.mealLabel(log.mealType),
          stickerUri: this.stickerAt(index),
          colorIndex: stickyColorIndex(log.id),
          tilt: stickyTilt(log.id)
        })
        .margin({ right: 8, bottom: 10 })
      }, (log: FoodLog) => log.id.toString())
    }
    .width('100%')
    // 右下角留给趴在板边的卡通猫，别让便签被压住
    .padding({ right: 30, bottom: 22 })
  }

  /** 空态：黑板上还什么都没有 */
  @Builder
  EmptyBoard() {
    Column({ space: 8 }) {
      Text('黑板还是空的')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(ChalkColors.CHALK)
      Text('去拍一张食物，抠出轮廓贴到这里来')
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
