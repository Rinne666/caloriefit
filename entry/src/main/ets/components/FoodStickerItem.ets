/**
 * 模切白边食物贴纸。
 *
 * 对应设计方案「模切白边食物贴纸组件 (FoodStickerItem)」。
 *
 * 视觉分三层（从下往上）：
 *   ① 热量签 —— 奶油白的胶带式小条：餐次 + 食物名 + kcal + 蛋白/碳水/脂肪三色圆点
 *   ② 贴纸本体 —— 白边已经烘进 PNG（沿食物轮廓的模切纸边），这里不再套容器
 *   ③ 顶部装饰 —— 半透明和纸胶带 或 红色立体图钉，压在贴纸正上方边缘
 *
 * 背面（双击翻面）：一张手写风便签卡，写三大营养素克数、AI 饭搭子点评和碎碎念。
 */

import { PinDecorationType, StickyPaperStyle, paperColors } from '../models/BoardModels';

/** 三大营养素的圆点色（固定色值，不跟随主题：黑板上要的是「一眼分清」） */
const DOT_PROTEIN: string = '#6FB6F0';
const DOT_CARB: string = '#F2B44C';
const DOT_FAT: string = '#E8899C';

@Component
export struct FoodStickerItem {
  /** 食物名 */
  @Prop title: string = '';
  /** 热量 */
  @Prop kcal: number = 0;
  /** 餐次标签 */
  @Prop mealLabel: string = '';
  /** 贴纸图（data URI）；空串表示没有贴纸 */
  @Prop stickerUri: string = '';
  /** 心情 emoji */
  @Prop moodEmoji: string = '';
  /** 碎碎念首行摘要 */
  @Prop memoSummary: string = '';
  /** 背面：三大营养素 */
  @Prop proteinG: number = 0;
  @Prop carbsG: number = 0;
  @Prop fatG: number = 0;
  /** 背面：AI 饭搭子点评 */
  @Prop aiAdvice: string = '';
  /** 是否翻到背面 */
  @Prop flipped: boolean = false;
  /** 便签纸配色（背面用） */
  @Prop paperStyle: StickyPaperStyle = StickyPaperStyle.CREAM_YELLOW;
  /** 顶部装饰 */
  @Prop pinType: PinDecorationType = PinDecorationType.WASHI_TAPE_DOT;
  /** 贴纸边长（vp） */
  @Prop stickerSize: number = 84;
  /**
   * 是不是示例贴纸。
   *
   * 示例的热量是编的，餐次（早餐/午餐/加餐）也是编的 ——
   * 标成「示例」才不会让人以为这三条真的吃过。
   */
  @Prop isDemo: boolean = false;

  /** 便签纸主色 */
  private paperBg(): string {
    return paperColors(this.paperStyle)[0];
  }

  /** 折角色 */
  private paperFold(): string {
    return paperColors(this.paperStyle)[1];
  }

  /** 是否深色纸（黑板粉笔卡） */
  private isDarkPaper(): boolean {
    return this.paperBg() === '#2B3035';
  }

  /* ------------------------------ 正面 ------------------------------ */

  @Builder
  WashiTape() {
    if (this.pinType === PinDecorationType.WASHI_TAPE_STRIPE) {
      // 斜纹胶带
      Row()
        .width(46)
        .height(13)
        .linearGradient({
          angle: 135,
          colors: [['#66FFFFFF', 0], ['#55E7B7C9', 0.45], ['#66FFFFFF', 0.55], ['#55E7B7C9', 1]]
        })
        .rotate({ angle: -4 })
    } else {
      // 波点胶带
      Stack() {
        Row()
          .width(46)
          .height(13)
          .backgroundColor('#4DE8B7C9')
        Row({ space: 7 }) {
          ForEach([0, 1, 2, 3, 4], (i: number) => {
            Circle()
              .width(4)
              .height(4)
              .fill('#66FFFFFF')
          }, (i: number) => i.toString())
        }
        .margin({ top: 4 })
      }
      .rotate({ angle: -4 })
    }
  }

  @Builder
  ThumbTack() {
    Stack() {
      Circle()
        .width(13)
        .height(13)
        .fill('#E24B4B')
      Circle()
        .width(5)
        .height(5)
        .fill('#FF9E9E')
        .offset({ x: -2, y: -2 })
    }
    .shadow({ radius: 3, color: '#55000000', offsetX: 0, offsetY: 2 })
  }

  @Builder
  CalorieTape() {
    Column({ space: 1 }) {
      // 名称单独一行：挤在一行里会被热量数字和三个圆点挤成「..」
      Text(this.title.length > 0 ? this.title : '食物')
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor('#4A3B1E')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row({ space: 4 }) {
        Text(this.isDemo ? '示例' : (this.mealLabel.length > 0 ? this.mealLabel : '加餐'))
          .fontSize(9)
          .fontColor(this.isDemo ? '#B26A3C' : '#8A7742')
        Text(`${this.kcal}`)
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor('#C2552F')
        Text('kcal')
          .fontSize(8)
          .fontColor('#9A8352')
        Circle().width(5).height(5).fill(DOT_PROTEIN)
        Circle().width(5).height(5).fill(DOT_CARB)
        Circle().width(5).height(5).fill(DOT_FAT)
      }
      .width('100%')
    }
    .width(this.stickerSize + 22)
    .padding({ left: 7, right: 7, top: 3, bottom: 3 })
    .backgroundColor('#FDF5E2')
    .borderRadius(5)
    .shadow({ radius: 4, color: '#33000000', offsetX: 0, offsetY: 2 })
  }

