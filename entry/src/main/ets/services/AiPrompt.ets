/**
 * System Prompt（与 PM 第1步确认版本一致，独立文件便于版本管理）
 */

import { AI_SYSTEM_PROMPT } from '../common/AiConstants';

export class AiPrompt {
  static systemPrompt(): string {
    return AI_SYSTEM_PROMPT;
  }

  static userPrompt(): string {
    return '请识别这张照片中的食物，估算整份热量，严格按System要求返回JSON。';
  }
}