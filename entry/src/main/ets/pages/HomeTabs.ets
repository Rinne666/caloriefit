/**
 * 今日页的子页宿主：综合 / 社群 / 饮水 / 断食。
 *
 * 对应 NutriScan 的 Home 四个子页（Overall / Club / Water / Fasting）。
 * 真机截图里它们是横排的图标+文字、选中项带圆角高亮框。
 *
 * ⚠ 这里刻意**不用 Tabs**，而是自己画分段控件 + 条件渲染。
 *   原因是踩过的坑：Tabs 套在 Navigation 的底 Tab 里（Tabs → TabContent →
 *   Tabs → TabContent）会静默废掉导航 —— pushPathByName 照常成功、
 *   返回按钮照常出现，但目标页内容节点始终挂不上树，画面全白且日志无任何异常。
 *   实测 FoodEdit 与 ComingSoon 两个目标页同时中招，去掉内层 Tabs 立刻恢复。
 *   而且原版本来就是分段药丸而不是可滑动 Tab，手写控件反而更贴近。
 */

import { color, fontSize, space, radius, layout, glassShadow, buttonGlow } from '../common/DesignTokens';
import { HomePage } from './HomePage';
import { ClubPage } from './ClubPage';
import { WaterPage } from './WaterPage';
import { FastingPage } from './FastingPage';
import { FoodEditParams } from './HomePage';

const SUB_TABS: string[] = ['综合', '社群', '饮水', '断食'];
const SUB_ICONS: string[] = ['📊', '👥', '💧', '⏳'];

@Component
export struct HomeTabs {
  @Consume('navStack') navStack: NavPathStack;
  @State private current: number = 0;

  private iconFor(i: number): string {
    return i >= 0 && i < SUB_ICONS.length ? SUB_ICONS[i] : '•';
  }

  @Builder
  SubBar(label: string, index: number) {
    Column({ space: 2 }) {
      Text(this.iconFor(index))
        .fontSize(20)
      Text(label)
        .fontSize(fontSize.caption)
        .fontColor(this.current === index ? color.primary : color.textSecondary)
        .maxLines(1)
    }
    // 固定宽度而非百分比：父容器是 Row 的自然宽度，
    // 百分比在这里会塌缩到内容宽度，中文标签会被挤成竖排。
    .width(76)
    .height(58)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.current === index ? color.glassFill : Color.Transparent)
    .borderRadius(radius.medium)
    .onClick(() => {
      this.current = index;
    })
  }

  /**
   * 悬浮「+」记录入口 —— 对应原版 Home 的浮动加号。
   *
   * 放在 HomeTabs 而不是 HomePage，是为了四个子页都能直接记录，
   * 不必先切回「综合」。
   */
  @Builder
  Fab() {
    Button('+')
      .width(58)
      .height(58)
      .fontSize(30)
      .fontColor(color.onPrimary)
      .backgroundColor(color.primary)
      .borderRadius(29)
      .shadow(glassShadow(16, 8))
      // 抬高到内容上方：贴着底部会压住「记录运动」按钮。
      // 悬浮按钮本来就该盖在内容上，滚动时下方的卡片从它底下过去。
      .margin({ right: 20, bottom: 130 })
      .onClick(() => {
        this.navStack.pushPathByName('FoodEdit',
          new FoodEditParams('add', AppStorage.get<string>('selectedDate') ?? '', -1));
      })
  }

  build() {
    // Stack 默认居中对齐，这里必须显式指定 BottomEnd，FAB 才会贴到右下。
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        Row() {
          ForEach(SUB_TABS, (label: string, i: number) => {
            this.SubBar(label, i)
          }, (label: string, i: number) => label + i)
        }
        .width('100%')
        .padding({ top: 6, bottom: 6, left: 6, right: 6 })
        .justifyContent(FlexAlign.Center)

        if (this.current === 0) {
          HomePage()
        } else if (this.current === 1) {
          ClubPage()
        } else if (this.current === 2) {
          WaterPage()
        } else {
          FastingPage()
        }
      }
      .width('100%')
      .height('100%')

      this.Fab()
    }
    .width('100%')
    .height('100%')
  }
}
