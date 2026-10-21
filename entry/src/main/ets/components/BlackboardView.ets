/**
 * 今日黑板 —— 当日饮食记录的「黑板 + 贴纸画布」主视图。
 *
 * 对应设计方案「黑板与手帐画布布局（Blackboard & Pinboard Canvas）」。
 *
 * ## 布局参考 nosh
 *   ① 顶部横排日期胶囊条，当前日期高亮，可点选切换
 *   ② 板面上方的摄入仪表（今日摄入 / 还可以吃 / 三大营养素）
 *   ③ 一排操作：黑板↔网格视图切换、粉笔分栏、一键规整、底纹切换、生成分享卡
 *   ④ 自由画布：贴纸与便签可拖拽、双指缩放、双指旋转、单击打开抽屉、双击翻面
 *   ⑤ 结构化网格视图：按早/午/晚/加餐分组，规整排列
 *   ⑥ 底部：卡通猫 + 粉笔槽
 *
 * ## 数据口径
 * 摄入与预算来自 DailySummaryService，与首页/进度页同一份，不另算一套。
 * 贴纸节点的名称/热量/宏量来自 food_log（黑板节点只存空间状态），
 * 见 repositories/BoardRepository.ets 头部说明。
 *
 * ## 与旧版的差别
 * 旧版是一排横向滚动的便签卡（StickyNoteCard），只能看不能摆。
 * 现在改成真正的自由画布：位置、缩放、角度、层级都落库，
 * 第二天打开还是用户自己摆的样子。
 */

import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { componentSnapshot } from '@kit.ArkUI';

import {
  BoardNodeModel,
  BoardNodeType,
  BoardThemeType,
  BoardViewMode,
  boardThemeColors
} from '../models/BoardModels';
import { BoardRepository } from '../repositories/BoardRepository';
import { FoodRepository } from '../repositories/FoodRepository';
import { Database } from '../database/Database';
import { DailySummary } from '../models/DailySummary';
import { DailySummaryService } from '../services/DailySummaryService';
import { MacroRepository, MacroDayTotal } from '../repositories/MacroRepository';
import { toDateKey, parseDateKey } from '../common/DateUtils';
import { MEAL_LABELS } from '../common/Constants';
import { BlackboardNodeWrapper } from './BlackboardNodeWrapper';
import { FoodStickerItem } from './FoodStickerItem';
import { StickyNoteItem } from './StickyNoteItem';
import { NoteEditorSheet, NodeEditResult } from './NoteEditorSheet';
import { SharePosterDialog } from './SharePosterDialog';

/** 日期胶囊上的一项 */
class DateChip {
  key: string = '';
  /** 日，如 21 */
  day: string = '';
  /** 星期，如 三 */
  week: string = '';

  constructor(key: string, day: string, week: string) {
    this.key = key;
    this.day = day;
    this.week = week;
  }
}

const WEEK_LABELS: string[] = ['一', '二', '三', '四', '五', '六', '日'];

/** 自由画布高度（vp） */
const CANVAS_HEIGHT: number = 340;
/** 画布默认宽度（vp），实际宽度由 onAreaChange 校正 */
const CANVAS_WIDTH_FALLBACK: number = 330;
/**
 * 贴纸占位尺寸。
 *
 * 比内容本身略大一点：贴纸有旋转，旋转后外接框会变大，
 * 占位按内容尺寸算会把相邻贴纸「顶开」。
 */
const STICKER_BOX_W: number = 106;
const STICKER_BOX_H: number = 128;
/** 便签占位尺寸 */
const NOTE_BOX_W: number = 136;
const NOTE_BOX_H: number = 148;

/**
 * 跳到餐食编辑页的参数。
 *
 * 各页面都各自定义一份同结构的参数类（见 pages/HomePage.ets、pages/FoodPage.ets），
 * 目的是让页面之间不互相 import —— 黑板组件同样自己定义一份。
 */
class BoardFoodEditParams {
  mode: string = 'edit';
  date: string = '';
  id: number = -1;

  constructor(mode: string, date: string, id: number) {
    this.mode = mode;
    this.date = date;
    this.id = id;
  }
}

