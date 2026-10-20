/**
 * 统一空状态提示
 *
 * 空状态沿用页面的平面卡片材质，按钮使用品牌强调色。
 */

import {
  color, fontSize, space, layout,
  glass, glassGradient, glassShadow,
  primaryButtonGradient, buttonGlow
} from '../common/DesignTokens';

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
        .textAlign(TextAlign.Center)

      if (this.buttonText.length > 0) {
        Button(this.buttonText)
          .height(layout.buttonHeight)
          .fontSize(fontSize.body)
          .fontColor(color.onPrimary)
          .linearGradient(primaryButtonGradient())
          .borderRadius(14)
          .shadow(buttonGlow())
          .onClick(() => {
            this.onAction();
          })
      }
    }
    .width('100%')
    .padding(layout.cardPadding * 2)
    .linearGradient({
      angle: 160,
      colors: [[color.glassFillStrong, 0], [color.glassFill, 1]]
    })
    .borderRadius(glass.cardRadius)
    .border({ width: glass.borderWidth, color: color.glassBorder })
    .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
    .alignItems(HorizontalAlign.Center)
  }
}
