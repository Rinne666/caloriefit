/**
 * V1.1 AI 识别常量：配置键、默认值、Prompt、错误码、限制。
 */

export class AiConfigKeys {
  static readonly PREFS_NAME = 'caloriefit_ai_settings';
  static readonly BASE_URL = 'ai.base_url';
  static readonly MODEL_NAME = 'ai.model_name';
  static readonly REMEMBER_KEY = 'ai.remember_key';
  static readonly DEMO_MODE = 'ai.demo_mode';
}

export class AiDefaults {
  // 默认走 OpenCSG 网关（OpenAI 兼容）。实测 deepseek-v4.1-flash-1017 可吃
  // image_url（usage 返回 image_tokens），识别准确且延迟 5~7s，落在 30s 超时内。
  static readonly BASE_URL = 'https://opencsg.com/aigateway/v1';
  static readonly MODEL_NAME = 'deepseek-v4.1-flash-1017';
  static readonly REMEMBER_KEY = false;
  static readonly DEMO_MODE = false;
}

/**
 * 安全存储里的凭证别名。
 * 原为 'caloriefit_dashscope_key'，换服务方后改成与厂商无关的名字；
 * 旧别名下的历史 Key 由 AiCredentialStore 主动清理，避免在系统安全存储里留孤儿凭证。
 */
export const AI_SECRET_ALIAS = 'caloriefit_ai_key';
/** 旧别名，仅用于清理遗留凭证，不再写入。 */
export const AI_LEGACY_SECRET_ALIAS = 'caloriefit_dashscope_key';

/** 图片约束（客户端策略） */
export class AiImageLimits {
  static readonly MAX_LONG_SIDE = 1280;
  static readonly MAX_BYTES = 2 * 1024 * 1024;
  static readonly INITIAL_QUALITY = 85;
  static readonly MIN_QUALITY = 30;
}

export const AI_REQUEST_TIMEOUT_MS = 30000;
export const AI_LOW_CONFIDENCE = 0.5;

export const AI_SYSTEM_PROMPT: string = `你是CalorieFit的食物视觉识别与热量估算助手。识别图片中可见的食物，估算整份可食用部分的总热量kcal。考虑食物种类、份量、烹饪方式、酱料和油脂，不要把餐具计算进去。不能从照片准确确定重量时，应作保守的区间判断并在备注中说明。不得把估算说成实测值。如果不是食物图片，返回foodName为无法识别、estimatedTotalKcal为null、confidence为0。

同时估算三大宏量营养素（克）：proteinG蛋白质、carbsG碳水化合物、fatG脂肪。三者必须与总热量自洽：按蛋白4kcal/g、碳水4kcal/g、脂肪9kcal/g回算，回算值与estimatedTotalKcal的偏差不得超过正负20%。无法可靠估算时返回null，不要为了填满字段而编造数字。

只返回一个合法JSON对象，不输出Markdown。字段必须为：
foodName字符串，estimatedTotalKcal整数或null，confidence为0到1之间的数字，
proteinG整数或null（0到999），carbsG整数或null（0到999），fatG整数或null（0到999），
notes字符串，控制在60字以内。
多种食物在foodName中合并命名，热量与宏量均返回整盘合计。

还要给出食物在图片中的位置，用于把食物抠成一张独立贴纸：
foodBox是食物的外接矩形，foodPolygon是食物的轮廓顶点。
两者坐标都是相对整张图片的0到1000整数，左上角为(0,0)，x向右、y向下。
foodBox格式为{"x":整数,"y":整数,"width":整数,"height":整数}。
foodPolygon格式为[[x,y],[x,y],...]，至少3个点，沿轮廓依次排列；不便给出时可以省略该字段。
只框食物本身，不要把盘子、桌面、餐具等背景框进去。判断不了位置时foodBox给null。`;

export const AI_USER_PROMPT: string = '请识别这张照片中的食物，估算整份热量与三大宏量（蛋白质/碳水/脂肪），严格按System要求返回JSON。';

