/**
 * 计步基线状态持久化。
 *
 * 存 preferences 而不是 RDB，理由有三：
 *   1. 基线是**设备状态**（传感器计数器的偏移量），不是用户健康记录。
 *      放 RDB 会跟「清空全部记录」抢语义：清掉记录不该把基线一起清掉，
 *      否则用户清一次数据，第二天步数就归零重新估算。
 *   2. 不需要改表结构，避开 V6 迁移链。daily_activity 已经有 source 列，
 *      直接写 'SENSOR_PEDOMETER' 即可。
 *   3. 读写频次低（每次传感器上报一次），preferences 的量级完全够用。
 *
 * 但「删除全部数据并撤回同意」会清掉它 —— 见 PersonalDataService，
 * 那是彻底清除本机数据，不能留残余。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { StepBaselineState, DEFAULT_TIMESTAMP_UNIT } from '../services/StepBaseline';

const PREF_NAME = 'caloriefit_step';
const KEY_BASELINE = 'step_baseline_state';

/**
 * 基线状态以 JSON 字符串存。
 * preferences 的 ValueType 不含对象，所以自己序列化。
 */
export class StepBaselineRepository {
  static async load(ctx: common.UIAbilityContext): Promise<StepBaselineState | null> {
    try {
      const store = await preferences.getPreferences(ctx, { name: PREF_NAME });
      const raw = await store.get(KEY_BASELINE, '');
      if (typeof raw !== 'string' || raw.length === 0) {
        return null;
      }
      const parsed = JSON.parse(raw) as StepBaselineState;
      if (parsed === null || typeof parsed.baselineDate !== 'string') {
        return null;
      }
      // 旧版本存的状态没有 lastTimestamp / timestampUnit 字段，
      // 直接补默认值，否则后面做单位标定时会算出 NaN。
      if (typeof parsed.lastTimestamp !== 'number' || !isFinite(parsed.lastTimestamp)) {
        parsed.lastTimestamp = 0;
      }
      if (typeof parsed.timestampUnit !== 'number' || !isFinite(parsed.timestampUnit) ||
        parsed.timestampUnit <= 0) {
        parsed.timestampUnit = DEFAULT_TIMESTAMP_UNIT;
      }
      return parsed;
    } catch (e) {
      // 脏数据不应该让整个步数功能挂掉，丢掉重新建基线即可
      return null;
    }
  }

  static async save(ctx: common.UIAbilityContext, state: StepBaselineState): Promise<void> {
    try {
      const store = await preferences.getPreferences(ctx, { name: PREF_NAME });
      await store.put(KEY_BASELINE, JSON.stringify(state));
      await store.flush();
    } catch (e) {
      // 持久化失败不影响本次会话内的计算
    }
  }

  static async clear(ctx: common.UIAbilityContext): Promise<void> {
    try {
      const store = await preferences.getPreferences(ctx, { name: PREF_NAME });
      await store.delete(KEY_BASELINE);
      await store.flush();
    } catch (e) {
    }
  }
}
