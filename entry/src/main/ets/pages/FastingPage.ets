/**
 * 断食 Fasting —— 对应 NutriScan 首页子页（综合 / 社群 / 饮水 / 断食 之一）
 *
 * 实测依据：方案名 16:8 / 18:6 / 20:4 / 14:10 / 12:12 与自定义窗口，
 * 日志有「16:8 fast complete」。
 * 推断：原版的热量分配、到点提醒推送都拿不到证据，
 * 这里只做「选方案 → 开始计时 → 到点标记完成」这条主干。
 *
 * 计时器每秒刷新一次；页面离开时在 aboutToDisappear 停掉，
 * 不然切个 Tab 回来会看到几个定时器叠加在跑。
 */

import { color, fontSize, space, radius, layout, glass, glassGradient, glassShadow, toneVeil } from '../common/DesignTokens';
import { anim } from '../common/Motion';
import { FastingRepository, ActiveFasting } from '../repositories/FastingRepository';
import { FASTING_PLANS, FastingPlan, Provenance, provenanceLabel } from '../services/MockContent';
import { toDateKey, parseDateKey } from '../common/DateUtils';

@Component
export struct FastingPage {
  @StorageLink('selectedDate') @Watch('reload') selectedDate: string = '';
  @State private active: ActiveFasting | null = null;
  @State private nowMs: number = Date.now();
  @State private filled: boolean = false;

  private timer: number = -1;

  aboutToAppear(): void {
    this.reload();
  }

  aboutToDisappear(): void {
    this.stopTimer();
  }

  enterView(): void {
    this.filled = true;
    this.startTimer();
  }

  reload(): void {
    this.loadData();
  }

  private async loadData(): Promise<void> {
    try {
      this.active = await FastingRepository.active(this.selectedDate);
    } catch (e) {
      this.active = null;
    }
  }

  private startTimer(): void {
    this.stopTimer();
    this.timer = setInterval(() => {
      this.nowMs = Date.now();
    }, 1000);
  }

