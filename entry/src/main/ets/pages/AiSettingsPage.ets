/**
 * AI 设置页：模型名称 / Base URL / API Key（掩码+显隐）/ 安全记住 / 演示模式 / 清除 Key。
 */

import { AiConfigRepository } from '../repositories/AiConfigRepository';
import { AiCredentialStore } from '../repositories/AiCredentialStore';
import { AppDialogService } from '../services/AppDialogService';
import { AiConfig } from '../models/AiConfig';
import { color, fontSize, space, radius, layout, pageGradient } from '../common/DesignTokens';
import { AiDefaults } from '../common/AiConstants';

/** Base URL 校验：仅允许 HTTPS 且 host 属于百炼域名 */
function validateBaseUrl(input: string): boolean {
  const trimmed = input.trim();
  if (!trimmed.startsWith('https://')) {
    return false;
  }
  try {
    const host = trimmed.replace('https://', '').split('/')[0].split(':')[0];
    return host === 'dashscope.aliyuncs.com' || host.endsWith('.maas.aliyuncs.com');
  } catch (e) {
    return false;
  }
}

@Component
export struct AiSettingsPage {
  @State modelInput: string = AiDefaults.MODEL_NAME;
  @State baseUrlInput: string = AiDefaults.BASE_URL;
  @State keyInput: string = '';
  @State showKey: boolean = false;
  @State rememberKey: boolean = false;
  @State demoMode: boolean = false;
  @State hasStoredKey: boolean = false;

  aboutToAppear(): void {
    this.loadConfig();
  }

  private async loadConfig(): Promise<void> {
    try {
      const config = await AiConfigRepository.loadConfig();
      this.modelInput = config.modelName;
      this.baseUrlInput = config.baseUrl;
      this.rememberKey = config.rememberApiKey;
      this.demoMode = AiConfigRepository.isDemoMode();
      const key = await AiCredentialStore.getApiKey();
      this.hasStoredKey = key !== null && key.length > 0;
    } catch (e) {
      AppDialogService.toast('加载配置失败');
    }
  }

  private async saveConfig(): Promise<void> {
    const model = this.modelInput.trim();
    const baseUrl = this.baseUrlInput.trim();
    if (model.length === 0) {
      AppDialogService.toast('模型名称不能为空');
      return;
    }
    if (!validateBaseUrl(baseUrl)) {
      AppDialogService.toast('Base URL 必须是 https 且属于百炼域名');
      return;
    }
    try {
      const config = new AiConfig(baseUrl, model, this.rememberKey);
      await AiConfigRepository.saveConfig(config);
      const key = this.keyInput.trim();
      if (key.length > 0) {
        await AiCredentialStore.saveApiKey(key, this.rememberKey);
        if (this.rememberKey) {
          const ok = await AiCredentialStore.canPersistSecurely();
          if (!ok) {
            AppDialogService.toast('无法安全记住 Key，本次会话内有效');
          } else {
            AppDialogService.toast('配置已保存，API Key 已安全记住');
          }
        } else {
          AppDialogService.toast('配置已保存，Key 本次会话内有效');
        }
      } else {
        AppDialogService.toast('配置已保存');
      }
      this.keyInput = '';
      this.hasStoredKey = (await AiCredentialStore.getApiKey()) !== null;
    } catch (e) {
      AppDialogService.toast('保存失败：当前环境无法安全存储，请改用会话模式');
    }
  }

  private confirmClearKey(): void {
    AppDialogService.confirm('清除 API Key',
      '将删除安全存储与本会话中的 API Key，AI 识别将不可用，直到重新配置。',
      '清除', () => {
        this.doClearKey();
      });
  }