  @Builder
  FrontFace() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 3 }) {
        // 贴纸本体：白边已烘进 PNG，外面不再套白色圆角容器 ——
        // 套了容器就变成「把照片缩进一个方框」，不是剪贴贴纸了。
        Stack() {
          if (this.stickerUri.length > 0) {
            Image(this.stickerUri)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
          } else {
            Image($r('app.media.mascot_cat'))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
              .padding(4)
          }
        }
        .width(this.stickerSize)
        .height(this.stickerSize)
        .shadow({ radius: 7, color: '#40000000', offsetX: 0, offsetY: 3 })

        this.CalorieTape()
      }

      // 顶部装饰：压在贴纸上边缘。
      // 注意 @Builder 的返回值是 void，不能直接在调用后链式写属性 ——
      // 必须包一层容器，margin 挂在容器上。
      if (this.pinType === PinDecorationType.RED_THUMB_TACK) {
        Row() {
          this.ThumbTack()
        }
        .margin({ left: this.stickerSize * 0.5 - 6, top: -4 })
      } else if (this.pinType !== PinDecorationType.NONE) {
        Row() {
          this.WashiTape()
        }
        .margin({ left: this.stickerSize * 0.5 - 23, top: -5 })
      }

      // 心情角标：右下角一枚微缩折角便签
      if (this.moodEmoji.length > 0 || this.memoSummary.length > 0) {
        Stack({ alignContent: Alignment.TopStart }) {
          Row({ space: 2 }) {
            if (this.moodEmoji.length > 0) {
              Text(this.moodEmoji).fontSize(9)
            }
            if (this.memoSummary.length > 0) {
              Text(this.memoSummary)
                .fontSize(8)
                .fontColor('#6B5A2E')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .padding({ left: 4, right: 4, top: 2, bottom: 2 })
          .width(56)
          .backgroundColor('#FFF3C4')
          .borderRadius(3)
          .shadow({ radius: 3, color: '#33000000', offsetX: 0, offsetY: 1 })
        }
        .position({ x: this.stickerSize - 46, y: this.stickerSize - 10 })
      }
    }
    .width(this.stickerSize + 22)
    .height(this.stickerSize + 40)
  }

  /* ------------------------------ 背面 ------------------------------ */

  @Builder
  BackFace() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 4 }) {
        Text(this.title.length > 0 ? this.title : '食物')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isDarkPaper() ? '#F4F1E4' : '#4A3B1E')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 6 }) {
          this.MacroChip('蛋白', this.proteinG, DOT_PROTEIN)
          this.MacroChip('碳水', this.carbsG, DOT_CARB)
          this.MacroChip('脂肪', this.fatG, DOT_FAT)
        }

        if (this.aiAdvice.length > 0) {
          Text(this.aiAdvice)
            .fontSize(9)
            .fontColor(this.isDarkPaper() ? '#C6CFC4' : '#7A6640')
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        if (this.memoSummary.length > 0) {
          Text(this.memoSummary)
            .fontSize(9)
            .fontColor(this.isDarkPaper() ? '#E4E8E2' : '#5A4A2A')
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 14, bottom: 8 })
      .alignItems(HorizontalAlign.Start)

      // 折角
      Path({ width: 14, height: 14 })
        .commands('M0 14 L14 0 L14 14 Z')
        .fill(this.paperFold())
        .position({ x: this.stickerSize - 4, y: this.stickerSize + 6 })
    }
    .width(this.stickerSize + 22)
    .height(this.stickerSize + 40)
    .backgroundColor(this.paperBg())
    .borderRadius(6)
    .shadow({ radius: 7, color: '#40000000', offsetX: 0, offsetY: 3 })
  }

  @Builder
  MacroChip(label: string, grams: number, dot: string) {
    Row({ space: 3 }) {
      Circle().width(5).height(5).fill(dot)
      Text(`${label} ${Math.round(grams)}g`)
        .fontSize(9)
        .fontColor(this.isDarkPaper() ? '#DDE2DC' : '#6B5A2E')
    }
  }

  build() {
    Stack() {
      if (this.flipped) {
        // 容器已经绕 Y 轴转了 180°，背面再自转 180°把镜像抵消
        Stack() {
          this.BackFace()
        }
        .rotate({ angle: 180 })
      } else {
        this.FrontFace()
      }
    }
    .rotate({ x: 0, y: 1, z: 0, angle: this.flipped ? 180 : 0 })
  }
}
