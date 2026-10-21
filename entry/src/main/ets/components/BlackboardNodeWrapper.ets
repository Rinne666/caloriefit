/**
 * 黑板节点的手势外壳。
 *
 * 对应设计方案「难点二：黑板画布上的『贴纸+便签』自由手势矩阵与物理阻尼动效」。
 *
 * ## 手势矩阵
 * `GestureGroup(GestureMode.Parallel, ...)` 同时挂四种识别器：
 *   · 单指平移 —— 拖动贴纸
 *   · 双指捏合 —— 缩放
 *   · 双指旋转 —— 转角度
 *   · 单击 —— 打开详情抽屉
 *
 * ## 为什么用 priorityGesture 而不是 gesture
 * 今日页整体是一个纵向 Scroll。如果用普通 `gesture`，
 * 拖动贴纸时祖先 Scroll 会把手势抢走，贴纸纹丝不动、页面倒是滚起来了。
 * `priorityGesture` 让节点的识别器**优先于祖先**，
 * 于是「按住贴纸拖 = 挪贴纸，按住空白拖 = 滚页面」。
 *
 * ## 为什么位置和缩放要分层
 * 位置（外层 `.position`）和缩放/旋转（内层 `.scale` / `.rotate`）分开：
 * 缩放/旋转挂在带弹簧动画的内层，拖拽时跟手；
 * 位置不挂动画，否则每帧位移都会被动画插值，贴纸会「拖泥带水」甩不掉。
 *
 * ## 单击 / 双击
 * 方案要求「单击弹卡片、双击原地翻转」。
 * ArkUI 里同时挂 count:1 和 count:2 的 TapGesture 会打架，
 * 所以这里自己判双击：第一次点击起一个 280ms 的定时器，
 * 窗口内再点一次就是双击（翻转），否则定时器到点当作单击（开抽屉）。
 */

import { curves } from '@kit.ArkUI';
import { BoardNodeModel } from '../models/BoardModels';

/** 双击判定窗口（毫秒） */
const DOUBLE_TAP_WINDOW: number = 280;

@Component
export struct BlackboardNodeWrapper {
  /** 节点。@ObjectLink：拖动时只有这一个节点刷新，不牵动整块黑板 */
  @ObjectLink node: BoardNodeModel;
  /** 画布宽（vp），用于把节点限制在画布内 */
  @Prop canvasWidth: number = 360;
  /** 画布高（vp） */
  @Prop canvasHeight: number = 380;
  /** 节点自身占位宽（vp） */
  @Prop nodeWidth: number = 104;
  /** 节点自身占位高（vp） */
  @Prop nodeHeight: number = 104;
  /** 点击置顶 */
  onBringToFront: (id: number) => void = () => {};
  /** 打开详情 */
  onOpenNode: (node: BoardNodeModel) => void = () => {};
  /** 变换结束，需要落库 */
  onTransformEnd: (node: BoardNodeModel) => void = () => {};
  /** 翻转 */
  onToggleFlip: (node: BoardNodeModel) => void = () => {};
  /** 节点内容 */
  @BuilderParam content: () => void;

  @State private pressed: boolean = false;
  private startX: number = 0;
  private startY: number = 0;
  private startScale: number = 1;
  private startRotation: number = 0;
  private lastTapAt: number = 0;
  private tapTimer: number = -1;
  /** 最近一次拖拽发生的时间；用来区分「拖完顺手点一下」和「真的要打开抽屉」 */
  private draggedAt: number = 0;

  aboutToDisappear(): void {
    if (this.tapTimer !== -1) {
      clearTimeout(this.tapTimer);
      this.tapTimer = -1;
    }
  }

  private clampX(x: number): number {
    const max = Math.max(0, this.canvasWidth - this.nodeWidth);
    if (x < 0) {
      return 0;
    }
    return x > max ? max : x;
  }

