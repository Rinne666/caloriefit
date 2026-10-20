/**
 * 引导流程页 —— 对应 NutriScan 的 splash_screen + setup_screen。
 *
 * 结构按真机截图还原：
 *   顶部品牌色进度条 · 左上返回箭头 · 大标题 · 卡片内容 · 底部白色药丸 CTA
 *
 * 与原版的差异（有意为之）：
 *   · 没有语言选择屏 —— 本 App 只发中文，做一屏只能选自己
 *   · 没有订阅墙     —— 本项目定位为完全免费，不设试用/升级/订阅墙
 *                        （原版那一屏还是虚假折扣：划线价与实付价相同却宣称 70% off）
 *   · 引导结果会**真的写进体征档案**，直接驱动 BMR/TDEE 与宏量目标推导
 *
 * 白底黑字的大药丸 CTA 是原版最强的视觉符号之一，两种主题下都保留。
 */

import { common } from '@kit.AbilityKit';
import {
  color, fontSize, space, radius, layout,
  glass, glassGradient, glassShadow, toneVeil,
  heroGradient, primaryButtonGradient, pageGradient
} from '../common/DesignTokens';
import { anim } from '../common/Motion';
import {
  GoalMode, ActivityLevel, modeLabel, activityLabel
} from '../models/Calculation';
import {
  OnboardStep, ONBOARD_STEP_COUNT, OnboardDraft, OnboardingService
} from '../services/OnboardingService';

/** 药丸 CTA：白底黑字，原版标志性元素 */
const CTA_BG: string = '#FFFFFF';
const CTA_FG: string = '#0C0C0C';

@Component
export struct OnboardingPage {
  onDone: () => void = () => {};

  /** 0 = 启动页，1..N = 引导步骤 */
  @State private phase: number = 0;
  @State private step: OnboardStep = OnboardStep.GOAL;
  @State private draft: OnboardDraft = new OnboardDraft();

  private splashTimer: number = -1;

  aboutToAppear(): void {
    // 启动页停留 1.4s，和原版 splash 一致的量级
    this.splashTimer = setTimeout(() => {
      this.phase = 1;
    }, 1400);
  }

  aboutToDisappear(): void {
    if (this.splashTimer !== -1) {
      clearTimeout(this.splashTimer);
      this.splashTimer = -1;
    }
  }

  private async finish(): Promise<void> {
    try {
      const host = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await OnboardingService.applyToProfile(host, this.draft);
      OnboardingService.markDone(host);
    } catch (e) {
      // 引导完成态写失败不该把用户卡在引导里，照样放行
    }
    this.onDone();
  }

  private next(): void {
    if (this.step === OnboardStep.LIFESTYLE) {
      this.finish();
      return;
    }
    this.step = this.step + 1;
  }

  private back(): void {
    if (this.step === OnboardStep.GOAL) {
      return;
    }
    this.step = this.step - 1;
  }

  private progressRatio(): number {
    return (this.step + 1) / ONBOARD_STEP_COUNT;
  }

  /* ---------------- 各步骤标题 ---------------- */

  private title(): string {
    if (this.step === OnboardStep.GOAL) { return '你想达成什么'; }
    if (this.step === OnboardStep.ACTIVITY) { return '平时的活动量'; }
    if (this.step === OnboardStep.NOTIFY) { return '随时掌握进度'; }
    if (this.step === OnboardStep.SUPPLEMENT) { return '你会吃补剂吗'; }
    return '你的生活方式';  }

  private subtitle(): string {
    if (this.step === OnboardStep.GOAL) { return '决定每天的热量缺口与宏量比例'; }
    if (this.step === OnboardStep.ACTIVITY) { return '决定 BMR 到 TDEE 的乘数'; }
    if (this.step === OnboardStep.NOTIFY) { return '只在目标有变化时才提醒'; }
    if (this.step === OnboardStep.SUPPLEMENT) { return '影响是否给你推补剂建议'; }
    return '用来让饮食建议更贴合你的实际情况';
  }

  /* ---------------- 复用片段 ---------------- */

