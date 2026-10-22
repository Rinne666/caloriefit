/**
 * 个人信息保护「双清单」页：已收集清单 / 第三方共享清单。
 *
 * 根节点必须是 NavDestination —— Navigation 才有对象可挂载。
 * 直接放 Scroll 当根节点会「路由推得进去、返回键也出现、内容全白且日志无异常」。
 */

import { color, fontSize, space, pageGradient } from '../common/DesignTokens';
import { PrivacyInventoryContent } from '../components/PrivacyInventoryContent';

export class PrivacyInventoryParams {
  /** 'collected' | 'shared' */
  mode: string = 'collected';
  title: string = '个人信息清单';

  constructor(mode: string, title: string) {
    this.mode = mode;
    this.title = title;
  }
}

@Component
export struct PrivacyInventoryPage {
  @Consume('navStack') navStack: NavPathStack;
  @State private mode: string = 'collected';
  @State private title: string = '个人信息清单';

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
          Text(this.title)
            .fontSize(fontSize.sectionTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.text)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: space.sm, right: space.md, top: space.sm, bottom: space.sm })

        Scroll() {
          PrivacyInventoryContent({ mode: this.mode })
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
    .onReady((ctx: NavDestinationContext) => {
      const p = ctx.pathInfo.param as PrivacyInventoryParams | null | undefined;
      if (p !== null && p !== undefined && typeof p.mode === 'string') {
        this.mode = p.mode;
        this.title = typeof p.title === 'string' ? p.title : '个人信息清单';
      }
    })
  }
}
