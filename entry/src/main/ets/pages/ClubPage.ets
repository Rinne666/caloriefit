/**
 * 社群 Club —— 对应 NutriScan 首页子页（综合 / 社群 / 饮水 / 断食 之一）
 *
 * 实测依据：日志里有「Club couldn't be loaded」「official posts config read failed」
 * 与开关文案「Afficher mon profil dans le Club」（在 Club 展示我的资料）。
 * 内容源是服务端配置，本地拉不到 —— 所以帖子全部是 MOCK，
 * 每张卡片右上角都带「示例」角标，不伪装成真实用户内容。
 */

import { color, fontSize, space, layout, glass, glassGradient, glassShadow, toneVeil } from '../common/DesignTokens';
import { anim } from '../common/Motion';
import { CLUB_POSTS, ClubPost, Provenance, provenanceLabel } from '../services/MockContent';

@Component
export struct ClubPage {
  @State private entered: boolean = false;
  @State private showProfile: boolean = true;

  enterView(): void {
    this.entered = true;
  }

  build() {
    Scroll() {
      Column({ space: space.md }) {
        // 「在 Club 展示我的资料」开关（对应实测文案）
        Row() {
          Column({ space: 2 }) {
            Text('在 Club 展示我的资料')
              .fontSize(fontSize.body)
              .fontColor(color.text)
            Text('关闭后其他成员看不到你的记录与排名')
              .fontSize(fontSize.caption)
              .fontColor(color.textHint)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.showProfile })
            .onChange((v: boolean) => {
              this.showProfile = v;
            })
        }
        .width('100%')
        .padding(layout.cardPadding)
        .linearGradient(glassGradient(toneVeil('club-toggle')))
        .borderRadius(glass.cardRadius)
        .border({ width: glass.borderWidth, color: color.glassBorder })
        .backdropBlur(glass.blurRadius)
        .alignItems(VerticalAlign.Center)

        Text('动态')
          .fontSize(fontSize.sectionTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(color.text)
          .width('100%')

        ForEach(CLUB_POSTS, (post: ClubPost) => {
          Column({ space: space.sm }) {
            Row({ space: space.xs }) {
              Text(post.official ? '📢' : '👤')
                .fontSize(20)
              Column({ space: 1 }) {
                Text(post.author)
                  .fontSize(fontSize.secondary)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(color.text)
                Text(post.badge)
                  .fontSize(fontSize.caption)
                  .fontColor(color.textHint)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(provenanceLabel(post.provenance))
                .fontSize(fontSize.caption)
                .fontColor(color.textHint)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor(color.glassFill)
                .borderRadius(6)
            }
            .width('100%')

            Text(post.content)
              .fontSize(fontSize.body)
              .fontColor(color.text)
              .width('100%')

            Row({ space: space.lg }) {
              Text(`👍 ${post.likes}`)
                .fontSize(fontSize.caption)
                .fontColor(color.textHint)
              Text(`💬 ${post.comments}`)
                .fontSize(fontSize.caption)
                .fontColor(color.textHint)
            }
            .width('100%')
          }
          .width('100%')
          .padding(layout.cardPadding)
          .linearGradient(glassGradient(toneVeil(post.id)))
          .borderRadius(glass.cardRadius)
          .border({ width: glass.borderWidth, color: color.glassBorder })
          .backdropBlur(glass.blurRadius)
          .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
          .alignItems(HorizontalAlign.Start)
        }, (post: ClubPost) => post.id)

        Text('帖子内容为示例数据：原版由服务端下发，本地无法拉取真实内容。')
          .fontSize(fontSize.caption)
          .fontColor(color.textHint)
          .width('100%')
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
