/**
 * 黑板节点的编辑抽屉（bindSheet 的内容）。
 *
 * 对应设计方案「编辑与补录能力」：
 *   · 修改食物名称 / 热量 / 三大营养素 / 份量 / 用餐时间
 *   · 编辑心情 Emoji、和谁吃、当时的碎碎念
 *   · 切换便签纸颜色与胶带/图钉样式
 *   · 复制到指定日期
 *   · 删除
 *
 * ## 为什么贴纸节点的食物字段是只读的
 * FOOD_STICKER 节点的内容**不存在节点上**，它来自 food_log。
 * 所以在这里直接改「热量」是改不动的 —— 改了也不会生效（下次加载又被覆盖）。
 * 正确做法是：贴纸节点的食物信息跳转到已有的餐食编辑页去改，
 * 这里只编辑**属于黑板自己的**东西：心情、和谁吃、碎碎念、纸色、胶带。
 */

import {
  BoardNodeModel,
  BoardNodeType,
  PinDecorationType,
  StickyPaperStyle,
  paperColors
} from '../models/BoardModels';

/** 编辑结果 */
export class NodeEditResult {
  title: string = '';
  calories: number = 0;
  proteinG: number | null = null;
  carbsG: number | null = null;
  fatG: number | null = null;
  portionDesc: string = '';
  mealCategory: number = 3;
  timeStr: string = '';
  moodEmoji: string = '';
  companionText: string = '';
  memoText: string = '';
  paperStyle: StickyPaperStyle = StickyPaperStyle.CREAM_YELLOW;
  pinType: PinDecorationType = PinDecorationType.WASHI_TAPE_DOT;
}

/** 餐次可选项 */
const MEAL_OPTIONS: string[] = ['早餐', '午餐', '晚餐', '加餐'];
/** 心情候选 */
const MOOD_OPTIONS: string[] = ['😋', '🥳', '🍵', '💪', '😌', '🤤'];

@Component
export struct NoteEditorSheet {
  /** 被编辑的节点。用普通成员而不是 @Prop —— @Prop 会深拷贝，
   *  拷贝出来的对象和数据库里的行脱钩，改了也存不回去。 */
  node: BoardNodeModel | null = null;
  /** 保存 */
  onSave: (result: NodeEditResult) => void = () => {};
  /** 删除 */
  onDelete: (node: BoardNodeModel) => void = () => {};
  /** 复制到指定日期 */
  onCopy: (node: BoardNodeModel, targetDate: string) => void = () => {};
  /** 去餐食编辑页改食物本身 */
  onEditFood: (node: BoardNodeModel) => void = () => {};
  /** 关闭 */
  onClose: () => void = () => {};

  @State private title: string = '';
  @State private calories: string = '';
  @State private protein: string = '';
  @State private carbs: string = '';
  @State private fat: string = '';
  @State private portion: string = '';
  @State private mealCategory: number = 3;
  @State private timeStr: string = '';
  @State private mood: string = '';
  @State private companion: string = '';
  @State private memo: string = '';
  @State private paperStyle: StickyPaperStyle = StickyPaperStyle.CREAM_YELLOW;
  @State private pinType: PinDecorationType = PinDecorationType.WASHI_TAPE_DOT;

  aboutToAppear(): void {
    const n = this.node;
    if (n === null) {
      return;
    }
    this.title = n.title;
    this.calories = `${n.calories}`;
    this.protein = n.proteinGrams === null ? '' : `${Math.round(n.proteinGrams)}`;
    this.carbs = n.carbsGrams === null ? '' : `${Math.round(n.carbsGrams)}`;
    this.fat = n.fatGrams === null ? '' : `${Math.round(n.fatGrams)}`;
    this.portion = n.portionDesc;
    this.mealCategory = n.mealCategory;
    this.timeStr = n.timeStr;
    this.mood = n.moodEmoji;
    this.companion = n.companionText;
    this.memo = n.memoText;
    this.paperStyle = n.paperStyle;
    this.pinType = n.pinType;
  }

  /** 贴纸节点：食物字段归 food_log 管，这里只读 */
  private isSticker(): boolean {
    return this.node !== null && this.node.nodeType === BoardNodeType.FOOD_STICKER;
  }

  private isDemo(): boolean {
    return this.node !== null && this.node.nodeType === BoardNodeType.DEMO_STICKER;
  }

  private parseNumber(text: string): number | null {
    if (text.trim().length === 0) {
      return null;
    }
    const v = Number(text);
    if (isNaN(v)) {
      return null;
    }
    return v;
  }

