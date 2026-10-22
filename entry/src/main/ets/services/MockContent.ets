/**
 * Mock / 推断数据集中地。
 *
 * 为什么单独一个文件：这个项目里「哪些是实测的、哪些是我推断的、哪些是纯假数据」
 * 是交付要求的一部分。散落到各页面就没人说得清了，所以统一在这里标注。
 *
 * 三档来源（界面上会用对应角标显示）：
 *   MEASURED 真机截图 / strings_all.txt 实测
 *   INFERRED 有实测证据支撑，但具体算法或数值是我推的
 *   MOCK     原样编的假数据，只为了让界面和跳转能走通
 *
 * 硬规矩：**任何 INFERRED / MOCK 都不许在界面上装成实测值。**
 * 页面上要么显示角标，要么在文案里写明「示例数据」。
 */

/** 数据来源等级 */
export enum Provenance {
  /** 真机截图 / strings_all.txt 实测 */
  MEASURED = 'measured',
  /** 有实测证据支撑，具体算法或数值是推断的 */
  INFERRED = 'inferred',
  /** 原样编的假数据，只为走通界面 */
  MOCK = 'mock'
}

export function provenanceLabel(p: Provenance): string {
  if (p === Provenance.MEASURED) {
    return '实测';
  }
  if (p === Provenance.INFERRED) {
    return '推断';
  }
  return '示例';
}

/* ==================================================================
 * ⚠ 以下「饮水 Water」「断食 Fasting」「膳食计划 Diet Plan」三段对应的功能
 *   已于 2026-10-20 下线（产品决策：聚焦热量记录 + 今日黑板）。
 *   这里**保留**它们 —— 这些是原版 NutriScan 的实测证据（字段名、文案、
 *   方案清单），后续若要恢复功能可以直接复用，不必重���去原版里挖。
 * ================================================================== */

/* ==================================================================
 * 饮水 Water
 * ------------------------------------------------------------------
 * 实测：UI 上 goal 2,650 ml 带铅笔图标（可手改）、快加 250/500 ml、
 *       「% completed」用青色、周条 M–S 今天高亮描边、
 *       底部卡片是 Day Streak + Avg/Day + 七天柱图。
 *       字段名 total_ml 出自 strings。
 * 推断：每日目标公式原版未知，按品类通行的 体重(kg) × 35 ml 计算。
 * ================================================================== */

/** 每公斤体重建议摄入毫升数（推断） */
export const WATER_ML_PER_KG: number = 35;

/** 快捷添加量（实测：250 / 500 / 自定义） */
export const WATER_QUICK_ML: number[] = [250, 500];

export function waterTargetMl(weightKg: number): number {
  if (!(weightKg > 0)) {
    return 0;
  }
  // 取整到 50 的倍数，与原版 2,650 这种数字的颗粒度一致
  return Math.round((weightKg * WATER_ML_PER_KG) / 50) * 50;
}

/* ==================================================================
 * 断食 Fasting
 * ------------------------------------------------------------------
 * 实测：方案名 16:8 / 18:6 / 20:4 / 14:10 / 12:12 均在 strings 中命中，
 *       并有文案「16:8, 18:6 或你自己的窗口」，说明还有自定义窗口。
 *       日志里有「16:8 fast complete」，即按方案计时到点提示完成。
 * 推断：各方案的具体热量分配与提醒逻辑原版未知，此处只做计时与展示。
 * ================================================================== */

export class FastingPlan {
  id: string;
  name: string;
  fastingHours: number;
  eatingHours: number;
  /** 一句话说明，MEASURED 文案直译自 strings */
  note: string;
  provenance: Provenance;

  constructor(id: string, name: string, fastingHours: number, eatingHours: number,
              note: string, provenance: Provenance) {
    this.id = id;
    this.name = name;
    this.fastingHours = fastingHours;
    this.eatingHours = eatingHours;
    this.note = note;
    this.provenance = provenance;
  }
}

