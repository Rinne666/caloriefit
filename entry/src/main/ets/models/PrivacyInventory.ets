/**
 * 个人信息保护「双清单」的数据模型与实际内容。
 *
 * 依据：《工业和信息化部关于开展信息通信服务感知提升行动的通知》
 * （工信部信管函〔2021〕292号）要求各相关企业建立已收集个人信息清单和
 * 与第三方共享个人信息清单，并在 APP 二级菜单中展示。华为应用市场
 * 《用户隐私》同样把该项列入上架要求。
 *
 * 本文件里的每一条都**对应代码里的实际行为**，不是示例数据：
 *   · 存储位置一栏区分「应用本地数据库」「应用本地配置」「系统安全存储」；
 *   · 共享清单只列真正会离开设备的字段；
 *   · 第三方 SDK 清单逐个核实过源码（@pura/harmony-dialog 无任何网络 import）。
 * 改动应用的数据处理行为时，这里必须同步更新，否则清单就与实际不符。
 */

/** 已收集个人信息清单的一行 */
export class CollectedInfoItem {
  /** 信息种类 */
  name: string;
  /** 使用目的 */
  purpose: string;
  /** 使用场景 */
  scenario: string;
  /** 存储位置 */
  storage: string;
  /** 是否属于敏感个人信息 */
  sensitive: boolean;

  constructor(name: string, purpose: string, scenario: string, storage: string, sensitive: boolean) {
    this.name = name;
    this.purpose = purpose;
    this.scenario = scenario;
    this.storage = storage;
    this.sensitive = sensitive;
  }
}

/** 与第三方共享个人信息清单的一行 */
export class SharedInfoItem {
  /** 个人信息种类 */
  name: string;
  /** 接收方 */
  recipient: string;
  /** 使用目的 */
  purpose: string;
  /** 使用场景 */
  scenario: string;
  /** 共享方式 */
  method: string;

  constructor(name: string, recipient: string, purpose: string, scenario: string, method: string) {
    this.name = name;
    this.recipient = recipient;
    this.purpose = purpose;
    this.scenario = scenario;
    this.method = method;
  }
}

/** 第三方 SDK 的一行（用于说明其不涉及个人信息共享） */
export class ThirdPartySdkItem {
  name: string;
  purpose: string;
  /** 是否涉及个人信息收集或传输 */
  transmits: boolean;
  note: string;

  constructor(name: string, purpose: string, transmits: boolean, note: string) {
    this.name = name;
    this.purpose = purpose;
    this.transmits = transmits;
    this.note = note;
  }
}

/** 本机保存、不与任何第三方共享的数据 */
export const LOCAL_ONLY_FIELDS: string[] = [
  '身体档案（年龄、性别、身高、体重、体脂率、活动水平、目标模式）',
  '饮食记录（日期、餐次、食物名称、重量、每 100g 热量、总热量、蛋白质/碳水/脂肪、AI 置信度与备注）',
  '运动记录（日期、类型、时长、消耗热量）',
  '饮水记录（日期、毫升数）',
  '断食记录（日期、方案、开始与结束时间、完成标记）',
  '当日步数',
  '外观偏好（主题模式）',
  '隐私同意记录（政策版本号、同意时间、分项同意结果）',
  '引导草稿（目标模式、活动量、是否服用补剂、作息是否规律、每周外食次数）'
];

