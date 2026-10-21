/**
 * 本轮缺陷修复的单元测试。
 *
 * 覆盖调试报告里的 12 个已复现问题中**能落到纯逻辑/仓储层**的部分，
 * 以及 3 项源码级 P1 风险：
 *
 *   ① AiUrlPolicy —— AI 地址白名单（userinfo 绕过、http、伪造后缀）
 *   ② FoodRepository —— 贴纸文件引用计数（删副本不能带走原记录的贴纸）
 *   ③ OverlayBackHandler —— 页内浮层的返回键登记（关最上面那个）
 *   ④ Validators —— 宏量目标与体征档案的输入上限
 *
 * 为什么这几条必须有单测：
 *   ① URL 白名单绕过 = 把 App 变成任意地址的通用客户端，
 *      绕过去就等于隐私政策里声明的服务方范围失效了；
 *   ② 贴纸误删 = 用户照片的衍生数据凭空消失，且**不可恢复**；
 *   ③ 返回键处理错了 = 用户在弹层里按返回直接退出应用。
 */

import { describe, it, expect, beforeAll } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo } from '@kit.CoreFileKit';
import { Database } from '../../../main/ets/database/Database';
import { FoodRepository } from '../../../main/ets/repositories/FoodRepository';
import { FoodLog, FoodLogInput } from '../../../main/ets/models/FoodLog';
import { AiUrlPolicy } from '../../../main/ets/common/AiUrlPolicy';
import { OverlayBackHandler } from '../../../main/ets/common/OverlayBackHandler';
import {
  validateMacroGrams,
  validateBodyWeight,
  validateBodyHeight,
  validateBodyAge
} from '../../../main/ets/common/Validators';
import { StickerCutoutService } from '../../../main/ets/services/StickerCutoutService';

/** 单测专用日期，避免碰到真实数据 */
const TEST_DATE: string = '2026-04-10';