export enum AiErrorCode {
  NO_API_KEY = 'NO_API_KEY',
  INVALID_CONFIG = 'INVALID_CONFIG',
  IMAGE_INVALID = 'IMAGE_INVALID',
  IMAGE_TOO_LARGE = 'IMAGE_TOO_LARGE',
  CAMERA_UNAVAILABLE = 'CAMERA_UNAVAILABLE',
  NETWORK_ERROR = 'NETWORK_ERROR',
  TIMEOUT = 'TIMEOUT',
  UNAUTHORIZED = 'UNAUTHORIZED',
  FORBIDDEN = 'FORBIDDEN',
  RATE_LIMITED = 'RATE_LIMITED',
  QUOTA_EXCEEDED = 'QUOTA_EXCEEDED',
  SERVER_ERROR = 'SERVER_ERROR',
  INVALID_RESPONSE = 'INVALID_RESPONSE',
  CANCELLED = 'CANCELLED',
  SECURE_STORE_UNAVAILABLE = 'SECURE_STORE_UNAVAILABLE'
}

/** 错误码 → 中文提示（不暴露原始服务端响应） */
export function aiErrorText(code: AiErrorCode): string {
  switch (code) {
    case AiErrorCode.NO_API_KEY:
      return '尚未配置 API Key，请先在 AI 设置中配置';
    case AiErrorCode.INVALID_CONFIG:
      return 'AI 服务配置无效，请检查 Base URL 与模型名称';
    case AiErrorCode.IMAGE_INVALID:
      return '无法读取该图片，请更换一张';
    case AiErrorCode.IMAGE_TOO_LARGE:
      return '图片过大，压缩后仍超过 2MB，请更换图片';
    case AiErrorCode.CAMERA_UNAVAILABLE:
      return '当前设备无法使用相机，请从相册选择照片';
    case AiErrorCode.NETWORK_ERROR:
      return '网络连接失败，请检查网络后重试';
    case AiErrorCode.TIMEOUT:
      return '识别请求超时（30 秒），请重试';
    case AiErrorCode.UNAUTHORIZED:
      return 'API Key 无效或与服务地域不匹配';
    case AiErrorCode.FORBIDDEN:
      return '没有模型访问权限，请检查服务配置';
    case AiErrorCode.RATE_LIMITED:
      return '请求过于频繁或模型容量已满，请稍后重试';
    case AiErrorCode.QUOTA_EXCEEDED:
      return '模型调用额度不足，请检查 AI 服务控制台';
    case AiErrorCode.SERVER_ERROR:
      return '模型服务暂时不可用，请稍后重试';
    case AiErrorCode.INVALID_RESPONSE:
      return 'AI 返回了无法解析的结果，请重试或手动输入';
    case AiErrorCode.CANCELLED:
      return '识别已取消';
    case AiErrorCode.SECURE_STORE_UNAVAILABLE:
      return '当前环境无法安全记住 API Key，本次会话内有效';
    default:
      return '发生未知错误，请重试';
  }
}

/** AiError：携带错误码的异常 */
export class AiError extends Error {
  code: AiErrorCode;

  constructor(code: AiErrorCode, detail?: string) {
    super(detail !== undefined && detail.length > 0 ? `${code}: ${detail}` : code);
    this.code = code;
  }
}

/**
 * 演示模式注入的固定模拟响应（PM 确认数据，仅用于开发测试，不发网络请求）。
 * foodBox 是示例图里**主体食物**（沙拉盘）的位置（0~1000 尺度），
 * 故意不包含右上角的米饭碗 —— 这样「只保留食物轮廓」的效果一眼可见：
 * 抠完的贴纸里只剩盘子，右上角是透明的。
 */
export const AI_DEMO_RESPONSE: string = '{"foodName":"演示食物（模拟识别）","estimatedTotalKcal":620,"proteinG":38,"carbsG":72,"fatG":19,"confidence":0.85,"notes":"本地演示数据，非真实AI识别结果。仅用于开发测试。","foodBox":{"x":100,"y":200,"width":680,"height":760}}';

/**
 * 宏量一致性容差：Atwater 回算值与总热量的最大相对偏差。
 * ±20% 取自 VLM 估算场景 —— 视觉模型对宏量的不确定度显著高于总热量，
 * 过紧会把大量本可用的结果误杀。
 *
 * 依据：参考 App 的实测数据 150×4+144×4+78×9=1878 为完全自洽样本；
 * 真实识别场景取 20% 容忍估算误差。
 */
export const AI_MACRO_TOLERANCE: number = 0.20;

/** 宏量单字段上限（克/份）—— 超过视为模型幻觉 */
export const AI_MACRO_MAX_G: number = 999;