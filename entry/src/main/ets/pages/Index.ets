/**
 * 唯一 @Entry 页面：初始化数据库、持有全局状态（日期/刷新版本号），
 * Navigation 容器内放三个 Tab，编辑页通过 NavPathStack 打开 NavDestination。
 *
 * 底 Tab 结构对齐 NutriScan 实测路由图：
 *   今日（热量记录 + 今日黑板，个人记录）
 *   2026-10-20：原「膳食」Tab 与今日下的「饮水/断食」子页已下线，
 *   底部收敛为 今日 / 进度 / 营养师 / 我的 四个 Tab。
 *   进度（今天/本周/近30天 + Readiness/NutriScore）
 *   2026-10-21：原「营养师」Tab 已下线（功能未实现，只是 ComingSoon 占位；
 *   服务端对话协议未知，保留一个点不动的入口对用户没有价值），
 *   底部收敛为 今日 / 进度 / 我的 三个 Tab。
 *   我的
 *
 * 2026-10-21：底栏**只保留图标按钮**，文字标签已去掉。
 *   文字没有消失，而是转成 `accessibilityText` —— 可见层不再显示，
 *   但读屏软件仍会念出「今日 / 进度 / 我的」。
 *   注意：`uitest dumpLayout` 取的是**渲染文本**，不会把 accessibilityText
 *   吐进 text 字段，所以自动化脚本按文字点底栏已失效，改用树里的可点击子项定位
 *   （见 tools/verify_all.py 的 tap_tab）。
 *
 * 路由覆盖原则：**任何一个入口都不能是死路**。
 * 凡是做了的路由指到实页，没做的指到 ComingSoon 占位，
 * 占位页上写清「本应功能 / 未实现原因 / 补上需要」。
 */

import { Database } from '../database/Database';
import { SettingsRepository } from '../repositories/SettingsRepository';
import { AppSettings } from '../models/AppSettings';
import { HomeTabs } from './HomeTabs';
import { ProgressPage } from './ProgressPage';
import { ProfilePage } from './ProfilePage';
import { FoodPage } from './FoodPage';
import { ActivityPage } from './ActivityPage';
import { FoodEditPage } from './FoodEditPage';
import { MealDetailPage } from './MealDetailPage';
import { ActivityEditPage } from './ActivityEditPage';
import { AiRecognitionPage } from './AiRecognitionPage';
import { AiSettingsPage } from './AiSettingsPage';
import { ComingSoonPage } from '../components/ComingSoonPage';
import { OnboardingPage } from './OnboardingPage';
import { OnboardingService } from '../services/OnboardingService';
import { PrivacyConsentService } from '../services/PrivacyConsentService';
import { PrivacyConsentPage } from './PrivacyConsentPage';
import { PrivacyPolicyPage } from './PrivacyPolicyPage';
import { PrivacyInventoryPage } from './PrivacyInventoryPage';
import { AccountPage } from './AccountPage';
import { common } from '@kit.AbilityKit';
import { color, fontSize, pageGradient } from '../common/DesignTokens';
import { todayKey } from '../common/DateUtils';

@Entry
@Component
struct Index {
  @Provide('navStack') navStack: NavPathStack = new NavPathStack();
  @StorageLink('selectedDate') @Watch('onDateChanged') selectedDate: string = todayKey();
  @State appReady: boolean = false;
  @State initError: string = '';
  /** 是否已走过引导。false 时首屏是 OnboardingPage，走完才进主界面 */
  @State onboarded: boolean = false;
  @State private selectedBottomTab: number = 0;
  @StorageLink('privacyConsentAccepted') privacyConsentAccepted: boolean = false;

  aboutToAppear(): void {
    this.initApp();
  }

