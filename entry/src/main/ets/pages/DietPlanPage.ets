/**
 * 膳食 Diet Plan —— 对应 NutriScan 第二个底 Tab，
 * 下含四个子页：膳食计划 / 购物清单 / 补剂 / 生活方式。
 *
 * 实测依据：
 *   · `/api/v2/generate_grocery_list`（购物清单是服务端生成的）
 *   · 字段 groceryList、supplement / supplement_needed / supplement_note、
 *     supplements_count、lifestyle / lifestyle_view_shown
 *   · 「Lifestyle & Feelings」分类
 *   · 文案「Every scan, meal idea, recipe and grocery list goes 100% plant-based.」
 *   · 引导语「Can you take Nutritional Supplements?」
 *
 * 计划生成是服务端行为，本地无法复刻 —— 所以四个子页全部标 MOCK，
 * 界面上写明「示例数据」，不假装是真实生成结果。
 */

import { color, fontSize, space, radius, layout, glass, glassGradient, glassShadow, toneVeil } from '../common/DesignTokens';
import { anim } from '../common/Motion';
import {
  DIET_PLAN, DayPlan, MealPlanSlot, GROCERY_LIST, GroceryItem,
  SUPPLEMENTS, SupplementItem, LIFESTYLES, LifestyleItem, Provenance, provenanceLabel
} from '../services/MockContent';

const SUB_TABS: string[] = ['膳食计划', '购物清单', '补剂', '生活方式'];

@Component
export struct DietPlanPage {
  @State private sub: number = 0;
  @State private entered: boolean = false;
  @State private checkedIds: string[] = [];

  enterView(): void {
    this.entered = true;
  }

  private toggle(id: string): void {
    if (this.checkedIds.includes(id)) {
      this.checkedIds = this.checkedIds.filter((x: string) => x !== id);
    } else {
      this.checkedIds = this.checkedIds.concat([id]);
    }
  }

  private isChecked(id: string): boolean {
    return this.checkedIds.includes(id);
  }

  @Builder
  SubBar(label: string, index: number) {
    Text(label)
      .fontSize(fontSize.secondary)
      .fontColor(this.sub === index ? color.primary : color.textSecondary)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor(this.sub === index ? color.glassFill : Color.Transparent)
      .borderRadius(radius.pill)
      .onClick(() => {
        this.sub = index;
      })
  }

  @Builder
  PlanView() {
    Column({ space: space.md }) {
      Text('全植物基（实测文案：Every scan, meal idea, recipe and grocery list goes 100% plant-based.）')
        .fontSize(fontSize.caption)
        .fontColor(color.textHint)
        .width('100%')

      ForEach(DIET_PLAN, (d: DayPlan) => {
        Column({ space: space.sm }) {
          Row() {
            Text(d.dateLabel)
              .fontSize(fontSize.sectionTitle)
              .fontWeight(FontWeight.Bold)
              .fontColor(color.text)
              .layoutWeight(1)
            Text(provenanceLabel(d.provenance))
              .fontSize(fontSize.caption)
              .fontColor(color.textHint)
          }
          .width('100%')

          ForEach(d.slots, (slot: MealPlanSlot, i: number) => {
            Row() {
              Text(slot.meal)
                .fontSize(fontSize.caption)
                .fontColor(color.textHint)
                .width(44)
              Text(slot.dishes.join('、'))
                .fontSize(fontSize.secondary)
                .fontColor(color.text)
                .layoutWeight(1)
              Text(`${slot.kcal}`)
                .fontSize(fontSize.secondary)
                .fontColor(color.text)
            }
            .width('100%')
          }, (slot: MealPlanSlot, i: number) => slot.meal + i)
        }
        .width('100%')
        .padding(layout.cardPadding)
        .linearGradient(glassGradient(toneVeil(d.dateLabel)))
        .borderRadius(glass.cardRadius)
        .border({ width: glass.borderWidth, color: color.glassBorder })
        .alignItems(HorizontalAlign.Start)
      }, (d: DayPlan) => d.dateLabel)

      Text('计划由服务端生成（实测 /api/v2/generate_grocery_list），本地为示例数据。')
        .fontSize(fontSize.caption)
        .fontColor(color.textHint)
        .width('100%')
    }
    .width('100%')
  }

