/**
 * 黑板节点的持久化。
 *
 * ## 设计取舍
 * **黑板节点不是饮食记录的副本，而是它的「投影」**：
 *   FOOD_STICKER 节点只存位置/缩放/旋转/层级/装饰这些「黑板状态」，
 *   食物名称、热量、宏量、贴纸图一律从 food_log 读。
 *   好处是改完食物记录回到黑板，贴纸上的数字立刻跟着变，
 *   不会出现「餐食卡 430 kcal、黑板贴纸 380 kcal」两处对不上。
 *
 * ## 自动物化
 * 当某天的 food_log 里有记录、但黑板上还没有对应节点时，
 * `getNodes` 会自动补一个节点出来（默认位置）。
 * 这样「今天记了三餐」就一定在黑板上有三张贴纸，不需要用户手动摆。
 * 已经摆过的节点保留自己的空间状态，不会被重置。
 */

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Database } from '../database/Database';
import {
  BoardNodeModel,
  BoardNodeType,
  BoardSetting,
  BoardThemeType,
  BoardViewMode,
  PinDecorationType,
  StickyPaperStyle,
  nodeTiltWithSeed
} from '../models/BoardModels';
import { FoodRepository } from './FoodRepository';
import { FoodLog, FoodLogInput } from '../models/FoodLog';
import { StickerCutoutService } from '../services/StickerCutoutService';
import { PresetStickerKind } from '../services/StickerProcessor';

const TABLE = 'board_node';
const SETTING_TABLE = 'board_setting';
const DOMAIN = 0x0002;
const TAG = 'CalorieFitBoard';

/** 贴纸节点的默认尺寸（vp），用于排布与命中区域 */
export const BOARD_STICKER_SIZE: number = 104;
/** 便签节点的默认尺寸（vp） */
export const BOARD_NOTE_WIDTH: number = 148;
export const BOARD_NOTE_HEIGHT: number = 156;