export const FASTING_PLANS: FastingPlan[] = [
  new FastingPlan('16:8', '16:8', 16, 8,
    '两餐制，经典入门方案', Provenance.MEASURED),
  new FastingPlan('18:6', '18:6', 18, 6,
    '两餐窄窗口，16:8 觉得轻松后进阶', Provenance.MEASURED),
  new FastingPlan('20:4', '20:4', 20, 4,
    '严格版 Warrior，冷门但见效快', Provenance.MEASURED),
  new FastingPlan('14:10', '14:10', 14, 10,
    '新手友好，接近一日三餐', Provenance.MEASURED),
  new FastingPlan('12:12', '12:12', 12, 12,
    '不吃晚餐的轻断食', Provenance.MEASURED),
  new FastingPlan('custom', '自定义窗口', 0, 0,
    '自己定进食与断食时长', Provenance.MEASURED)
];

/* ==================================================================
 * 补剂 Supplements（实测：supplement / supplement_needed /
 * supplement_note / supplements_count 字段名 + 引导语原文）
 * ================================================================== */

export class SupplementItem {
  id: string;
  name: string;
  need: string;
  note: string;
  provenance: Provenance;

  constructor(id: string, name: string, need: string, note: string, provenance: Provenance) {
    this.id = id;
    this.name = name;
    this.need = need;
    this.note = note;
    this.provenance = provenance;
  }
}

export const SUPPLEMENTS: SupplementItem[] = [
  new SupplementItem('vitd', '维生素 D', '日照不足', '室内久坐者常见缺口', Provenance.MOCK),
  new SupplementItem('b12', '维生素 B12', '纯素饮食', '植物性饮食需额外补充', Provenance.MOCK),
  new SupplementItem('omega3', 'Omega-3', '深海鱼摄入少', '每周吃鱼不足两次时建议', Provenance.MOCK),
  new SupplementItem('iron', '铁', '经期 / 已知偏低', '需配合血检判断，勿自行加量', Provenance.MOCK),
  new SupplementItem('creatine', '肌酸', '力量训练人群', '证据较充分，3–5g/日', Provenance.MOCK)
];

/* ==================================================================
 * 生活方式 Lifestyle（实测字段名 lifestyle / lifestyle_view_shown /
 * 「Lifestyle & Feelings」分类，以及文案
 * 「We'll suggest meals that match your lifestyle, routine, and food habits.」）
 * ================================================================== */

export class LifestyleItem {
  id: string;
  group: string;
  title: string;
  detail: string;
  provenance: Provenance;

  constructor(id: string, group: string, title: string, detail: string, provenance: Provenance) {
    this.id = id;
    this.group = group;
    this.title = title;
    this.detail = detail;
    this.provenance = provenance;
  }
}

export const LIFESTYLE_GROUPS: string[] = ['Lifestyle & Feelings'];

export const LIFESTYLES: LifestyleItem[] = [
  new LifestyleItem('routine', 'Lifestyle & Feelings', '作息规律',
    '固定三餐时段，睡眠尽量稳定', Provenance.MOCK),
  new LifestyleItem('eatout', 'Lifestyle & Feelings', '外食频率',
    '每周外食次数会影响饮食计划的可执行度', Provenance.MOCK),
  new LifestyleItem('cuisine', 'Lifestyle & Feelings', '偏好菜系',
    '按你的习惯推荐，而不是通用食谱', Provenance.MOCK),
  new LifestyleItem('stress', 'Lifestyle & Feelings', '压力水平',
    '高压力日建议提高碳水比例', Provenance.MOCK)
];

/* ==================================================================
 * 膳食计划 Diet Plan + 购物清单 Grocery
 * ------------------------------------------------------------------
 * 实测：`groceryList` 字段、`/api/v2/generate_grocery_list` 接口路径、
 *       文案「Every scan, meal idea, recipe and grocery list goes
 *       100% plant-based.」（全植物基）、
 *       「Conocer tus alergias nos ayuda a evitar ingredientes...」（过敏原）。
 * 推断：计划生成是服务端行为，本地无法复刻 —— 以下为 mock。
 * ================================================================== */

export class MealPlanSlot {
  meal: string;
  dishes: string[];
  kcal: number;

  constructor(meal: string, dishes: string[], kcal: number) {
    this.meal = meal;
    this.dishes = dishes;
    this.kcal = kcal;
  }
}

export class DayPlan {
  dateLabel: string;
  slots: MealPlanSlot[];
  provenance: Provenance;

