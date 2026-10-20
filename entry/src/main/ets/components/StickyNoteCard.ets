/**
 * 便签卡片 —— 贴在黑板上的一张便签纸。
 *
 * 形态参考实物便签：轻微歪斜（模拟随手贴）、顶部一条半透明胶带、
 * 白边贴纸样式的食物图、餐次小角标。
 *
 * 颜色与歪斜角度都由记录 id 派生（见 ChalkTokens.stickyTilt / stickyColorIndex），
 * 保证同一条记录每次渲染完全一致 —— 刷新页面时便签不该自己转个圈。
 */

import { StickyColors, CartoonColors } from '../common/ChalkTokens';

/** 取便签纸颜色；用函数而不是数组下标，避免 ArkTS 的索引访问限制 */
export function stickyPaper(index: number): string {
  return StickyColors.PALETTE[index % StickyColors.PALETTE.length];
}

@Component
export struct StickyNoteCard {
  /** 食物名 */
  @Prop name: string = '';
  /** 热量（千卡） */
  @Prop kcal: number = 0;
  /** 餐次标签 */
  @Prop mealLabel: string = '';
  /** 食物贴纸的 base64 data URI；空串表示没有贴纸 */
  @Prop stickerUri: string = '';
  /** 配色下标 */
  @Prop colorIndex: number = 0;
  /** 歪斜角度（度） */
  @Prop tilt: number = 0;
  /** 卡片宽度 */
  @Prop cardWidth: number = 124;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 6 }) {
        // 贴纸：白底圆角容器 + 投影，做出「剪贴贴纸」的白边效果
        Stack() {
          if (this.stickerUri.length > 0) {
            Image(this.stickerUri)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
          } else {
            // 没有贴纸（手动录入或抠图失败）时用吉祥物占位，不留空白
            Image($r('app.media.mascot_cat'))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
          }
        }
        .width(62)
        .height(62)
        .padding(4)
        .backgroundColor(CartoonColors.STICKER_EDGE)
        .borderRadius(16)
        .shadow({ radius: 6, color: '#33000000', offsetX: 0, offsetY: 3 })

        Text(this.name)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(CartoonColors.INK)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .width('100%')

        Text(`${this.kcal} kcal`)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#8A7742')
      }
      .padding({ left: 8, right: 8, top: 15, bottom: 8 })
      .width(this.cardWidth)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(stickyPaper(this.colorIndex))
      .borderRadius(10)
      .shadow({ radius: 12, color: '#55000000', offsetX: 0, offsetY: 6 })

      // 顶部胶带：半透明，斜贴一点
      Column()
        .width('58%')
        .height(13)
        .backgroundColor('#66FFFFFF')
        .borderRadius(2)
        .rotate({ angle: -3 })
        .margin({ top: 4 })

      // 餐次角标
      Text(this.mealLabel)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .backgroundColor(CartoonColors.INK)
        .borderRadius(9)
        .margin({ left: 8, top: 12 })
    }
    .rotate({ angle: this.tilt })
  }
}
