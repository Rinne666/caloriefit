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

import { color, fontSize, space, radius, layout } from '../common/DesignTokens';
import { HomePage } from './HomePage';
import { ClubPage } from './ClubPage';
import { WaterPage } from './WaterPage';
import { FastingPage } from './FastingPage';

const SUB_TABS: string[] = ['综合', '社群', '饮水', '断食'];
const SUB_ICONS: string[] = ['📊', '👥', '💧', '⏳'];

@Component
export struct HomeTabs {
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

  build() {
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
    .layoutWeight(1)
  }
}