export class BoardRepository {
  /**
   * 取某天的全部黑板节点（贴纸 + 便签 + 示例）。
   *
   * 顺带把「有饮食记录但没节点」的情况补齐。
   */
  static async getNodes(date: string): Promise<BoardNodeModel[]> {
    const store = await Database.ensure();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('date', date)
      .orderByAsc('z_index')
      .orderByAsc('id');
    const resultSet = await store.query(predicates);
    const nodes: BoardNodeModel[] = [];
    try {
      while (resultSet.goToNextRow()) {
        nodes.push(BoardRepository.mapRow(resultSet));
      }
    } finally {
      resultSet.close();
    }
    await BoardRepository.materializeMissing(date, nodes);
    await BoardRepository.resolveFoodStickers(nodes);

    // 示例节点：这一天一旦有了真实记录就不再显示。
    // 数据仍留在库里 —— 用户把记录全删了，示例还能回来接着当空态示例。
    let hasFood = false;
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i].nodeType === BoardNodeType.FOOD_STICKER) {
        hasFood = true;
        break;
      }
    }
    const visible: BoardNodeModel[] = [];
    let hasDemo = false;
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i].nodeType === BoardNodeType.DEMO_STICKER) {
        hasDemo = true;
        break;
      }
    }
    if (hasDemo) {
      // 内置贴纸的画法可能升级了 —— 先让旧文件失效，再读
      await StickerCutoutService.ensurePresetVersion();
    }
    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i];
      if (node.nodeType === BoardNodeType.DEMO_STICKER) {
        if (hasFood) {
          continue;
        }
        await BoardRepository.resolveDemoSticker(node);
      }
      visible.push(node);
    }
    return visible;
  }

  /** 示例贴纸在库里存的是相对路径，展示前转成 data URI */
  private static async resolveDemoSticker(node: BoardNodeModel): Promise<void> {
    if (node.stickerUri.length === 0 || node.stickerUri.startsWith('data:')) {
      return;
    }
    const uri = await StickerCutoutService.loadDataUri(node.stickerUri);
    if (uri.length > 0) {
      node.stickerUri = uri;
    }
  }

  /**
   * 给「有记录但没节点」的饮食补一个节点。
   *
   * 位置按序号排成松散的三列，并带一点随机偏移和自然倾角，
   * 避免所有贴纸严丝合缝地排成一行（那样就不像黑板了）。
   */
  private static async materializeMissing(date: string, nodes: BoardNodeModel[]): Promise<void> {
    const known: number[] = [];
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i].nodeType === BoardNodeType.FOOD_STICKER && nodes[i].foodId !== null) {
        known.push(nodes[i].foodId as number);
      }
    }
    let logs: FoodLog[] = [];
    try {
      logs = await FoodRepository.getByDate(date);
    } catch (_e) {
      return;
    }
    let created = 0;
    for (let i = 0; i < logs.length; i++) {
      const log = logs[i];
      if (known.indexOf(log.id) >= 0) {
        continue;
      }
      const node = new BoardNodeModel();
      node.date = date;
      node.nodeType = BoardNodeType.FOOD_STICKER;
      node.foodId = log.id;
      node.title = log.name;
      node.calories = log.calories;
      node.proteinGrams = log.proteinG;
      node.carbsGrams = log.carbsG;
      node.fatGrams = log.fatG;
      node.mealCategory = log.mealType;
      const slot = known.length + created;
      const pos = BoardRepository.defaultPosition(slot, log.id);
      node.x = pos[0];
      node.y = pos[1];
      node.rotation = nodeTiltWithSeed(log.id);
      node.zIndex = await BoardRepository.nextZIndex(date);
      node.paperStyle = BoardRepository.paperStyleFor(log.id);
      node.pinType = PinDecorationType.WASHI_TAPE_DOT;
      try {
        node.id = await BoardRepository.upsert(node);
        nodes.push(node);
        created++;
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'materialize node failed for food %{public}d', log.id);
      }
    }
  }

  /** 默认位置：松散三列 + 抖动，vp */
  private static defaultPosition(index: number, seed: number): number[] {
    const col = index % 3;
    const row = Math.floor(index / 3);
    const jitterX = (Math.abs(seed) % 5) * 4 - 8;
    const jitterY = (Math.abs(seed) % 7) * 3 - 9;
    const x = 14 + col * 116 + jitterX;
    const y = 10 + row * 122 + jitterY;
    return [x, y];
  }

  /** 贴纸节点的便签配色由记录 id 派生，保证同一张贴纸每次颜色一致 */
  private static paperStyleFor(seed: number): StickyPaperStyle {
    const styles: StickyPaperStyle[] = [
      StickyPaperStyle.CREAM_YELLOW,
      StickyPaperStyle.MINT_GREEN,
      StickyPaperStyle.SAKURA_PINK,
      StickyPaperStyle.KRAFT_PAPER
    ];
    return styles[Math.abs(seed) % styles.length];
  }

  /** 从 food_log 读贴纸节点的内容 */
  private static async resolveFoodStickers(nodes: BoardNodeModel[]): Promise<void> {
    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i];
      if (node.nodeType !== BoardNodeType.FOOD_STICKER || node.foodId === null) {
        continue;
      }
      const log = await FoodRepository.getById(node.foodId);
      if (log === null) {
        continue;
      }
      node.title = log.name;
      node.calories = log.calories;
      node.proteinGrams = log.proteinG;
      node.carbsGrams = log.carbsG;
      node.fatGrams = log.fatG;
      node.mealCategory = log.mealType;
      if (log.stickerPath !== null) {
        const uri = await StickerCutoutService.loadDataUri(log.stickerPath);
        if (uri.length > 0) {
          node.stickerUri = uri;
        }
      }
    }
  }

  /* ------------------------------ 写操作 ------------------------------ */

  /** 新建或更新一个节点；返回节点 id */
  static async upsert(node: BoardNodeModel): Promise<number> {
    const store = await Database.ensure();
    const now = Date.now();
    const bucket: relationalStore.ValuesBucket = {
      'date': node.date,
      'node_type': node.nodeType,
      'food_id': node.foodId,
      'title': node.title,
      'calories': node.calories,
      'protein_g': node.proteinGrams,
      'carbs_g': node.carbsGrams,
      'fat_g': node.fatGrams,
      'portion_desc': node.portionDesc,
      'meal_category': node.mealCategory,
      'time_str': node.timeStr,
      'mood_emoji': node.moodEmoji,
      'companion_text': node.companionText,
      'memo_text': node.memoText,
      'ai_advice': node.aiAdvice,
      'sticker_uri': node.stickerUri,
      'paper_style': node.paperStyle,
      'pin_type': node.pinType,
      'pos_x': node.x,
      'pos_y': node.y,
      'scale': node.scale,
      'rotation': node.rotation,
      'z_index': node.zIndex,
      'is_flipped': node.isFlipped ? 1 : 0,
      'updated_at': now
    };
    if (node.id > 0) {
      const predicates = new relationalStore.RdbPredicates(TABLE);
      predicates.equalTo('id', node.id);
      await store.update(bucket, predicates);
      return node.id;
    }
    // created_at 是 NOT NULL 且没有默认值 —— 插入时必须显式带上，
    // 漏了会直接撞 SQLite 的约束（报 "constraint violation"，看不出是哪一列）。
    bucket['created_at'] = now;
    const rowId = await store.insert(TABLE, bucket);
    node.id = rowId;
    return rowId;
  }

  /** 只保存空间状态（拖拽/缩放/旋转/置顶时高频调用） */
  static async saveTransform(id: number, x: number, y: number,
    scale: number, rotation: number, zIndex: number): Promise<void> {
    const store = await Database.ensure();
    const bucket: relationalStore.ValuesBucket = {
      'pos_x': x,
      'pos_y': y,
      'scale': scale,
      'rotation': rotation,
      'z_index': zIndex,
      'updated_at': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    await store.update(bucket, predicates);
  }

  /** 保存便签内容（碎碎念 / 心情 / 和谁吃 / 纸色 / 胶带） */
  static async saveContent(id: number, title: string, calories: number,
    proteinG: number | null, carbsG: number | null, fatG: number | null,
    portionDesc: string, mealCategory: number, timeStr: string,
    moodEmoji: string, companionText: string, memoText: string,
    paperStyle: StickyPaperStyle, pinType: PinDecorationType): Promise<void> {
    const store = await Database.ensure();
    const bucket: relationalStore.ValuesBucket = {
      'title': title,
      'calories': calories,
      'protein_g': proteinG,
      'carbs_g': carbsG,
      'fat_g': fatG,
      'portion_desc': portionDesc,
      'meal_category': mealCategory,
      'time_str': timeStr,
      'mood_emoji': moodEmoji,
      'companion_text': companionText,
      'memo_text': memoText,
      'paper_style': paperStyle,
      'pin_type': pinType,
      'updated_at': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    await store.update(bucket, predicates);
  }

  /** 翻转状态（翻到背面看便签） */
  static async saveFlipped(id: number, flipped: boolean): Promise<void> {
    const store = await Database.ensure();
    const bucket: relationalStore.ValuesBucket = {
      'is_flipped': flipped ? 1 : 0,
      'updated_at': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    await store.update(bucket, predicates);
  }

  /** 只改餐次（分栏拖拽时用） */
  static async saveMealCategory(id: number, mealCategory: number): Promise<void> {
    const store = await Database.ensure();
    const bucket: relationalStore.ValuesBucket = {
      'meal_category': mealCategory,
      'updated_at': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    await store.update(bucket, predicates);
  }

  /** 删一个节点 */
  static async delete(id: number): Promise<void> {
    const store = await Database.ensure();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    await store.delete(predicates);
  }

  /** 清掉某天的全部节点 */
  static async clearByDate(date: string): Promise<void> {
    const store = await Database.ensure();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('date', date);
    await store.delete(predicates);
  }

  /** 当天的最大 zIndex + 1 */
  static async nextZIndex(date: string): Promise<number> {
    const store = await Database.ensure();
    const resultSet = await store.querySql(
      `SELECT COALESCE(MAX(z_index), -1) AS max_z FROM ${TABLE} WHERE date = ?`, [date]);
    let maxZ = -1;
    try {
      if (resultSet.goToNextRow()) {
        maxZ = resultSet.getLong(resultSet.getColumnIndex('max_z'));
      }
    } finally {
      resultSet.close();
    }
    return maxZ + 1;
  }

  /* ------------------------------ 设置 ------------------------------ */

  /** 读黑板设置（主题 + 视图模式） */
  static async getSetting(): Promise<BoardSetting> {
    const store = await Database.ensure();
    const predicates = new relationalStore.RdbPredicates(SETTING_TABLE);
    predicates.equalTo('id', 1);
    const resultSet = await store.query(predicates);
    try {
      if (resultSet.goToNextRow()) {
        const theme = resultSet.getLong(resultSet.getColumnIndex('theme'));
        const viewMode = resultSet.getLong(resultSet.getColumnIndex('view_mode'));
        return new BoardSetting(
          theme as BoardThemeType,
          viewMode as BoardViewMode
        );
      }
    } finally {
      resultSet.close();
    }
    return new BoardSetting(BoardThemeType.CHALKBOARD, BoardViewMode.FREE_CANVAS);
  }

  /** 写黑板设置 */
  static async saveSetting(theme: BoardThemeType, viewMode: BoardViewMode): Promise<void> {
    const store = await Database.ensure();
    const bucket: relationalStore.ValuesBucket = {
      'theme': theme,
      'view_mode': viewMode,
      'updated_at': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(SETTING_TABLE);
    predicates.equalTo('id', 1);
    await store.update(bucket, predicates);
  }

  /* ------------------------------ 示例数据 ------------------------------ */

  /**
   * 给某一天铺一套示例节点：3 张内置矢量美食贴纸 + 1 张心情便签。
   *
   * 规则：
   *   · 这一天还没有示例节点、也还没有真实饮食记录时才铺（空板子给点东西看）；
   *   · 一旦这一天有了真实记录，示例就不再显示（见 getNodes 的过滤）；
   *   · 贴纸图存成文件（只存一份），节点里只存相对路径。
   *
   * 示例节点**不写入 food_log**，所以不会污染「今日摄入」。
   */
  static async seedDemo(date: string): Promise<number> {
    const store = await Database.ensure();
    const resultSet = await store.querySql(
      `SELECT COUNT(*) AS cnt FROM ${TABLE} WHERE date = ? AND node_type = ?`,
      [date, BoardNodeType.DEMO_STICKER]);
    let count = 0;
    try {
      if (resultSet.goToNextRow()) {
        count = resultSet.getLong(resultSet.getColumnIndex('cnt'));
      }
    } finally {
      resultSet.close();
    }
    if (count > 0) {
      return 0;
    }

    const kinds: PresetStickerKind[] = [
      PresetStickerKind.PAN_FRIED_BUN,
      PresetStickerKind.AVOCADO_TOAST,
      PresetStickerKind.ICED_AMERICANO
    ];
    const names: string[] = ['生煎包四只', '牛油果滑蛋吐司', '冰美式'];
    const kcals: number[] = [430, 380, 95];
    // 位置按「板子最窄的情况」排：板面实际宽度随机型在 280~380vp 之间，
    // 排得太靠右会在窄屏上顶出板面（渲染时还有一次夹取兜底）。
    const posX: number[] = [6, 120, 24];
    const posY: number[] = [6, 26, 150];
    const meals: number[] = [0, 1, 3];   // 早餐 / 午餐 / 加餐

    let created = 0;
    for (let i = 0; i < kinds.length; i++) {
      try {
        const path = await StickerCutoutService.ensurePresetSticker(kinds[i]);
        if (path.length === 0) {
          continue;
        }
        const node = new BoardNodeModel();
        node.date = date;
        node.nodeType = BoardNodeType.DEMO_STICKER;
        node.foodId = null;
        node.title = names[i];
        node.calories = kcals[i];
        node.mealCategory = meals[i];
        node.timeStr = i === 0 ? '08:20' : (i === 1 ? '12:30' : '15:10');
        node.stickerUri = path;
        node.x = posX[i];
        node.y = posY[i];
        node.rotation = [-2, 3, -1][i];
        node.zIndex = await BoardRepository.nextZIndex(date);
        node.paperStyle = BoardRepository.paperStyleFor(i + 1);
        node.pinType = i === 1 ? PinDecorationType.RED_THUMB_TACK : PinDecorationType.WASHI_TAPE_DOT;
        node.id = await BoardRepository.upsert(node);
        created++;
      } catch (e) {
        const err = e as Error;
        hilog.warn(DOMAIN, TAG, 'seed demo sticker %{public}d failed: %{public}s', i, err.message);
      }
    }

    try {
      const note = new BoardNodeModel();
      note.date = date;
      note.nodeType = BoardNodeType.STICKY_NOTE;
      note.foodId = null;
      note.title = '今天的小确幸';
      note.calories = 0;
      note.mealCategory = 2;
      note.timeStr = '21:10';
      note.moodEmoji = '🥳';
      note.companionText = '和老友小聚';
      note.memoText = '外皮焦脆汁水超多！这家的生煎包饭搭子认证～';
      note.aiAdvice = '蛋白质摄入不错，明天记得补点蔬菜均衡一下～';
      note.x = 140;
      note.y = 134;
      note.rotation = 2;
      note.zIndex = await BoardRepository.nextZIndex(date);
      note.paperStyle = StickyPaperStyle.CREAM_YELLOW;
      note.pinType = PinDecorationType.WASHI_TAPE_STRIPE;
      note.id = await BoardRepository.upsert(note);
      created++;
    } catch (e) {
      const err = e as Error;
      hilog.warn(DOMAIN, TAG, 'seed demo note failed: %{public}s', err.message);
    }
    return created;
  }

  /* ------------------------------ 复制到指定日期 ------------------------------ */

  /**
   * 把一个节点复制到另一天。
   *
   * 贴纸节点要连**饮食记录**一起复制 —— 只复制黑板节点的话，
   * 目标那天会出现一张贴纸却没有对应的餐食记录，
   * 「今日摄入」和黑板就对不上了。
   */
  static async copyToDate(node: BoardNodeModel, targetDate: string): Promise<number> {
    if (node.nodeType === BoardNodeType.FOOD_STICKER && node.foodId !== null) {
      const log = await FoodRepository.getById(node.foodId);
      if (log === null) {
        return 0;
      }
      const input = new FoodLogInput(
        targetDate, log.name, log.mealType, log.grams, log.kcalPer100g,
        log.calories, log.entryMode, log.aiConfidence, log.aiNotes,
        log.proteinG, log.carbsG, log.fatG, log.stickerPath
      );
      const newFoodId = await FoodRepository.insert(input);
      const copy = BoardRepository.cloneNode(node);
      copy.date = targetDate;
      copy.foodId = newFoodId;
      copy.id = 0;
      copy.zIndex = await BoardRepository.nextZIndex(targetDate);
      return BoardRepository.upsert(copy);
    }
    const copy = BoardRepository.cloneNode(node);
    copy.date = targetDate;
    copy.id = 0;
    copy.zIndex = await BoardRepository.nextZIndex(targetDate);
    return BoardRepository.upsert(copy);
  }

  /** 复制一个节点的全部字段（不改 id / date） */
  private static cloneNode(node: BoardNodeModel): BoardNodeModel {
    const copy = new BoardNodeModel();
    copy.date = node.date;
    copy.nodeType = node.nodeType;
    copy.foodId = node.foodId;
    copy.title = node.title;
    copy.calories = node.calories;
    copy.proteinGrams = node.proteinGrams;
    copy.carbsGrams = node.carbsGrams;
    copy.fatGrams = node.fatGrams;
    copy.portionDesc = node.portionDesc;
    copy.mealCategory = node.mealCategory;
    copy.timeStr = node.timeStr;
    copy.moodEmoji = node.moodEmoji;
    copy.companionText = node.companionText;
    copy.memoText = node.memoText;
    copy.aiAdvice = node.aiAdvice;
    copy.stickerUri = node.stickerUri;
    copy.paperStyle = node.paperStyle;
    copy.pinType = node.pinType;
    copy.x = node.x;
    copy.y = node.y;
    copy.scale = node.scale;
    copy.rotation = node.rotation;
    copy.zIndex = node.zIndex;
    copy.isFlipped = node.isFlipped;
    return copy;
  }

  /* ------------------------------ 行映射 ------------------------------ */

  private static mapRow(rs: relationalStore.ResultSet): BoardNodeModel {
    const node = new BoardNodeModel();
    node.id = rs.getLong(rs.getColumnIndex('id'));
    node.date = rs.getString(rs.getColumnIndex('date'));
    node.nodeType = rs.getLong(rs.getColumnIndex('node_type')) as BoardNodeType;
    const foodIdx = rs.getColumnIndex('food_id');
    if (foodIdx >= 0 && rs.getColumnTypeSync(foodIdx) !== relationalStore.ColumnType.NULL) {
      node.foodId = rs.getLong(foodIdx);
    } else {
      node.foodId = null;
    }
    node.title = rs.getString(rs.getColumnIndex('title'));
    node.calories = rs.getLong(rs.getColumnIndex('calories'));
    node.proteinGrams = BoardRepository.readNullableDouble(rs, 'protein_g');
    node.carbsGrams = BoardRepository.readNullableDouble(rs, 'carbs_g');
    node.fatGrams = BoardRepository.readNullableDouble(rs, 'fat_g');
    node.portionDesc = rs.getString(rs.getColumnIndex('portion_desc'));
    node.mealCategory = rs.getLong(rs.getColumnIndex('meal_category'));
    node.timeStr = rs.getString(rs.getColumnIndex('time_str'));
    node.moodEmoji = rs.getString(rs.getColumnIndex('mood_emoji'));
    node.companionText = rs.getString(rs.getColumnIndex('companion_text'));
    node.memoText = rs.getString(rs.getColumnIndex('memo_text'));
    node.aiAdvice = rs.getString(rs.getColumnIndex('ai_advice'));
    node.stickerUri = rs.getString(rs.getColumnIndex('sticker_uri'));
    node.paperStyle = rs.getLong(rs.getColumnIndex('paper_style')) as StickyPaperStyle;
    node.pinType = rs.getLong(rs.getColumnIndex('pin_type')) as PinDecorationType;
    node.x = rs.getDouble(rs.getColumnIndex('pos_x'));
    node.y = rs.getDouble(rs.getColumnIndex('pos_y'));
    node.scale = rs.getDouble(rs.getColumnIndex('scale'));
    node.rotation = rs.getDouble(rs.getColumnIndex('rotation'));
    node.zIndex = rs.getLong(rs.getColumnIndex('z_index'));
    node.isFlipped = rs.getLong(rs.getColumnIndex('is_flipped')) === 1;
    return node;
  }

  private static readNullableDouble(rs: relationalStore.ResultSet, column: string): number | null {
    const idx = rs.getColumnIndex(column);
    if (idx < 0 || rs.getColumnTypeSync(idx) === relationalStore.ColumnType.NULL) {
      return null;
    }
    return rs.getDouble(idx);
  }
}
