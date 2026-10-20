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
import { AiConfig } from '../models/AiConfig';
import { FoodRegion } from '../models/FoodSticker';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AiErrorCode, AiError, aiErrorText, AI_LOW_CONFIDENCE } from '../common/AiConstants';
import { StickerCutoutService } from '../services/StickerCutoutService';
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
  /** V6：抠好的食物贴纸（相对 filesDir 的路径），透传给编辑页入库 */
  stickerPath: string = '';
}

@Component
export struct AiRecognitionPage {
  @Consume('navStack') navStack: NavPathStack;
  @State date: string = '';
  @State photoUri: string | null = null;
  /**
   * 预览用的图片源，与 photoUri 分开。
   *
   * photoUri 必须是**真实文件路径**（prepareImage 走 fileIo.open）；
   * 而 ArkUI 的 Image 对沙箱真实路径不一定能解码 —— 实测把 cacheDir 里的
   * 真实路径直接喂给 Image，预览区是一片空白（文件本身完好、fileIo 也能读）。
   * rawfile 的 Resource 才是 Image 认的形式，所以：显示走 $rawfile 资源，
   * 读取走缓存副本，两条通道各司其职。
   */
  @State private previewSrc: ResourceStr = '';
  @State result: AiRecognitionResult | null = null;
  @State errorMessage: string = '';
  @State hasError: boolean = false;
  @State busy: boolean = false;
  @State private requestPending: boolean = false;
  @State demoMode: boolean = false;
  /**
   * V6：抠好的食物贴纸。
   * stickerPath 是落盘路径（给编辑页入库）；stickerPreviewUri 是给本页预览的
   * base64 data URI —— ArkUI 的 Image 解不了沙箱真实路径（见 previewSrc 注释），
   * 所以显示一律走 data URI。
   */
  @State stickerPath: string = '';
  @State stickerPreviewUri: string = '';
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
      this.previewSrc = $rawfile(SAMPLE_RAW_FILE);
      this.result = null;
      this.stickerPath = '';
      this.stickerPreviewUri = '';
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
      this.previewSrc = uri;
      this.result = null;
      this.stickerPath = '';
      this.stickerPreviewUri = '';
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
      this.previewSrc = uri;
      this.result = null;
      this.stickerPath = '';
      this.stickerPreviewUri = '';
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
    if (this.busy || this.requestPending || this.photoUri === null) {
      return;
    }
    const demo = AiConfigRepository.isDemoMode();
    // 无 Key：跳设置或手动
    let apiKey = '';
    try {
      apiKey = (await AiCredentialStore.getApiKey()) ?? '';
    } catch (e) {
      apiKey = '';
    }
    if (apiKey.length === 0) {
      if (!demo) {
        this.askForApiKey();
        return;
      }
    }

