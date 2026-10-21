/**
 * 手帐分享卡预览。
 *
 * 对应设计方案「SharePosterDialog：用 componentSnapshot 截取黑板画布生成手帐分享海报」。
 *
 * ## 只做应用内预览，不导出到相册
 * 导出到相册需要 `ohos.permission.WRITE_IMAGEVIDEO`，而这个 App 对隐私披露有严格要求
 * （见 models/PrivacyInventory.ets 与两份隐私清单页）：新增一个「写入相册」的能力
 * 就得同步改三处披露文本并升版本号。
 * 分享卡本身是**用户自己屏幕上的内容**，没有外发的必要，
 * 所以这里只做「生成 + 应用内预览 + 存进沙箱」，不引入相册权限。
 * 想要图片的话，系统截图同样可用。
 */

@Component
export struct SharePosterDialog {
  /** 分享卡图片（base64 data URI） */
  @Prop posterUri: string = '';
  /** 已保存到沙箱的路径 */
  @Prop savedPath: string = '';
  /** 关闭 */
  onClose: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 10 }) {
        Text('今日手帐分享卡')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#4A3B1E')
          .width('100%')

        if (this.posterUri.length > 0) {
          Image(this.posterUri)
            .width('100%')
            .objectFit(ImageFit.Contain)
            .borderRadius(10)
            .shadow({ radius: 8, color: '#33000000', offsetX: 0, offsetY: 4 })
        }

        Text(this.savedPath.length > 0 ? `已保存到：${this.savedPath}` : '')
          .fontSize(10)
          .fontColor('#8A7742')
          .width('100%')
          .maxLines(2)

        Text('分享卡只在本机生成与预览，不会发送到任何服务器。')
          .fontSize(10)
          .fontColor('#A08A55')
          .width('100%')

        Button('关闭')
          .fontSize(13)
          .height(36)
          .width('100%')
          .backgroundColor('#C2552F')
          .fontColor('#FFFFFF')
          .onClick(() => this.onClose())
      }
      .padding(16)
      .width('86%')
      .backgroundColor('#FFF8E7')
      .borderRadius(16)
      .shadow({ radius: 20, color: '#55000000', offsetX: 0, offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
  }
}