  private async doClearKey(): Promise<void> {
    try {
      await AiCredentialStore.clearApiKey();
      this.hasStoredKey = false;
      this.keyInput = '';
      AppDialogService.toast('API Key 已清除');
    } catch (e) {
      AppDialogService.toast('清除失败');
    }
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: space.md }) {
          Text('AI 识别设置')
            .fontSize(fontSize.pageTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.text)
            .width('100%')

          // 模型与地址
          Column({ space: space.md }) {
            Column({ space: space.xs }) {
              Text('模型名称')
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
              TextInput({ text: this.modelInput, placeholder: '例如 qwen3-vl-plus' })
                .height(layout.inputHeight)
                .fontSize(fontSize.body)
                .backgroundColor(color.surfaceMuted)
                .borderRadius(radius.medium)
                .onChange((value: string) => {
                  this.modelInput = value;
                })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            Column({ space: space.xs }) {
              Text('Base URL（兼容模式根地址）')
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
              TextInput({ text: this.baseUrlInput })
                .height(layout.inputHeight)
                .fontSize(fontSize.caption)
                .backgroundColor(color.surfaceMuted)
                .borderRadius(radius.medium)
                .onChange((value: string) => {
                  this.baseUrlInput = value;
                })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            Column({ space: space.xs }) {
              Text(`API Key${this.hasStoredKey ? '（已存储，输入可更换）' : ''}`)
                .fontSize(fontSize.secondary)
                .fontColor(color.textSecondary)
              Row({ space: space.sm }) {
                TextInput({ text: this.keyInput, placeholder: 'sk-…' })
                  .type(InputType.Password)
                  .showPasswordIcon(this.showKey)
                  .height(layout.inputHeight)
                  .fontSize(fontSize.body)
                  .backgroundColor(color.surfaceMuted)
                  .borderRadius(radius.medium)
                  .layoutWeight(1)
                  .onChange((value: string) => {
                    this.keyInput = value;
                  })
              }
              .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            Row() {
              Column({ space: 2 }) {
                Text('安全记住 API Key')
                  .fontSize(fontSize.body)
                  .fontColor(color.text)
                Text('启用后使用系统安全存储，下次启动自动读取')
                  .fontSize(fontSize.caption)
                  .fontColor(color.textHint)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.rememberKey })
                .selectedColor(color.primary)
                .onChange((isOn: boolean) => {
                  this.rememberKey = isOn;
                })
            }
            .width('100%')

            Row() {
              Column({ space: 2 }) {
                Text('演示模式（不发送网络请求）')
                  .fontSize(fontSize.body)
                  .fontColor(color.text)
                Text('使用本地模拟 AI 响应，用于无 Key 演示完整链路')
                  .fontSize(fontSize.caption)
                  .fontColor(color.textHint)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.demoMode })
                .selectedColor(color.primary)
                .onChange((isOn: boolean) => {
                  this.demoMode = isOn;
                  AiConfigRepository.setDemoMode(isOn);
                })
            }
            .width('100%')
          }
          .padding(layout.cardPadding)
          .backgroundColor(color.surface)
          .borderRadius(radius.card)
          .border({ width: layout.borderWidth, color: color.border })
          .width('100%')

          // 保存
          Button('保存配置')
            .width('100%')
            .height(layout.buttonHeight)
            .fontSize(fontSize.body)
            .fontColor(color.onPrimary)
            .backgroundColor(color.primary)
            .borderRadius(radius.large)
            .onClick(() => {
              this.saveConfig();
            })

          // 清除 Key
          Button('清除 API Key')
            .width('100%')
            .height(layout.buttonHeight)
            .fontSize(fontSize.body)
            .fontColor(color.danger)
            .backgroundColor(color.dangerLight)
            .borderRadius(radius.large)
            .onClick(() => {
              this.confirmClearKey();
            })

          Text('安全说明：API Key 不写入代码、日志或普通配置文件；选择“记住”时仅存入系统安全存储。')
            .fontSize(fontSize.caption)
            .fontColor(color.textHint)
            .width('100%')
        }
        .padding(layout.pagePadding)
        .constraintSize({ minHeight: '100%' })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .backgroundColor(color.bg)
      .linearGradient(pageGradient())
    }
    .title('AI 设置')
    .backgroundColor(color.bg)
    .linearGradient(pageGradient())
  }
}