  constructor(dateLabel: string, slots: MealPlanSlot[], provenance: Provenance) {
    this.dateLabel = dateLabel;
    this.slots = slots;
    this.provenance = provenance;
  }
}

export const DIET_PLAN: DayPlan[] = [
  new DayPlan('周一', [
    new MealPlanSlot('早餐', ['燕麦粥', '蓝莓', '杏仁'], 420),
    new MealPlanSlot('午餐', ['藜麦沙拉', '烤南瓜'], 560),
    new MealPlanSlot('晚餐', ['豆腐炒蔬菜', '糙米饭'], 480)
  ], Provenance.MOCK),
  new DayPlan('周二', [
    new MealPlanSlot('早餐', ['豆浆', '全麦吐司'], 390),
    new MealPlanSlot('午餐', ['鹰嘴豆咖喱', '糙米饭'], 600),
    new MealPlanSlot('晚餐', ['番茄豆腐汤', '全麦面包'], 430)
  ], Provenance.MOCK),
  new DayPlan('周三', [
    new MealPlanSlot('早餐', ['奇亚籽布丁'], 350),
    new MealPlanSlot('午餐', ['烤时蔬配毛豆'], 540),
    new MealPlanSlot('晚餐', ['扁豆汤', '蒸南瓜'], 460)
  ], Provenance.MOCK)
];

export class GroceryItem {
  id: string;
  name: string;
  amount: string;
  checked: boolean;
  provenance: Provenance;

  constructor(id: string, name: string, amount: string, checked: boolean, provenance: Provenance) {
    this.id = id;
    this.name = name;
    this.amount = amount;
    this.checked = checked;
    this.provenance = provenance;
  }
}

export const GROCERY_LIST: GroceryItem[] = [
  new GroceryItem('g1', '燕麦片', '500g', false, Provenance.MOCK),
  new GroceryItem('g2', '蓝莓', '200g', false, Provenance.MOCK),
  new GroceryItem('g3', '杏仁', '100g', false, Provenance.MOCK),
  new GroceryItem('g4', '藜麦', '300g', false, Provenance.MOCK),
  new GroceryItem('g5', '南瓜', '1 个', true, Provenance.MOCK),
  new GroceryItem('g6', '嫩豆腐', '2 盒', false, Provenance.MOCK),
  new GroceryItem('g7', '糙米', '500g', false, Provenance.MOCK),
  new GroceryItem('g8', '毛豆', '200g', false, Provenance.MOCK),
  new GroceryItem('g9', '扁豆', '300g', false, Provenance.MOCK)
];

/* ==================================================================
 * 进度 Progress
 * ------------------------------------------------------------------
 * 实测：`readiness_score` / `readiness_breakdown` 字段、
 *       接口 `/api/v1/progress/readiness`、
 *       筛选维度 Today / Week / 30 Days，
 *       以及「Average NutriScore Last 30 Days」「Your protein target, last 30 days」等文案。
 * 推断：NutriScore 与 Readiness 的算法完全未知 —— 界面上给占位，不编数。
 * ================================================================== */

export const PROGRESS_RANGES: string[] = ['今天', '本周', '近 30 天'];

/* ==================================================================
 * 我的 You
 * ------------------------------------------------------------------
 * 实测：日志含 AllMealsRepositoryImpl.addFavouriteMeal / removeFavouriteMeal、
 *       接口 `/api/v1/favourite_food_items`、
 *       「Choose Reminder Type」「Edit repeat meal schedule」
 *       「Active Vacation Mode」「You can only start vacation mode up to 30 days in the past.」
 *       「Built for restarts: streaks survive off days, and vacation mode means no guilt.」
 * ================================================================== */

export class YouEntry {
  id: string;
  title: string;
  subtitle: string;
  /** 对应 NavPathStack 路由名；未实现时指向 ComingSoon */
  route: string;
  /** 'real' 已实现 / 'mock' 示例数据 / 'todo' 未实现跳转 */
  status: string;
  provenance: Provenance;

  constructor(id: string, title: string, subtitle: string, route: string,
              status: string, provenance: Provenance) {
    this.id = id;
    this.title = title;
    this.subtitle = subtitle;
    this.route = route;
    this.status = status;
    this.provenance = provenance;
  }
}
