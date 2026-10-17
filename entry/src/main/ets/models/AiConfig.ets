/**
 * AI 配置（不含 API Key）
 */

export class AiConfig {
  baseUrl: string;
  modelName: string;
  rememberApiKey: boolean;

  constructor(baseUrl: string, modelName: string, rememberApiKey: boolean) {
    this.baseUrl = baseUrl;
    this.modelName = modelName;
    this.rememberApiKey = rememberApiKey;
  }
}