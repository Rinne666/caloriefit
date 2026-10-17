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
  static readonly BASE_URL = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
  static readonly MODEL_NAME = 'qwen3-vl-plus';
  static readonly REMEMBER_KEY = false;
  static readonly DEMO_MODE = false;
}

export const AI_SECRET_ALIAS = 'caloriefit_dashscope_key';

/** 图片约束（客户端策略） */
export class AiImageLimits {
  static readonly MAX_LONG_SIDE = 1280;
  static readonly MAX_BYTES = 2 * 1024 * 1024;
  static readonly INITIAL_QUALITY = 85;
  static readonly MIN_QUALITY = 30;
}

export const AI_REQUEST_TIMEOUT_MS = 30000;
export const AI_LOW_CONFIDENCE = 0.5;

export const AI_SYSTEM_PROMPT: string = `你是CalorieFit的食物视觉识别与热量估算助手。识别图片中可见的食物，估算整份可食用部分的总热量kcal。考虑食物种类、份量、烹饪方式、酱料和油脂，不要把餐具计算进去。不能从照片准确确定重量时，应作保守的区间判断并在备注中说明。不得把估算说成实测值。如果不是食物图片，返回foodName为无法识别、estimatedTotalKcal为null、confidence为0。只返回一个合法JSON对象，不输出Markdown。字段必须为foodName字符串、estimatedTotalKcal整数或null、confidence为0到1之间的数字、notes字符串。多种食物在foodName中合并命名，热量返回整盘合计。`;

export const AI_USER_PROMPT: string = '请识别这张照片中的食物，估算整份热量，严格按System要求返回JSON。';

export enum AiErrorCode {
  NO_API_KEY = 'NO_API_KEY',
  INVALID_CONFIG = 'INVALID_CONFIG',
  IMAGE_INVALID = 'IMAGE_INVALID',
  IMAGE_TOO_LARGE = 'IMAGE_TOO_LARGE',
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
    case AiErrorCode.NETWORK_ERROR:
      return '网络连接失败，请检查网络后重试';
    case AiErrorCode.TIMEOUT:
      return '识别请求超时（30 秒），请重试';
    case AiErrorCode.UNAUTHORIZED:
      return 'API Key 无效或与服务地域不匹配';
    case AiErrorCode.FORBIDDEN:
      return '没有模型访问权限，请检查服务配置';
    case AiErrorCode.RATE_LIMITED:
      return '请求过于频繁，请稍后重试';
    case AiErrorCode.QUOTA_EXCEEDED:
      return '模型调用额度不足，请检查百炼控制台';
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

/** 演示模式注入的模拟响应（用于无 Key 端到端验证，不发网络请求） */
export const AI_DEMO_RESPONSES: string[] = [
  '{"foodName":"米饭配鸡肉和蔬菜","estimatedTotalKcal":620,"confidence":0.72,"notes":"估计为一人份套餐，含米饭、鸡肉、蔬菜及少量烹饪油；实际重量和酱料用量不确定。"}',
  '{"foodName":"牛肉面一碗","estimatedTotalKcal":540,"confidence":0.66,"notes":"按一碗普通大小的牛肉面估算，含面条、牛肉与汤底油脂；份量假设不确定。"}',
  '{"foodName":"苹果一个","estimatedTotalKcal":95,"confidence":0.85,"notes":"按中等大小苹果估算，约 180g；品种差异会带来小幅误差。"}'
];