/** 已收集个人信息清单 */
export const COLLECTED_INFO_LIST: CollectedInfoItem[] = [
  new CollectedInfoItem(
    '身体档案：年龄、性别、身高、体重、体脂率、活动水平、目标模式',
    '计算基础代谢（BMR）、每日总消耗（TDEE）与热量及三大宏量目标',
    '我的 → 体征档案；首次启动引导流程',
    '应用本地数据库', true),
  new CollectedInfoItem(
    '饮食记录：日期、餐次、食物名称、食用重量、每 100g 热量、总热量、蛋白质/碳水/脂肪、AI 置信度与备注',
    '统计当日摄入热量与宏量，展示餐食详情与每日进度',
    '今日 → 早餐/午餐/晚餐/加餐；我的 → 全部餐食',
    '应用本地数据库', true),
  new CollectedInfoItem(
    '运动记录：日期、运动类型、时长、消耗热量',
    '统计活动热量与运动时长，汇总当日活动量',
    '我的 → 运动记录',
    '应用本地数据库', true),
  new CollectedInfoItem(
    '饮水记录：日期、毫升数',
    '展示饮水进度、日均用量与本周趋势',
    '今日 → 饮水',
    '应用本地数据库', false),
  new CollectedInfoItem(
    '断食记录：日期、方案、开始与结束时间、完成标记',
    '断食计时、方案历史与完成标记',
    '今日 → 断食',
    '应用本地数据库', true),
  new CollectedInfoItem(
    '当日步数',
    '展示步数与目标进度，作为活动量的参考',
    '我的 → 运动记录（需你主动授权动作权限；未授权时由你手动填写）',
    '应用本地数据库', true),
  new CollectedInfoItem(
    'AI 服务配置：服务地址、模型名称、是否记住密钥、演示模式开关',
    '按你的配置发起识别请求；演示模式用于本地模拟，不发送网络请求',
    '我的 → AI 食物识别设置',
    '应用本地配置', false),
  new CollectedInfoItem(
    'API Key',
    '调用你所配置的 AI 服务；默认仅在本次运行期间保留，开启“安全记住”后存入系统安全存储',
    '我的 → AI 食物识别设置',
    '系统安全存储', true),
  new CollectedInfoItem(
    '华为账号标识：UnionID、OpenID',
    '识别这是哪台设备上的账号记录；不登录也可完整使用全部记录功能',
    '我的 → 华为账号（登录后）',
    '应用本地配置', true),
  new CollectedInfoItem(
    '外观偏好：主题模式',
    '记住你的界面主题选择',
    '我的 → 外观',
    '应用本地配置', false),
  new CollectedInfoItem(
    '隐私同意记录：政策版本号、同意时间、通用规则与健康信息分项同意结果',
    '记录你的同意与撤回；政策版本变更时重新征求同意',
    '首次启动同意页',
    '应用本地配置', false),
  new CollectedInfoItem(
    '引导草稿：目标模式、活动量、是否服用补剂、作息是否规律、每周外食次数',
    '记录引导答案，并把目标与活动量写入体征档案参与热量推导',
    '首次启动引导流程',
    '应用本地配置', false)
];

/** 与第三方共享个人信息清单 */
export const SHARED_INFO_LIST: SharedInfoItem[] = [
  new SharedInfoItem(
    '食物照片（经缩放与压缩后的图像，不含相册其它内容）',
    '阿里云百炼（DashScope）及其子域名，由你在 AI 设置中自行指定',
    '识别照片中的食物并估算整份热量与营养素',
    '仅在 AI 识别页由你选图或拍照，并在上传确认窗点击“同意并识别”之后；拒绝上传仍可手动记录',
    'HTTPS 请求，每次上传前单独征求同意'),
  new SharedInfoItem(
    '你配置的 API Key',
    '同接收方',
    '调用鉴权',
    '同上述上传场景',
    'HTTPS 请求头 Authorization'),
  new SharedInfoItem(
    '华为账号标识：UnionID、OpenID',
    '华为账号服务（HMS Account Kit）',
    '完成登录鉴权，向应用返回你的账号标识',
    '仅在「我的 → 华为账号」中由你主动点击登录后发生；退出登录即撤销',
    '系统账号组件，凭证不经过本应用')
];

/** 第三方 SDK 清单 */
export const THIRD_PARTY_SDKS: ThirdPartySdkItem[] = [
  new ThirdPartySdkItem(
    '@pura/harmony-dialog',
    '统一弹窗与加载提示的 UI 组件',
    false,
    '纯本地渲染，源码中无任何网络 import，不采集也不传输个人信息')
];

/** 明确不收集的信息项 */
export const NOT_COLLECTED_FIELDS: string[] = [
  '姓名、手机号、身份证号等身份标识',
  '精确地理位置、通讯录、通话记录、短信',
  '生物特征',
  '设备标识符与广告标识符（OAID）',
  '剪贴板内容、相册后台扫描结果'
];
