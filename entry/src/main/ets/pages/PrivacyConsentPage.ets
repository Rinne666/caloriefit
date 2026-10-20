import { common } from '@kit.AbilityKit';
import { AppDialogService } from '../services/AppDialogService';
import { PrivacyConsentService } from '../services/PrivacyConsentService';
import { PrivacyPolicyContent } from '../components/PrivacyPolicyContent';
import { color, fontSize, space, radius, layout, pageGradient } from '../common/DesignTokens';
import { Compliance } from '../common/Compliance';

@Component
export struct PrivacyConsentPage {
  onAccepted: () => void = () => {};

  @State private generalAccepted: boolean = false;
  @State private healthAccepted: boolean = false;
  @State private saving: boolean = false;
  @State private showPolicy: boolean = false;

  /**
   * 政策是**页内浮层**（showPolicy），不是 NavDestination。
   * 不接管返回键的话，用户在政策页按返回会直接**退出整个应用**，
   * 而不是回到同意页 —— 同意流程被打断，用户得重新冷启动。
   *
   * 返回 true 表示"已处理"，系统不再往下传。
   */
  onBackPress(): boolean {
    if (this.showPolicy) {
      this.showPolicy = false;
      return true;
    }
    return false;
  }

  private async acceptAndContinue(): Promise<void> {
    if (this.saving || !this.generalAccepted || !this.healthAccepted) {
      return;
    }
    const host = this.getUIContext().getHostContext();
    if (host === undefined) {
      AppDialogService.toast('无法读取应用上下文，请重启应用后重试');
      return;
    }
    this.saving = true;
    try {
      await PrivacyConsentService.accept(host as common.UIAbilityContext);
      this.onAccepted();
    } catch (e) {
      AppDialogService.toast('同意记录保存失败，请重试');
    } finally {
      this.saving = false;
    }
  }

  private async declineAndExit(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (host === undefined) {
      return;
    }
    try {
      await (host as common.UIAbilityContext).terminateSelf();
    } catch (e) {
      AppDialogService.toast('如不同意，请通过系统返回键离开应用；此时不会保存健康资料');
    }
  }

  @Builder
  ConsentRow(label: string, checked: boolean, onToggle: () => void) {
    Row({ space: space.sm }) {
      Checkbox()
        .select(checked)
        .onChange((value: boolean) => {
          if (value !== checked) {
            onToggle();
          }
        })
        .width(24)
        .height(24)
      Text(label)
        .fontSize(fontSize.secondary)
        .fontColor(color.textSecondary)
        .lineHeight(22)
        .layoutWeight(1)
        .onClick(onToggle)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  build() {
    Column() {
      if (this.showPolicy) {
        Row({ space: space.sm }) {
          Button('‹')
            .width(42)
            .height(42)
            .fontSize(30)
            .fontColor(color.text)
            .backgroundColor(Color.Transparent)
            .onClick(() => this.showPolicy = false)
          Text('隐私政策')
            .fontSize(fontSize.sectionTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.text)
        }
        .width('100%')
        .padding({ left: space.sm, right: space.md, top: space.sm, bottom: space.sm })

        Scroll() {
          PrivacyPolicyContent()
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      } else {
        Scroll() {
          Column({ space: space.lg }) {
            Text('CalorieFit')
              .fontSize(fontSize.caption)
              .fontWeight(FontWeight.Bold)
              .fontColor(color.primary)
              .width('100%')

            Text('请先阅读隐私说明')
              .fontSize(fontSize.pageTitle)
              .fontWeight(FontWeight.Bold)
              .fontColor(color.text)
              .width('100%')

            Text('本应用提供个性化热量估算与健康记录。开始前，请了解本机数据处理方式，并分别决定是否同意处理健康信息。')
              .fontSize(fontSize.body)
              .fontColor(color.textSecondary)
              .lineHeight(25)
              .width('100%')

            // 政策入口放在首屏固定位置：说明文字一旦变长，它就会被挤出折叠线以下，
            // 用户看不到政策全文，审核时也判为"政策不可达"。
            Button('阅读完整隐私政策')
              .width('100%')
              .height(42)
              .fontSize(fontSize.secondary)
              .fontColor(color.primary)
              .backgroundColor(color.primaryLight)
              .borderRadius(radius.medium)
              .onClick(() => this.showPolicy = true)

            Column({ space: space.md }) {
              Text('会在本机处理')
                .fontSize(fontSize.sectionTitle)
                .fontWeight(FontWeight.Bold)
                .fontColor(color.text)
              Text('你主动填写的身体档案、目标，以及主动添加的饮食、运动、饮水和断食记录，用于热量计算与记录统计。你在运动页主动开启计步采集后，当日步数会从设备计步传感器读入并保存在本机。当前版本不设自有账号体系，也不把这些本地记录同步到开发者服务器；若你选择登录华为账号，账号标识同样只保存在本机。')
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
                .lineHeight(23)
              Text('AI 食物识别为可选功能。真实识别会在每次上传前再次说明图片与 API Key 的接收地址；拒绝上传仍可手动记录。')
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
                .lineHeight(23)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(layout.cardPadding)
            .backgroundColor(color.surface)
            .border({ width: layout.borderWidth, color: color.border })
            .borderRadius(radius.card)

            if (Compliance.isDraft) {
              Text(`开发预览提示：${Compliance.pendingSummary()}此版本不能直接作为正式上架政策。`)
                .fontSize(fontSize.caption)
                .fontColor(color.food)
                .lineHeight(20)
                .width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(layout.pagePadding)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)

        Column({ space: space.md }) {
          this.ConsentRow(
            '我已阅读并同意《隐私政策》及个人信息处理规则',
            this.generalAccepted,
            () => this.generalAccepted = !this.generalAccepted
          )
          this.ConsentRow(
            '我单独同意处理身体档案、饮食、运动、饮水和断食等健康信息',
            this.healthAccepted,
            () => this.healthAccepted = !this.healthAccepted
          )

          Button('同意并继续')
            .width('100%')
            .height(layout.buttonHeight)
            .fontSize(fontSize.body)
            .fontColor(this.generalAccepted && this.healthAccepted ? color.onPrimary : color.disabledText)
            .backgroundColor(this.generalAccepted && this.healthAccepted ? color.primary : color.disabledBg)
            .borderRadius(radius.large)
            .enabled(this.generalAccepted && this.healthAccepted && !this.saving)
            .onClick(() => this.acceptAndContinue())

          Button('不同意并退出')
            .width('100%')
            .height(42)
            .fontSize(fontSize.secondary)
            .fontColor(color.textSecondary)
            .backgroundColor(Color.Transparent)
            .onClick(() => this.declineAndExit())
        }
        .width('100%')
        .padding({ left: layout.pagePadding, right: layout.pagePadding, top: space.sm, bottom: space.md })
        .backgroundColor(color.bg)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(color.bg)
    .linearGradient(pageGradient())
  }
}
