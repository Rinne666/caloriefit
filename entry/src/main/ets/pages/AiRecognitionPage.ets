/**
 * AI 食物识别页：选图 → 预览 → 识别（加载弹窗）→ 结果卡 → 使用结果并编辑。
 * AI 结果只允许预填，不直接写库。
 */

import { PhotoPickerService } from '../services/PhotoPickerService';
import { ImageProcessor } from '../services/ImageProcessor';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { AiRecognitionService } from '../services/AiRecognitionService';
import { AiConfigRepository } from '../repositories/AiConfigRepository';
import { AiCredentialStore } from '../repositories/AiCredentialStore';
import { AppDialogService } from '../services/AppDialogService';
import { AiImagePayload } from '../models/AiImagePayload';
import { AiRecognitionResult } from '../models/AiRecognitionResult';
import { AiErrorCode, AiError, aiErrorText, AI_LOW_CONFIDENCE } from '../common/AiConstants';
import { color, fontSize, space, radius, layout, pageGradient } from '../common/DesignTokens';
import { formatNumber } from '../common/DateUtils';

/** 内置示例图文件名，放在 resources/rawfile 下 */
const SAMPLE_RAW_FILE: string = 'sample_meal.jpg';

class AiRecognitionParams {  date: string = '';
}

class AiEditParams {
  mode: string = 'ai';
  date: string = '';
  name: string = '';
  calories: number = 0;
  aiConfidence: number = 0;
  aiNotes: string = '';
  /** V3：AI 估算的三大宏量，透传给编辑页预填 */
  proteinG: number | null = null;
  carbsG: number | null = null;
  fatG: number | null = null;
}

@Component
export struct AiRecognitionPage {
  @Consume('navStack') navStack: NavPathStack;
  @State date: string = '';
  @State photoUri: string | null = null;
  @State result: AiRecognitionResult | null = null;
  @State errorMessage: string = '';
  @State hasError: boolean = false;
  @State busy: boolean = false;
  @State demoMode: boolean = false;
  private requestSeq: number = 0;

  private buildParams(p: AiRecognitionParams | null | undefined): void {
    if (p !== null && p !== undefined && typeof p.date === 'string') {
      this.date = p.date;
    }
    this.demoMode = AiConfigRepository.isDemoMode();
  }

  /**
   * 载入内置示例图，让整条识别链路在没有相册的环境下也能跑通。
   *
   * 为什么要多这一步拷贝：
   *   $rawfile() 在本 SDK 返回的是 **Resource 对象**，不是路径字符串；
   *   而 ImageProcessor.prepareImage() 走 fileIo.open(uri: string)，
   *   需要真实路径。所以先把 rawfile 的字节读出来写到 cacheDir，
   *   拿到一个货真价实的字符串路径。
   */
  private async useSampleImage(): Promise<void> {
    if (this.busy) {
      return;
    }
    try {
      const host = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const bytes = await host.resourceManager.getRawFileContent(SAMPLE_RAW_FILE);
      const dst = `${host.cacheDir}/${SAMPLE_RAW_FILE}`;
      const f = fileIo.openSync(dst, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE
        | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, bytes.buffer);
      fileIo.closeSync(f);
      this.photoUri = dst;
      this.result = null;
      this.hasError = false;
      this.errorMessage = '';
    } catch (e) {
      this.hasError = true;
      this.errorMessage = '示例图载入失败，请改用相册或拍照';
    }
  }

  private bumpRefresh(): void {    const cur = AppStorage.get<number>('refreshTick') ?? 0;
    AppStorage.setOrCreate<number>('refreshTick', cur + 1);
  }

  private async pickImage(): Promise<void> {
    if (this.busy) {
      return;
    }
    try {
      const uri = await PhotoPickerService.selectOneImage();
      if (uri === null) {
        return;
      }
      this.photoUri = uri;
      this.result = null;
      this.hasError = false;
      this.errorMessage = '';
    } catch (e) {
      this.showError(e);
    }
  }

