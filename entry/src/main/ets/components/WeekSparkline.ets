/**
 * 周趋势柱状图 —— 近 7 日热量摄入
 *
 * 对应 NutriScan 首页每个指标下方的 M T W T F S S 周条。
 *
 * 卡片面与描边统一走主题 token。
 *
 * 设计要点：
 *   · 固定 7 个槽位，缺数据的日子画空槽而非压缩 —— 保持星期对齐
 *   · 超出目标线的柱子转红
 *   · 当天槽位加品牌色加粗
 *   · 无数据时降低透明度而不是画 0，避免"看起来是 0 千卡"的误读
 */

import {
  color, fontSize, layout,
  glass, glassGradient, glassShadow, toneVeil
} from '../common/DesignTokens';
import { anim } from '../common/Motion';
import { DayPoint } from '../repositories/MacroRepository';
import { toDateKey, parseDateKey } from '../common/DateUtils';

const WEEK_LABELS: string[] = ['一', '二', '三', '四', '五', '六', '日'];

/** 柱区高度(vp)。底轨固定此高，数据柱按比例填充。 */
const BAR_AREA: number = 56;

@Component
export struct WeekSparkline {
  /** 近 N 日序列（升序，长度 <= 7，从旧到新） */
  @Prop points: DayPoint[] = [];
  @Prop targetKcal: number = 1800;
  @Prop selectedDate: string = '';

  /**
   * 柱子生长开关。
   *
   * 首次渲染为 false（高度 0），出现后翻 true，
   * 由 .animation() 的隐式动画把高度推上去 —— 逐根 delay 形成波浪感。
   * 不能在 aboutToAppear 里就置 true：那会儿 build 还没跑，动画没有初值。
   * 方法名避开 onAppear：那是 CustomComponent 上已存在的属性。
   */
  @State private grown: boolean = false;

  growBars(): void {
    this.grown = true;
  }

  /**
   * 柱区最大刻度。
   *
   * 刻意用普通方法而非 getter：实测 ArkUI 的 @Component struct 中
   * `private get` 求值不可靠，曾返回 NaN，导致所有 .height(NaN)
   * 静默不渲染 —— 编译通过、日志无异常，柱子整个消失。
   */
  private calcMaxKcal(): number {
    let m: number = this.targetKcal > 0 ? this.targetKcal : 0;
    for (let i = 0; i < this.points.length; i++) {
      if (this.points[i].kcal > m) {
        m = this.points[i].kcal;
      }
    }
    return m <= 0 ? 1 : m;
  }

  /** 柱高。非法值一律回退 0，避免 .height(NaN) 静默吞掉整根柱子 */
  private barHeight(kcal: number): number {
    if (!(kcal > 0)) {
      return 0;
    }
    const max = this.calcMaxKcal();
    if (!(max > 0)) {
      return 0;
    }
    const ratio = kcal / max;
    if (!isFinite(ratio)) {
      return 0;
    }
    const h = Math.round(ratio * BAR_AREA);
    return Math.max(4, Math.min(BAR_AREA, h));
  }

  /** 把近 N 日对齐到"周一..周日"7 个槽位 */
  private weekSlots(): DayPoint[] {
    const slots: DayPoint[] = [];
    const sel = parseDateKey(this.selectedDate);
    const dow = (sel.getDay() + 6) % 7;           // 周一 = 0
    const monday = new Date(sel);
    monday.setDate(sel.getDate() - dow);

    // ArkTS 不保证 Record 索引访问可用（arkts-no-props-by-index），
    // 这里改成线性匹配：7 个槽位 × 少量数据，代价可忽略且行为确定。
    for (let i = 0; i < 7; i++) {
      const d = new Date(monday);
      d.setDate(monday.getDate() + i);
      const key = toDateKey(d);
      let found: DayPoint | null = null;
      for (let j = 0; j < this.points.length; j++) {
        if (this.points[j].date === key) {
          found = this.points[j];
          break;
        }
      }
      slots.push(found !== null ? found as DayPoint : {
        date: key, kcal: 0, proteinG: 0, carbsG: 0, fatG: 0
      });
    }
    return slots;
  }

  private isOverTarget(kcal: number): boolean {
    return this.targetKcal > 0 && kcal > this.targetKcal;
  }

  private isSelected(date: string): boolean {
    return date === this.selectedDate;
  }

  private labelFor(dateKey: string): string {
    const d = parseDateKey(dateKey);
    return WEEK_LABELS[(d.getDay() + 6) % 7];
  }

  build() {
    Column({ space: 6 }) {
      Row() {
        Text('近 7 日摄入')
          .fontSize(fontSize.sectionTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(color.text)

        Blank()

        Text(`目标 ${this.targetKcal} kcal`)
          .fontSize(fontSize.caption)
          .fontColor(color.textHint)
      }
      .width('100%')

      Stack({ alignContent: Alignment.BottomStart }) {
        Row() {
          ForEach(this.weekSlots(), (p: DayPoint, i: number) => {
            Column({ space: 4 }) {
              // 每槽都画底轨：空数据日也能看出「这里有一天但没记录」，
              // 而不是一个 3px 的残桩（v1 首版就是这么做的，看起来像坏了）
              Stack({ alignContent: Alignment.BottomStart }) {
                Row()
                  .width(18)
                  .height(BAR_AREA)
                  .borderRadius(6)
                  .backgroundColor(color.ringTrack)

                // 不用 if：无数据时 barHeight 返回 0，.height(0) 天然不可见。
                // 实测在 Stack 内用 if 包裹条件子组件时填充柱不渲染，
                // 而 barHeight 已经算对了 —— 去掉条件后恢复正常。
                Row()
                  .width(18)
                  .height(this.grown ? this.barHeight(p.kcal) : 0)
                  .borderRadius(6)
                  .backgroundColor(this.isOverTarget(p.kcal) ? color.danger : color.primary)
                  .animation({
                    duration: anim.dataMs,
                    delay: i * anim.barStaggerMs,
                    curve: anim.easeData
                  })
              }
              .width(18)
              .height(BAR_AREA)

              // 星期
              Text(this.labelFor(p.date))
                .fontSize(fontSize.caption)
                .fontColor(this.isSelected(p.date) ? color.primary : color.textHint)
                .fontWeight(this.isSelected(p.date) ? FontWeight.Bold : FontWeight.Normal)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
          }, (p: DayPoint) => `${p.date}#${p.kcal}`)
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)

        // 目标线：横贯，位置 = 目标占最大值的比例
        Divider()
          .strokeWidth(1)
          .color(color.divider)
          .margin({ bottom: this.barHeight(this.targetKcal) })
      }
      .width('100%')
      .height(BAR_AREA + 20)
    }
    .width('100%')
    .padding(layout.cardPadding)
    .linearGradient(glassGradient(toneVeil('trend')))
    .borderRadius(glass.cardRadius)
    .border({ width: glass.borderWidth, color: color.glassBorder })
    .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
    .alignItems(HorizontalAlign.Start)
    .onAppear(() => {
      this.growBars();
    })
  }
}
