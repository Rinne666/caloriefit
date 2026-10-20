/**
 * 个人信息保护「双清单」正文。
 *
 * mode = 'collected' 渲染「已收集个人信息清单」
 * mode = 'shared'    渲染「第三方共享个人信息清单」
 *
 * 内容来自 models/PrivacyInventory.ets，与应用实际数据处理行为一一对应。
 */

import { color, fontSize, space, radius } from '../common/DesignTokens';
import {
  CollectedInfoItem, SharedInfoItem, ThirdPartySdkItem,
  COLLECTED_INFO_LIST, SHARED_INFO_LIST, THIRD_PARTY_SDKS,
  LOCAL_ONLY_FIELDS, NOT_COLLECTED_FIELDS
} from '../models/PrivacyInventory';

@Component
export struct PrivacyInventoryContent {
  /** 'collected' | 'shared' */
  @Prop mode: string = 'collected';

  @Builder
  SectionTitle(title: string, hint: string) {
    Column({ space: space.xxs }) {
      Text(title)
        .fontSize(fontSize.sectionTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(color.text)
        .width('100%')
      Text(hint)
        .fontSize(fontSize.caption)
        .fontColor(color.textHint)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  Field(label: string, value: string) {
    Row({ space: space.sm }) {
      Text(label)
        .fontSize(fontSize.caption)
        .fontColor(color.textHint)
        .width(64)
      Text(value)
        .fontSize(fontSize.secondary)
        .fontColor(color.textSecondary)
        .layoutWeight(1)
        .lineHeight(20)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
  }

  @Builder
  CollectedRow(item: CollectedInfoItem) {
    Column({ space: space.xs }) {
      Row({ space: space.xs }) {
        Text(item.name)
          .fontSize(fontSize.secondary)
          .fontWeight(FontWeight.Medium)
          .fontColor(color.text)
          .layoutWeight(1)
        if (item.sensitive) {
          Text('敏感个人信息')
            .fontSize(fontSize.caption)
            .fontColor(color.food)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor(color.foodLight)
            .borderRadius(radius.small)
        }
      }
      .width('100%')

      this.Field('使用目的', item.purpose)
      this.Field('使用场景', item.scenario)
      this.Field('存储位置', item.storage)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: space.sm, bottom: space.sm })
    .border({ width: { bottom: 1 }, color: color.divider })
  }

  @Builder
  SharedRow(item: SharedInfoItem) {
    Column({ space: space.xs }) {
      Text(item.name)
        .fontSize(fontSize.secondary)
        .fontWeight(FontWeight.Medium)
        .fontColor(color.text)
        .width('100%')
      this.Field('接收方', item.recipient)
      this.Field('使用目的', item.purpose)
      this.Field('使用场景', item.scenario)
      this.Field('共享方式', item.method)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: space.sm, bottom: space.sm })
    .border({ width: { bottom: 1 }, color: color.divider })
  }

  @Builder
  SdkRow(item: ThirdPartySdkItem) {
    Column({ space: space.xs }) {
      Row({ space: space.xs }) {
        Text(item.name)
          .fontSize(fontSize.secondary)
          .fontWeight(FontWeight.Medium)
          .fontColor(color.text)
          .layoutWeight(1)
        Text(item.transmits ? '涉及数据传输' : '不涉及个人信息')
          .fontSize(fontSize.caption)
          .fontColor(item.transmits ? color.danger : color.macroOk)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(item.transmits ? color.dangerLight : color.surfaceMuted)
          .borderRadius(radius.small)
      }
      .width('100%')
      this.Field('用途', item.purpose)
      this.Field('说明', item.note)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: space.sm, bottom: space.sm })
    .border({ width: { bottom: 1 }, color: color.divider })
  }

  @Builder
  BulletList(title: string, items: string[]) {
    Column({ space: space.xs }) {
      Text(title)
        .fontSize(fontSize.secondary)
        .fontWeight(FontWeight.Medium)
        .fontColor(color.text)
        .width('100%')
      ForEach(items, (line: string) => {
        Text('· ' + line)
          .fontSize(fontSize.caption)
          .fontColor(color.textSecondary)
          .lineHeight(19)
          .width('100%')
      }, (line: string) => line)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  build() {
    Column({ space: space.lg }) {
      if (this.mode === 'shared') {
        Text('第三方共享个人信息清单')
          .fontSize(fontSize.pageTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(color.text)
          .width('100%')

        Text('下列信息只在你主动发起 AI 识别并确认上传时离开设备。除此之外，应用不与任何第三方共享个人信息。')
          .fontSize(fontSize.secondary)
          .fontColor(color.textSecondary)
          .lineHeight(22)
          .width('100%')

        this.SectionTitle('一、共享给第三方的信息',
          '接收方由你在 AI 设置中自行指定，当前限定为阿里云百炼（DashScope）及其子域名。')
        ForEach(SHARED_INFO_LIST, (item: SharedInfoItem) => {
          this.SharedRow(item)
        }, (item: SharedInfoItem) => item.name)

        this.SectionTitle('二、仅保存在本机、不与第三方共享的信息', '下列信息全部只存放在本机，卸载应用即随之删除。')
        this.BulletList('', LOCAL_ONLY_FIELDS)

        this.SectionTitle('三、第三方 SDK 清单', '应用内集成的全部第三方组件，逐个核实过源码。')
        ForEach(THIRD_PARTY_SDKS, (item: ThirdPartySdkItem) => {
          this.SdkRow(item)
        }, (item: ThirdPartySdkItem) => item.name)
      } else {
        Text('已收集个人信息清单')
          .fontSize(fontSize.pageTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(color.text)
          .width('100%')

        Text('本应用不设自有账号体系，不登录也可完整使用全部记录功能。除下表所列信息外，不收集其他个人信息；所有信息都只保存在本机。')
          .fontSize(fontSize.secondary)
          .fontColor(color.textSecondary)
          .lineHeight(22)
          .width('100%')

        this.SectionTitle('一、收集的信息及用途',
          '每项均标注使用目的、使用场景、存储位置，以及是否属于敏感个人信息。')
        ForEach(COLLECTED_INFO_LIST, (item: CollectedInfoItem) => {
          this.CollectedRow(item)
        }, (item: CollectedInfoItem) => item.name)

        this.SectionTitle('二、明确不收集的信息', '列出是为了让你能核对，而不是承诺。')
        this.BulletList('', NOT_COLLECTED_FIELDS)

        this.SectionTitle('三、存储与删除', '数据保留至你在应用内删除或卸载应用；AI 服务收到的数据按该服务方规则办理。')
        this.BulletList('', [
          '身体档案、饮食、运动与步数记录保存在应用本地数据库',
          'AI 配置、外观偏好、同意记录与引导草稿保存在应用本地配置',
          'API Key 默认仅在本次运行期间保留，开启“安全记住”后存入系统安全存储',
          '当前版本关闭应用数据备份；可通过“我的 → 删除数据并撤回同意”一次性清除'
        ])
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(space.lg)
  }
}