  @Builder
  Pill(label: string, selected: boolean, onTap: () => void) {
    Row() {
      Text(label)
        .fontSize(fontSize.body)
        .fontWeight(selected ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(color.text)
        .layoutWeight(1)
      if (selected) {
        Text('✓')
          .fontSize(fontSize.secondary)
          .fontColor(color.primary)
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 20, right: 20 })
    .backgroundColor(selected ? color.glassFillStrong : color.glassFill)
    .borderRadius(radius.pill)
    .border({ width: 1, color: selected ? color.glassBorder : color.glassFill })
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  Cta(text: string, enabled: boolean) {
    Button(text)
      .width('100%')
      .height(54)
      .fontSize(fontSize.body)
      .fontWeight(FontWeight.Medium)
      .fontColor(CTA_FG)
      .backgroundColor(CTA_BG)
      .borderRadius(radius.pill)
      .opacity(enabled ? 1 : 0.5)
      .onClick(() => {
        if (enabled) {
          this.next();
        }
      })
  }

  /* ---------------- 各步骤内容 ---------------- */

  @Builder
  GoalBody() {
    this.Pill(modeLabel(GoalMode.WEIGHT_LOSS), this.draft.goal === GoalMode.WEIGHT_LOSS, () => {
      this.draft.goal = GoalMode.WEIGHT_LOSS;
    })
    this.Pill(modeLabel(GoalMode.MAINTAIN), this.draft.goal === GoalMode.MAINTAIN, () => {
      this.draft.goal = GoalMode.MAINTAIN;
    })
    this.Pill(modeLabel(GoalMode.SURPLUS), this.draft.goal === GoalMode.SURPLUS, () => {
      this.draft.goal = GoalMode.SURPLUS;
    })
    this.Pill(modeLabel(GoalMode.RECOMP), this.draft.goal === GoalMode.RECOMP, () => {
      this.draft.goal = GoalMode.RECOMP;
    })
  }

  @Builder
  ActivityBody() {
    this.Pill(activityLabel(ActivityLevel.SEDENTARY),
      this.draft.activity === ActivityLevel.SEDENTARY, () => {
        this.draft.activity = ActivityLevel.SEDENTARY;
      })
    this.Pill(activityLabel(ActivityLevel.LIGHT),
      this.draft.activity === ActivityLevel.LIGHT, () => {
        this.draft.activity = ActivityLevel.LIGHT;
      })
    this.Pill(activityLabel(ActivityLevel.MODERATE),
      this.draft.activity === ActivityLevel.MODERATE, () => {
        this.draft.activity = ActivityLevel.MODERATE;
      })
    this.Pill(activityLabel(ActivityLevel.VERY_ACTIVE),
      this.draft.activity === ActivityLevel.VERY_ACTIVE, () => {
        this.draft.activity = ActivityLevel.VERY_ACTIVE;
      })
  }

  /** 通知诱导：按原版 flow_02 的「预览卡 + 三条说明」布局 */
  @Builder
  NotifyBody() {
    Column({ space: space.md }) {
      Column({ space: space.xs }) {
        Row() {
          Row() {
            Text('●')
              .fontSize(18)
              .fontColor(color.primary)
          }
          .width(36)
          .height(36)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(color.glassFill)
          .borderRadius(8)

          Column({ space: 2 }) {
            Text('CalorieFit')
              .fontSize(fontSize.secondary)
              .fontWeight(FontWeight.Medium)
              .fontColor(color.text)
            Text('今天离蛋白目标还差 12g，一杯希腊酸奶就够了')
              .fontSize(fontSize.caption)
              .fontColor(color.textSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
      }
      .width('100%')
      .padding(layout.cardPadding)
      .backgroundColor(color.glassFillStrong)
      .borderRadius(radius.large)
      .border({ width: 1, color: color.glassBorder })
      .alignItems(HorizontalAlign.Start)

      Column() {
        this.Bullet('🎯', '只在目标有变化时提醒')
        this.Bullet('🗓', '一周几条，绝不刷屏')
        this.Bullet('🔕', '随时可在设置里关掉')
      }
      .width('100%')
      .backgroundColor(color.glassFill)
      .borderRadius(radius.large)
      .border({ width: 1, color: color.glassBorder })
    }
    .width('100%')
  }

  @Builder
  Bullet(icon: string, text: string) {
    Row({ space: space.sm }) {
      Row() {
        Text(icon)
          .fontSize(16)
      }
      .width(34)
      .height(34)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(color.glassFillStrong)
      .borderRadius(8)

      Text(text)
        .fontSize(fontSize.body)
        .fontColor(color.text)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: space.md, right: space.md, top: space.sm, bottom: space.sm })
  }

  @Builder
  SupplementBody() {
    this.Pill('愿意，会按需推荐', this.draft.supplements, () => {
      this.draft.supplements = true;
    })
    this.Pill('不吃，只看饮食建议', !this.draft.supplements, () => {
      this.draft.supplements = false;
    })
  }

  @Builder
  LifestyleBody() {
    Text('作息是否规律')
      .fontSize(fontSize.secondary)
      .fontColor(color.textSecondary)
      .width('100%')
      .margin({ top: space.sm })

    this.Pill('规律，三餐定时', this.draft.routine, () => {
      this.draft.routine = true;
    })
    this.Pill('不太规律，经常漏餐', !this.draft.routine, () => {
      this.draft.routine = false;
    })

    Text('外食频率')
      .fontSize(fontSize.secondary)
      .fontColor(color.textSecondary)
      .width('100%')
      .margin({ top: space.md })

    this.Pill('几乎不外食', this.draft.eatOut === 0, () => {
      this.draft.eatOut = 0;
    })
    this.Pill('偶尔外食', this.draft.eatOut === 1, () => {
      this.draft.eatOut = 1;
    })
    this.Pill('经常外食', this.draft.eatOut === 2, () => {
      this.draft.eatOut = 2;
    })
  }

  /* ---------------- 启动页 ---------------- */

  @Builder
  Splash() {
    Column({ space: space.md }) {
      Blank()

      Column({ space: space.md }) {
        Text('🍽')
          .fontSize(72)
        Text('CalorieFit')
          .fontSize(40)
          .fontWeight(FontWeight.Bold)
          .fontColor(color.text)
        Text('记录 · 目标 · 一眼看懂今天还差多少')
          .fontSize(fontSize.secondary)
          .fontColor(color.textSecondary)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)

      Blank()

      Text('准备中…')
        .fontSize(fontSize.caption)
        .fontColor(color.textHint)
    }
    .width('100%')
    .height('100%')
    .padding(layout.pagePadding)
    .linearGradient(heroGradient())
  }

  /* ---------------- 主结构 ---------------- */

  build() {
    if (this.phase === 0) {
      this.Splash()
    } else {
      Column() {
        // 进度条 + 返回
        Row() {
          Button('‹')
            .width(40)
            .height(40)
            .fontSize(24)
            .fontColor(this.step === OnboardStep.GOAL ? color.disabledText : color.text)
            .backgroundColor(Color.Transparent)
            .enabled(this.step !== OnboardStep.GOAL)
            .onClick(() => {
              this.back();
            })

          Blank()

          Text(`${this.step + 1} / ${ONBOARD_STEP_COUNT}`)
            .fontSize(fontSize.caption)
            .fontColor(color.textHint)
        }
        .width('100%')
        .padding({ left: 4, right: 4, top: 8, bottom: 8 })

        // 连续进度条（品牌色填充）
        Row() {
          Row()
            .width(`${Math.round(this.progressRatio() * 100)}%`)
            .height(4)
            .borderRadius(2)
            .backgroundColor(color.primary)
            .animation({ duration: anim.enterMs, curve: anim.ease })
        }
        .width('100%')
        .height(4)
        .borderRadius(2)
        .backgroundColor(color.ringTrack)

        Column({ space: space.md }) {
          Text(this.title())
            .fontSize(fontSize.hero)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.text)
            .width('100%')

          Text(this.subtitle())
            .fontSize(fontSize.secondary)
            .fontColor(color.textSecondary)
            .width('100%')

          Column({ space: space.sm }) {
            if (this.step === OnboardStep.GOAL) {
              this.GoalBody()
            } else if (this.step === OnboardStep.ACTIVITY) {
              this.ActivityBody()
            } else if (this.step === OnboardStep.NOTIFY) {
              this.NotifyBody()
            } else if (this.step === OnboardStep.SUPPLEMENT) {
              this.SupplementBody()
            } else {
              this.LifestyleBody()
            }
          }
          .width('100%')
          .padding(layout.cardPadding)
          .linearGradient(glassGradient(toneVeil(`onboard-${this.step + 1}`)))
          .borderRadius(glass.cardRadius)
          .border({ width: glass.borderWidth, color: color.glassBorder })
          .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
          .alignItems(HorizontalAlign.Start)

          Blank()

          // 把末步判断放在组件树里，让 step 的 @State 变化驱动按钮文案刷新。
          if (this.step === OnboardStep.LIFESTYLE) {
            this.Cta('开始使用', true)
          } else {
            this.Cta('继续', true)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ top: space.lg, left: layout.pagePadding, right: layout.pagePadding })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(color.bg)
      .linearGradient(pageGradient())
    }
  }
}
