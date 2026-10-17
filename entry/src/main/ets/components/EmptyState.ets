/**
 * 统一空状态提示
 */

import { color, fontSize, space, radius, layout } from '../common/DesignTokens';

@Component
export struct EmptyState {
  @Prop message: string;
  @Prop buttonText: string = '';
  onAction: () => void = () => {};

  build() {
    Column({ space: space.md }) {
      Text(this.message)
        .fontSize(fontSize.body)
        .fontColor(color.textHint)

      if (this.buttonText.length > 0) {
        Button(this.buttonText)
          .height(layout.buttonHeight)
          .fontSize(fontSize.body)
          .fontColor(color.onPrimary)
          .backgroundColor(color.primary)
          .borderRadius(radius.large)
          .onClick(() => {
            this.onAction();
          })
      }
    }
    .width('100%')
    .padding(layout.cardPadding * 2)
    .backgroundColor(color.surface)
    .borderRadius(radius.card)
    .border({ width: layout.borderWidth, color: color.border })
    .alignItems(HorizontalAlign.Center)
  }
}