  @Builder
  GroceryView() {
    Column({ space: space.sm }) {
      Text(`购物清单 · 已勾选 ${this.checkedIds.length}/${GROCERY_LIST.length}`)
        .fontSize(fontSize.body)
        .fontWeight(FontWeight.Bold)
        .fontColor(color.text)
        .width('100%')

      ForEach(GROCERY_LIST, (item: GroceryItem) => {
        Row({ space: space.sm }) {
          Text(this.isChecked(item.id) ? '☑' : '☐')
            .fontSize(18)
            .fontColor(this.isChecked(item.id) ? color.primary : color.textHint)
          Text(item.name)
            .fontSize(fontSize.body)
            .fontColor(this.isChecked(item.id) ? color.textHint : color.text)
            .decoration({ type: this.isChecked(item.id) ? TextDecorationType.LineThrough : TextDecorationType.None })
          Blank()
          Text(item.amount)
            .fontSize(fontSize.caption)
            .fontColor(color.textHint)
        }
        .width('100%')
        .padding({ top: space.sm, bottom: space.sm })
        .onClick(() => {
          this.toggle(item.id);
        })
      }, (item: GroceryItem) => item.id)

      Text('勾选状态存在内存中：原版清单由服务端持久化，本地不做落库。')
        .fontSize(fontSize.caption)
        .fontColor(color.textHint)
        .width('100%')
    }
    .width('100%')
    .padding(layout.cardPadding)
    .linearGradient(glassGradient(toneVeil('grocery')))
    .borderRadius(glass.cardRadius)
    .border({ width: glass.borderWidth, color: color.glassBorder })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SupplementView() {
    Column({ space: space.sm }) {
      Text('需要补充')
        .fontSize(fontSize.body)
        .fontWeight(FontWeight.Bold)
        .fontColor(color.text)
        .width('100%')

      ForEach(SUPPLEMENTS, (s: SupplementItem) => {
        Row() {
          Column({ space: 2 }) {
            Text(s.name)
              .fontSize(fontSize.body)
              .fontColor(color.text)
            Text(s.note)
              .fontSize(fontSize.caption)
              .fontColor(color.textHint)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column({ space: 2 }) {
            Text(provenanceLabel(s.provenance))
              .fontSize(fontSize.caption)
              .fontColor(color.textHint)
            Text(s.need)
              .fontSize(fontSize.caption)
              .fontColor(color.primary)
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')
        .padding({ top: space.sm, bottom: space.sm })
      }, (s: SupplementItem) => s.id)

      Text('补剂项为示例数据；原版字段 supplement_needed / supplement_note 已确认存在。')
        .fontSize(fontSize.caption)
        .fontColor(color.textHint)
        .width('100%')
    }
    .width('100%')
    .padding(layout.cardPadding)
    .linearGradient(glassGradient(toneVeil('supplements')))
    .borderRadius(glass.cardRadius)
    .border({ width: glass.borderWidth, color: color.glassBorder })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  LifestyleView() {
    Column({ space: space.sm }) {
      ForEach(LIFESTYLES, (l: LifestyleItem) => {
        Column({ space: 4 }) {
          Text(l.group)
            .fontSize(fontSize.caption)
            .fontColor(color.textHint)
          Text(l.title)
            .fontSize(fontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(color.text)
          Text(l.detail)
            .fontSize(fontSize.caption)
            .fontColor(color.textHint)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(layout.cardPadding)
        .linearGradient(glassGradient(toneVeil(l.id)))
        .borderRadius(glass.cardRadius)
        .border({ width: glass.borderWidth, color: color.glassBorder })
      }, (l: LifestyleItem) => l.id)

      Text('实测依据：分类名「Lifestyle & Feelings」与文案「We\'ll suggest meals that match your lifestyle, routine, and food habits.」；条目内容为示例。')
        .fontSize(fontSize.caption)
        .fontColor(color.textHint)
        .width('100%')
    }
    .width('100%')
  }

  build() {
    Scroll() {
      Column({ space: space.md }) {
        Text('膳食')
          .fontSize(fontSize.pageTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(color.text)
          .width('100%')

        Row({ space: space.sm }) {
          ForEach(SUB_TABS, (label: string, i: number) => {
            this.SubBar(label, i)
          }, (label: string, i: number) => label + i)
        }
        .width('100%')

        if (this.sub === 0) {
          this.PlanView()
        } else if (this.sub === 1) {
          this.GroceryView()
        } else if (this.sub === 2) {
          this.SupplementView()
        } else {
          this.LifestyleView()
        }
      }
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
    .backgroundColor(color.bg)
    .linearGradient({ angle: 135, colors: [[color.pageDeep, 0], [color.pageMid, 1]] })
  }
}
