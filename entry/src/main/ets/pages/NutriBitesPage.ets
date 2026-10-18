/**
 * 营养师 NutriBites —— 对应 NutriScan 第四个底 Tab（AI 对话入口）。
 *
 * 证据：路由图里有「NutriBites ──> AI 对话」，日志里后端自述
 * `resourceInterfaceMap.put("chat","com.example.mind_ai_service")`，
 * 后端 `"agent":"gemini"`，另外 monika 关键词命中 177 次。
 *
 * 但**请求体内容没抓到**，服务端对话协议未知，且需要 Gemini 侧的服务端凭据。
 * 所以这一屏做成未实现跳转，而不是拿本地的 MaaS 端点硬凑一个假的对话 ——
 * 那会让用户以为接的是原版后端。
 */

import { color, fontSize, space, layout } from '../common/DesignTokens';
import { ComingSoonPage, setComingSoon } from '../components/ComingSoonPage';
import { Provenance } from '../services/MockContent';

@Component
export struct NutriBitesPage {
  aboutToAppear(): void {
    setComingSoon('NutriBites',
      'AI 营养对话：基于扫描记录与宏量缺口给出建议',
      '服务端对话协议未知，且需要 Gemini 侧凭据',
      '抓包拿到请求体结构，或搭一个自有后端并改写这一屏',
      Provenance.INFERRED);
  }

  build() {
    Scroll() {
      Column({ space: space.md }) {
        Text('营养师')
          .fontSize(fontSize.pageTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(color.text)
          .width('100%')

        ComingSoonPage()
      }
      .padding(layout.pagePadding)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor(color.bg)
    .linearGradient({ angle: 135, colors: [[color.pageDeep, 0], [color.pageMid, 1]] })
  }
}