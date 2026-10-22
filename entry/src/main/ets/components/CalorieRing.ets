/**
 * 热量进度环：环居中 + 中央数字滚动 + 剩余/超标文案切换。
 *
 * 对应 NutriScan 首页的主视觉：环是页面第一眼落点，
 * 中央数字必须跟着环一起走，否则会出现「环还在长、数字已经停」的割裂。
 *
 * ⚠ 这里刻意用普通方法而不是 `private get`：
 *   ArkUI 的 @Component struct 中 `private get` 求值不可靠，
 *   曾返回 NaN 导致 .height(NaN) 静默不渲染。WeekSparkline / MacroBar
 *   都踩过同一个坑，全项目现在已无 `private get`。
 *
 * onHero：置于主视觉饱和卡上时，轨道与文字改用白色系 ——
 * 那张卡在浅色主题下也是深色饱和底，跟随主题的 text/ringTrack 压在上面会糊掉。
 */

import { color, fontSize, layout } from '../common/DesignTokens';
import { AnimatedRing } from './AnimatedRing';
import { AnimatedNumber } from './AnimatedNumber';

@Component
export struct CalorieRing {
  @Prop consumed: number;
  @Prop budget: number;
  @Prop onHero: boolean = false;

  private over(): boolean {
    return this.consumed > this.budget;
  }

  /** 环的完成比例，超标时封顶 1 —— 溢出量由中央文案表达，不靠环长出边界 */
  private ratio(): number {
    const b: number = this.budget > 0 ? this.budget : 1;
    return Math.max(0, Math.min(1, this.consumed / b));
  }

  private remain(): number {
    return Math.max(0, this.budget - this.consumed);
  }

  build() {
    Stack() {
      AnimatedRing({
        ratio: this.ratio(),
        onHero: this.onHero
      })

      Column({ space: 4 }) {
        if (this.over()) {
          AnimatedNumber({
            target: this.consumed - this.budget,
            textSize: fontSize.metric,
            textColor: color.danger
          })
          Text('kcal')
            .fontSize(fontSize.secondary)
            .fontColor(this.onHero ? '#CCFFFFFF' : color.textSecondary)
        } else {
          AnimatedNumber({
            target: this.remain(),
            textSize: fontSize.hero,
            textColor: this.onHero ? '#FFFFFF' : color.text
          })
          Text('剩余预算 kcal')
            .fontSize(fontSize.secondary)
            .fontColor(this.onHero ? '#CCFFFFFF' : color.textSecondary)
        }
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .width(layout.ringSize)
    .height(layout.ringSize)
  }
}