  private stopTimer(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private elapsedMs(): number {
    if (this.active === null) {
      return 0;
    }
    const d = this.nowMs - this.active.startAt;
    return d > 0 ? d : 0;
  }

  private totalMs(): number {
    if (this.active === null) {
      return 0;
    }
    const d = this.active.endAt - this.active.startAt;
    return d > 0 ? d : 1;
  }

  private progress(): number {
    return Math.max(0, Math.min(1, this.elapsedMs() / this.totalMs()));
  }

  private remainingText(): string {
    const remain = this.totalMs() - this.elapsedMs();
    if (remain <= 0) {
      return '已完成';
    }
    const totalMin = Math.floor(remain / 60000);
    const h = Math.floor(totalMin / 60);
    const m = totalMin % 60;
    const s = Math.floor((remain % 60000) / 1000);
    return `${h}:${m < 10 ? '0' : ''}${m}:${s < 10 ? '0' : ''}${s}`;
  }

  private elapsedText(): string {
    const totalMin = Math.floor(this.elapsedMs() / 60000);
    const h = Math.floor(totalMin / 60);
    const m = totalMin % 60;
    return `${h} 小时 ${m} 分`;
  }

  private planOf(id: string): FastingPlan | null {
    for (let i = 0; i < FASTING_PLANS.length; i++) {
      if (FASTING_PLANS[i].id === id) {
        return FASTING_PLANS[i];
      }
    }
    return null;
  }

  private async start(p: FastingPlan): Promise<void> {
    if (p.fastingHours <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '自定义窗口需要先设定时长' });
      return;
    }
    try {
      const start = Date.now();
      await FastingRepository.start(this.selectedDate, p.id, start, start + p.fastingHours * 3600 * 1000);
      await this.loadData();
      this.nowMs = Date.now();
      this.getUIContext().getPromptAction().showToast({ message: `已开始 ${p.name}` });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '启动失败' });
    }
  }

  private async completeNow(): Promise<void> {
    if (this.active === null) {
      return;
    }
    try {
      await FastingRepository.complete(this.active.id, Date.now());
      await this.loadData();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '操作失败' });
    }
  }

  private async abandon(): Promise<void> {
    try {
      await FastingRepository.abandon(this.selectedDate);
      await this.loadData();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '操作失败' });
    }
  }

  build() {
    Scroll() {
      Column({ space: space.md }) {
        if (this.active !== null) {
          // 进行中的窗口
          Column({ space: space.sm }) {
            Text(this.planOf(this.active.planId) !== null
              ? (this.planOf(this.active.planId) as FastingPlan).name : this.active.planId)
              .fontSize(fontSize.sectionTitle)
              .fontWeight(FontWeight.Bold)
              .fontColor(color.text)

            Text(this.remainingText())
              .fontSize(40)
              .fontWeight(FontWeight.Bold)
              .fontColor(color.primary)

            Text(`已坚持 ${this.elapsedText()}`)
              .fontSize(fontSize.secondary)
              .fontColor(color.textSecondary)

            // 进度条
            Row()
              .width('100%')
              .height(10)
              .borderRadius(5)
              .backgroundColor(color.ringTrack)
            Row()
              .width(`${Math.round(this.progress() * 100)}%`)
              .height(10)
              .borderRadius(5)
              .backgroundColor(color.primary)
              .animation({ duration: 600, curve: anim.easeData })

            Row({ space: space.md }) {
              Button('标记完成')
                .layoutWeight(1)
                .height(layout.buttonHeight)
                .fontSize(fontSize.body)
                .fontColor(color.onPrimary)
                .backgroundColor(color.primary)
                .borderRadius(14)
                .onClick(() => {
                  this.completeNow();
                })

              Button('放弃')
                .layoutWeight(1)
                .height(layout.buttonHeight)
                .fontSize(fontSize.body)
                .fontColor(color.danger)
                .backgroundColor(color.dangerLight)
                .borderRadius(14)
                .onClick(() => {
                  this.abandon();
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(layout.cardPadding)
          .linearGradient(glassGradient(toneVeil('fasting-active')))
          .borderRadius(glass.cardRadius)
          .border({ width: glass.borderWidth, color: color.glassBorder })
          .backdropBlur(glass.blurRadius)
          .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
          .alignItems(HorizontalAlign.Start)
        }

        Text('选择断食方案')
          .fontSize(fontSize.sectionTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(color.text)
          .width('100%')

        ForEach(FASTING_PLANS, (p: FastingPlan) => {
          Row() {
            Column({ space: 2 }) {
              Text(p.name)
                .fontSize(fontSize.body)
                .fontWeight(FontWeight.Bold)
                .fontColor(color.text)
              Text(p.note)
                .fontSize(fontSize.caption)
                .fontColor(color.textHint)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text(provenanceLabel(p.provenance))
              .fontSize(fontSize.caption)
              .fontColor(color.textHint)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(color.glassFill)
              .borderRadius(radius.small)

            Text('开始')
              .fontSize(fontSize.caption)
              .fontColor(color.primary)
              .padding(8)
              .onClick(() => {
                this.start(p);
              })
          }
          .width('100%')
          .padding(layout.cardPadding)
          .linearGradient(glassGradient(toneVeil(p.id)))
          .borderRadius(glass.cardRadius)
          .border({ width: glass.borderWidth, color: color.glassBorder })
          .backdropBlur(glass.blurRadius)
          .alignItems(VerticalAlign.Center)
        }, (p: FastingPlan) => p.id)

        Text('方案名称为实测（strings 命中）；原版的热量分配与到点提醒无证据，此处未实现。')
          .fontSize(fontSize.caption)
          .fontColor(color.textHint)
          .width('100%')
      }
      .padding(layout.pagePadding)
      .opacity(this.filled ? 1 : 0)
      .translate({ x: 0, y: this.filled ? 0 : anim.enterShiftVp })
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
