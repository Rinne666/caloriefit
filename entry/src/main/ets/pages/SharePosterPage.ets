/**
 * 今日手帐分享卡预览（独立路由页）。
 *
 * 对应设计方案「SharePosterDialog：用 componentSnapshot 截取黑板画布生成手帐分享海报」。
 *
 * ## 为什么是独立路由页，不是页内覆盖层
 * 之前预览是黑板组件里的一个覆盖层，有三个问题：
 *   1. 覆盖层只在黑板组件范围内，首页的 FAB 与底栏仍**盖在它上面**；
 *   2. 长画布的预览高度失控，「关闭」按钮被挤出可见区域，用户退不出；
 *   3. 页内覆盖层收不到系统返回键，按返回会**直接退出应用**。
 * 独立 NavDestination 这三条全解决：整屏、底部固定操作栏、返回键由 Navigation 接管。
 *
 * ## 只做应用内预览，不导出到相册
 * 导出到相册需要 `ohos.permission.WRITE_IMAGEVIDEO`，而这个 App 对隐私披露有严格要求
 * （见 models/PrivacyInventory.ets 与两份隐私清单页）：新增一个「写入相册」的能力
 * 就得同步改三处披露文本并升版本号。
 * 分享卡本身是**用户自己屏幕上的内容**，没有外发的必要，
 * 所以这里只做「生成 + 应用内预览 + 存进沙箱」，不引入相册权限。
 * 想要图片的话，系统截图同样可用。
 */

/** 路由参数（与 components/BlackboardView.ets 的 BoardPosterParams 结构一致） */
class SharePosterParams {
  posterUri: string = '';
  savedPath: string = '';

  constructor(posterUri: string, savedPath: string) {
    this.posterUri = posterUri;
    this.savedPath = savedPath;
  }
}

@Component
export struct SharePosterPage {
  @Consume('navStack') navStack: NavPathStack;
  /** 分享卡图片（base64 data URI） */
  @State private posterUri: string = '';
  /** 已保存到沙箱的路径 */
  @State private savedPath: string = '';

  /**
   * 预览图的最大高度（vp）。
   *
   * 不限高的话，长画布（一天十几条记录时画布会长到 1000vp 以上）
   * 会把下面的「关闭」按钮顶出屏幕 —— 用户看得到图，却退不出去。
   */
  private static readonly POSTER_MAX_H: number = 460;

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        Scroll() {
          Column({ space: 10 }) {
            if (this.posterUri.length > 0) {
              Image(this.posterUri)
                .width('100%')
                .constraintSize({ maxHeight: SharePosterPage.POSTER_MAX_H })
                .objectFit(ImageFit.Contain)
                .borderRadius(10)
                .shadow({ radius: 8, color: '#33000000', offsetX: 0, offsetY: 4 })
            } else {
              Text('没有可预览的分享卡')
                .fontSize(13)
                .fontColor('#8A7742')
            }

            Text(this.savedPath.length > 0 ? `已保存到：${this.savedPath}` : '')
              .fontSize(10)
              .fontColor('#8A7742')
              .width('100%')
              .maxLines(3)

            Text('分享卡只在本机生成与预览，不会发送到任何服务器。')
              .fontSize(10)
              .fontColor('#A08A55')
              .width('100%')
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12 })
        }
        // Scroll 占满剩余空间，按钮固定在底部 —— 无论画布多长都点得到
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)

        Button('关闭')
          .fontSize(13)
          .height(40)
          .width('88%')
          .backgroundColor('#C2552F')
          .fontColor('#FFFFFF')
          .margin({ bottom: 18 })
          .onClick(() => {
            this.navStack.pop();
          })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FFF8E7')
    }
    .title('今日手帐分享卡')
    .backgroundColor('#FFF8E7')
    .onReady((ctx: NavDestinationContext) => {
      const p = ctx.pathInfo.param as SharePosterParams | null | undefined;
      if (p !== null && p !== undefined) {
        this.posterUri = p.posterUri;
        this.savedPath = p.savedPath;
      }
    })
  }
}
