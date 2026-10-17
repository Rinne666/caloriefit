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
import { AiErrorCode, AiError, AI_DEMO_RESPONSES } from '../common/AiConstants';

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
  /** 构建请求体（图片 Base64 仅在此处进入内存字符串，不入日志） */
  private static buildRequestBody(config: AiConfig, imagePayload: AiImagePayload): string {
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
      max_tokens: 256,
      response_format: responseFormat,
      messages: messages
    };
    return JSON.stringify(requestObj);
  }

  /** 演示模式：随机注入一条模拟响应，用于无 Key 的端到端链路验证 */
  private static async recognizeWithDemo(): Promise<AiRecognitionResult> {
    await new Promise<void>((resolve: () => void) => setTimeout(resolve, 1200));
    const idx = Math.floor(Math.random() * AI_DEMO_RESPONSES.length);
    return AiResponseParser.parseContent(AI_DEMO_RESPONSES[idx]);
  }

  static async recognize(imagePayload: AiImagePayload,
    config: AiConfig, apiKey: string): Promise<AiRecognitionResult> {
    if (await AiConfigRepository.isDemoMode()) {
      return AiRecognitionService.recognizeWithDemo();
    }
    if (config.baseUrl.length === 0 || config.modelName.length === 0) {
      throw new AiError(AiErrorCode.INVALID_CONFIG);
    }
    if (apiKey.length === 0) {
      throw new AiError(AiErrorCode.NO_API_KEY);
    }
    const body = AiRecognitionService.buildRequestBody(config, imagePayload);
    const responseText = await AiHttpClient.postChatCompletions(config.baseUrl, apiKey, body);

    let root: Record<string, Object>;
    try {
      root = JSON.parse(responseText) as Record<string, Object>;
    } catch (e) {
      throw new AiError(AiErrorCode.INVALID_RESPONSE, 'body not json');
    }
    const choices = root['choices'];
    if (!Array.isArray(choices) || choices.length === 0) {
      throw new AiError(AiErrorCode.INVALID_RESPONSE, 'no choices');
    }
    const first = choices[0] as Record<string, Object>;
    const message = first['message'] as Record<string, Object> | undefined;
    if (message === undefined || message === null) {
      throw new AiError(AiErrorCode.INVALID_RESPONSE, 'no message');
    }
    const content = message['content'];
    if (typeof content !== 'string') {
      throw new AiError(AiErrorCode.INVALID_RESPONSE, 'content type');
    }
    return AiResponseParser.parseContent(content);
  }
}