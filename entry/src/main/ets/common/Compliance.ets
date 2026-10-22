/**
 * 发布合规配置 —— 运营主体信息与隐私政策版本的唯一改入口。
 *
 * 为什么集中在这里：
 *   这些字段是上架前必须由运营主体提供的**真实信息**（应用资质审核要求
 *   「APP 应提供真实完整有效的开发者或运营者信息」，隐私政策必须包含
 *   有效的用户隐私问题反馈渠道）。原先它们散落在隐私政策正文里，
 *   改一处漏一处，极易把占位符原样带进正式发布包。
 *
 * 上架前的动作：
 *   1. 逐项把下面 OPERATOR_* / AI_RECIPIENT_INFO / MINOR_POLICY 换成真实值；
 *   2. 把 POLICY_VERSION 换成正式版本号（内容变更时递增，已同意旧版本的用户
 *      需要重新征求同意 —— PrivacyConsentService 按版本号比对）；
 *   3. 清空 PENDING_FIELDS。应用会据此在隐私政策页显示"待补齐"提示，
 *      全部填好后提示自动消失，避免占位符悄悄出厂。
 */

export class Compliance {
  /** 个人信息处理者（运营主体）法定全称 */
  static readonly OPERATOR_NAME: string = '【待填写运营主体法定全称】';

  /** 隐私问题与权利请求联系方式 */
  static readonly OPERATOR_CONTACT: string = '【待填写客服邮箱或电话】';

  /** AI 接收方（模型服务商）的法定主体、联系方式、数据留存期限与隐私政策链接 */
  static readonly AI_RECIPIENT_INFO: string = '【发布前待核对并补充】';

  /** 目标用户范围与未成年人使用规则 */
  static readonly MINOR_POLICY: string =
    '【发布前由运营主体确认，并按确认范围实现年龄/监护人同意流程】';

  /**
   * 隐私政策版本号。
   * 正式发布前应从 draft-* 改为正式版本；政策内容实质变更时递增，
   * 会让已同意旧版本的用户重新走首启同意流程。
   *
   * 2026-10-21：AI 识别默认服务方由阿里云百炼改为 OpenCSG（opencsg.com），
   * 第三方接收方发生实质变化，故递增版本号。
   */
  static readonly POLICY_VERSION: string = 'draft-2026-10-21-1';

  /** 尚未填写的字段名。全部补齐后清空，本应用即视为可发布。 */
  static readonly PENDING_FIELDS: string[] = [
    '运营主体法定全称',
    '隐私问题与权利请求联系方式',
    'AI 接收方信息',
    '未成年人使用规则'
  ];

  /** 是否仍是待补齐状态 */
  static get isDraft(): boolean {
    return Compliance.PENDING_FIELDS.length > 0;
  }

  /** 待补齐项的展示文案（用于隐私政策页顶部提示） */
  static pendingSummary(): string {
    if (!Compliance.isDraft) {
      return '';
    }
    return '正式发布前须由运营主体补齐：' + Compliance.PENDING_FIELDS.join('、') + '。';
  }
}
