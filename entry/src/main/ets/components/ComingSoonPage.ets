/**
 * 未实现功能的跳转占位页。
 *
 * 存在的意义：路由必须可达。
 * 用户点进去不能是死路，也不能是白屏 —— 得让他看到
 * 「这个功能本来该做什么」「为什么现在没做」「补上需要什么」。
 *
 * 这不是偷懒的遮羞布。反过来，如果把没做的功能删掉、或让按钮点了没反应，
 * 交付物就是不完整的：用户无法判断哪些已实现、哪些待补。占位页把这件事显式化。
 *
 * ⚠ 内容走 AppStorage 而不是构造参数，这是被实测逼出来的：
 *   作为 navDestination 的 @Builder 分支根节点渲染时，
 *   **带初始化对象的** @Component 内容节点挂不上树 —— 组件被构造、
 *   aboutToAppear 会跑，但画面全白且日志无任何异常；
 *   同一个位置的**无参** @Component（FoodEditPage 等）则正常。
 *   所以这里改成无参组件 + @StorageProp 读内容，
 *   由 setComingSoon() 在跳转前写入。
 */

import { color, fontSize, space, layout, glass, glassGradient, glassShadow, toneVeil } from '../common/DesignTokens';
import { anim } from '../common/Motion';
import { Provenance, provenanceLabel } from '../services/MockContent';

/** AppStorage 键。与 setComingSoon() 一一对应。 */
export const CS_ROUTE_NAME: string = 'cs_route_name';
export const CS_INTENT: string = 'cs_intent';
export const CS_BLOCKER: string = 'cs_blocker';
export const CS_NEEDED: string = 'cs_needed';
export const CS_PROVENANCE: string = 'cs_provenance';
/** 覆盖层是否展开。由 Index 监听并渲染全屏层。 */
export const CS_VISIBLE: string = 'cs_visible';

/** 展开覆盖层 */
export function openComingSoon(): void {
  AppStorage.setOrCreate<boolean>(CS_VISIBLE, true);
}

/** 收起覆盖层 */
export function closeComingSoon(): void {
  AppStorage.setOrCreate<boolean>(CS_VISIBLE, false);
}

/**
 * 写入占位页内容并展开覆盖层 —— 页面侧的唯一入口。
 */
export function showComingSoon(
  routeName: string,
  intent: string,
  blocker: string,
  needed: string,
  provenance: Provenance
): void {
  AppStorage.setOrCreate<string>(CS_ROUTE_NAME, routeName);
  AppStorage.setOrCreate<string>(CS_INTENT, intent);
  AppStorage.setOrCreate<string>(CS_BLOCKER, blocker);
  AppStorage.setOrCreate<string>(CS_NEEDED, needed);
  AppStorage.setOrCreate<Provenance>(CS_PROVENANCE, provenance);
  openComingSoon();
}

/**
 * 写入占位页内容。跳转前调用。
 *
 * 用 AppStorage 而不是 NavPathStack 的 param：一是绕开上面记的坑，
 * 二是占位内容本质是"应用级的一次性提示"，不是需要随路由传的结构化数据。
 */
export function setComingSoon(
  routeName: string,
  intent: string,
  blocker: string,
  needed: string,
  provenance: Provenance
): void {
  AppStorage.setOrCreate<string>(CS_ROUTE_NAME, routeName);
  AppStorage.setOrCreate<string>(CS_INTENT, intent);
  AppStorage.setOrCreate<string>(CS_BLOCKER, blocker);
  AppStorage.setOrCreate<string>(CS_NEEDED, needed);
  AppStorage.setOrCreate<Provenance>(CS_PROVENANCE, provenance);
}

/**
 * 跳转参数载体（供 NavPathStack 使用）。
 *
 * 当前 ComingSoon 已改为**覆盖层**而非独立目标页（见 Index.ets 注释），
 * 这个类保留给后续可能恢复成独立路由的场景。内容仍走 AppStorage，
 * 它只当占位。
 */
export class ComingSoonRoute {
  tag: string;

  constructor(tag: string) {
    this.tag = tag;
  }
}

@Component
export struct ComingSoonPage {
  @StorageProp(CS_ROUTE_NAME) routeName: string = '未命名功能';
  @StorageProp(CS_INTENT) intent: string = '';
  @StorageProp(CS_BLOCKER) blocker: string = '';
  @StorageProp(CS_NEEDED) needed: string = '';
  @StorageProp(CS_PROVENANCE) provenance: Provenance = Provenance.MOCK;

  @State private entered: boolean = false;

  /**
   * 入场兜底。
   *
   * 除了 .onAppear() 修饰符，再加一个 setTimeout：
   * 两者谁先到都行。反正都是把同一个状态置 true，
   * 宁可动画偶尔由定时器触发，也不能出现「路由可达但看不见」。
   */
  aboutToAppear(): void {
    setTimeout(() => {
      this.enterView();
    }, 0);
  }

  enterView(): void {
    this.entered = true;
  }

  build() {
    // 外层只负责尺寸与背景，不参与透明度动画 —— 内容那层的入场状态
    // 万一没翻转，页面底色也已经是对的，不会白屏。
    Column() {
      Scroll() {
        Column({ space: space.lg }) {
          Column({ space: space.sm }) {
            Text('⚠')
              .fontSize(44)

            Text(this.routeName)
              .fontSize(fontSize.pageTitle)
              .fontWeight(FontWeight.Bold)
              .fontColor(color.text)

            Text(`未实现 · 证据状态：${provenanceLabel(this.provenance)}`)
              .fontSize(fontSize.caption)
              .fontColor(color.textHint)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)

          Column({ space: space.sm }) {
            this.Field('本应功能', this.intent)
            this.Field('未实现原因', this.blocker)
            this.Field('补上需要', this.needed)
          }
          .width('100%')
          .padding(layout.cardPadding)
          .linearGradient(glassGradient(toneVeil(this.routeName)))
          .borderRadius(glass.cardRadius)
          .border({ width: glass.borderWidth, color: color.glassBorder })
          .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
          .alignItems(HorizontalAlign.Start)

          Text('证据状态已标在标题下方；补齐条件见上。')
            .fontSize(fontSize.caption)
            .fontColor(color.textHint)
        }
        .width('100%')
        .padding(layout.pagePadding)
        .opacity(this.entered ? 1 : 0)
        .translate({ x: 0, y: this.entered ? 0 : anim.enterShiftVp })
        .animation({ duration: anim.enterMs, curve: anim.ease })
        .onAppear(() => {
          this.enterView();
        })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(color.bg)
    .linearGradient({ angle: 135, colors: [[color.pageDeep, 0], [color.pageMid, 1]] })
  }

  /**
   * 字段行。
   *
   * 方法名刻意不叫 Row —— Row 是 ArkUI 内置组件，
   * 自定义 @Builder 取同名会和 DSL 里的 Row(...) 解析打架。
   */
  @Builder
  Field(label: string, value: string) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(fontSize.caption)
        .fontColor(color.textHint)
      Text(value)
        .fontSize(fontSize.secondary)
        .fontColor(color.text)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
