/**
 * 隐私政策正文。
 *
 * 运营主体与第三方信息统一从 common/Compliance.ets 取，那里是唯一改入口。
 * 占位项是否尚未补齐由 Compliance.isDraft 判定，页面上会显式提示，
 * 避免占位符原样进入正式发布包。
 */

import { color, fontSize, space } from '../common/DesignTokens';
import { Compliance } from '../common/Compliance';

@Component
export struct PrivacyPolicyContent {
  @Builder
  Section(title: string, body: string) {
    Column({ space: space.xs }) {
      Text(title)
        .fontSize(fontSize.sectionTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(color.text)
        .width('100%')
      Text(body)
        .fontSize(fontSize.secondary)
        .fontColor(color.textSecondary)
        .lineHeight(23)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  build() {
    Column({ space: space.lg }) {
      Text(Compliance.isDraft ? 'CalorieFit 隐私政策（开发预览草案）' : 'CalorieFit 隐私政策')
        .fontSize(fontSize.pageTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(color.text)
        .width('100%')

      Text(`版本：${Compliance.POLICY_VERSION}。`)
        .fontSize(fontSize.caption)
        .fontColor(color.food)
        .width('100%')

      if (Compliance.isDraft) {
        Text(Compliance.pendingSummary())
          .fontSize(fontSize.caption)
          .fontColor(color.food)
          .lineHeight(18)
          .width('100%')
      }

      this.Section('一、运营主体与联系渠道',
        `个人信息处理者：${Compliance.OPERATOR_NAME}。隐私问题与权利请求联系方式：${Compliance.OPERATOR_CONTACT}。`)

      this.Section('二、处理的信息及用途',
        '当你使用个性化记录时，应用会在本机保存你主动填写的年龄、性别、身高、体重、活动水平和目标，用于估算热量预算；保存你主动记录的食物、热量与营养素、运动、饮水和断食数据，用于展示个人记录与统计。你主动开启计步采集后，应用会从设备计步传感器读取当日累计步数并保存在本机，用于展示步数与目标进度。AI 设置中的服务地址、模型名和偏好用于发起你主动请求的识别。主题等外观偏好用于记住界面设置。应用不要求注册账号。逐项清单见「我的 → 已收集个人信息清单」。')

      this.Section('三、健康信息的特别说明',
        '身体档案、饮食与运动记录可能属于敏感个人信息。处理这些信息是个性化热量估算和健康记录功能所需；目前数据保存在设备本地数据库。你可单独决定是否同意处理此类信息；撤回同意时，可在“我的”中选择删除数据并撤回同意。' +
        '本应用提供的热量与营养素为估算结果，仅供一般饮食记录参考，不用于诊断或治疗，也不构成医疗建议。' +
        '如你有特殊健康状况、正在服药或准备调整饮食方案，请先咨询合格的医疗专业人员或营养师，并结合自身情况判断。')

      this.Section('四、保存位置与期限',
        '个人档案、目标和记录保存在本机应用数据库；AI 配置保存在本机应用配置中。API Key 默认仅在本次运行期间保留；启用“安全记住”后使用系统安全存储。当前版本关闭应用数据备份。数据保留至你在应用内删除或卸载应用。卸载后系统对数据的清理行为以设备系统规则为准。')

      this.Section('五、AI 食物识别与第三方接收方',
        'AI 识别是可选功能。只有你在识别页面选择图片并在上传确认窗点击“同意并识别”后，应用才会把该图片缩放并压缩后，通过 HTTPS 发送到你在设置页配置的 AI 服务地址；请求同时携带你配置的 API Key。' +
        '该地址当前限定为阿里云百炼（DashScope）及其子域名；开发者没有自有业务服务器中转，也与该服务方不存在合作、代理或转售关系，费用、账号与服务协议均由你与该服务方之间直接约定。' +
        `接收方的最终法定主体、联系方式、数据留存期限及隐私政策链接：${Compliance.AI_RECIPIENT_INFO}` +
        '拒绝本次上传仍可手动记录食物。演示模式只返回本地模拟结果，不发送网络请求。逐项清单见「我的 → 第三方共享个人信息清单」。')

      this.Section('六、系统权限与照片',
        '模块声明两项权限：INTERNET（用于在你主动请求时访问你配置的 AI 服务地址）和 ACTIVITY_MOTION（用于读取计步传感器，自动统计你当日走的步数）。相册选图和拍照通过系统选择器发起，不声明相册或相机权限；只有你主动选择或拍摄的单张图片会进入识别流程。应用不会在后台扫描相册或自动拍照。计步权限需要你在运动页主动点击开启后由系统弹窗授权，你不授权时步数可手动填写，其余功能不受影响。')

      this.Section('七、你的权利',
        '你可以在应用中查看和修改个人档案、目标及记录，也可以通过“我的 → 删除数据并撤回同意”清除本地健康记录、AI 配置和 API Key。AI 服务收到的数据如何查询或删除，需按该服务方的规则另行办理。你也可以通过本政策第一节的渠道联系我们。')

      this.Section('八、未成年人',
        `应用的目标用户范围及未成年人使用规则：${Compliance.MINOR_POLICY}`)

      this.Section('九、政策更新',
        '当处理目的、信息范围、接收方或权利渠道发生实质变化时，运营主体应更新本政策版本，并在相关处理开始前重新告知和征求所需同意。')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(space.lg)
  }
}
