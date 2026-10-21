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
import { relationalStore } from '@kit.ArkData';
import { Database } from '../../../main/ets/database/Database';
import { FoodRepository } from '../../../main/ets/repositories/FoodRepository';
import { FoodLog, FoodLogInput } from '../../../main/ets/models/FoodLog';
import { BoardRepository } from '../../../main/ets/repositories/BoardRepository';
import { BoardNodeModel, BoardNodeType } from '../../../main/ets/models/BoardModels';
import { AiUrlPolicy } from '../../../main/ets/common/AiUrlPolicy';
import { OverlayBackHandler } from '../../../main/ets/common/OverlayBackHandler';
import {
  validateMacroGrams,
  validateBodyWeight,
  validateBodyHeight,
  validateBodyAge
} from '../../../main/ets/common/Validators';
import { StickerCutoutService } from '../../../main/ets/services/StickerCutoutService';
import { migrateV7ToV8 } from '../../../main/ets/database/MigrationV7ToV8';

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

    /* ---------------- V7 → V8 迁移：放开 node_type 并转换旧示例便签 ---------------- */

    it('V7→V8 迁移放开 node_type 并把旧示例便签转成 DEMO_NOTE', 0, async () => {
      const store = await Database.ensure();
      // 造一张 V7 结构的 board_node（CHECK 只允许 0/1/2）
      await store.executeSql('DROP TABLE IF EXISTS board_node_v7_probe');
      await store.executeSql(`
        CREATE TABLE board_node_v7_probe (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          date TEXT NOT NULL,
          node_type INTEGER NOT NULL CHECK (node_type IN (0, 1, 2)),
          food_id INTEGER,
          title TEXT NOT NULL DEFAULT '',
          calories INTEGER NOT NULL DEFAULT 0,
          protein_g REAL, carbs_g REAL, fat_g REAL,
          portion_desc TEXT NOT NULL DEFAULT '',
          meal_category INTEGER NOT NULL DEFAULT 3,
          time_str TEXT NOT NULL DEFAULT '',
          mood_emoji TEXT NOT NULL DEFAULT '',
          companion_text TEXT NOT NULL DEFAULT '',
          memo_text TEXT NOT NULL DEFAULT '',
          ai_advice TEXT NOT NULL DEFAULT '',
          sticker_uri TEXT NOT NULL DEFAULT '',
          paper_style INTEGER NOT NULL DEFAULT 0,
          pin_type INTEGER NOT NULL DEFAULT 0,
          pos_x REAL NOT NULL DEFAULT 0, pos_y REAL NOT NULL DEFAULT 0,
          scale REAL NOT NULL DEFAULT 1, rotation REAL NOT NULL DEFAULT 0,
          z_index INTEGER NOT NULL DEFAULT 0,
          is_flipped INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
        )`);
      // 旧写法：示例便签存成普通 STICKY_NOTE(1)
      await store.executeSql(`
        INSERT INTO board_node_v7_probe
          (date, node_type, food_id, title, calories, ai_advice, created_at, updated_at)
        VALUES ('2026-04-11', 1, NULL, '今天的小确幸', 0,
                '蛋白质摄入不错，明天记得补点蔬菜均衡一下～', 1, 1)`);
      // 旧约束下插 node_type=3 必须失败
      let rejected = false;
      try {
        await store.executeSql(`
          INSERT INTO board_node_v7_probe
            (date, node_type, title, created_at, updated_at)
          VALUES ('2026-04-11', 3, '不该插进去', 1, 1)`);
      } catch (e) {
        rejected = true;
      }
      expect(rejected).assertTrue();

      // 迁移本体：把探针表改名为 board_node，再跑真正的迁移
      await store.executeSql('DROP TABLE IF EXISTS board_node');
      await store.executeSql('ALTER TABLE board_node_v7_probe RENAME TO board_node');
      await migrateV7ToV8(store);

      // 约束已放开：node_type=3 现在能插
      let accepted = true;
      try {
        await store.executeSql(`
          INSERT INTO board_node
            (date, node_type, title, created_at, updated_at)
          VALUES ('2026-04-11', 3, '示例便签', 1, 1)`);
      } catch (e) {
        accepted = false;
      }
      expect(accepted).assertTrue();

      // 旧的示例便签已被转成 DEMO_NOTE，点评也换成了描述功能的新文案
      const rs = await store.querySql(
        "SELECT node_type, ai_advice FROM board_node WHERE title = '今天的小确幸'");
      try {
        expect(rs.goToFirstRow()).assertTrue();
        expect(rs.getLong(rs.getColumnIndex('node_type'))).assertEqual(3);
        const advice = rs.getString(rs.getColumnIndex('ai_advice'));
        expect(advice.includes('蛋白质摄入不错')).assertFalse();
        expect(advice.includes('示例内容')).assertTrue();
      } finally {
        rs.close();
      }

      // 清理：把探针表删掉，恢复到干净状态
      await store.executeSql('DELETE FROM board_node');
      await store.executeSql('DROP TABLE IF EXISTS board_node_v7_probe');
    });

    it('黑板节点的 renderKey 随内容变化', 0, () => {
      const a = new BoardNodeModel();
      a.id = 7;
      a.title = '米饭';
      a.calories = 120;
      a.mealCategory = 1;
      const key1 = a.renderKey();

      // 只改 id 之外的内容 → key 必须变，否则列表会复用旧组件、显示旧数据
      a.calories = 240;
      const key2 = a.renderKey();
      expect(key1 === key2).assertFalse();

      // 内容没变 → key 不变，组件仍复用，拖拽状态不丢
      const b = new BoardNodeModel();
      b.id = 7;
      b.title = '米饭';
      b.calories = 120;
      b.mealCategory = 1;
      expect(b.renderKey() === key1).assertTrue();
    });

    it('饮食记录的 renderKey 随内容变化', 0, () => {
      const a = new FoodLog(1, '2026-04-11', '米饭', 1, 100, 120, 120, 0,
        null, null, 10, 20, 5, 1, 1, null);
      const key1 = a.renderKey();
      a.calories = 240;
      expect(a.renderKey() === key1).assertFalse();
      a.calories = 120;
      expect(a.renderKey() === key1).assertTrue();
    });
  });
}
