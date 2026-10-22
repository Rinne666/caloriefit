/**
 * 华为账号页 —— 登录 / 查看会话 / 退出登录。
 *
 * 入口在「我的 → 华为账号」。
 *
 * 交互要点：
 *   · 登录按钮用**官方 `LoginWithHuaweiIDButton` 组件**。华为设计规范要求
 *     账号登录必须使用官方按钮样式，自绘按钮会被审核驳回。
 *   · 未勾选用户协议时，controller 的协议状态置 NOT_ACCEPTED，点登录会被
 *     Account Kit 拦下（1005300001），界面上也同步置灰。
 *   · 账号标识（UnionID）属个人信息，界面上脱敏显示，不整串露出。
 *   · 退出登录 = 撤销账号侧授权 + 清本地会话，两者都做。
 */

import { common } from '@kit.AbilityKit';
import { loginComponentManager, LoginWithHuaweiIDButton } from '@kit.AccountKit';
import {
  color, fontSize, space, radius, layout,
  glass, glassGradient, glassShadow, pageGradient
} from '../common/DesignTokens';
import { AccountSession } from '../models/AccountSession';
import { AccountRepository } from '../repositories/AccountRepository';
import { HuaweiAccountService, AccountErrorCode } from '../services/HuaweiAccountService';
import { AppDialogService } from '../services/AppDialogService';

@Component
export struct AccountPage {
  @Consume('navStack') navStack: NavPathStack;

  /** 本机会话；null = 未登录 */
  @State private session: AccountSession | null = null;
  /** 是否已勾选用户协议 */
  @State private agreed: boolean = false;
  /** 前置条件是否就绪（client_id 已配） */
  @State private configured: boolean = true;
  /** 登录中的加载态 */
  @State private busy: boolean = false;
  /** 错误提示 */
  @State private errorText: string = '';

  /**
   * 官方按钮的 controller 与 params。
   *
   * 必须是**稳定的实例** —— 每次 build 重建 controller 的话，之前注册的
   * 点击回调就丢了，点了按钮没反应。
   */
  private controller: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController();
  private buttonParams: loginComponentManager.LoginWithHuaweiIDButtonParams = {
    // 白底黑字，与应用现有的主 CTA（#FFFFFF / #0C0C0C）同一套视觉
    style: loginComponentManager.Style.BUTTON_WHITE,
    borderRadius: 24,
    supportDarkMode: true,
    loginType: loginComponentManager.LoginType.ID
  };

  aboutToAppear(): void {
    this.initController();
    this.loadState();
  }

  private initController(): void {
    this.controller
      .setAgreementStatus(loginComponentManager.AgreementStatus.NOT_ACCEPTED)
      .onClickLoginWithHuaweiIDButton((err: BusinessError, credential) => {
        this.onLoginResult(err, credential);
      });
  }

  private loadState(): void {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    const context = ctx as common.UIAbilityContext;
    this.session = AccountRepository.getSession(context);
    HuaweiAccountService.isConfigured().then((ok: boolean) => {
      this.configured = ok;
    });
  }

  private onLoginResult(err: BusinessError, credential: loginComponentManager.HuaweiIDCredential): void {
    if (err !== undefined && err !== null) {
      // 用户取消不提示错误，其余按错误码给出可执行的说明
      if (err.code !== AccountErrorCode.USER_CANCELED) {
        this.errorText = HuaweiAccountService.errorText(err.code);
      }
      this.busy = false;
      return;
    }
    if (credential === undefined || credential === null || credential.unionID.length === 0) {
      this.errorText = HuaweiAccountService.errorText(AccountErrorCode.NOT_LOGGED_IN);
      this.busy = false;
      return;
    }
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    const context = ctx as common.UIAbilityContext;
    const session = new AccountSession(credential.unionID, credential.openID, Date.now());
    AccountRepository.saveSession(context, session);
    this.session = session;
    this.errorText = '';
    this.busy = false;
    AppDialogService.toast('已登录华为账号');
  }

