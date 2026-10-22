/**
 * AI Base URL 白名单策略（可单测的纯逻辑）。
 *
 * ## 为什么不能自己 split 字符串
 * 原来的校验是 `url.replace('https://','').split('/')[0].split(':')[0]`。
 * 这套字符串切分会被 **userinfo** 骗过：
 *
 *   `https://opencsg.com:443@example.invalid/v1`
 *     → 字符串切分得到 host = `opencsg.com`  → 通过白名单 ✅（错误）
 *     → 标准 URL 解析得到 hostname = `example.invalid` → 实际发到别处
 *
 * 只要在已声明域名后面加一段 `:xxx@`，请求就能发到任意地址，
 * 绕过「只连隐私政策已披露的服务方」这条产品与合规约束。
 *
 * ## 现在的规则
 *   1. 协议必须是 https；
 *   2. **不许带 userinfo**（`user:pass@host`）—— 主机名会骗过人，一律拒绝；
 *   3. hostname 必须是白名单域名本身或其子域。
 *
 * 用系统的 `url.URL`（`@kit.ArkTS`）做标准解析，不自己实现 URL 语义。
 */

import { url } from '@kit.ArkTS';

/**
 * 已声明的服务方域名。
 *
 * opencsg.com —— OpenCSG 模型网关（默认，OpenAI 兼容）
 * dashscope.aliyuncs.com / *.maas.aliyuncs.com —— 阿里云百炼（备用）
 * 放开白名单等于把 App 变成任意地址的通用客户端，属于产品与合规决策，不在此处擅自放开。
 */
export const ALLOWED_BASE_URL_HOSTS: string[] = [
  'opencsg.com',
  'dashscope.aliyuncs.com',
  'maas.aliyuncs.com'
];

export class AiUrlPolicy {
  /** 白名单域名（对外只读拷贝，避免调用方误改） */
  static allowedHosts(): string[] {
    return ALLOWED_BASE_URL_HOSTS.slice();
  }

  /**
   * 这个 Base URL 是不是允许连的服务方地址。
   *
   * @param input 用户填写的 Base URL
   */
  static isAllowedBaseUrl(input: string): boolean {
    const trimmed = input.trim();
    if (trimmed.length === 0) {
      return false;
    }
    // 先用字符串把明显不是 https 的挡掉，避免把 http:// 也丢给解析器
    if (!trimmed.toLowerCase().startsWith('https://')) {
      return false;
    }
    let parsed: url.URL;
    try {
      // 非法 URL 字符串会抛 BusinessError 10200002
      parsed = new url.URL(trimmed);
    } catch (e) {
      return false;
    }
    if (parsed.protocol !== 'https:') {
      return false;
    }
    // userinfo 存在 ⇒ 用户以为连的是 host，实际连的是 @ 后面那个 —— 直接拒
    if (parsed.username.length > 0 || parsed.password.length > 0) {
      return false;
    }
    const host = parsed.hostname.toLowerCase();
    if (host.length === 0) {
      return false;
    }
    return AiUrlPolicy.allowedHosts().some((allowed: string) => {
      return host === allowed || host.endsWith(`.${allowed}`);
    });
  }
}
