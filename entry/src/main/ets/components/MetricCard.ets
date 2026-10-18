/**
 * 统计卡片：标题 + 大数字 + 单位 + 自绘线性进度条。
 * 组件不访问数据库，只接受数据。
 *
 * V4：外壳换成玻璃层，色调用 title 做种子 ——
 * 于是同一行里的「步数」和「运动时长」自动是两个不同色调，
 * 而调色板、圆角、排版完全一致，这就是「统一但不重复」。
 */

import {
  color, fontSize, space, layout,
  glass, glassGradient, glassShadow, toneVeil
} from '../common/DesignTokens';

@Component
export struct MetricCard {
  @Prop title: string;
  @Prop valueText: string;
  @Prop unit: string;
  @Prop progress: number;
  @Prop barColor: ResourceColor = color.primary;
  @Prop goalText: string = '';

  build() {
    Column({ space: space.xs }) {
      Text(this.title)
        .fontSize(fontSize.secondary)
        .fontColor(color.textSecondary)

      Row({ space: 4 }) {
        Text(this.valueText)
          .fontSize(fontSize.metric)
          .fontWeight(FontWeight.Bold)
          .fontColor(color.text)
        Text(this.unit)
          .fontSize(fontSize.caption)
          .fontColor(color.textHint)
          .margin({ bottom: 4 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      if (this.goalText.length > 0) {
        Text(this.goalText)
          .fontSize(fontSize.caption)
          .fontColor(color.textHint)
          .width('100%')
      }

      // 自绘线性进度条：轨道 + 填充
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(layout.progressHeight)
          .borderRadius(layout.progressHeight / 2)
          .backgroundColor(color.ringTrack)

        Row()
          .width(`${Math.min(100, this.progress * 100)}%`)
          .height(layout.progressHeight)
          .borderRadius(layout.progressHeight / 2)
          .backgroundColor(this.barColor)
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(layout.cardPadding)
    .linearGradient(glassGradient(toneVeil(this.title)))
    .borderRadius(glass.cardRadius)
    .border({ width: glass.borderWidth, color: color.glassBorder })
    .backdropBlur(glass.blurRadius)
    .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
  }
}