  private async capturePhoto(): Promise<void> {
    if (this.busy) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      const uri = await PhotoPickerService.captureImage(context);
      if (uri === null) {
        return;
      }
      this.photoUri = uri;
      this.result = null;
      this.hasError = false;
      this.errorMessage = '';
    } catch (e) {
      this.showError(e);
    }
  }

  private showError(e: object): void {
    const code = e instanceof AiError ? e.code : AiErrorCode.NETWORK_ERROR;
    this.errorMessage = aiErrorText(code);
    this.hasError = true;
  }

  private async startRecognize(): Promise<void> {
    if (this.busy || this.photoUri === null) {
      return;
    }
    // 无 Key：跳设置或手动
    let apiKey = '';
    try {
      apiKey = (await AiCredentialStore.getApiKey()) ?? '';
    } catch (e) {
      apiKey = '';
    }
    if (apiKey.length === 0) {
      const demo = AiConfigRepository.isDemoMode();
      if (!demo) {
        this.askForApiKey();
        return;
      }
    }

    const seq = ++this.requestSeq;
    this.busy = true;
    this.hasError = false;
    this.errorMessage = '';
    const loadingId = AppDialogService.showLoading('正在识别食物…');
    try {
      const imagePayload = await ImageProcessor.prepareImage(this.photoUri!);
      const config = await AiConfigRepository.loadConfig();
      const result = await AiRecognitionService.recognize(imagePayload, config, apiKey);
      if (seq !== this.requestSeq) {
        return; // 迟到结果丢弃
      }
      this.result = result;
    } catch (e) {
      if (seq !== this.requestSeq) {
        return;
      }
      this.showError(e as object);
    } finally {
      if (seq === this.requestSeq) {
        this.busy = false;
        AppDialogService.closeLoading(loadingId);
      }
    }
  }

  private askForApiKey(): void {
    AppDialogService.confirm('需要 API Key',
      '尚未配置 AI 服务密钥。是否前往 AI 设置页配置？也可以继续手动录入。',
      '去设置', () => {
        this.navStack.pushPathByName('AiSettings', new Object());
      });
  }

  private useResult(): void {
    if (this.result === null || this.result.estimatedTotalKcal === null) {
      return;
    }
    const p = new AiEditParams();
    p.mode = 'ai';
    p.date = this.date;
    p.name = this.result.foodName;
    p.calories = this.result.estimatedTotalKcal;
    p.aiConfidence = this.result.confidence;
    p.aiNotes = this.result.notes;
    p.proteinG = this.result.proteinG;
    p.carbsG = this.result.carbsG;
    p.fatG = this.result.fatG;
    this.navStack.pushPathByName('FoodEdit', p);
  }

  private goManual(): void {
    const p = new AiEditParams();
    p.mode = 'add';
    p.date = this.date;
    this.navStack.pushPathByName('FoodEdit', p);
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: space.md }) {
          // 标题
          Text('AI 食物识别')
            .fontSize(fontSize.pageTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(color.text)
            .width('100%')

          // 演示模式显著标注（PM 要求）
          if (this.demoMode) {
            Text('⚠ 演示模式：当前结果为本地模拟数据，并非真实 AI 识别')
              .fontSize(fontSize.secondary)
              .fontColor(color.food)
              .padding(space.sm)
              .backgroundColor(color.foodLight)
              .borderRadius(radius.medium)
              .width('100%')
          }

          // 选图区域
          if (this.photoUri === null) {
            Column({ space: space.md }) {
              Column({ space: space.sm }) {
                Text('📷')
                  .fontSize(40)
                Text('获取一张食物照片')
                  .fontSize(fontSize.body)
                  .fontColor(color.text)
                Text('支持 JPG、PNG · 最多一张')
                  .fontSize(fontSize.caption)
                  .fontColor(color.textHint)
              }
              .alignItems(HorizontalAlign.Center)

              Row({ space: space.sm }) {
                Button('从相册选择')
                  .layoutWeight(1)
                  .height(44)
                  .fontSize(fontSize.body)
                  .fontColor(color.onPrimary)
                  .backgroundColor(color.primary)
                  .borderRadius(radius.large)
                  .onClick(() => {
                    this.pickImage();
                  })
                Button('拍照')
                  .layoutWeight(1)
                  .height(44)
                  .fontSize(fontSize.body)
                  .fontColor(color.primary)
                  .backgroundColor(color.surface)
                  .borderRadius(radius.large)
                  .border({ width: layout.borderWidth, color: color.primary })
                  .onClick(() => {
                    this.capturePhoto();
                  })
              }
              .width('100%')

              /**
               * 内置示例图。
               *
               * 为什么需要它：模拟器只有 /data/local/tmp 可写，
               * 图库里塞不进照片，「从相册选择」在模拟器上永远返回空。
               * 这条入口让整条链路在任何设备上都能走通 ——
               * 配了 Key 就走真实识别，演示模式则返回本地模拟数据。
               *
               * 放 rawfile 而不是 media：prepareImage() 走 fileIo.open()
               * 需要真实文件路径，$rawfile() 正好给字符串路径；
               * $r('app.media.*') 给的是 Resource 对象，喂不进 fileIo。
               */
              Button('没有照片？用内置示例图试一下')
                .width('100%')
                .height(40)
                .fontSize(fontSize.caption)
                .fontColor(color.textHint)
                .backgroundColor(Color.Transparent)
                .onClick(() => {
                  this.useSampleImage();
                })
            }
            .width('100%')
            .padding(layout.cardPadding)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(color.surfaceMuted)
            .borderRadius(16)
          } else {
            Column() {
              Image(this.photoUri)
                .width('100%')
                .height(180)
                .objectFit(ImageFit.Cover)
                .borderRadius(16)
            }
            .width('100%')

            Row({ space: space.sm }) {
              Button('更换图片')
                .layoutWeight(1)
                .height(40)
                .fontSize(fontSize.secondary)
                .fontColor(color.primary)
                .backgroundColor(color.primaryLight)
                .borderRadius(radius.pill)
                .onClick(() => {
                  this.pickImage();
                })
              Button('重新拍照')
                .layoutWeight(1)
                .height(40)
                .fontSize(fontSize.secondary)
                .fontColor(color.primary)
                .backgroundColor(color.primaryLight)
                .borderRadius(radius.pill)
                .onClick(() => {
                  this.capturePhoto();
                })
            }
            .width('100%')
          }

          // 隐私提示
          Text('照片将发送至配置的 AI 服务进行分析，热量结果仅供参考。')
            .fontSize(fontSize.caption)
            .fontColor(color.textHint)
            .width('100%')

          // 开始识别
          Button('开始 AI 识别')
            .width('100%')
            .height(layout.buttonHeight)
            .fontSize(fontSize.body)
            .fontColor(color.onPrimary)
            .backgroundColor(color.primary)
            .borderRadius(radius.large)
            .enabled(this.photoUri !== null && !this.busy)
            .onClick(() => {
              this.startRecognize();
            })

          // 错误卡
          if (this.hasError) {
            Column({ space: space.sm }) {
              Text(this.errorMessage)
                .fontSize(fontSize.body)
                .fontColor(color.danger)
              Row({ space: space.md }) {
                Button('重试')
                  .layoutWeight(1)
                  .height(40)
                  .fontSize(fontSize.body)
                  .fontColor(color.onPrimary)
                  .backgroundColor(color.primary)
                  .borderRadius(radius.large)
                  .onClick(() => {
                    this.startRecognize();
                  })
                Button('手动录入')
                  .layoutWeight(1)
                  .height(40)
                  .fontSize(fontSize.body)
                  .fontColor(color.primary)
                  .backgroundColor(color.primaryLight)
                  .borderRadius(radius.large)
                  .onClick(() => {
                    this.goManual();
                  })
              }
              .width('100%')
            }
            .alignItems(HorizontalAlign.Center)
            .padding(layout.cardPadding)
            .backgroundColor(color.dangerLight)
            .borderRadius(radius.card)
            .width('100%')
          }

          // 结果卡
          if (this.result !== null) {
            Column({ space: space.sm }) {
              Row() {
                Text('识别结果')
                  .fontSize(fontSize.sectionTitle)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(color.text)
                  .layoutWeight(1)
                Text('AI 估算')
                  .fontSize(fontSize.caption)
                  .fontColor(color.primary)
                  .backgroundColor(color.primaryLight)
                  .borderRadius(radius.pill)
                  .padding({ left: space.sm, right: space.sm, top: 4, bottom: 4 })
              }
              .width('100%')

              if (this.result.estimatedTotalKcal !== null) {
                Column({ space: 4 }) {
                  Text('估算整份热量')
                    .fontSize(fontSize.secondary)
                    .fontColor(color.textSecondary)
                  Row({ space: space.xxs }) {
                    Text(formatNumber(this.result.estimatedTotalKcal))
                      .fontSize(fontSize.metric)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(color.primary)
                    Text('kcal')
                      .fontSize(fontSize.caption)
                      .fontColor(color.textHint)
                      .margin({ bottom: 5 })
                  }
                  .alignItems(VerticalAlign.Bottom)
                }
                .alignItems(HorizontalAlign.Center)
                .width('100%')

                Text(this.result.foodName)
                  .fontSize(fontSize.body)
                  .fontColor(color.text)
                  .width('100%')

                // V3：三大宏量估算
                if (this.result.hasMacros()) {
                  Row({ space: space.xs }) {
                    Column({ space: 2 }) {
                      Text('蛋白')
                        .fontSize(fontSize.caption)
                        .fontColor(color.textHint)
                      Text(`${this.result.proteinG}g`)
                        .fontSize(fontSize.body)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(color.text)
                    }
                    .layoutWeight(1)

                    Column({ space: 2 }) {
                      Text('碳水')
                        .fontSize(fontSize.caption)
                        .fontColor(color.textHint)
                      Text(`${this.result.carbsG}g`)
                        .fontSize(fontSize.body)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(color.text)
                    }
                    .layoutWeight(1)

                    Column({ space: 2 }) {
                      Text('脂肪')
                        .fontSize(fontSize.caption)
                        .fontColor(color.textHint)
                      Text(`${this.result.fatG}g`)
                        .fontSize(fontSize.body)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(color.text)
                    }
                    .layoutWeight(1)
                  }
                  .width('100%')
                  .padding({ top: space.xs, bottom: space.xs })
                  .backgroundColor(color.surfaceMuted)
                  .borderRadius(radius.medium)
                } else if (this.result.estimatedTotalKcal !== null) {
                  Text('未能可靠估算宏量，可在下一步手动补录')
                    .fontSize(fontSize.caption)
                    .fontColor(color.textHint)
                    .width('100%')
                }

                Text(`AI 置信度：${this.result.confidence.toFixed(2)}（自评，非准确率）`)
                  .fontSize(fontSize.caption)
                  .fontColor(color.textHint)
                  .width('100%')

                Text(this.result.notes)
                  .fontSize(fontSize.secondary)
                  .fontColor(color.textSecondary)
                  .width('100%')

                if (this.result.confidence < AI_LOW_CONFIDENCE) {
                  Text('⚠ 识别置信度较低，请仔细核对后保存')
                    .fontSize(fontSize.secondary)
                    .fontColor(color.food)
                    .padding(space.sm)
                    .backgroundColor(color.foodLight)
                    .borderRadius(radius.medium)
                    .width('100%')
                }

                Button('使用结果并编辑')
                  .width('100%')
                  .height(layout.buttonHeight)
                  .fontSize(fontSize.body)
                  .fontColor(color.onPrimary)
                  .backgroundColor(color.primary)
                  .borderRadius(radius.large)
                  .onClick(() => {
                    this.useResult();
                  })
              } else {
                Text('无法可靠识别这张图片中的食物，请手动录入。')
                  .fontSize(fontSize.body)
                  .fontColor(color.textSecondary)
                Button('手动录入')
                  .width('100%')
                  .height(40)
                  .fontSize(fontSize.body)
                  .fontColor(color.onPrimary)
                  .backgroundColor(color.primary)
                  .borderRadius(radius.large)
                  .onClick(() => {
                    this.goManual();
                  })
              }
            }
            .padding(layout.cardPadding)
            .backgroundColor(color.surface)
            .borderRadius(radius.card)
            .border({ width: layout.borderWidth, color: color.border })
            .width('100%')
          }
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
    .title('AI 拍照识别')
    .backgroundColor(color.bg)
    .linearGradient(pageGradient())
    .onReady((ctx: NavDestinationContext) => {
      const p = ctx.pathInfo.param as AiRecognitionParams | null | undefined;
      this.buildParams(p);
    })
  }
}