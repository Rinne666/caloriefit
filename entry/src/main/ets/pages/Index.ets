/**
 * 唯一 @Entry 页面：初始化数据库、持有全局状态（日期/刷新版本号），
 * Navigation 容器内放四个 Tab，编辑页通过 NavPathStack 打开 NavDestination。
 */

import { Database } from '../database/Database';
import { SettingsRepository } from '../repositories/SettingsRepository';
import { AppSettings } from '../models/AppSettings';
import { HomePage } from './HomePage';
import { FoodPage } from './FoodPage';
import { ActivityPage } from './ActivityPage';
import { ProfilePage } from './ProfilePage';
import { FoodEditPage } from './FoodEditPage';
import { ActivityEditPage } from './ActivityEditPage';
import { AiRecognitionPage } from './AiRecognitionPage';
import { AiSettingsPage } from './AiSettingsPage';
import { color, fontSize, pageGradient } from '../common/DesignTokens';
import { todayKey } from '../common/DateUtils';

@Entry
@Component
struct Index {
  @Provide('navStack') navStack: NavPathStack = new NavPathStack();
  @StorageLink('selectedDate') @Watch('onDateChanged') selectedDate: string = todayKey();
  @State appReady: boolean = false;
  @State initError: string = '';

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
      this.appReady = true;
    } catch (e) {
      const err = e as Error;
      this.initError = err.message;
    }
  }

  private onDateChanged(): void {
    // 切换日期后各页面通过自己的 @Watch 重新加载
  }

  @Builder
  PageMap(name: string) {
    if (name === 'FoodEdit') {
      FoodEditPage()
    } else if (name === 'ActivityEdit') {
      ActivityEditPage()
    } else if (name === 'AiRecognition') {
      AiRecognitionPage()
    } else if (name === 'AiSettings') {
      AiSettingsPage()
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
      } else {
        Tabs({ barPosition: BarPosition.End }) {
          TabContent() {
            HomePage()
          }
          .tabBar('今日')

          TabContent() {
            FoodPage()
          }
          .tabBar('饮食')

          TabContent() {
            ActivityPage()
          }
          .tabBar('运动')

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