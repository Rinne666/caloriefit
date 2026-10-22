/**
 * AI 识别服务编排：校验配置与图片 → 构建请求 → HTTPS 调用 → 解析校验。
 * 演示模式（无 Key 演示）直接返回注入的模拟响应，不发网络请求。
 */

import { AiConfig } from '../models/AiConfig';
import { AiImagePayload } from '../models/AiImagePayload';
import { AiRecognitionResult } from '../models/AiRecognitionResult';
import { AiPrompt } from './AiPrompt';
import { AiHttpClient } from './AiHttpClient';
import { AiResponseParser } from './AiResponseParser';
import { AiConfigRepository } from '../repositories/AiConfigRepository';
import { AiErrorCode, AiError, AI_DEMO_RESPONSE } from '../common/AiConstants';
import { hilog } from '@kit.PerformanceAnalysisKit';

interface imageUrlInner {
  url: string;
}

interface ChatTextPart {
  type: string;
  text: string;
}

interface ChatImagePart {
  type: string;
  image_url: imageUrlInner;
}

interface ChatResponseFormat {
  type: string;
}

interface ChatMessage {
  role: string;
  content: string | Array<ChatTextPart | ChatImagePart>;
}

interface ChatRequestBody {
  model: string;
  stream: boolean;
  enable_thinking: boolean;
  temperature: number;
  max_tokens: number;
  response_format: ChatResponseFormat;
  messages: Array<ChatMessage>;
}

export class AiRecognitionService {
  /**
   * 识别请求的 token 预算。
   *
   * 为什么不按「一个 JSON 几百 token」来定：现在的默认模型
   * （deepseek-v4.1-flash-1017）是**推理模型**，网关会在正式答案前先吐一段
   * reasoning_content。请求里的 `enable_thinking: false` **只有部分上游节点认**，
   * 认的那部分不推理，不认的那部分照推理 —— 实测同一张图：
   *   · 认 enable_thinking → reasoning 0 字，正文 136 token 就完事；
   *   · 不认              → reasoning 1700~6500 字，正文被截断成空。
   * 之前用 512 的预算，遇到不认的上游节点就会**整次识别拿不到正文**，
   * App 只能报「AI 返回了无法解析的结果」。
   * ��以预算按「推理可能吃掉的量」给：4096 覆盖了实测最长的 3829 token 推理。
   */
  private static readonly MAX_TOKENS: number = 4096;
  /**
   * 预算仍然不够时的重试额度（正文被截断 → 空 content）。
   * 只有这一种情况才重试：正常返回不会走到这里。
   */
  private static readonly RETRY_MAX_TOKENS: number = 8192;

  /** 构建请求体（图片 Base64 仅在此处进入内存字符串，不入日志） */
  private static buildRequestBody(config: AiConfig, imagePayload: AiImagePayload,
    maxTokens: number): string {
    const responseFormat: ChatResponseFormat = { type: 'json_object' };
    const textPart: ChatTextPart = { type: 'text', text: AiPrompt.userPrompt() };
    const urlInner: imageUrlInner = { url: imagePayload.base64DataUrl };
    const imagePart: ChatImagePart = { type: 'image_url', image_url: urlInner };
    const parts: Array<ChatTextPart | ChatImagePart> = [textPart, imagePart];
    const sysMsg: ChatMessage = { role: 'system', content: AiPrompt.systemPrompt() };
    const userMsg: ChatMessage = { role: 'user', content: parts };
    const messages: Array<ChatMessage> = [sysMsg, userMsg];
    const requestObj: ChatRequestBody = {
      model: config.modelName,
      stream: false,
      enable_thinking: false,
      temperature: 0.2,
      // V3：响应新增 proteinG/carbsG/fatG 三个字段，256 偏紧，
      // 中文 notes 又是高 token 消耗，提到 512 避免 JSON 被截断。
      // 推理模型还要在正文之前写 reasoning，所以最终按推理量给足（见上方常量）。
      max_tokens: maxTokens,
      response_format: responseFormat,
      messages: messages
    };
    return JSON.stringify(requestObj);
  }

  /** 演示模式：注入固定模拟响应（不发网络请求，仍走完整解析流程） */
  private static async recognizeWithDemo(): Promise<AiRecognitionResult> {
    await new Promise<void>((resolve: () => void) => setTimeout(resolve, 1200));
    return AiResponseParser.parseContent(AI_DEMO_RESPONSE);
  }

  static async recognize(imagePayload: AiImagePayload,
    config: AiConfig, apiKey: string): Promise<AiRecognitionResult> {
    if (AiConfigRepository.isDemoMode()) {
      return AiRecognitionService.recognizeWithDemo();
    }
    if (config.baseUrl.length === 0 || config.modelName.length === 0) {
      throw new AiError(AiErrorCode.INVALID_CONFIG);
    }
    if (apiKey.length === 0) {
      throw new AiError(AiErrorCode.NO_API_KEY);
    }
    const body = AiRecognitionService.buildRequestBody(config, imagePayload,
      AiRecognitionService.MAX_TOKENS);
    let responseText = await AiHttpClient.postChatCompletions(config.baseUrl, apiKey, body);
    let content = AiRecognitionService.extractContent(responseText);

    // 空正文 = 推理把 token 预算吃光、正文被整段截断（实测踩到过）。
    // 这种情况下加大预算重试一次，比直接报「无法解析」对用户有用。
    if (content.length === 0) {
      hilog.warn(0x0000, 'AiRecognition', 'empty content, retry with larger token budget');
      const retryBody = AiRecognitionService.buildRequestBody(config, imagePayload,
        AiRecognitionService.RETRY_MAX_TOKENS);
      responseText = await AiHttpClient.postChatCompletions(config.baseUrl, apiKey, retryBody);
      content = AiRecognitionService.extractContent(responseText);
    }
    if (content.length === 0) {
      throw new AiError(AiErrorCode.INVALID_RESPONSE, 'empty content');
    }
    return AiResponseParser.parseContent(content);
  }

  /**
   * 从 OpenAI 兼容响应里取出助手正文。
   * 结构不对、内容不是字符串、正文为空 —— 一律返回空串（由调用方决定怎么报）。
   */
  private static extractContent(responseText: string): string {
    let root: Record<string, Object>;
    try {
      root = JSON.parse(responseText) as Record<string, Object>;
    } catch (e) {
      return '';
    }
    const choices = root['choices'];
    if (!Array.isArray(choices) || choices.length === 0) {
      return '';
    }
    const first = choices[0] as Record<string, Object>;
    const message = first['message'] as Record<string, Object> | undefined;
    if (message === undefined || message === null) {
      return '';
    }
    const content = message['content'];
    if (typeof content !== 'string') {
      return '';
    }
    return content;
  }
}