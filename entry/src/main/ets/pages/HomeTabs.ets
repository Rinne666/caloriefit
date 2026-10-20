/**
 * 今日页。
 *
 * 产品面向单用户，不提供社群、好友动态或公开资料入口。
 *
 * ⚠ 这里刻意**不用 Tabs**，而是直接渲染内容。
 *   原因是踩过的坑：Tabs 套在 Navigation 的底 Tab 里（Tabs → TabContent →
 *   Tabs → TabContent）会静默废掉导航 —— pushPathByName 照常成功、
 *   返回按钮照常出现，但目标页内容节点始终挂不上树，画面全白且日志无任何异常。
 *   实测 FoodEdit 与 ComingSoon 两个目标页同时中招，去掉内层 Tabs 立刻恢复。
 *
 * 2026-10-20：饮水与断食两个子页已下线（产品决策：聚焦「热量记录 + 今日黑板」）。
 *   原来「综合 / 饮水 / 断食」那排分段药丸随之取消 —— 只剩一个子页时，
 *   分段控件既没有切换语义、也占掉 74vp 的高度，纯属浪费。
 *   底部的「+」记录入口随之常驻显示。
 */

import { color, fontSize, space, radius, layout, glassShadow } from '../common/DesignTokens';
import { HomePage } from './HomePage';
import { FoodEditParams } from './HomePage';
import { toDateKey, parseDateKey, isFutureDate, displayDate } from '../common/DateUtils';

@Component
export struct HomeTabs {
  @Consume('navStack') navStack: NavPathStack;
  @StorageLink('selectedDate') selectedDate: string = '';

  private todayLabel(): string {
    const key = this.selectedDate !== '' ? this.selectedDate : toDateKey(new Date());
    return key === toDateKey(new Date()) ? '今天' : displayDate(key);
  }

  private showDatePicker(): void {
    const key = this.selectedDate !== '' ? this.selectedDate : toDateKey(new Date());
    this.getUIContext().showDatePickerDialog({
      start: new Date(2020, 0, 1),
      end: new Date(2100, 11, 31),
      selected: parseDateKey(key),
      onDateAccept: (value: Date) => {
        const nextKey = toDateKey(value);
        if (isFutureDate(nextKey)) {
          this.getUIContext().getPromptAction().showToast({ message: '不允许查看未来日期' });
          return;
        }
        AppStorage.setOrCreate<string>('selectedDate', nextKey);
      }
    });
  }

  /**
   * 免费版标识。
   *
   * 原版这里是「免费试用 1 周」+ 渐变「升级」两个可点按钮，本项目按产品定位
   * **完全免费**，已整体删除升级/试用入口：没有应用内购买、没有订阅校验、
   * 没有权益墙，所有已实现功能默认全部可用。
   * 这里保留一个不可点的静态标识，让「免费」在界面上是明示的，而不是「少了点什么」。
   */
  @Builder
  FreeBadge() {
    Text('全部功能免费')
      .fontSize(fontSize.caption)
      .fontColor(color.textSecondary)
      .height(32)
      .padding({ left: 12, right: 12 })
      .textAlign(TextAlign.Center)
      .backgroundColor(color.surface)
      .border({ width: 1, color: color.border })
      .borderRadius(radius.pill)
  }

  @Builder
  TodayHeader() {
    Row({ space: space.xs }) {
      Button() {
        Row({ space: 6 }) {
          Text('‹')
            .fontSize(24)
            .fontColor(color.activity)
          Text(this.todayLabel())
            .fontSize(fontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(color.text)
            .maxLines(1)
        }
      }
      .height(36)
      .padding({ left: 12, right: 14 })
      .backgroundColor(color.bg)
      .border({ width: 1, color: color.border })
      .borderRadius(radius.pill)
      .onClick(() => this.showDatePicker())

      Blank().layoutWeight(1)

      this.FreeBadge()
    }
    .width('100%')
    .padding({ left: layout.pagePadding, right: layout.pagePadding, top: 8, bottom: 8 })
  }

  /**
   * 悬浮「+」记录入口 —— 对应原版 Home 的浮动加号。
   *
   * 原本只在「综合」子页显示；子页取消后它常驻。
   */
  @Builder
  Fab() {
    Button('+')
      .width(64)
      .height(64)
      .fontSize(34)
      .fontColor(Color.White)
      .backgroundColor(color.activity)
      .borderRadius(32)
      .shadow(glassShadow(12, 4))
      // 原版的蓝色餐食记录按钮停在内容区右下，紧挨底栏上沿。
      .margin({ right: 20, bottom: 0 })
      .onClick(() => {
        this.navStack.pushPathByName('FoodEdit',
          new FoodEditParams('add', AppStorage.get<string>('selectedDate') ?? '', -1));
      })
  }

  build() {
    // Stack 默认居中对齐，这里必须显式指定 BottomEnd，FAB 才会贴到右下。
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        this.TodayHeader()

        HomePage()
      }
      .width('100%')
      .height('100%')

      this.Fab()
    }
    .width('100%')
    .height('100%')
  }
}