  private clampY(y: number): number {
    const max = Math.max(0, this.canvasHeight - this.nodeHeight);
    if (y < 0) {
      return 0;
    }
    return y > max ? max : y;
  }

  /** 单击 / 双击判定 */
  private handleTap(): void {
    // 刚拖过 → 这次点击是拖拽收尾带出来的，不是「点一下打开抽屉」。
    //
    // ArkUI 的手势竞技场里，PanGesture 先识别成功之后，
    // 同一次按压仍可能补发一次 TapGesture —— 实测把贴纸拖走之后，
    // 编辑抽屉会自己弹出来，挡住整个黑板。
    // 用「最近拖拽时间」把这种尾巴点击挡掉。
    if (Date.now() - this.draggedAt < 400) {
      this.draggedAt = 0;
      return;
    }
    const now = Date.now();
    if (now - this.lastTapAt < DOUBLE_TAP_WINDOW) {
      // 第二次点击：双击 → 原地翻转
      this.lastTapAt = 0;
      if (this.tapTimer !== -1) {
        clearTimeout(this.tapTimer);
        this.tapTimer = -1;
      }
      this.onToggleFlip(this.node);
      return;
    }
    this.lastTapAt = now;
    // 等一等，看有没有第二击
    this.tapTimer = setTimeout(() => {
      this.tapTimer = -1;
      this.onOpenNode(this.node);
    }, DOUBLE_TAP_WINDOW);
  }

  build() {
    Stack() {
      this.content()
    }
    .scale({
      x: this.node.scale * (this.pressed ? 1.06 : 1),
      y: this.node.scale * (this.pressed ? 1.06 : 1)
    })
    .rotate({ angle: this.node.rotation })
    // 缩放/旋转走弹簧，捏起来有「拿在手里」的回弹感
    .animation({ curve: curves.springMotion(0.32, 0.82) })
    .width(this.nodeWidth)
    .height(this.nodeHeight)
    .priorityGesture(
      GestureGroup(GestureMode.Parallel,
        TapGesture({ count: 1 })
          .onAction(() => {
            this.onBringToFront(this.node.id);
            this.handleTap();
          }),
        PanGesture({ fingers: 1, distance: 2 })
          .onActionStart(() => {
            this.pressed = true;
            this.draggedAt = Date.now();
            this.onBringToFront(this.node.id);
            this.startX = this.node.x;
            this.startY = this.node.y;
          })
          .onActionUpdate((event: GestureEvent) => {
            this.node.x = this.clampX(this.startX + event.offsetX);
            this.node.y = this.clampY(this.startY + event.offsetY);
          })
          .onActionEnd(() => {
            this.pressed = false;
            this.onTransformEnd(this.node);
          })
          .onActionCancel(() => {
            this.pressed = false;
          }),
        PinchGesture({ fingers: 2 })
          .onActionStart(() => {
            this.onBringToFront(this.node.id);
            this.startScale = this.node.scale;
          })
          .onActionUpdate((event: GestureEvent) => {
            const next = this.startScale * event.scale;
            this.node.scale = Math.min(2.2, Math.max(0.55, next));
          })
          .onActionEnd(() => {
            this.onTransformEnd(this.node);
          }),
        RotationGesture({ fingers: 2 })
          .onActionStart(() => {
            this.onBringToFront(this.node.id);
            this.startRotation = this.node.rotation;
          })
          .onActionUpdate((event: GestureEvent) => {
            this.node.rotation = this.startRotation + event.angle;
          })
          .onActionEnd(() => {
            this.onTransformEnd(this.node);
          })
      )
    )
    // 位置在**渲染时**再夹一次：
    // 板面宽度随机型变（280~380vp），存下来的位置来自更宽的板面时
    // 直接用会顶出板面。夹取只影响显示，不动存下来的值 ——
    // 换回宽屏时贴纸还回到原来的位置。
    .position({ x: this.clampX(this.node.x), y: this.clampY(this.node.y) })
  }
}