  private doSave(): void {
    const result = new NodeEditResult();
    result.title = this.title.trim();
    result.calories = Math.max(0, Math.round(this.parseNumber(this.calories) ?? 0));
    result.proteinG = this.parseNumber(this.protein);
    result.carbsG = this.parseNumber(this.carbs);
    result.fatG = this.parseNumber(this.fat);
    result.portionDesc = this.portion.trim();
    result.mealCategory = this.mealCategory;
    result.timeStr = this.timeStr.trim();
    result.moodEmoji = this.mood.trim();
    result.companionText = this.companion.trim();
    result.memoText = this.memo.trim();
    result.paperStyle = this.paperStyle;
    result.pinType = this.pinType;
    this.onSave(result);
  }

  @Builder
  FieldLabel(text: string) {
    Text(text)
      .fontSize(11)
      .fontColor('#8A7742')
      .margin({ top: 10, bottom: 4 })
      .width('100%')
  }

  @Builder
  PaperSwatch(style: StickyPaperStyle) {
    Stack() {
      Row()
        .width(30)
        .height(30)
        .backgroundColor(this.paperBgOf(style))
        .borderRadius(6)
        .border({ width: this.paperStyle === style ? 2 : 0, color: '#C2552F' })
      if (this.paperStyle === style) {
        Text('✓')
          .fontSize(14)
          .fontColor('#C2552F')
      }
    }
    .onClick(() => {
      this.paperStyle = style;
    })
  }

  /** 某种便签纸的主色 */
  private paperBgOf(style: StickyPaperStyle): string {
    return paperColors(style)[0];
  }

  @Builder
  PinOption(pin: PinDecorationType, label: string) {
    Text(label)
      .fontSize(11)
      .fontColor(this.pinType === pin ? '#FFFFFF' : '#6B5A2E')
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(this.pinType === pin ? '#C2552F' : '#F3E7C8')
      .borderRadius(10)
      .onClick(() => {
        this.pinType = pin;
      })
  }