/** 跳到 AI 识别页的参数（与 pages/HomePage.ets 的同名类结构一致） */
class BoardAiParams {
  date: string = '';

  constructor(date: string) {
    this.date = date;
  }
}

@Component
export struct BlackboardView {
  /** 路由栈：从黑板跳到餐食编辑页用 */
  @Consume('navStack') navStack: NavPathStack;
  /**
   * 数据刷新广播。写库方（编辑页、全部餐食页）bumpRefresh() 之后，
   * 黑板必须跟着重载 —— 否则保存完记录回到今日页会出现
   * 「今日餐食」已显示新条目、黑板却还是旧数据的两处不同步。
   */
  @StorageLink('refreshTick') @Watch('reload') refreshTick: number = 0;
  /** 选中的日期。外部改动时黑板同步重建胶囊条并重载 */
  @StorageLink('selectedDate') @Watch('onDateChanged') selectedDate: string = '';
  @State summary: DailySummary | null = null;
  /** 当日宏量合计（粉笔字那一行用） */
  @State macroDay: MacroDayTotal | null = null;
  /** 黑板节点 */
  @State nodes: BoardNodeModel[] = [];
  /** 底纹主题 */
  @State theme: BoardThemeType = BoardThemeType.CHALKBOARD;
  /** 视图模式 */
  @State viewMode: BoardViewMode = BoardViewMode.FREE_CANVAS;
  @State chips: DateChip[] = [];
  /** 编辑抽屉是否打开 */
  @State private sheetOpen: boolean = false;
  /** 正在编辑的节点 */
  @State private editingNode: BoardNodeModel | null = null;
  /** 分享卡预览是否打开 */
  @State private posterOpen: boolean = false;
  @State private posterUri: string = '';
  @State private posterPath: string = '';
  /** 是否显示粉笔分栏线 */
  @State private showDividers: boolean = false;
  /** 画布实际宽度 */
  @State private canvasWidth: number = CANVAS_WIDTH_FALLBACK;
  /** 当前最大的 zIndex，置顶时用 */
  @State private topZ: number = 0;

  aboutToAppear(): void {
    this.buildChips();
    this.reload();
  }

  /** 外部改了日期：重建胶囊条并重载 */
  private onDateChanged(): void {
    this.buildChips();
    this.reload();
  }

  /** 最近 7 天（含今天），按周一为一周之首 */
  private buildChips(): void {
    const out: DateChip[] = [];
    const base = this.selectedDate !== '' ? parseDateKey(this.selectedDate) : new Date();
    const dow = (base.getDay() + 6) % 7;
    const monday = new Date(base);
    monday.setDate(base.getDate() - dow);
    for (let i = 0; i < 7; i++) {
      const d = new Date(monday);
      d.setDate(monday.getDate() + i);
      const key = toDateKey(d);
      const today = toDateKey(new Date());
      if (key > today) {
        continue;
      }
      out.push(new DateChip(key, d.getDate().toString(), WEEK_LABELS[i]));
    }
    this.chips = out;
  }

  private async reload(): Promise<void> {
    const picked = AppStorage.get<string>('selectedDate');
    const date = picked !== undefined && picked !== null && picked.length > 0
      ? picked : toDateKey(new Date());
    try {
      this.summary = await DailySummaryService.getSummary(date);
      this.macroDay = await MacroRepository.getDayTotal(date);
    } catch (_e) {
      this.summary = null;
      this.macroDay = null;
    }
    try {
      const setting = await BoardRepository.getSetting();
      this.theme = setting.theme;
      this.viewMode = setting.viewMode;
    } catch (_e) {
      this.theme = BoardThemeType.CHALKBOARD;
      this.viewMode = BoardViewMode.FREE_CANVAS;
    }
    await this.loadNodes(date);
  }

  private async loadNodes(date: string): Promise<void> {
    try {
      let nodes = await BoardRepository.getNodes(date);
      this.nodes = nodes;
      this.topZ = this.computeTopZ(nodes);
      // 这天还什么都没有 → 铺一套示例节点，让用户第一秒就能上手拖拽
      if (nodes.length === 0) {
        const created = await BoardRepository.seedDemo(date);
        if (created > 0) {
          this.nodes = await BoardRepository.getNodes(date);
          this.topZ = this.computeTopZ(this.nodes);
        }
      }
    } catch (_e) {
      this.nodes = [];
    }
  }

