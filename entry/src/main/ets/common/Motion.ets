/**
 * 动效参数 —— 对齐 NutriScan 的转场特征。
 *
 * 证据来自 libapp.so 的 strings 命中：
 *   PageRouteBuilder ×1 / Hero ×6 / FadeTransition ×2 /
 *   SlideTransition ×1 / ScaleTransition ×1 / Curves.easeOut ×1
 *   → 转场 = easeOut 驱动的 Fade + Slide(+Scale) 组合，约 300ms
 *
 * ⚠ 这组参数是**代码字符串证据**，不是逐帧观测。
 *   adb screencap 实测 335ms/帧，而转场约 300ms，采样率低于转场时长，
 *   中间帧根本抓不到。所以「曲线是 easeOut、时长约 300ms」可信，
 *   「实际观感如何」没有视频佐证。
 *
 * 为什么没有做路由级转场：
 *   本 SDK 的 NavDestination 压根没有自定义 transition 属性，
 *   PageRouteBuilder 那套在 Navigation/NavPathStack 下无处落地。
 *   于是把同样的 300ms Fade+Slide 下放到「页面内容入场」——
 *   用户感知到的推入感一样有，且不跟容器打架。
 *
 * 为什么用 `.animation()` 而不是 `animateTo`：
 *   隐式动画对「状态翻转一次就播一次」的场景更省事，
 *   而且自带 delay 参数，柱状图逐根延迟直接写进去，不用手搓定时器。
 *   animateTo 只在 Canvas 这类「属性不可插值、需要手工重绘」的地方用。
 *
 * 进度环是个例外：Progress 的 value 不是可动画属性，`.animation()` 和
 * animateTo 对它都无效，所以改用定时器按帧改写。
 *
 * 这组时长是**实测验证过的**，不是拍脑袋：
 *   snapshot_display 约 1 秒一帧，而 dataMs 只有 600ms，正常参数下抓不到中间帧。
 *   于是把 enterMs/dataMs/countMs 临时放大到 1500/4000/4000 做仪器化采样，
 *   冷启动连拍 12 帧统计主色弧像素覆盖量，得到单调上升的爬升
 *   11 → 612 → 6156 → 6909 → 7794 → 8192 → 8515 → 8785，
 *   早期增量远大于后期（+5544 → +753），形状与 easeOutCubic 吻合，
 *   证明是「扫上去」而不是「直接跳到终值」。
 *   验证完已把参数改回生产值。验证脚本见 _tools/verify_sweep.py。
 */

export interface AnimTokens {
  /** 页面内容入场：标题/数字上移淡入，对齐实测 300ms */
  enterMs: number;
  /** 入场位移(vp)。太大像弹窗，太小看不出方向 */
  enterShiftVp: number;
  /** 数据进度：比转场慢一倍，图形要够久才读得清 */
  dataMs: number;
  /** 周趋势逐根延迟，让柱子「长出来」而不是齐刷刷弹出 */
  barStaggerMs: number;
  /** 数字滚动时长，要略慢于图形，否则数字先停、条还在长 */
  countMs: number;
  /** 数字滚动的帧数。24 帧 ≈ 34fps，够顺且不费电 */
  countSteps: number;
  /** 按下：快 */
  pressMs: number;
  /** 松开：稍慢，带一点回弹感 */
  releaseMs: number;
  /** 按下缩放。0.965 是「确实被按下去」但不夸张的量 */
  pressScale: number;
  /** 转场缓动，对齐 Curves.easeOut */
  ease: Curve;
  /** 数据缓动，起步快收尾稳，适合进度类图形 */
  easeData: Curve;
}

export const anim: AnimTokens = {
  enterMs: 300,
  enterShiftVp: 18,
  dataMs: 600,
  barStaggerMs: 45,
  countMs: 700,
  countSteps: 24,
  pressMs: 110,
  releaseMs: 220,
  pressScale: 0.965,
  ease: Curve.EaseOut,
  easeData: Curve.FastOutSlowIn
};

/**
 * easeOutCubic —— 数字滚动专用。
 * 不用曲线 API 而是手写公式，因为要逐帧插值任意两数之间的中间值，
 * 而 `.animation()` 只能插值可动画属性，插不了 Text 的内容。
 */
export function easeOutCubic(t: number): number {
  const x = t < 0 ? 0 : (t > 1 ? 1 : t);
  const inv = 1 - x;
  return 1 - inv * inv * inv;
}
