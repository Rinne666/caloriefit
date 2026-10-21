/**
 * 彩色折角便签。
 *
 * 对应设计方案「便签组件 (StickyNoteItem)」。
 *
 * 形态参考实物便签：右下角一个**立体折角**（纸被折起来，露出的背面比正面深），
 * 顶部一条半透明和纸胶带或一枚红色图钉，正文区带淡淡的横线信纸底纹。
 *
 * 内容分区：
 *   顶栏 —— 心情 emoji + 用餐时段胶囊（😋 午餐 · 12:30），右侧热量印章
 *   主体 —— 标题 + 碎碎念正文
 *   底部 —— 「👥 和谁吃」标签 + 一句 AI 饭搭子评语
 */

import { PinDecorationType, StickyPaperStyle, paperColors } from '../models/BoardModels';

@Component
export struct StickyNoteItem {
  /** 标题 */
  @Prop title: string = '';
  /** 热量 */
  @Prop kcal: number = 0;
  /** 餐次标签 */
  @Prop mealLabel: string = '';
  /** 用餐时间 */
  @Prop timeStr: string = '';
  /** 心情 emoji */
  @Prop moodEmoji: string = '';
  /** 和谁吃 */
  @Prop companionText: string = '';
  /** 碎碎念 */
  @Prop memoText: string = '';
  /** AI 饭搭子评语 */
  @Prop aiAdvice: string = '';
  /** 便签纸配色 */
  @Prop paperStyle: StickyPaperStyle = StickyPaperStyle.CREAM_YELLOW;
  /** 顶部装饰 */
  @Prop pinType: PinDecorationType = PinDecorationType.WASHI_TAPE_DOT;
  /** 便签宽（vp） */
  @Prop noteWidth: number = 148;
  /** 便签高（vp） */
  @Prop noteHeight: number = 156;

  private isDark(): boolean {
    return this.paperStyle === StickyPaperStyle.CHALK_CARD;
  }

  /** 纸的主色 */
  private paperBg(): string {
    return paperColors(this.paperStyle)[0];
  }

  /** 折角（纸背）的颜色 */
  private paperFold(): string {
    return paperColors(this.paperStyle)[1];
  }

  private ink(): string {
    return this.isDark() ? '#F1EFE6' : '#4A3B1E';
  }

  private inkDim(): string {
    return this.isDark() ? '#AFB7AE' : '#8A7742';
  }

  @Builder
  WashiTape() {
    if (this.pinType === PinDecorationType.RED_THUMB_TACK) {
      Stack() {
        Circle().width(12).height(12).fill('#E24B4B')
        Circle().width(4).height(4).fill('#FF9E9E').offset({ x: -2, y: -2 })
      }
      .shadow({ radius: 3, color: '#55000000', offsetX: 0, offsetY: 2 })
    } else if (this.pinType !== PinDecorationType.NONE) {
      Row()
        .width(52)
        .height(14)
        .backgroundColor('#5CE8B7C9')
        .rotate({ angle: -3 })
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 5 }) {
        // 顶栏：心情 + 时段 + 热量印章
        Row({ space: 4 }) {
          if (this.moodEmoji.length > 0) {
            Text(this.moodEmoji).fontSize(13)
          }
          Text(this.timeStr.length > 0 ? `${this.mealLabel} · ${this.timeStr}` : this.mealLabel)
            .fontSize(10)
            .fontColor(this.inkDim())
            .maxLines(1)
          Blank()
          if (this.kcal > 0) {
            Text(`${this.kcal}`)
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor('#C2552F')
          }
        }
        .width('100%')

        // 标题
        Text(this.title.length > 0 ? this.title : '便签')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.ink())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        // 正文
        if (this.memoText.length > 0) {
          Text(this.memoText)
            .fontSize(11)
            .fontColor(this.isDark() ? '#DDE2DC' : '#5E4E2E')
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }

        // 和谁吃
        if (this.companionText.length > 0) {
          Text(`👥 ${this.companionText}`)
            .fontSize(10)
            .fontColor(this.inkDim())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }

        // AI 饭搭子评语
        if (this.aiAdvice.length > 0) {
          Text(this.aiAdvice)
            .fontSize(10)
            .fontColor(this.isDark() ? '#9FD8B5' : '#6E8F4E')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 10, right: 12, top: 16, bottom: 8 })
      .alignItems(HorizontalAlign.Start)

      // 折角：纸被折起来，露出背面（比正面深）
      Path({ width: 20, height: 20 })
        .commands('M0 20 L20 0 L20 20 Z')
        .fill(this.paperFold())
        .position({ x: this.noteWidth - 20, y: this.noteHeight - 20 })

      // 顶部装饰。@Builder 返回 void，不能直接链式 .position，
      // 所以包一层容器再定位。
      if (this.pinType !== PinDecorationType.NONE) {
        Stack() {
          this.WashiTape()
        }
        .position({ x: this.noteWidth / 2 - 26, y: -6 })
      }
    }
    .width(this.noteWidth)
    .height(this.noteHeight)
    .backgroundColor(this.paperBg())
    .borderRadius(4)
    .clip(true)
    .shadow({ radius: 10, color: '#55000000', offsetX: 0, offsetY: 5 })
  }
}
