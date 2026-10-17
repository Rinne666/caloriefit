/**
 * 热量进度环：168×168，环宽 12，中央显示剩余预算；超标显示红色“超出”。
 */

import { color, fontSize, layout, radius } from '../common/DesignTokens';
import { formatNumber } from '../common/DateUtils';

@Component
export struct CalorieRing {
  @Prop consumed: number;
  @Prop budget: number;

  build() {
    Stack() {
      Progress({
        value: Math.min(this.consumed, this.budget),
        total: this.budget > 0 ? this.budget : 1,
        type: ProgressType.Ring
      })
        .width(layout.ringSize)
        .height(layout.ringSize)
        .style({ strokeWidth: layout.ringStroke })
        .color(color.primary)
        .backgroundColor(color.ringTrack)

      Column({ space: 4 }) {
        if (this.consumed > this.budget) {
          Text(`超出 ${formatNumber(this.consumed - this.budget)}`)
            .fontSize(fontSize.metric)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.danger)
          Text('kcal')
            .fontSize(fontSize.secondary)
            .fontColor(color.textSecondary)
        } else {
          Text(formatNumber(this.budget - this.consumed))
            .fontSize(fontSize.hero)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.text)
          Text('剩余预算 kcal')
            .fontSize(fontSize.secondary)
            .fontColor(color.textSecondary)
        }
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
  }
}