/**
 * 华为账号会话模型。
 *
 * 本应用的账号体系是**纯本地**的：登录成功后只在本机保存 Account Kit
 * 返回的 UnionID / OpenID 作为会话标识，不建服务器、不做数据同步。
 * 依据是 Account Kit 的 `HuaweiIDCredential` 本身就带 `unionID`/`openID`
 * 两个必选字段，一键登录拿到授权码后**无需**再拿授权码去服务端换 token。
 *
 * 这也是本应用能维持「零自建后端」定位的前提：一旦要跨设备同步或服务端
 * 鉴权，就必须补一个能换 access token 的后端。
 */

/** 一次登录会话 */
export class AccountSession {
  /** UnionID：同一开发者下跨应用唯一。用它做本应用的账号主键。 */
  unionId: string;
  /** OpenID：单个应用内唯一。 */
  openId: string;
  /** 登录时刻（毫秒） */
  loginAt: number;

  constructor(unionId: string, openId: string, loginAt: number) {
    this.unionId = unionId;
    this.openId = openId;
    this.loginAt = loginAt;
  }

  /**
   * 展示用的脱敏标识。
   *
   * UnionID 是账号标识符，属个人信息。界面上不整串显示：
   * 只露头尾各 4 位，中间用省略号。
   */
  maskedId(): string {
    const id = this.unionId;
    if (id.length <= 10) {
      return id.length > 0 ? `${id.charAt(0)}****` : '';
    }
    return `${id.substring(0, 4)}****${id.substring(id.length - 4)}`;
  }
}
