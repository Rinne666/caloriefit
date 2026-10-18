/**
 * 唯一 @Entry 页面：初始化数据库、持有全局状态（日期/刷新版本号），
 * Navigation 容器内放五个 Tab，编辑页通过 NavPathStack 打开 NavDestination。
 *
 * 底 Tab 结构对齐 NutriScan 实测路由图：
 *   今日（内含 综合/社群/饮水/断食 四个子页）
 *   膳食（膳食计划/购物清单/补剂/生活方式）
 *   进度（今天/本周/近30天 + Readiness/NutriScore）
 *   营养师（AI 对话，未实现跳转）
 *   我的
 *
 * 路由覆盖原则：**任何一个入口都不能是死路**。
 * 凡是做了的路由指到实页，没做的指到 ComingSoon 占位，
 * 占位页上写清「本应功能 / 未实现原因 / 补上需要」。
 */

import { Database } from '../database/Database';
import { SettingsRepository } from '../repositories/SettingsRepository';
import { AppSettings } from '../models/AppSettings';
import { HomeTabs } from './HomeTabs';
import { DietPlanPage } from './DietPlanPage';
import { ProgressPage } from './ProgressPage';
import { NutriBitesPage } from './NutriBitesPage';
import { ProfilePage } from './ProfilePage';
import { FoodPage } from './FoodPage';
import { ActivityPage } from './ActivityPage';
import { FoodEditPage } from './FoodEditPage';
import { ActivityEditPage } from './ActivityEditPage';
import { AiRecognitionPage } from './AiRecognitionPage';
import { AiSettingsPage } from './AiSettingsPage';
import { ComingSoonPage } from '../components/ComingSoonPage';
import { OnboardingPage } from './OnboardingPage';
import { OnboardingService } from '../services/OnboardingService';
import { common } from '@kit.AbilityKit';import { color, fontSize, pageGradient } from '../common/DesignTokens';
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
    } else if (name === 'AiRecognition') {
      AiRecognitionPage()
    } else if (name === 'AiSettings') {
      AiSettingsPage()
    } else if (name === 'FoodLog') {
      // 全部餐食：从底 Tab 收进二级路由，入口在「我的 → 全部餐食」
      FoodPage()
    } else if (name === 'ActivityLog') {
      ActivityPage()
    }
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
            .tabBar('今日')

            TabContent() {
              DietPlanPage()
            }
            .tabBar('膳食')

            TabContent() {
              ProgressPage()
            }
            .tabBar('进度')

            TabContent() {
              NutriBitesPage()
            }
            .tabBar('营养师')

            TabContent() {
              ProfilePage()
            }
            .tabBar('我的')
          }
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