  private toggleAgreement(): void {
    this.agreed = !this.agreed;
    this.controller.setAgreementStatus(
      this.agreed ? loginComponentManager.AgreementStatus.ACCEPTED
        : loginComponentManager.AgreementStatus.NOT_ACCEPTED
    );
  }

  private confirmSignOut(): void {
    AppDialogService.confirm('退出登录', '退出后将清除本机的账号标识，并撤销本应用在华为账号侧的授权。'
      + '本机的饮食、运动等记录不受影响。', '退出登录', () => {
        this.doSignOut();
      });
  }

  private async doSignOut(): Promise<void> {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    this.busy = true;
    await HuaweiAccountService.signOut(ctx as common.UIAbilityContext);
    this.session = null;
    this.busy = false;
    AppDialogService.toast('已退出登录');
  }

  @Builder
  SectionCard(title: string, subtitle: string) {
    Column({ space: space.xs }) {
      Text(title)
        .fontSize(fontSize.sectionTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(color.text)
        .width('100%')
      Text(subtitle)
        .fontSize(fontSize.caption)
        .fontColor(color.textHint)
        .lineHeight(19)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(layout.cardPadding)
    .linearGradient(glassGradient(color.glassFill))
    .borderRadius(glass.cardRadius)
    .border({ width: glass.borderWidth, color: color.glassBorder })
    .shadow(glassShadow(glass.shadowRadius, glass.shadowOffsetY))
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: space.md }) {
          Text('华为账号')
            .fontSize(fontSize.pageTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.text)
            .width('100%')

          if (!this.configured) {
            this.SectionCard('尚未配置 client_id',
              '华为账号登录需要 AGC 控制台分配的 client_id。请在「项目设置 → 常规 → 应用」中获取，'
              + '填入 module.json5 的 metadata.client_id 后重新构建。'
              + '另外 Account Kit 会校验包指纹，调试包必须已签名且证书指纹与 AGC 登记一致。')
          } else if (this.session !== null) {
            this.SectionCard('已登录', '账号标识已保存在本机，不会上传到任何服务器。')
            Row({ space: space.sm }) {
              Column({ space: space.xs }) {
                Text('UnionID')
                  .fontSize(fontSize.caption)
                  .fontColor(color.textHint)
                Text(this.session !== null ? this.session.maskedId() : '')
                  .fontSize(fontSize.body)
                  .fontColor(color.text)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding(layout.cardPadding)
            .linearGradient(glassGradient(color.glassFill))
            .borderRadius(glass.cardRadius)
            .border({ width: glass.borderWidth, color: color.glassBorder })

            Button('退出登录')
              .width('100%')
              .height(layout.buttonHeight)
              .fontSize(fontSize.body)
              .fontColor(color.danger)
              .backgroundColor(color.dangerLight)
              .borderRadius(radius.large)
              .enabled(!this.busy)
              .onClick(() => {
                this.confirmSignOut();
              })
          } else {
            this.SectionCard('登录华为账号',
              '用于在本机标识你的账号，方便识别这是哪台设备上的记录。'
              + '登录后只在本机保存账号标识，不做跨设备同步，也不会上传你的饮食记录。')

            // 用户协议勾选
            Row({ space: space.sm }) {
              Checkbox()
                .select(this.agreed)
                .onChange((value: boolean) => {
                  if (value !== this.agreed) {
                    this.toggleAgreement();
                  }
                })
                .width(24)
                .height(24)
              Text('我已阅读并同意《用户协议》与《隐私政策》')
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
                .lineHeight(22)
                .layoutWeight(1)
                .onClick(() => {
                  this.toggleAgreement();
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)

            if (this.errorText.length > 0) {
              Text(this.errorText)
                .fontSize(fontSize.caption)
                .fontColor(color.danger)
                .lineHeight(19)
                .width('100%')
            }

            // 官方登录按钮。样式必须用官方的，自绘会被审核驳回。
            LoginWithHuaweiIDButton({
              params: this.buttonParams,
              controller: this.controller
            })
            .width('100%')
            .height(48)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(space.lg)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .backgroundColor(color.bg)
      .linearGradient(pageGradient())
    }
    .hideTitleBar(true)
    .backgroundColor(color.bg)
  }
}
