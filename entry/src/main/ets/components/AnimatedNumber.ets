/**
 * 数字滚动 —— 从旧值缓动到新值。
 *
 * 为什么不用 `.animation()`：
 *   隐式动画只能插值「可动画属性」（宽高透明度之类），
 *   Text 的**内容**不是可动画属性，状态一变文字就跳变。
 *   所以只能自己按帧插值。
 *
 * 为什么不用 animateTo：
 *   同上。animateTo 也只对可动画属性生效。
 *
 * 缓动用 easeOutCubic 手写公式而不是曲线 API ——
 * 我们要的是「任意两数之间的中间值」，不是「某属性的插值」。
 *
 * 帧数固定 24（≈34fps）：再密看不出差别，只是白烧电。
 */

import { anim, easeOutCubic } from '../common/Motion';
import { color } from '../common/DesignTokens';
import { formatNumber } from '../common/DateUtils';

@Component
export struct AnimatedNumber {
  /** 目标值 */
  @Prop @Watch('startCount') target: number = 0;
  /** 小数位；0 表示整数 */
  @Prop decimals: number = 0;
  @Prop textSize: number = 26;
  @Prop weight: FontWeight = FontWeight.Bold;
  @Prop textColor: ResourceColor = color.text;

  @State private shown: number = 0;
  private timer: number = -1;

  aboutToDisappear(): void {
    this.clearTimer();
  }

  /**
   * 滚动起点。
   *
   * 不叫 onAppear：那是 CustomComponent 上已存在的 onAppear?: () => void 属性，
   * 自定义方法同名会编译失败。起名 startCount，在 build() 里用修饰符调。
   */
  startCount(): void {
    this.clearTimer();
    if (!isFinite(this.target)) {
      this.shown = 0;
      return;
    }
    const from: number = this.shown;
    const to: number = this.target;
    if (Math.abs(to - from) < 0.0001) {
      this.shown = to;
      return;
    }
    const steps: number = anim.countSteps;
    const interval: number = Math.max(8, Math.round(anim.countMs / steps));
    let i: number = 0;
    this.timer = setInterval(() => {
      i++;
      const t: number = Math.min(1, i / steps);
      this.shown = from + (to - from) * easeOutCubic(t);
      if (t >= 1) {
        this.clearTimer();
      }
    }, interval);
  }

  private clearTimer(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private display(): string {
    if (this.decimals === 0) {
      // 必须走 formatNumber 而不是直接 Math.round().toString() ——
      // 后者会把 1580 显示成 "1580"，而全 App 其他数字都带千分位，
      // 同一个页面里两种写法会明显对不上。
      return formatNumber(this.shown);
    }
    return this.shown.toFixed(this.decimals);
  }

  build() {
    Text(this.display())
      .fontSize(this.textSize)
      .fontWeight(this.weight)
      .fontColor(this.textColor)
      .onAppear(() => {
        this.startCount();
      })
  }
}
