/**
 * 统计卡片：标题 + 大数字 + 单位 + 自绘线性进度条。
 * 组件不访问数据库，只接受数据。
 */

import { color, fontSize, space, radius, layout } from '../common/DesignTokens';

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

      Row({ space: space.xxs }) {
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
    .padding(layout.cardPadding)
    .backgroundColor(color.surface)
    .borderRadius(radius.card)
    .border({ width: layout.borderWidth, color: color.border })
  }
}