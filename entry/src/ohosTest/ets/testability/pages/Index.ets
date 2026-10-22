@Entry
@Component
struct Index {
  @State message: string = 'CalorieFit 单元测试运行中';

  build() {
    Row() {
      Column() {
        Text(this.message)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
    }
    .height('100%')
  }
}