    try {
      const config = await AiConfigRepository.loadConfig();
      if (!demo) {
        this.requestPending = true;
        this.getUIContext().showAlertDialog({
          title: '确认发送食物照片',
          message: `本次选中的照片会缩放并压缩后，通过 HTTPS 发送至以下 AI 服务：\n${config.baseUrl}\n\n请求还会携带你配置的 API Key。应用没有自有服务器中转；接收方的处理和留存规则以该服务方政策为准。不同意可取消并手动记录。`,
          primaryButton: {
            value: '取消',
            action: () => {
              this.requestPending = false;
            }
          },
          secondaryButton: {
            value: '同意并识别',
            action: () => {
              this.requestPending = false;
              this.performRecognition(config, apiKey);
            }
          }
        });
        return;
      }
      await this.performRecognition(config, apiKey);
    } catch (e) {
      this.requestPending = false;
      this.showError(e as object);
    }
  }

  private async performRecognition(config: AiConfig, apiKey: string): Promise<void> {
    const seq = ++this.requestSeq;
    this.busy = true;
    this.hasError = false;
    this.errorMessage = '';
    const loadingId = AppDialogService.showLoading('正在识别食物…');
    try {
      const imagePayload = await ImageProcessor.prepareImage(this.photoUri!);
      const result = await AiRecognitionService.recognize(imagePayload, config, apiKey);
      if (seq !== this.requestSeq) {
        return; // 迟到结果丢弃
      }
      this.result = result;
      // 抠出食物轮廓贴纸。失败不阻断识别结果 —— 只是这次没有贴纸。
      await this.makeSticker(result.foodRegion, seq);
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

  private askForApiKey(): void {    AppDialogService.confirm('需要 API Key',
      '尚未配置 AI 服务密钥。是否前往 AI 设置页配置？也可以继续手动录入。',
      '去设置', () => {
        this.navStack.pushPathByName('AiSettings', new Object());
      });
  }

  /**
   * 把食物抠成透明背景贴纸。
   *
   * 做两件事：落盘一份 PNG（给编辑页入库，路径存库），
   * 再生成一份 base64 data URI（给本页预览）。
   *
   * 为什么要 data URI：ArkUI 的 Image 解不了沙箱里的真实文件路径
   * （见 previewSrc 上方注释，实测是空白图），只有 data URI / rawfile 两种形式可用。
   *
   * 任何一步失败都只影响贴纸，不影响识别结果本身 —— 用户照样能保存这条记录。
   */
  private async makeSticker(region: FoodRegion | null, seq: number): Promise<void> {
    this.stickerPath = '';
    this.stickerPreviewUri = '';
    const uri = this.photoUri;
    if (uri === null) {
      return;
    }
    const t0 = Date.now();
    try {
      const cut = await StickerCutoutService.cutoutFromUri(uri, region);
      try {
        this.stickerPath = await StickerCutoutService.savePng(cut, StickerCutoutService.newBaseName());
        const packer = image.createImagePacker();
        try {
          const opts: image.PackingOption = { format: 'image/png', quality: 100 };
          const png = await packer.packToData(cut, opts);
          this.stickerPreviewUri = StickerCutoutService.toDataUri(png);
        } finally {
          packer.release();
        }
      } finally {
        cut.release();
      }
      hilog.info(0x0000, 'StickerCutout', 'makeSticker done in %{public}d ms', Date.now() - t0);
    } catch (_e) {
      this.stickerPath = '';
      this.stickerPreviewUri = '';
      hilog.error(0x0000, 'StickerCutout', 'makeSticker failed after %{public}d ms', Date.now() - t0);
    }
    if (seq !== this.requestSeq) {
      // 识别已被新请求取代，这张贴纸作废
      this.stickerPath = '';
      this.stickerPreviewUri = '';
    }
  }

  private useResult(): void {
    if (this.result === null || this.result.estimatedTotalKcal === null) {
      return;
    }
    const p = new AiEditParams();
    p.mode = 'ai';
    p.date = this.date;    p.name = this.result.foodName;
    p.calories = this.result.estimatedTotalKcal;
    p.aiConfidence = this.result.confidence;
    p.aiNotes = this.result.notes;
    p.proteinG = this.result.proteinG;
    p.carbsG = this.result.carbsG;
    p.fatG = this.result.fatG;
    p.stickerPath = this.stickerPath;
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
              Image(this.previewSrc)
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
            .enabled(this.photoUri !== null && !this.busy && !this.requestPending)
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
                Text('AI 生成估算')
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

                // V6：食物轮廓贴纸预览。
                // 左原图、右抠出来的贴纸 —— 并排对照才能看出「只保留了食物本身」。
                if (this.stickerPreviewUri.length > 0) {
                  Column({ space: 6 }) {
                    Row({ space: space.md }) {
                      Column({ space: 4 }) {
                        Image(this.previewSrc)
                          .width(92)
                          .height(92)
                          .objectFit(ImageFit.Cover)
                          .borderRadius(12)
                        Text('原图')
                          .fontSize(fontSize.caption)
                          .fontColor(color.textHint)
                      }
                      .alignItems(HorizontalAlign.Center)

                      Text('→')
                        .fontSize(fontSize.sectionTitle)
                        .fontColor(color.textHint)

                      Column({ space: 4 }) {
                        // 白色圆角容器 = 贴纸的白边效果
                        Image(this.stickerPreviewUri)
                          .width(92)
                          .height(92)
                          .objectFit(ImageFit.Contain)
                          .padding(5)
                          .backgroundColor('#FFFFFF')
                          .borderRadius(14)
                        Text('食物轮廓贴纸')
                          .fontSize(fontSize.caption)
                          .fontColor(color.primary)
                      }
                      .alignItems(HorizontalAlign.Center)
                    }
                    .width('100%')
                    .justifyContent(FlexAlign.Center)
                  }
                  .width('100%')
                  .padding({ top: space.xs, bottom: space.xs })
                }

                // 显性标识：内容由 AI 生成，必须同时含「AI」与「生成/合成」，
                // 且位于生成内容附近（《人工智能生成合成内容标识办法》要求）。
                // 放在食物名正下方而不是卡片末尾 —— 末尾会被折叠线挡住，等于没有。
                Text('以上食物名称、热量与宏量均为 AI 生成，仅供参考')
                  .fontSize(fontSize.caption)
                  .fontColor(color.textHint)
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
