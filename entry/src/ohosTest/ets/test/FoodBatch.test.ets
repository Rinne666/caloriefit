/**
 * 批量抠图验证：用**多张真实食物照片**验证「能否提取出食物主体」。
 *
 * 素材来源：TheMealDB 公开食物图库（CC 图片），已下载到
 * `entry/src/main/resources/rawfile/`（rawfile 是**扁平**目录，不支持子路径 ——
 * 踩过一次 GetRawFileContent failed），共 6 张：
 *   food0 15-minute chicken & halloumi burgers
 *   food1 Ayam Percik
 *   food2 Æbleskiver
 *   food3 Alfajores
 *   food4 Chilli prawn linguine
 *   food5 Fettuccine Alfredo
 *
 * 这个用例做三件事：
 *   1) **机制断言**：抠图后保留区不透明、区外透明（直接读 alpha 通道）
 *   2) **入库**：把 6 张抠图结果写成当日饮食记录并挂上 sticker_path
 *      —— 这样就能在 App 的「今日黑板」上**亲眼**看到抠出来的贴纸，
 *      比隔着日志猜可靠得多
 *   3) 打印透明像素占比，量化「背景被抠掉了多少」
 *
 * ⚠ 运行前提：**必须先 uninstall 再装**，不能直接 `install -r` 覆盖：
 *   实测 `hdc install -r` 在**同版本覆盖**时不会真正替换 bundle 的资源表 ——
 *   主包换成最新构建后，测试包里新增的 rawfile 仍然读不到，
 *   报 `GetRawFileContent failed`。先 `hdc uninstall` 再装测试包
 *   （ohosTest 是 `deliveryWithInstall: true`，会带上主包）就正常。
 *   这个坑不只影响测试：改了任何 rawfile 资源后，`install -r` 都可能不生效。
 *
 * 走的是**降级路径**（region = null → 中心椭圆），因为没有真实模型坐标。
 * 真实链路里坐标由 AI 给出、形状更准；但「区域外被抠成透明」两者共用同一段代码。
 *
 * 跑完记得清理：用打印出来的记录 id 调 FoodRepository.delete 删除，
 * 否则会残留在当日黑板上。
 */

import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { StickerCutoutService } from '../../../main/ets/services/StickerCutoutService';
import { Database } from '../../../main/ets/database/Database';
import { FoodRepository } from '../../../main/ets/repositories/FoodRepository';
import { FoodLogInput } from '../../../main/ets/models/FoodLog';

/** 文件名 / 菜名 / 热量 / 餐次 */
class FoodCase {
  file: string = '';
  name: string = '';
  kcal: number = 0;
  meal: number = 0;

  constructor(file: string, name: string, kcal: number, meal: number) {
    this.file = file;
    this.name = name;
    this.kcal = kcal;
    this.meal = meal;
  }
}

const DOMAIN = 0x0000;
const TAG = 'FoodBatch';

const CASES: FoodCase[] = [
  new FoodCase('food0.jpg', '鸡肉汉堡', 620, 0),
  new FoodCase('food1.jpg', 'Ayam Percik 烤鸡', 540, 1),
  new FoodCase('food2.jpg', '丹麦炸饼', 480, 3),
  new FoodCase('food3.jpg', 'Alfajores 夹心饼', 430, 3),
  new FoodCase('food4.jpg', '辣虾意面', 590, 1),
  new FoodCase('food5.jpg', '培根奶油意面', 720, 2)
];

export default function foodBatchTest() {
  describe('FoodBatchTest', () => {

    it('六张真实食物图_抠出主体_背景透明_并写入当日记录', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      // 数据库在**主模块**（entry）的沙箱里
      const ctx = delegator.getAppContext().getApplicationContext();
      Database.ensure(ctx);
      // 照片在**测试模块**（entry_test）的 rawfile 里 —— 同 bundle 不同模块，
      // 资源互不可见，必须用测试 Ability 自己的 context 读。
      const modCtx = AppStorage.get<common.UIAbilityContext>('testModuleCtx');
      if (modCtx === undefined || modCtx === null) {
        hilog.error(DOMAIN, TAG, 'testModuleCtx 未初始化');
        expect(modCtx !== undefined && modCtx !== null).assertTrue();
        return;
      }

      let allOk = true;
      const ids: number[] = [];

      for (let i = 0; i < CASES.length; i++) {
        const c = CASES[i];
        const bytes = await modCtx.resourceManager.getRawFileContent(c.file);
        const buf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
        const source = image.createImageSource(buf);
        const pm = await source.createPixelMap();
        let cut: image.PixelMap | null = null;
        try {
          // region = null → 中心椭圆降级
          cut = await StickerCutoutService.cutout(pm, null);
          const info = await cut.getImageInfo();
          const w = info.size.width;
          const h = info.size.height;
          const ab = new ArrayBuffer(w * h * 4);
          await cut.readPixelsToBuffer(ab);
          const u8 = new Uint8Array(ab);

          const alphaAt = (x: number, y: number): number => u8[(y * w + x) * 4 + 3];
          const center = alphaAt(Math.floor(w / 2), Math.floor(h / 2));
          const corner = alphaAt(1, 1);

          // 统计透明像素占比 —— 量化「背景被抠掉了多少」
          let transparent = 0;
          const total = w * h;
          for (let p = 3; p < u8.length; p += 4) {
            if (u8[p] < 8) {
              transparent++;
            }
          }
          const transparentRatio = transparent / total;

          const centerOk = center > 200;
          const cornerOk = corner < 50;
          const ratioOk = transparentRatio > 0.12;
          const ok = centerOk && cornerOk && ratioOk;
          if (!ok) {
            allOk = false;
          }
          hilog.info(DOMAIN, TAG,
            '%{public}s %{public}d x %{public}d center=%{public}d corner=%{public}d transparent=%{public}d%% => %{public}s',
            c.file, w, h, center, corner, Math.round(transparentRatio * 100), ok ? 'OK' : 'FAIL');

          // 落盘并写进当日记录，让黑板页能直接看到这张贴纸。
          // entryMode = 1（AI 整份估算）时 grams / kcalPer100g 必须是 null。
          const relPath = await StickerCutoutService.savePng(cut, StickerCutoutService.newBaseName());
          const input = new FoodLogInput('2026-10-21', c.name, c.meal,
            null, null, c.kcal, 1, 0.9, '批量抠图验证样本', 20, 30, 12, relPath);
          const id = await FoodRepository.insert(input);
          ids.push(id);
          hilog.info(DOMAIN, TAG, 'inserted id=%{public}d name=%{public}s sticker=%{public}s',
            id, c.name, relPath);
        } finally {
          if (cut !== null) {
            cut.release();
          }
          pm.release();
          source.release();
        }
      }
      expect(allOk).assertTrue();
      expect(ids.length).assertEqual(CASES.length);
    });

  });
}
