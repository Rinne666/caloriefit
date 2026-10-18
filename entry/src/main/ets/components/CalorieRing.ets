/**
 * 热量进度环：168×168，环宽 12，中央显示剩余预算；超标显示红色“超出”。
 *
 * V4：新增 onHero。主视觉卡是恒定深色饱和底，跟随主题的
 * color.text / color.ringTrack 在上面会糊掉，所以那一档改用白字
 * 与半透明白轨道；品牌色仍作填充 —— 荧光绿压蓝紫底是对比最强的一组。
 */

import { color, fontSize, layout } from '../common/DesignTokens';
import { formatNumber } from '../common/DateUtils';

@Component
export struct CalorieRing {
  @Prop consumed: number;
  @Prop budget: number;
  /** 置于主视觉饱和卡上时置 true：轨道与文字改用白色系 */
  @Prop onHero: boolean = false;

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
        .backgroundColor(this.onHero ? '#33FFFFFF' : color.ringTrack)

      Column({ space: 4 }) {
        if (this.consumed > this.budget) {
          Text(`超出 ${formatNumber(this.consumed - this.budget)}`)
            .fontSize(fontSize.metric)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.danger)
          Text('kcal')
            .fontSize(fontSize.secondary)
            .fontColor(this.onHero ? '#CCFFFFFF' : color.textSecondary)
        } else {
          Text(formatNumber(this.budget - this.consumed))
            .fontSize(fontSize.hero)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.onHero ? '#FFFFFF' : color.text)
          Text('剩余预算 kcal')
            .fontSize(fontSize.secondary)
            .fontColor(this.onHero ? '#CCFFFFFF' : color.textSecondary)
        }
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
  }
}