/**
 * 步数写入优先级与来源标记的单元测试。
 *
 * 核心要验的是"手动值优先于传感器"这条业务规则：
 * 用户手动校正过之后，传感器上报不能把用户填的数冲掉；
 * 用户点「恢复自动采集」之后，传感器重新接管。
 *
 * 跑的是真实的生产代码 `repositories/ActivityRepository.ets`。
 */

import { describe, it, expect, beforeAll } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Database } from '../../../main/ets/database/Database';
import { ActivityRepository } from '../../../main/ets/repositories/ActivityRepository';
import { STEP_SOURCE_MANUAL, STEP_SOURCE_SENSOR, stepSourceLabel } from '../../../main/ets/models/DailyActivity';

const TEST_DATE: string = '2026-03-15';

export default function activityRepositoryTest() {
  describe('ActivityRepositoryTest', () => {

    beforeAll(() => {
      // 仓储层依赖 Database 单例，测试要先给它一个上下文。
      // ApplicationContext 本身就是 Context，直接传，不用强转成 UIAbilityContext
      // （ArkTS 不允许 ApplicationContext → UIAbilityContext 的直接断言）。
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const ctx = delegator.getAppContext().getApplicationContext();
      Database.ensure(ctx);
    });

    it('手动写入后来源标记为手动校正', 0, async () => {
      await ActivityRepository.setDailySteps(TEST_DATE, 8888);
      const row = await ActivityRepository.getByDate(TEST_DATE);
      expect(row !== null).assertTrue();
      expect(row!.steps).assertEqual(8888);
      expect(row!.source).assertEqual(STEP_SOURCE_MANUAL);
    });

    it('传感器上报不覆盖手动值', 0, async () => {
      // 先确保当天是手动值
      await ActivityRepository.setDailySteps(TEST_DATE, 8888);
      const written = await ActivityRepository.setSensorSteps(TEST_DATE, 100);
      expect(written).assertEqual(false);
      const row = await ActivityRepository.getByDate(TEST_DATE);
      expect(row!.steps).assertEqual(8888);
      expect(row!.source).assertEqual(STEP_SOURCE_MANUAL);
    });

    it('恢复自动采集后传感器重新接管', 0, async () => {
      await ActivityRepository.setDailySteps(TEST_DATE, 8888);
      await ActivityRepository.clearManualSteps(TEST_DATE);
      const row = await ActivityRepository.getByDate(TEST_DATE);
      expect(row === null).assertTrue();

      const written = await ActivityRepository.setSensorSteps(TEST_DATE, 321);
      expect(written).assertEqual(true);
      const after = await ActivityRepository.getByDate(TEST_DATE);
      expect(after!.steps).assertEqual(321);
      expect(after!.source).assertEqual(STEP_SOURCE_SENSOR);
    });

    it('来源角标文案映射正确', 0, () => {
      expect(stepSourceLabel(STEP_SOURCE_SENSOR)).assertEqual('传感器自动');
      expect(stepSourceLabel(STEP_SOURCE_MANUAL)).assertEqual('手动校正');
      expect(stepSourceLabel('')).assertEqual('未采集');
    });
  });
}
