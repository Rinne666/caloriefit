/**
 * 今日页的个人记录子页：综合 / 饮水 / 断食。
 *
 * 产品面向单用户，不提供社群、好友动态或公开资料入口。
 * 子页切换沿用横排图标+文字、选中项带圆角高亮框的样式。
 *
 * ⚠ 这里刻意**不用 Tabs**，而是自己画分段控件 + 条件渲染。
 *   原因是踩过的坑：Tabs 套在 Navigation 的底 Tab 里（Tabs → TabContent →
 *   Tabs → TabContent）会静默废掉导航 —— pushPathByName 照常成功、
 *   返回按钮照常出现，但目标页内容节点始终挂不上树，画面全白且日志无任何异常。
 *   实测 FoodEdit 与 ComingSoon 两个目标页同时中招，去掉内层 Tabs 立刻恢复。
 *   而且原版本来就是分段药丸而不是可滑动 Tab，手写控件反而更贴近。
 */

import { color, fontSize, space, radius, layout, glassShadow } from '../common/DesignTokens';
import { HomePage } from './HomePage';
import { WaterPage } from './WaterPage';
import { FastingPage } from './FastingPage';
import { FoodEditParams } from './HomePage';
import { toDateKey, parseDateKey, isFutureDate, displayDate } from '../common/DateUtils';

const SUB_TABS: string[] = ['综合', '饮水', '断食'];

@Component
export struct HomeTabs {
  @Consume('navStack') navStack: NavPathStack;
  @StorageLink('selectedDate') selectedDate: string = '';
  @State private current: number = 0;
  onSubPageChange: (index: number) => void = (_index: number) => {};

  private tabTint(i: number): ResourceColor {
    return this.current === i ? color.text : color.textHint;
  }

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
      if (this.current === 0) {
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
      }

      Blank().layoutWeight(1)

      this.FreeBadge()
    }
    .width('100%')
    .padding({ left: layout.pagePadding, right: layout.pagePadding, top: 8, bottom: 8 })
  }

  /** 三个个人记录子 Tab 使用单色图标，不使用彩色 emoji。 */
  @Builder
  SubGlyph(index: number) {
    if (index === 0) {
      Image($r('app.media.home_food_bowl'))
        .width(24)
        .height(24)
        .fillColor(this.tabTint(index))
    } else if (index === 1) {
      if (this.current === index) {
        SymbolGlyph($r('sys.symbol.drop_fill'))
          .fontSize(24)
          .fontColor([this.tabTint(index)])
      } else {
        SymbolGlyph($r('sys.symbol.drop'))
          .fontSize(24)
          .fontColor([this.tabTint(index)])
      }
    } else if (this.current === index) {
      SymbolGlyph($r('sys.symbol.stopwatch_fill'))
        .fontSize(24)
        .fontColor([this.tabTint(index)])
    } else {
      SymbolGlyph($r('sys.symbol.stopwatch'))
        .fontSize(24)
        .fontColor([this.tabTint(index)])
    }
  }

  @Builder
  SubBar(label: string, index: number) {
    Column({ space: 2 }) {
      this.SubGlyph(index)
      Text(label)
        .fontSize(fontSize.secondary)
        .fontColor(this.tabTint(index))
        .maxLines(1)
    }
    .layoutWeight(1)
    .height(68)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.current === index ? color.bg : Color.Transparent)
    .border({ width: this.current === index ? 1 : 0, color: color.border })
    .borderRadius(20)
    .onClick(() => {
      this.current = index;
      this.onSubPageChange(index);
    })
  }

  /**
   * 悬浮「+」记录入口 —— 对应原版 Home 的浮动加号。
   *
   * 只在「综合」页显示；饮水和断食各自提供对应的记录入口。
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

        Stack({ alignContent: Alignment.BottomStart }) {
          Divider()
            .width('100%')
            .strokeWidth(1)
            .color(color.border)

          Row() {
            ForEach(SUB_TABS, (label: string, i: number) => {
              this.SubBar(label, i)
            }, (label: string, i: number) => label + i)
          }
          .width('100%')
          .height(74)
          .padding({ top: 4, left: 6, right: 6 })
        }
        .width('100%')
        .height(74)

        if (this.current === 0) {
          HomePage()
        } else if (this.current === 1) {
          WaterPage()
        } else {
          FastingPage()
        }
      }
      .width('100%')
      .height('100%')

      if (this.current === 0) {
        this.Fab()
      }
    }
    .width('100%')
    .height('100%')
  }
}
