/**
 * 页内浮层的返回键登记处。
 *
 * ## 为什么需要它
 * 系统返回键只派发给 **@Entry 组件**（本项目是 Index.ets）。
 * 页内的浮层（Report 占位、分享预览、未实现说明）自己收不到 onBackPress，
 * 于是用户按返回会**直接退出应用** —— 浮层还开着，人却回到了桌面。
 *
 * 之前 PrivacyConsentPage 在组件里写了 onBackPress，但组件不是 @Entry，
 * 拿不到派发 —— 这类浮层必须由 @Entry 统一接管。
 *
 * ## 用法
 *   打开浮层：const id = OverlayBackHandler.push(() => { this.xxxVisible = false; });
 *   关闭浮层：OverlayBackHandler.remove(id);
 *
 * 登记的是「怎么关自己」的回调，@Entry 收到返回键时按登记顺序
 * 从上往下关掉最上面那个，返回 true 表示已处理，系统不再往下传。
 */

/** 一个已登记的浮层 */
class OverlayEntry {
  id: number = 0;
  closer: () => void = () => {};

  constructor(id: number, closer: () => void) {
    this.id = id;
    this.closer = closer;
  }
}

export class OverlayBackHandler {
  private static nextId: number = 1;
  private static entries: OverlayEntry[] = [];

  /** 登记一个浮层，返回它的 id（关闭时要用这个 id 注销） */
  static push(closer: () => void): number {
    const id = OverlayBackHandler.nextId;
    OverlayBackHandler.nextId = OverlayBackHandler.nextId + 1;
    OverlayBackHandler.entries.push(new OverlayEntry(id, closer));
    return id;
  }

  /** 注销一个浮层（浮层自己关掉时调用） */
  static remove(id: number): void {
    for (let i = OverlayBackHandler.entries.length - 1; i >= 0; i--) {
      if (OverlayBackHandler.entries[i].id === id) {
        OverlayBackHandler.entries.splice(i, 1);
        return;
      }
    }
  }

  /** 当前有没有浮层开着 */
  static hasOpen(): boolean {
    return OverlayBackHandler.entries.length > 0;
  }

  /**
   * 关掉最上面那个浮层。
   *
   * @return true 表示这次返回键已被处理（系统不该再退出应用）
   */
  static closeTop(): boolean {
    if (OverlayBackHandler.entries.length === 0) {
      return false;
    }
    const top = OverlayBackHandler.entries.pop();
    if (top === undefined) {
      return false;
    }
    try {
      top.closer();
    } catch (e) {
      // 关浮层失败不该让返回键变成「退出应用」
    }
    return true;
  }
}