  private computeTopZ(nodes: BoardNodeModel[]): number {
    let max = -1;
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i].zIndex > max) {
        max = nodes[i].zIndex;
      }
    }
    return max;
  }

  /* ------------------------------ 数据读取 ------------------------------ */

  private consumed(): number {
    return this.summary !== null ? this.summary.consumedKcal : 0;
  }

  private budget(): number {
    return this.summary !== null ? this.summary.dailyCalorieBudget : 0;
  }

  private remaining(): number {
    const left = this.budget() - this.consumed();
    return left > 0 ? left : 0;
  }

  private overBudget(): boolean {
    return this.consumed() > this.budget();
  }

  private macroText(): string {
    if (this.summary === null || this.macroDay === null) {
      return '';
    }
    const m = this.macroDay;
    return `蛋白 ${Math.round(m.actual.proteinG)}g · 碳水 ${Math.round(m.actual.carbsG)}g · 脂肪 ${Math.round(m.actual.fatG)}g`;
  }

  private mealLabel(mealType: number): string {
    return mealType >= 0 && mealType < MEAL_LABELS.length ? MEAL_LABELS[mealType] : '加餐';
  }

  private selectDate(key: string): void {
    if (key === this.selectedDate) {
      return;
    }
    AppStorage.setOrCreate<string>('selectedDate', key);
  }

  /* ------------------------------ 节点操作 ------------------------------ */

  /** 点击置顶 */
  private bringToFront(id: number): void {
    const node = this.findNode(id);
    if (node === null) {
      return;
    }
    if (node.zIndex === this.topZ) {
      return;
    }
    this.topZ = this.topZ + 1;
    node.zIndex = this.topZ;
    this.persistTransform(node);
  }

  private findNode(id: number): BoardNodeModel | null {
    for (let i = 0; i < this.nodes.length; i++) {
      if (this.nodes[i].id === id) {
        return this.nodes[i];
      }
    }
    return null;
  }

  /** 打开编辑抽屉 */
  private openNode(node: BoardNodeModel): void {
    this.editingNode = node;
    this.sheetOpen = true;
  }

  /** 变换结束：落库 */
  private async persistTransform(node: BoardNodeModel): Promise<void> {
    try {
      await BoardRepository.saveTransform(node.id, node.x, node.y, node.scale, node.rotation, node.zIndex);
    } catch (_e) {
      // 落库失败只影响下次打开的位置，不打断当前操作
    }
    if (this.showDividers) {
      await this.syncMealByColumn(node);
    }
  }

  /** 分栏模式下：贴纸落在哪一栏，餐次就跟着改成哪一栏 */
  private async syncMealByColumn(node: BoardNodeModel): Promise<void> {
    const col = this.mealColumnFor(node.x);
    if (col < 0 || col === node.mealCategory) {
      return;
    }
    node.mealCategory = col;
    try {
      await BoardRepository.saveMealCategory(node.id, col);
      if (node.foodId !== null) {
        await FoodRepository.updateMealType(node.foodId, col);
      }
      this.getUIContext().getPromptAction().showToast({ message: `已归入${MEAL_LABELS[col]}` });
      // 餐次变了，汇总数字要跟着重算
      this.refreshSummary();
    } catch (_e) {
      // 忽略
    }
  }

  /** 节点的 x 落在第几栏（0~3）；不在范围内返回 -1 */
  private mealColumnFor(x: number): number {
    const colWidth = this.canvasWidth / 4;
    if (colWidth <= 0) {
      return -1;
    }
    const col = Math.floor(x / colWidth);
    if (col < 0 || col > 3) {
      return -1;
    }
    return col;
  }

  private async refreshSummary(): Promise<void> {
    try {
      this.summary = await DailySummaryService.getSummary(this.selectedDate);
      this.macroDay = await MacroRepository.getDayTotal(this.selectedDate);
    } catch (_e) {
      // 忽略
    }
  }

  /** 双击翻面 */
  private async toggleFlip(node: BoardNodeModel): Promise<void> {
    node.isFlipped = !node.isFlipped;
    try {
      await BoardRepository.saveFlipped(node.id, node.isFlipped);
    } catch (_e) {
      // 忽略
    }
  }

  /** 保存抽屉里的编辑 */
  private async saveNodeEdit(result: NodeEditResult): Promise<void> {
    const node = this.editingNode;
    if (node === null) {
      this.sheetOpen = false;
      return;
    }
    node.title = result.title;
    node.calories = result.calories;
    node.proteinGrams = result.proteinG;
    node.carbsGrams = result.carbsG;
    node.fatGrams = result.fatG;
    node.portionDesc = result.portionDesc;
    node.mealCategory = result.mealCategory;
    node.timeStr = result.timeStr;
    node.moodEmoji = result.moodEmoji;
    node.companionText = result.companionText;
    node.memoText = result.memoText;
    node.paperStyle = result.paperStyle;
    node.pinType = result.pinType;
    try {
      await BoardRepository.saveContent(
        node.id, result.title, result.calories, result.proteinG, result.carbsG, result.fatG,
        result.portionDesc, result.mealCategory, result.timeStr,
        result.moodEmoji, result.companionText, result.memoText,
        result.paperStyle, result.pinType
      );
    } catch (_e) {
      // 忽略
    }
    this.sheetOpen = false;
    this.editingNode = null;
  }

  /** 删除节点 */
  private async deleteNode(node: BoardNodeModel): Promise<void> {
    this.sheetOpen = false;
    this.editingNode = null;
    try {
      if (node.nodeType === BoardNodeType.FOOD_STICKER && node.foodId !== null) {
        // 贴纸节点是饮食记录的投影：删节点等于删记录
        await FoodRepository.delete(node.foodId);
        await this.refreshSummary();
      } else {
        await BoardRepository.delete(node.id);
      }
    } catch (_e) {
      // 忽略
    }
    await this.loadNodes(this.selectedDate);
  }

  /** 复制到指定日期 */
  private async copyNode(node: BoardNodeModel, targetDate: string): Promise<void> {
    this.sheetOpen = false;
    this.editingNode = null;
    try {
      await BoardRepository.copyToDate(node, targetDate);
      this.getUIContext().getPromptAction().showToast({ message: `已复制到 ${targetDate}` });
    } catch (_e) {
      this.getUIContext().getPromptAction().showToast({ message: '复制失败' });
    }
  }

  /** 去餐食编辑页改食物本身 */
  private editFoodOf(node: BoardNodeModel): void {
    this.sheetOpen = false;
    this.editingNode = null;
    if (node.foodId === null) {
      return;
    }
    // 贴纸的内容来自 food_log，要改名称/热量/宏量就得去改那条记录本身
    this.navStack.pushPathByName('FoodEdit',
      new BoardFoodEditParams('edit', node.date, node.foodId));
  }

  /* ------------------------------ 画布操作 ------------------------------ */

  /** 一键规整：按餐次排成两列，保留 ±2° 手作感 */
  private async tidyUp(): Promise<void> {
    if (this.nodes.length === 0) {
      return;
    }
    const sorted = this.nodes.slice();
    sorted.sort((a: BoardNodeModel, b: BoardNodeModel) => {
      if (a.mealCategory !== b.mealCategory) {
        return a.mealCategory - b.mealCategory;
      }
      return a.id - b.id;
    });
    const colWidth = this.canvasWidth / 2;
    for (let i = 0; i < sorted.length; i++) {
      const node = sorted[i];
      const col = i % 2;
      const row = Math.floor(i / 2);
      node.x = col * colWidth + 10;
      node.y = 8 + row * 160;
      node.scale = 1;
      node.rotation = (i % 2 === 0) ? -2 : 2;
      this.persistTransform(node);
    }
    this.getUIContext().getPromptAction().showToast({ message: '已按餐次规整' });
  }

  /** 切换底纹主题 */
  private async cycleTheme(): Promise<void> {
    const next: BoardThemeType = this.theme === BoardThemeType.CHALKBOARD
      ? BoardThemeType.CORKBOARD
      : (this.theme === BoardThemeType.CORKBOARD ? BoardThemeType.DOT_JOURNAL : BoardThemeType.CHALKBOARD);
    this.theme = next;
    try {
      await BoardRepository.saveSetting(next, this.viewMode);
    } catch (_e) {
      // 忽略
    }
  }

  /** 切换视图：黑板自由视图 ↔ 结构化网格视图 */
  private async toggleViewMode(): Promise<void> {
    const next: BoardViewMode = this.viewMode === BoardViewMode.FREE_CANVAS
      ? BoardViewMode.STRUCTURED_GRID : BoardViewMode.FREE_CANVAS;
    this.viewMode = next;
    try {
      await BoardRepository.saveSetting(this.theme, next);
    } catch (_e) {
      // 忽略
    }
  }

  /** 生成今日手帐分享卡 */
  private async sharePoster(): Promise<void> {
    try {
      const options: componentSnapshot.SnapshotOptions = {
        scale: 2,
        waitUntilRenderFinished: true
      };
      const pixelMap = await componentSnapshot.get('boardCanvasShot', options);
      try {
        const packer = image.createImagePacker();
        try {
          const png = await packer.packToData(pixelMap, { format: 'image/png', quality: 100 });
          const helper = new util.Base64Helper();
          const b64 = helper.encodeToStringSync(new Uint8Array(png));
          this.posterUri = `data:image/png;base64,${b64}`;
        } finally {
          packer.release();
        }
        // 同时存一份到沙箱，方便后续接「保存到相册」
        this.posterPath = await this.savePoster(pixelMap);
        this.posterOpen = true;
      } finally {
        pixelMap.release();
      }
    } catch (e) {
      const err = e as Error;
      this.getUIContext().getPromptAction().showToast({ message: `生成失败：${err.message}` });
    }
  }

  private async savePoster(pixelMap: image.PixelMap): Promise<string> {
    try {
      const ctx = Database.getAppContext();
      if (ctx === null) {
        return '';
      }
      const dir = `${ctx.filesDir}/share`;
      if (!fileIo.accessSync(dir)) {
        await fileIo.mkdir(dir, true);
      }
      const path = `${dir}/board_${Date.now()}.png`;
      const file = await fileIo.open(path,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        const packer = image.createImagePacker();
        try {
          const opts: image.PackingOption = { format: 'image/png', quality: 100 };
          await packer.packToFile(pixelMap, file.fd, opts);
        } finally {
          packer.release();
        }
      } finally {
        fileIo.closeSync(file);
      }
      return path;
    } catch (_e) {
      return '';
    }
  }

  /* ------------------------------ 构建 ------------------------------ */

  @Builder
  DateStrip() {
    Row({ space: 6 }) {
      ForEach(this.chips, (chip: DateChip) => {
        Column({ space: 1 }) {
          Text(chip.day)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(chip.key === this.selectedDate ? '#1E2A22' : '#F4F1E4')
          Text(chip.week)
            .fontSize(10)
            .fontColor(chip.key === this.selectedDate ? '#1E2A22' : '#C6CFC4')
        }
        .width(36)
        .height(46)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(chip.key === this.selectedDate ? '#D5EE6E' : 'transparent')
        .borderRadius(18)
        .onClick(() => this.selectDate(chip.key))
      }, (chip: DateChip) => chip.key)
    }
    .width('100%')
    .padding({ left: 4, right: 4 })
  }

  /** 板面顶部：粉笔字写的当日摄入 */
  @Builder
  Header() {
    Row() {
      Column({ space: 2 }) {
        Text('今日摄入')
          .fontSize(13)
          .fontColor(this.theme === BoardThemeType.DOT_JOURNAL ? '#7A736A' : '#C6CFC4')
        Row({ space: 4 }) {
          Text(`${this.consumed()}`)
            .fontSize(34)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.overBudget() ? '#FFB3B3' : this.inkColor())
          Text(`/ ${this.budget()} kcal`)
            .fontSize(14)
            .fontColor(this.inkDimColor())
            .margin({ top: 12 })
        }
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      Column({ space: 2 }) {
        Text(this.overBudget() ? '已超出' : '还可以吃')
          .fontSize(12)
          .fontColor(this.inkDimColor())
        Text(`${this.remaining()}`)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.overBudget() ? '#FFB3B3' : this.inkColor())
        Text('kcal')
          .fontSize(11)
          .fontColor(this.inkDimColor())
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')

    if (this.macroText().length > 0) {
      Text(this.macroText())
        .fontSize(12)
        .fontColor(this.inkDimColor())
        .width('100%')
        .margin({ top: 4 })
    }
  }

  /** 操作排：拍照 / 视图 / 分栏 / 规整 / 底纹 / 分享 */
  @Builder
  ActionRow() {
    Row({ space: 5 }) {
      // 「一拍即贴」是黑板的主入口，放在操作排最左边并用主色区分。
      // 之所以要有这个常驻入口：黑板占满首屏后，
      // 页面下方「今日餐食」里的拍照入口会被推到首屏之外。
      Text('拍照')
        .fontSize(11)
        .fontColor('#FFFFFF')
        .padding({ left: 9, right: 9, top: 4, bottom: 4 })
        .backgroundColor('#C2552F')
        .borderRadius(9)
        .onClick(() => {
          this.navStack.pushPathByName('AiRecognition', new BoardAiParams(this.selectedDate));
        })

      Text(this.viewMode === BoardViewMode.FREE_CANVAS ? '网格' : '自由')
        .fontSize(11)
        .fontColor(this.inkColor())
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor(this.pillColor())
        .borderRadius(9)
        .onClick(() => this.toggleViewMode())

      Text(this.showDividers ? '分栏✓' : '分栏')
        .fontSize(11)
        .fontColor(this.inkColor())
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor(this.pillColor())
        .borderRadius(9)
        .onClick(() => {
          this.showDividers = !this.showDividers;
        })

      Text('规整')
        .fontSize(11)
        .fontColor(this.inkColor())
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor(this.pillColor())
        .borderRadius(9)
        .onClick(() => this.tidyUp())

      Text('底纹')
        .fontSize(11)
        .fontColor(this.inkColor())
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor(this.pillColor())
        .borderRadius(9)
        .onClick(() => this.cycleTheme())

      Text('分享')
        .fontSize(11)
        .fontColor(this.inkColor())
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor(this.pillColor())
        .borderRadius(9)
        .onClick(() => this.sharePoster())
    }
    .width('100%')
    .margin({ top: 8 })
  }

  /** 粉笔分栏线（早 / 午 / 晚 / 加餐） */
  @Builder
  Dividers() {
    ForEach([0, 1, 2, 3], (i: number) => {
      Column() {
        Text(MEAL_LABELS[i])
          .fontSize(9)
          .fontColor(this.inkDimColor())
        Divider()
          .vertical(true)
          .color(this.inkDimColor())
          .strokeWidth(1)
      }
      .width(this.canvasWidth / 4)
      .height('100%')
      .alignItems(HorizontalAlign.Center)
    }, (i: number) => i.toString())
  }

  /** 节点内容 */
  @Builder
  NodeContent(node: BoardNodeModel) {
    if (node.nodeType === BoardNodeType.STICKY_NOTE) {
      StickyNoteItem({
        title: node.title,
        kcal: node.calories,
        mealLabel: this.mealLabel(node.mealCategory),
        timeStr: node.timeStr,
        moodEmoji: node.moodEmoji,
        companionText: node.companionText,
        memoText: node.memoText,
        aiAdvice: node.aiAdvice,
        paperStyle: node.paperStyle,
        pinType: node.pinType,
        noteWidth: NOTE_BOX_W,
        noteHeight: NOTE_BOX_H
      })
    } else {
      FoodStickerItem({
        title: node.title,
        kcal: node.calories,
        mealLabel: this.mealLabel(node.mealCategory),
        stickerUri: node.stickerUri,
        moodEmoji: node.moodEmoji,
        memoSummary: node.memoText,
        proteinG: node.proteinGrams === null ? 0 : node.proteinGrams,
        carbsG: node.carbsGrams === null ? 0 : node.carbsGrams,
        fatG: node.fatGrams === null ? 0 : node.fatGrams,
        aiAdvice: node.aiAdvice,
        flipped: node.isFlipped,
        paperStyle: node.paperStyle,
        pinType: node.pinType,
        stickerSize: 84,
        isDemo: node.nodeType === BoardNodeType.DEMO_STICKER
      })
    }
  }

  /** 自由画布 */
  @Builder
  FreeCanvas() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.showDividers) {
        this.Dividers()
      }

      if (this.nodes.length === 0) {
        this.EmptyBoard()
      } else {
        ForEach(this.nodes, (node: BoardNodeModel) => {
          BlackboardNodeWrapper({
            node: node,
            canvasWidth: this.canvasWidth,
            canvasHeight: this.canvasHeight(),
            nodeWidth: node.nodeType === BoardNodeType.STICKY_NOTE ? NOTE_BOX_W : STICKER_BOX_W,
            nodeHeight: node.nodeType === BoardNodeType.STICKY_NOTE ? NOTE_BOX_H : STICKER_BOX_H,
            onBringToFront: (id: number) => this.bringToFront(id),
            onOpenNode: (n: BoardNodeModel) => this.openNode(n),
            onTransformEnd: (n: BoardNodeModel) => this.persistTransform(n),
            onToggleFlip: (n: BoardNodeModel) => this.toggleFlip(n),
            content: () => {
              this.NodeContent(node)
            }
          })
        }, (node: BoardNodeModel) => node.id.toString())
      }
    }
    .width('100%')
    .height(this.canvasHeight())
    .clip(true)
    .id('boardCanvasShot')
    .onAreaChange((_old: Area, area: Area) => {
      const w = parseFloat(area.width.toString());
      if (!isNaN(w) && w > 0) {
        this.canvasWidth = w;
      }
    })
  }

  /** 结构化网格视图：按餐次分组 */
  @Builder
  StructuredGrid() {
    Scroll() {
      Column({ space: 10 }) {
        ForEach([0, 1, 2, 3], (meal: number) => {
          Column({ space: 6 }) {
            Text(MEAL_LABELS[meal])
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.inkColor())
              .width('100%')

            if (this.nodesForMeal(meal).length === 0) {
              Text('—')
                .fontSize(11)
                .fontColor(this.inkDimColor())
                .width('100%')
            } else {
              Row({ space: 8 }) {
                ForEach(this.nodesForMeal(meal), (node: BoardNodeModel) => {
                  Column({ space: 3 }) {
                    if (node.nodeType === BoardNodeType.STICKY_NOTE) {
                      StickyNoteItem({
                        title: node.title,
                        kcal: node.calories,
                        mealLabel: this.mealLabel(node.mealCategory),
                        timeStr: node.timeStr,
                        moodEmoji: node.moodEmoji,
                        companionText: node.companionText,
                        memoText: node.memoText,
                        paperStyle: node.paperStyle,
                        pinType: node.pinType,
                        noteWidth: 132,
                        noteHeight: 132
                      })
                    } else {
                      FoodStickerItem({
                        title: node.title,
                        kcal: node.calories,
                        mealLabel: this.mealLabel(node.mealCategory),
                        stickerUri: node.stickerUri,
                        moodEmoji: node.moodEmoji,
                        memoSummary: node.memoText,
                        flipped: node.isFlipped,
                        paperStyle: node.paperStyle,
                        pinType: node.pinType,
                        stickerSize: 68,
                        isDemo: node.nodeType === BoardNodeType.DEMO_STICKER
                      })
                    }
                  }
                  .onClick(() => this.openNode(node))
                }, (node: BoardNodeModel) => node.id.toString())
              }
              .width('100%')
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        })
      }
      .width('100%')
      .padding({ bottom: 8 })
    }
    .width('100%')
    .height(this.canvasHeight())
    .scrollBar(BarState.Off)
  }

  /** 空态 */
  @Builder
  EmptyBoard() {
    Column({ space: 8 }) {
      Text('黑板还是空的')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.inkColor())
      Text('拍一张食物，抠出轮廓贴到这里来')
        .fontSize(13)
        .fontColor(this.inkDimColor())
      Text('贴纸可以拖动摆放，双指缩放旋转，双击翻面')
        .fontSize(11)
        .fontColor(this.inkDimColor())
        .margin({ top: 4 })
    }
    .width('100%')
    .height(this.canvasHeight())
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /** 取某个餐次分组的节点 */
  private nodesForMeal(meal: number): BoardNodeModel[] {
    const out: BoardNodeModel[] = [];
    for (let i = 0; i < this.nodes.length; i++) {
      if (this.nodes[i].mealCategory === meal) {
        out.push(this.nodes[i]);
      }
    }
    return out;
  }

  /**
   * 画布高度（vp）。
   *
   * 贴纸多了（用户一天记了十几条）画布要跟着长高，
   * 否则后面的贴纸全被压到板子底边、互相叠着。
   * 画布在页面纵向 Scroll 里，长高后页面自然能滚下去看到。
   *
   * 行数按**两列**算 —— 「一键规整」排的就是两列，
   * 画布要能装下规整后的结果，不能按三列算（否则规整完下排会被裁掉）。
   */
  private canvasHeight(): number {
    const rows = Math.ceil(this.nodes.length / 2);
    const needed = rows * 162 + 16;
    return needed > CANVAS_HEIGHT ? needed : CANVAS_HEIGHT;
  }

  private inkColor(): string {
    return boardThemeColors(this.theme).text;
  }

  private inkDimColor(): string {
    return boardThemeColors(this.theme).textDim;
  }

  private pillColor(): string {
    if (this.theme === BoardThemeType.DOT_JOURNAL) {
      return '#EFE9DC';
    }
    if (this.theme === BoardThemeType.CORKBOARD) {
      return '#E3C6A9';
    }
    return '#3E6150';
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        this.DateStrip()
        this.Board()
      }
      .width('100%')

      if (this.posterOpen) {
        SharePosterDialog({
          posterUri: this.posterUri,
          savedPath: this.posterPath,
          onClose: () => {
            this.posterOpen = false;
          }
        })
      }
    }
    .width('100%')
  }

  /** 木框 + 板面 */
  @Builder
  Board() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        this.Header()
        this.ActionRow()

        if (this.viewMode === BoardViewMode.FREE_CANVAS) {
          this.FreeCanvas()
        } else {
          this.StructuredGrid()
        }

        // 底部：卡通猫 + 粉笔槽
        Row() {
          Blank()
          Image($r('app.media.mascot_cat'))
            .width(46)
            .height(46)
            .objectFit(ImageFit.Contain)
            .margin({ right: 4 })
        }
        .width('100%')
        .height(34)
        .alignItems(VerticalAlign.Bottom)
      }
      .padding({ left: 14, right: 14, top: 12, bottom: 6 })
      .width('100%')
      .backgroundColor(boardThemeColors(this.theme).board)
      .borderRadius(12)
      .linearGradient({
        angle: 120,
        colors: [
          [boardThemeColors(this.theme).board, 0],
          [boardThemeColors(this.theme).texture, 0.45],
          [boardThemeColors(this.theme).board, 1]
        ]
      })

      // 粉笔槽
      Row() {
        Column()
          .width(26).height(8).backgroundColor('#F4F1E4').borderRadius(5)
          .rotate({ angle: -6 })
        Column()
          .width(26).height(8).backgroundColor('#FFD97D').borderRadius(5)
          .rotate({ angle: 4 })
          .margin({ left: 7 })
      }
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .backgroundColor('#A8794C')
      .borderRadius(6)
      .margin({ right: 66, bottom: 4 })
    }
    .width('100%')
    .padding(9)
    .backgroundColor(boardThemeColors(this.theme).frame)
    .borderRadius(18)
    .shadow({ radius: 16, color: '#66000000', offsetX: 0, offsetY: 8 })
    .bindSheet($$this.sheetOpen, this.EditorSheet(), {
      height: SheetSize.LARGE,
      dragBar: true,
      backgroundColor: '#FFF8E7',
      showClose: true
    })
  }

  @Builder
  EditorSheet() {
    NoteEditorSheet({
      node: this.editingNode,
      onSave: (result: NodeEditResult) => this.saveNodeEdit(result),
      onDelete: (node: BoardNodeModel) => this.deleteNode(node),
      onCopy: (node: BoardNodeModel, targetDate: string) => this.copyNode(node, targetDate),
      onEditFood: (node: BoardNodeModel) => this.editFoodOf(node),
      onClose: () => {
        this.sheetOpen = false;
        this.editingNode = null;
      }
    })
  }
}