  private async initApp(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        throw new Error('host context unavailable');
      }
      await Database.ensure(context);
      const settings: AppSettings = await SettingsRepository.getSettings();
      AppStorage.setOrCreate<AppSettings>('appSettings', settings);
      AppStorage.setOrCreate<number>('refreshTick', 0);
      this.privacyConsentAccepted = PrivacyConsentService.isAccepted(context as common.UIAbilityContext);
      AppStorage.setOrCreate<boolean>('privacyConsentAccepted', this.privacyConsentAccepted);
      this.onboarded = OnboardingService.isDone(context as common.UIAbilityContext);
      this.appReady = true;
    } catch (e) {
      const err = e as Error;
      this.initError = err.message;
    }
  }

  private onDateChanged(): void {
    // 切换日期后各页面通过自己的 @Watch 重新加载
  }

  private onPrivacyAccepted(): void {
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      this.onboarded = OnboardingService.isDone(context as common.UIAbilityContext);
    }
    this.selectedBottomTab = 0;
    this.privacyConsentAccepted = true;
  }

  /**
   * 路由分发。
   *
   * 每个分支都直接写组件调用，刻意不抽成嵌套 @Builder：
   * 实测过 @Builder 里再调 @Builder 传参这条链，在 navDestination 场景下
   * 不会渲染出内容（目标页只剩导航返回键，主体全白，且日志无任何异常）。
   * 直接调用这条路径是验证过能出图的。
   */
  @Builder
  PageMap(name: string, param: Object) {
    if (name === 'FoodEdit') {
      FoodEditPage()
    } else if (name === 'ActivityEdit') {
      ActivityEditPage()
    } else if (name === 'MealDetail') {
      // 餐食详情：根节点是 NavDestination，Navigation 才有东西可挂载
      MealDetailPage()
    } else if (name === 'AiRecognition') {
      AiRecognitionPage()
    } else if (name === 'AiSettings') {
      AiSettingsPage()
    } else if (name === 'PrivacyPolicy') {
      PrivacyPolicyPage()
    } else if (name === 'PrivacyInventory') {
      /**
       * 个人信息保护「双清单」。根节点是 NavDestination，Navigation 才有对象可挂载。
       */
      PrivacyInventoryPage()
    } else if (name === 'Account') {
      /**
       * 华为账号登录。根节点是 NavDestination，Navigation 才有对象可挂载。
       */
      AccountPage()
    } else if (name === 'FoodLog') {
      /**
       * 全部餐食：从底 Tab 收进二级路由，入口在「我的 → 全部餐食」。
       *
       * 必须包一层 NavDestination —— FoodPage 原本是 TabContent，
       * 根节点是 Scroll 不是 NavDestination。直接放进路由分支的话，
       * Navigation 没有可挂载的对象，结果是「路由推得进去、返回键也出现、
       * 内容全白且日志无异常」。这和 ComingSoon 当初踩的是同一个坑。
       * 页面自带标题栏，所以这里 hideTitleBar(true) 不让 Navigation 再加一条。
       */
      NavDestination() {
        FoodPage()
      }
      .hideTitleBar(true)
    } else if (name === 'ActivityLog') {
      NavDestination() {
        ActivityPage()
      }
      .hideTitleBar(true)
    }
  }

  private tabTint(index: number): ResourceColor {
    return this.selectedBottomTab === index ? color.text : color.textHint;
  }

  /** NutriScan 底栏使用单色线框符号；用系统 SymbolGlyph 避免彩色 emoji。 */
  @Builder
  TabGlyph(index: number) {
    if (index === 0) {
      if (this.selectedBottomTab === index) {
        SymbolGlyph($r('sys.symbol.house_fill'))
          .fontSize(24)
          .fontColor([this.tabTint(index)])
      } else {
        SymbolGlyph($r('sys.symbol.house'))
          .fontSize(24)
          .fontColor([this.tabTint(index)])
      }
    } else if (index === 1) {
      if (this.selectedBottomTab === index) {
        SymbolGlyph($r('sys.symbol.calendar_fill'))
          .fontSize(24)
          .fontColor([this.tabTint(index)])
      } else {
        SymbolGlyph($r('sys.symbol.calendar'))
          .fontSize(24)
          .fontColor([this.tabTint(index)])
      }
    } else if (index === 2) {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(21)
          .height(21)
          .fill(Color.Transparent)
          .stroke(this.tabTint(index))
          .strokeWidth(2)
        Circle()
          .width(3)
          .height(3)
          .fill(this.tabTint(index))
          .offset({ x: -4, y: -4 })
        Circle()
          .width(3)
          .height(3)
          .fill(this.tabTint(index))
          .offset({ x: 3, y: -3 })
        Circle()
          .width(3)
          .height(3)
          .fill(this.tabTint(index))
          .offset({ x: -2, y: 4 })
        Circle()
          .width(9)
          .height(9)
          .fill(color.surface)
          .offset({ x: 8, y: -8 })
      }
      .width(26)
      .height(26)
    } else {
      SymbolGlyph($r('sys.symbol.person'))
        .fontSize(24)
        .fontColor([this.tabTint(index)])
    }
  }

  /**
   * 底栏项：**只保留图标按钮**。
   *
   * 原来图标下面有一行文字标签（今日 / 进度 / 营养师 / 我的），
   * 按产品要求已从可见层去掉 —— 文字改挂到 `accessibilityText`，
   * 读屏软件仍能念出名字，不至于变成「三个 anonymous 按钮」。
   */
  @Builder
  TabItem(label: string, index: number) {
    Column() {
      this.TabGlyph(index)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(color.surface)
    .accessibilityText(label)
  }

  build() {
    Navigation(this.navStack) {
      if (!this.appReady) {
        Column({ space: 12 }) {
          Text(this.initError.length > 0 ? `初始化失败：${this.initError}` : '加载中…')
            .fontSize(fontSize.body)
            .fontColor(color.textSecondary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (!this.privacyConsentAccepted) {
        PrivacyConsentPage({
          onAccepted: () => this.onPrivacyAccepted()
        })
      } else if (!this.onboarded) {
        // 首启引导：目标 / 活动量 / 通知 / 补剂 / 生活方式，
        // 结果真的写进体征档案，直接影响 BMR/TDEE 推导
        OnboardingPage({
          onDone: () => {
            this.onboarded = true;
          }
        })
      } else {
        Tabs({ barPosition: BarPosition.End }) {
            TabContent() {
              HomeTabs()
            }
            .tabBar(this.TabItem('今日', 0))

            // 2026-10-20：原「膳食」Tab 已下线（产品决策：聚焦热量记录 + 今日黑板），
            // 底部由 5 个 Tab 收敛为 4 个，下面各 Tab 的索引依次前移一位。
            TabContent() {
              ProgressPage()
            }
            .tabBar(this.TabItem('进度', 1))

            // 2026-10-21：原「营养师」Tab 已下线（功能未实现，只是 ComingSoon 占位）。
            // 索引再次前移，「我的」由 3 变成 2。
            TabContent() {
              ProfilePage()
            }
            .tabBar(this.TabItem('我的', 2))
          }
          // 只剩图标后，底栏高度按图标高度收窄（原来 72 是「图标 + 文字」两行）。
          .barHeight(52)
          .onChange((index: number) => {
            this.selectedBottomTab = index;
          })
          .width('100%')
          .height('100%')
          .backgroundColor(color.bg)
          .linearGradient(pageGradient())
      }
    }
    .navDestination(this.PageMap)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
  }
}
