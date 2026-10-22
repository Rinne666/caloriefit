import { color, fontSize, space, pageGradient } from '../common/DesignTokens';
import { PrivacyPolicyContent } from '../components/PrivacyPolicyContent';

@Component
export struct PrivacyPolicyPage {
  @Consume('navStack') navStack: NavPathStack;

  build() {
    NavDestination() {
      Column() {
        Row({ space: space.sm }) {
          Button('‹')
            .width(42)
            .height(42)
            .fontSize(30)
            .fontColor(color.text)
            .backgroundColor(Color.Transparent)
            .onClick(() => this.navStack.pop())
          Text('隐私政策')
            .fontSize(fontSize.sectionTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.text)
        }
        .width('100%')
        .padding({ left: space.sm, right: space.md, top: space.sm, bottom: space.sm })

        Scroll() {
          PrivacyPolicyContent()
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(color.bg)
      .linearGradient(pageGradient())
    }
    .hideTitleBar(true)
    .backgroundColor(color.bg)
  }
}