/** 写一个假的贴纸文件，返回相对路径 */
async function writeFakeSticker(baseName: string): Promise<string> {
  const ctx = Database.getAppContext();
  const abs = `${ctx !== null ? ctx.filesDir : ''}/${'stickers'}/${baseName}.png`;
  const dir = abs.substring(0, abs.lastIndexOf('/'));
  if (!fileIo.accessSync(dir)) {
    await fileIo.mkdir(dir, true);
  }
  const file = await fileIo.open(abs,
    fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  try {
    const buf = new ArrayBuffer(8);
    await fileIo.write(file.fd, buf);
  } finally {
    fileIo.closeSync(file);
  }
  return `stickers/${baseName}.png`;
}

/** 造一条带贴纸的饮食记录 */
async function insertWithSticker(name: string, stickerPath: string): Promise<number> {
  const input = new FoodLogInput(
    TEST_DATE, name, 0, 100, 200, 200, 0, null, null,
    10, 20, 5, stickerPath);
  return FoodRepository.insert(input);
}

export default function fixRegressionTest() {
  describe('FixRegressionTest', () => {
    beforeAll(() => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const ctx = delegator.getAppContext().getApplicationContext();
      Database.ensure(ctx);
    });

    /* ---------------- AI 地址白名单 ---------------- */

    it('白名单域名本身与其子域通过', 0, () => {
      expect(AiUrlPolicy.isAllowedBaseUrl('https://opencsg.com/aigateway/v1')).assertTrue();
      expect(AiUrlPolicy.isAllowedBaseUrl('https://opencsg.com')).assertTrue();
      expect(AiUrlPolicy.isAllowedBaseUrl('https://api.opencsg.com/v1')).assertTrue();
      expect(AiUrlPolicy.isAllowedBaseUrl('https://dashscope.aliyuncs.com/compatible-mode/v1')).assertTrue();
      expect(AiUrlPolicy.isAllowedBaseUrl('https://x.maas.aliyuncs.com/v1')).assertTrue();
    });

    it('userinfo 伪装不能绕过白名单', 0, () => {
      // 这是调试报告实测的绕过手法：
      // 字符串切分取 host 会得到 opencsg.com，标准解析的 hostname 却是 example.invalid
      expect(AiUrlPolicy.isAllowedBaseUrl('https://opencsg.com:443@example.invalid/v1')).assertFalse();
      expect(AiUrlPolicy.isAllowedBaseUrl('https://opencsg.com@example.invalid/v1')).assertFalse();
      expect(AiUrlPolicy.isAllowedBaseUrl('https://opencsg.com@evil.invalid/v1')).assertFalse();
      // 即便真实主机在白名单，带凭证的写法也一律拒绝（主机名会骗过人）
      expect(AiUrlPolicy.isAllowedBaseUrl('https://user:pass@opencsg.com/v1')).assertFalse();
    });

    it('非 https 与非白名单域名被拒绝', 0, () => {
      expect(AiUrlPolicy.isAllowedBaseUrl('http://opencsg.com/v1')).assertFalse();
      expect(AiUrlPolicy.isAllowedBaseUrl('https://evil.invalid/v1')).assertFalse();
      // 后缀伪装：opencsg.com.evil.invalid 不是 opencsg.com 的子域
      expect(AiUrlPolicy.isAllowedBaseUrl('https://opencsg.com.evil.invalid/v1')).assertFalse();
      expect(AiUrlPolicy.isAllowedBaseUrl('')).assertFalse();
      expect(AiUrlPolicy.isAllowedBaseUrl('   ')).assertFalse();
      expect(AiUrlPolicy.isAllowedBaseUrl('not-a-url')).assertFalse();
    });

    /* ---------------- 贴纸文件引用计数 ---------------- */

    it('删除副本不会带走原记录的贴纸文件', 0, async () => {
      const sticker = await writeFakeSticker('refcount_test');
      const abs = StickerCutoutService.absolutePath(sticker);
      expect(fileIo.accessSync(abs)).assertTrue();

      const originalId = await insertWithSticker('原记录', sticker);
      const copyId = await insertWithSticker('复制记录', sticker);
      expect(originalId !== copyId).assertTrue();

      // 两条记录共用同一个贴纸文件
      const refs = await FoodRepository.countStickerReferences(sticker);
      expect(refs).assertEqual(2);

      // 删掉副本：文件必须还在
      await FoodRepository.delete(copyId);
      expect(fileIo.accessSync(abs)).assertTrue();
      const afterOne = await FoodRepository.countStickerReferences(sticker);
      expect(afterOne).assertEqual(1);

      // 原记录仍在，贴纸路径也还在
      const original = await FoodRepository.getById(originalId);
      expect(original !== null).assertTrue();
      const log = original as FoodLog;
      expect(log.stickerPath).assertEqual(sticker);
    });

    it('最后一个引用删除后贴纸文件才被回收', 0, async () => {
      const sticker = await writeFakeSticker('refcount_last');
      const abs = StickerCutoutService.absolutePath(sticker);
      const id = await insertWithSticker('唯一引用', sticker);
      expect(fileIo.accessSync(abs)).assertTrue();

      await FoodRepository.delete(id);
      // 引用数归零 → 文件才变成孤儿并被删除
      const refs = await FoodRepository.countStickerReferences(sticker);
      expect(refs).assertEqual(0);
      expect(fileIo.accessSync(abs)).assertFalse();
    });

    /* ---------------- 浮层返回键登记 ---------------- */

    it('返回键关掉最上面那个浮层', 0, () => {
      const order: string[] = [];
      const first = OverlayBackHandler.push(() => {
        order.push('first');
      });
      const second = OverlayBackHandler.push(() => {
        order.push('second');
      });
      expect(OverlayBackHandler.hasOpen()).assertTrue();

      // 后开的先关（栈语义）
      expect(OverlayBackHandler.closeTop()).assertTrue();
      expect(order.length).assertEqual(1);
      expect(order[0]).assertEqual('second');

      expect(OverlayBackHandler.closeTop()).assertTrue();
      expect(order[1]).assertEqual('first');

      // 全关完就没有浮层了，返回键交回系统
      expect(OverlayBackHandler.hasOpen()).assertFalse();
      expect(OverlayBackHandler.closeTop()).assertFalse();

      // 注销过的 id 不会再触发
      OverlayBackHandler.remove(first);
      OverlayBackHandler.remove(second);
      expect(OverlayBackHandler.hasOpen()).assertFalse();
    });

    /* ---------------- 输入校验 ---------------- */

    it('宏量目标有上限且必须是数字', 0, () => {
      expect(validateMacroGrams('120', '蛋白').ok).assertTrue();
      expect(validateMacroGrams('0', '蛋白').ok).assertTrue();
      expect(validateMacroGrams('', '蛋白').ok).assertFalse();
      expect(validateMacroGrams('abc', '蛋白').ok).assertFalse();
      expect(validateMacroGrams('-1', '蛋白').ok).assertFalse();
      expect(validateMacroGrams('99999', '蛋白').ok).assertFalse();
      expect(validateMacroGrams('12.34', '蛋白').ok).assertFalse();
    });

    it('体征档案走同一套上限校验', 0, () => {
      expect(validateBodyWeight('65').ok).assertTrue();
      expect(validateBodyWeight('99999').ok).assertFalse();
      expect(validateBodyWeight('0').ok).assertFalse();
      expect(validateBodyHeight('170').ok).assertTrue();
      expect(validateBodyHeight('170.5').ok).assertFalse();
      expect(validateBodyHeight('99999').ok).assertFalse();
      expect(validateBodyAge('30').ok).assertTrue();
      expect(validateBodyAge('0').ok).assertFalse();
      expect(validateBodyAge('999').ok).assertFalse();
    });
  });
}
