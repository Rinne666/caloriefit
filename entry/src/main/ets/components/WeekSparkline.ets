/**
 * 周趋势柱状图 —— 近 7 日热量摄入
 *
 * 对应 NutriScan 首页每个指标下方的 M T W T F S S 周条。
 *
 * V3：颜色全部走 DesignTokens 的资源限定符引用，深浅色自动切换。
 *
 * 设计要点：
 *   · 固定 7 个槽位，缺数据的日子画空槽而非压缩 —— 保持星期对齐
 *   · 超出目标线的柱子转红
 *   · 当天槽位加品牌色加粗
 *   · 无数据时降低透明度而不是画 0，避免"看起来是 0 千卡"的误读
 */

import { color, fontSize, space, radius, layout } from '../common/DesignTokens';
import { DayPoint } from '../repositories/MacroRepository';
import { toDateKey, parseDateKey } from '../common/DateUtils';

const WEEK_LABELS: string[] = ['一', '二', '三', '四', '五', '六', '日'];

@Component
export struct WeekSparkline {
  /** 近 N 日序列（升序，长度 <= 7，从旧到新） */
  @Prop points: DayPoint[] = [];
  @Prop targetKcal: number = 1800;
  @Prop selectedDate: string = '';

  private get maxKcal(): number {
    let m = this.targetKcal;
    for (let i = 0; i < this.points.length; i++) {
      if (this.points[i].kcal > m) {
        m = this.points[i].kcal;
      }
    }
    return m <= 0 ? 1 : m;
  }

  /** 把近 N 日对齐到"周一..周日"7 个槽位 */
  private weekSlots(): DayPoint[] {
    const slots: DayPoint[] = [];
    const sel = parseDateKey(this.selectedDate);
    const dow = (sel.getDay() + 6) % 7;           // 周一 = 0
    const monday = new Date(sel);
    monday.setDate(sel.getDate() - dow);

    const byDate: Record<string, DayPoint> = {};
    for (let i = 0; i < this.points.length; i++) {
      byDate[this.points[i].date] = this.points[i];
    }

    for (let i = 0; i < 7; i++) {
      const d = new Date(monday);
      d.setDate(monday.getDate() + i);
      const key = toDateKey(d);
      slots.push(byDate[key] ?? {
        date: key, kcal: 0, proteinG: 0, carbsG: 0, fatG: 0
      });
    }
    return slots;
  }

  private barHeight(kcal: number): number {
    const ratio = kcal / this.maxKcal;
    return Math.max(3, Math.round(ratio * 52));
  }

  private isOverTarget(kcal: number): boolean {
    return this.targetKcal > 0 && kcal > this.targetKcal;
  }

  private isSelected(date: string): boolean {
    return date === this.selectedDate;
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
          ForEach(this.weekSlots(), (p: DayPoint) => {
            Column({ space: 4 }) {
              // 柱体
              Row()
                .width(18)
                .height(this.barHeight(p.kcal))
                .borderRadius(6)
                .backgroundColor(this.isOverTarget(p.kcal) ? color.danger : color.primary)
                .opacity(p.kcal > 0 ? 1 : 0.25)

              // 星期
              Text(this.labelFor(p.date))
                .fontSize(fontSize.caption)
                .fontColor(this.isSelected(p.date) ? color.primary : color.textHint)
                .fontWeight(this.isSelected(p.date) ? FontWeight.Bold : FontWeight.Normal)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
          }, (p: DayPoint) => p.date)
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)

        // 目标线
        Divider()
          .strokeWidth(1)
          .color(color.divider)
          .margin({ bottom: this.barHeight(this.targetKcal) })
      }
      .width('100%')
      .height(78)
    }
    .width('100%')
    .padding(layout.cardPadding)
    .backgroundColor(color.surface)
    .borderRadius(radius.card)
    .border({ width: layout.borderWidth, color: color.border })
    .alignItems(HorizontalAlign.Start)
  }

  private labelFor(dateKey: string): string {
    const d = parseDateKey(dateKey);
    return WEEK_LABELS[(d.getDay() + 6) % 7];
  }
}
