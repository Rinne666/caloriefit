/**
 * 宏量进度条 —— 实际 / 目标，超标整条转红
 *
 * 对应 NutriScan 实测行为：碳水 155g / 目标 144g 时，
 * 该条进度线由常态色转为 #FF2E63，数字同时变红。
 *
 * V3：颜色全部走 DesignTokens 的资源限定符引用，
 * 深浅色由系统自动切换，组件内不再有 useDark 分支。
 *
 * 设计要点：
 *   · 超标时进度条填满并转红，末尾显示超出量
 *   · 目标值以竖线刻度标出，一眼能看出超了多少
 *   · 数值与目标同时变红时，色弱用户仍能靠刻度位置判断
 */

import { color, fontSize, space, radius, layout } from '../common/DesignTokens';
import { CalorieEngine } from '../services/CalorieEngine';

@Component
export struct MacroBar {
  @Prop label: string = '';
  @Prop actualG: number = 0;
  @Prop targetG: number = 0;
  @Prop barColor: ResourceColor = color.primary;

  private get isOver(): boolean {
    return this.actualG > this.targetG;
  }

  private get ratio(): number {
    return CalorieEngine.macroRatio(this.actualG, this.targetG);
  }

  /** 目标刻度位置：超标时贴在末端，表示"已越过目标" */
  private get markerPos(): string {
    if (this.targetG <= 0) {
      return '0%';
    }
    return `${Math.min(100, this.targetG / Math.max(this.targetG, this.actualG) * 100)}%`;
  }

  private get fillColor(): ResourceColor {
    return this.isOver ? color.danger : this.barColor;
  }

  private get valueColor(): ResourceColor {
    return this.isOver ? color.danger : color.text;
  }

  build() {
    Column({ space: 6 }) {
      Row() {
        Text(this.label)
          .fontSize(fontSize.body)
          .fontColor(color.text)

        Blank()

        Text(`${Math.round(this.actualG)}g / ${Math.round(this.targetG)}g`)
          .fontSize(fontSize.secondary)
          .fontWeight(this.isOver ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.valueColor)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 进度轨道 + 目标刻度
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(layout.progressHeight)
          .borderRadius(layout.progressHeight / 2)
          .backgroundColor(color.ringTrack)

        Row()
          .width(`${this.ratio * 100}%`)
          .height(layout.progressHeight)
          .borderRadius(layout.progressHeight / 2)
          .backgroundColor(this.fillColor)

        // 目标刻度竖线
        Row()
          .width(2)
          .height(layout.progressHeight + 4)
          .backgroundColor(color.textHint)
          .margin({ left: this.markerPos })
      }
      .width('100%')
      .height(layout.progressHeight + 4)
      .alignItems(VerticalAlign.Center)

      if (this.isOver) {
        Text(`超出 ${Math.round(this.actualG - this.targetG)}g`)
          .fontSize(fontSize.caption)
          .fontColor(color.danger)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/** 三宏量汇总卡：蛋白 / 碳水 / 脂肪 */
@Component
export struct MacroPanel {
  @Prop actualProtein: number = 0;
  @Prop actualCarbs: number = 0;
  @Prop actualFat: number = 0;
  @Prop targetProtein: number = 0;
  @Prop targetCarbs: number = 0;
  @Prop targetFat: number = 0;

  build() {
    Column({ space: space.md }) {
      MacroBar({
        label: '蛋白质',
        actualG: this.actualProtein,
        targetG: this.targetProtein,
        barColor: color.macroProtein
      })
      MacroBar({
        label: '碳水',
        actualG: this.actualCarbs,
        targetG: this.targetCarbs,
        barColor: color.macroCarbs
      })
      MacroBar({
        label: '脂肪',
        actualG: this.actualFat,
        targetG: this.targetFat,
        barColor: color.macroFat
      })
    }
    .width('100%')
    .padding(layout.cardPadding)
    .backgroundColor(color.surface)
    .borderRadius(radius.card)
    .border({ width: layout.borderWidth, color: color.border })
    .alignItems(HorizontalAlign.Start)
  }
}
