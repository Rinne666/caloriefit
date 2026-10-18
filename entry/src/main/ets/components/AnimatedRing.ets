/**
 * 热量进度环（带扫描动画）。
 *
 * 动画怎么做的：
 *   Progress 的 value 不是 ArkUI 的「可动画属性」，所以 `.animation()` 对它无效，
 *   animateTo 也不行。这里改用定时器按帧改写 value ——
 *   36 帧 / 600ms ≈ 60fps，肉眼看是连续扫上去的。
 *
 * 绕这一圈换来的是：颜色仍然走资源限定符，深浅色自动切换不用特殊处理。
 * （曾考虑过 Canvas 自绘圆弧，那样就得先把 ResourceColor 解析成
 *   strokeStyle 能吃的字面量，还要额外处理主题切换时的重绘，
 *   收益不抵复杂度。）
 *
 * 超标时整条转红，对应 NutriScan 实测行为。
 */

import { anim, easeOutCubic } from '../common/Motion';
import { color, layout } from '../common/DesignTokens';

const SWEEP_STEPS: number = 36;

@Component
export struct AnimatedRing {
  /** 已完成比例 0..1，外部负责夹取 */
  @Prop @Watch('startSweep') ratio: number = 0;
  /** 命名避开 CustomComponent 自带的 size 属性 */
  @Prop diameter: number = layout.ringSize;
  @Prop stroke: number = layout.ringStroke;
  @Prop valueColor: ResourceColor = color.primary;
  @Prop trackColor: ResourceColor = color.ringTrack;
  /** 置 true 表示位于主视觉饱和卡上，轨道改用半透明白 */
  @Prop onHero: boolean = false;

  @State private shown: number = 0;
  private timer: number = -1;

  aboutToDisappear(): void {
    this.clearTimer();
  }

  /**
   * 扫描起点。
   *
   * 刻意不叫 onAppear：onAppear 是 CustomComponent 上已存在的
   * `onAppear?: () => void` 属性，自定义方法同名会直接编译失败。
   * 所以起名 startSweep，再在 build() 里用 .onAppear() 修饰符调它。
   */
  startSweep(): void {
    this.clearTimer();
    const to: number = this.ratio > 1 ? 1 : (this.ratio < 0 ? 0 : this.ratio);
    const from: number = this.shown;
    if (!isFinite(to) || Math.abs(to - from) < 0.0005) {
      this.shown = to;
      return;
    }
    const interval: number = Math.max(8, Math.round(anim.dataMs / SWEEP_STEPS));
    let i: number = 0;
    this.timer = setInterval(() => {
      i++;
      const t: number = Math.min(1, i / SWEEP_STEPS);
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

  build() {
    Progress({
      value: Math.max(0, Math.min(this.shown, 1)) * 100,
      total: 100,
      type: ProgressType.Ring
    })
      .width(this.diameter)
      .height(this.diameter)
      .style({ strokeWidth: this.stroke })
      .color(this.valueColor)
      .backgroundColor(this.onHero ? color.heroRingTrack : this.trackColor)
      .onAppear(() => {
        this.startSweep();
      })
  }
}
