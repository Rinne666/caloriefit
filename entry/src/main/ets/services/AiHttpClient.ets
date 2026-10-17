/**
 * Network Kit HTTPS 客户端：OpenAI 兼容 chat/completions 请求，
 * 30s 超时，状态码映射为 AiErrorCode，请求完成后释放资源。
 */

import { http } from '@kit.NetworkKit';
import { AiErrorCode, AiError, AI_REQUEST_TIMEOUT_MS } from '../common/AiConstants';

export class AiHttpClient {
  static async postChatCompletions(baseUrl: string, apiKey: string, body: string): Promise<string> {
    let endpoint = baseUrl;
    if (endpoint.endsWith('/')) {
      endpoint = endpoint.slice(0, endpoint.length - 1);
    }
    if (endpoint.endsWith('/chat/completions')) {
      // 用户直接粘贴完整 Endpoint 时规范化
    } else {
      endpoint = `${endpoint}/chat/completions`;
    }

    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(endpoint, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${apiKey}`
        } as Record<string, string>,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: AI_REQUEST_TIMEOUT_MS,
        readTimeout: AI_REQUEST_TIMEOUT_MS
      });
      const status = response.responseCode;
      const text = response.result as string;
      if (status >= 200 && status < 300) {
        return text;
      }
      if (status === 401) {
        throw new AiError(AiErrorCode.UNAUTHORIZED);
      }
      if (status === 403) {
        throw new AiError(AiErrorCode.FORBIDDEN);
      }
      if (status === 429) {
        throw new AiError(AiErrorCode.RATE_LIMITED);
      }
      if (status >= 500) {
        throw new AiError(AiErrorCode.SERVER_ERROR);
      }
      // 百炼部分额度类错误以 4xx 返回，结合响应体错误码识别
      if (text.indexOf('Arrearage') >= 0 || text.indexOf('quota') >= 0 ||
        text.indexOf('AllocationQuota') >= 0) {
        throw new AiError(AiErrorCode.QUOTA_EXCEEDED);
      }
      throw new AiError(AiErrorCode.INVALID_RESPONSE, `http ${status}`);
    } catch (e) {
      if (e instanceof AiError) {
        throw e;
      }
      const err = e as BusinessErrorLike;
      const code = err.code ?? 0;
      // 2300025 客户端超时；2300006 DNS；2300007 连接失败
      if (code === 2300025) {
        throw new AiError(AiErrorCode.TIMEOUT);
      }
      if (code === 2300006 || code === 2300007 || code === 2300028) {
        throw new AiError(AiErrorCode.NETWORK_ERROR);
      }
      throw new AiError(AiErrorCode.NETWORK_ERROR);
    } finally {
      httpRequest.destroy();
    }
  }
}

interface BusinessErrorLike {
  code?: number;
  message?: string;
}