  build() {
    Scroll() {
      Column({ space: 4 }) {
        Text(this.isSticker() ? '食物贴纸' : '心情便签')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#4A3B1E')
          .width('100%')

        if (this.isSticker()) {
          Text('食物名称与营养数据来自餐食记录，改这里不会生效 —— 请到餐食编辑页修改。')
            .fontSize(11)
            .fontColor('#8A7742')
            .width('100%')
        }

        this.FieldLabel('标题')
        TextInput({ text: this.title, placeholder: '标题' })
          .fontSize(14)
          .fontColor('#4A3B1E')
          .placeholderColor('#B0A183')
          .backgroundColor('#FFFDF4')
          .borderRadius(8)
          .enabled(!this.isSticker())
          .onChange((value: string) => {
            this.title = value;
          })

        this.FieldLabel('热量 kcal')
        TextInput({ text: this.calories, placeholder: '0' })
          .fontSize(14)
          .fontColor('#4A3B1E')
          .placeholderColor('#B0A183')
          .backgroundColor('#FFFDF4')
          .borderRadius(8)
          .enabled(!this.isSticker())
          .onChange((value: string) => {
            this.calories = value;
          })

        this.FieldLabel('三大营养素 g（蛋白 / 碳水 / 脂肪）')
        Row({ space: 8 }) {
          TextInput({ text: this.protein, placeholder: '蛋白' })
            .fontSize(13).fontColor('#4A3B1E').placeholderColor('#B0A183')
            .backgroundColor('#FFFDF4').borderRadius(8).layoutWeight(1)
            .enabled(!this.isSticker())
            .onChange((value: string) => { this.protein = value; })
          TextInput({ text: this.carbs, placeholder: '碳水' })
            .fontSize(13).fontColor('#4A3B1E').placeholderColor('#B0A183')
            .backgroundColor('#FFFDF4').borderRadius(8).layoutWeight(1)
            .enabled(!this.isSticker())
            .onChange((value: string) => { this.carbs = value; })
          TextInput({ text: this.fat, placeholder: '脂肪' })
            .fontSize(13).fontColor('#4A3B1E').placeholderColor('#B0A183')
            .backgroundColor('#FFFDF4').borderRadius(8).layoutWeight(1)
            .enabled(!this.isSticker())
            .onChange((value: string) => { this.fat = value; })
        }
        .width('100%')

        this.FieldLabel('份量')
        TextInput({ text: this.portion, placeholder: '如：4只 / 约220g' })
          .fontSize(13).fontColor('#4A3B1E').placeholderColor('#B0A183')
            .backgroundColor('#FFFDF4').borderRadius(8)
          .enabled(!this.isSticker())
          .onChange((value: string) => { this.portion = value; })

        this.FieldLabel('用餐时段')
        Row({ space: 6 }) {
          ForEach(MEAL_OPTIONS, (label: string, index: number) => {
            Text(label)
              .fontSize(12)
              .fontColor(this.mealCategory === index ? '#FFFFFF' : '#6B5A2E')
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor(this.mealCategory === index ? '#C2552F' : '#F3E7C8')
              .borderRadius(10)
              .onClick(() => { this.mealCategory = index; })
          }, (label: string, index: number) => label)
        }
        .width('100%')

        this.FieldLabel('用餐时间')
        TextInput({ text: this.timeStr, placeholder: '12:30' })
          .fontSize(13).fontColor('#4A3B1E').placeholderColor('#B0A183')
            .backgroundColor('#FFFDF4').borderRadius(8)
          .onChange((value: string) => { this.timeStr = value; })

        this.FieldLabel('心情')
        Row({ space: 6 }) {
          ForEach(MOOD_OPTIONS, (emoji: string) => {
            Text(emoji)
              .fontSize(18)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(this.mood === emoji ? '#FFE9C7' : 'transparent')
              .borderRadius(8)
              .onClick(() => { this.mood = this.mood === emoji ? '' : emoji; })
          }, (emoji: string) => emoji)
        }
        .width('100%')

        this.FieldLabel('和谁吃')
        TextInput({ text: this.companion, placeholder: '如：和老友小聚' })
          .fontSize(13).fontColor('#4A3B1E').placeholderColor('#B0A183')
            .backgroundColor('#FFFDF4').borderRadius(8)
          .onChange((value: string) => { this.companion = value; })

        this.FieldLabel('碎碎念')
        TextArea({ text: this.memo, placeholder: '当时的碎碎念…' })
          .fontSize(13)
          .fontColor('#4A3B1E')
          .placeholderColor('#B0A183')
          .height(80)
          .backgroundColor('#FFFDF4')
          .borderRadius(8)
          .onChange((value: string) => { this.memo = value; })

        this.FieldLabel('便签纸')
        Row({ space: 8 }) {
          this.PaperSwatch(StickyPaperStyle.CREAM_YELLOW)
          this.PaperSwatch(StickyPaperStyle.MINT_GREEN)
          this.PaperSwatch(StickyPaperStyle.SAKURA_PINK)
          this.PaperSwatch(StickyPaperStyle.KRAFT_PAPER)
          this.PaperSwatch(StickyPaperStyle.CHALK_CARD)
        }
        .width('100%')

        this.FieldLabel('顶部装饰')
        Row({ space: 6 }) {
          this.PinOption(PinDecorationType.WASHI_TAPE_DOT, '波点胶带')
          this.PinOption(PinDecorationType.WASHI_TAPE_STRIPE, '斜纹胶带')
          this.PinOption(PinDecorationType.RED_THUMB_TACK, '图钉')
          this.PinOption(PinDecorationType.NONE, '无')
        }
        .width('100%')

        // 操作
        Row({ space: 8 }) {
          if (this.isSticker() && this.node !== null && this.node.foodId !== null) {
            Button('编辑食物')
              .fontSize(12)
              .height(34)
              .layoutWeight(1)
              .backgroundColor('#F3E7C8')
              .fontColor('#6B5A2E')
              .onClick(() => {
                if (this.node !== null) {
                  this.onEditFood(this.node);
                }
              })
          }
          Button('复制到今天')
            .fontSize(12)
            .height(34)
            .layoutWeight(1)
            .backgroundColor('#F3E7C8')
            .fontColor('#6B5A2E')
            .onClick(() => {
              if (this.node !== null) {
                this.onCopy(this.node, this.todayKey());
              }
            })
          Button('删除')
            .fontSize(12)
            .height(34)
            .layoutWeight(1)
            .backgroundColor('#FBE3E0')
            .fontColor('#C2552F')
            .onClick(() => {
              if (this.node !== null) {
                this.onDelete(this.node);
              }
            })
        }
        .width('100%')
        .margin({ top: 16 })

        Row({ space: 8 }) {
          Button('关闭')
            .fontSize(13)
            .height(38)
            .layoutWeight(1)
            .backgroundColor('#F3E7C8')
            .fontColor('#6B5A2E')
            .onClick(() => this.onClose())
          Button('保存')
            .fontSize(13)
            .height(38)
            .layoutWeight(1)
            .backgroundColor('#C2552F')
            .fontColor('#FFFFFF')
            .onClick(() => this.doSave())
        }
        .width('100%')
        .margin({ top: 8, bottom: 20 })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 16 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFF8E7')
    .scrollBar(BarState.Off)
  }

  private todayKey(): string {
    const d = new Date();
    const m = `${d.getMonth() + 1}`.padStart(2, '0');
    const day = `${d.getDate()}`.padStart(2, '0');
    return `${d.getFullYear()}-${m}-${day}`;
  }
}
