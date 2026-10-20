/**
 * 统计卡片：标题 + 大数字 + 单位 + 自绘线性进度条。
 * 组件不访问数据库，只接受数据。
 *
 * 卡片面与描边统一走主题 token，不随标题改变色调。
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
  @Prop sourceLabel: string = '';

  build() {
    Column({ space: space.xs }) {
      Row({ space: space.xs }) {
        Text(this.title)
          .fontSize(fontSize.secondary)
          .fontColor(color.textSecondary)
          .layoutWeight(1)

        if (this.sourceLabel.length > 0) {
          Text(this.sourceLabel)
            .fontSize(fontSize.caption)
            .fontColor(color.textHint)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor(color.surfaceMuted)
            .borderRadius(8)
        }
      }
      .width('100%')

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
    .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
  }
}
