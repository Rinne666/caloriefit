/**
 * 计步基线算法的单元测试。
 *
 * 跑的是**真实的生产代码** `services/StepBaseline.ets`，不是等价实现复写 ——
 * 这套算法的坑全在边界上（跨天拆分、重启复位、开机时间单位异常），
 * 复写一遍等于自己骗自己。
 *
 * 运行方式：
 *   hvigorw --mode module -p product=default -p module=entry@ohosTest -p buildMode=debug assembleHap
 *   hdc install entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap
 *   hdc shell aa test -b com.rinne.caloriefit -m entry_test -s unittest OpenHarmonyTestRunner -s class StepBaselineTest
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  StepReading, StepBaselineState, computeDailySteps,
  stepsBeforeMidnight, isBootTimePlausible, measureTimestampUnit, startOfDayMs,
  DEFAULT_TIMESTAMP_UNIT
} from '../../../main/ets/services/StepBaseline';

const DAY1: string = '2026-10-19';
const DAY2: string = '2026-10-20';

const HOUR: number = 3600 * 1000;

/** 某天某时（本地时区）的毫秒时间戳 */
function at(dateKey: string, hour: number, minute: number): number {
  const parts = dateKey.split('-');
  const y = parseInt(parts[0], 10);
  const mo = parseInt(parts[1], 10) - 1;
  const d = parseInt(parts[2], 10);
  return new Date(y, mo, d, hour, minute, 0, 0).getTime();
}

/** 造一次读数，timestamp 按文档约定是纳秒 */
function makeReading(cumulative: number, wallClockMs: number, bootWallMs: number): StepReading {
  return new StepReading(cumulative, (wallClockMs - bootWallMs) * 1000000, wallClockMs);
}

/** 造一次读数，模拟设备把 timestamp 按**毫秒**上报 */
function makeReadingMs(cumulative: number, wallClockMs: number, bootWallMs: number): StepReading {
  return new StepReading(cumulative, wallClockMs - bootWallMs, wallClockMs);
}

export default function stepBaselineTest() {
  describe('StepBaselineTest', () => {

    it('首次使用_设备今日开机_累计值全部计入今天', 0, () => {
      const now = at(DAY2, 12, 0);
      const boot = at(DAY2, 8, 0);
      const r = computeDailySteps(null, makeReading(4000, now, boot), DAY2);
      expect(r.steps).assertEqual(4000);
      expect(r.rebased).assertEqual(true);
      expect(r.state.baselineCumulative).assertEqual(0);
    });

    it('首次使用_设备昨日开机_按均匀步速倒推零点', 0, () => {
      // 昨天 22:00 开机，今天 12:00 读数，累计 10000 步
      // 开机到零点占 2 小时，开机至今共 14 小时 → 零点前约 10000*2/14 = 1428.57 步
      const now = at(DAY2, 12, 0);
      const boot = at(DAY1, 22, 0);
      const r = computeDailySteps(null, makeReading(10000, now, boot), DAY2);
      expect(r.steps).assertEqual(1429);
      expect(r.rebased).assertEqual(true);
    });

    it('同日_累计值增加_步数同步增加', 0, () => {
      const first = computeDailySteps(null, makeReading(2000, at(DAY2, 9, 0), at(DAY2, 7, 0)), DAY2);
      expect(first.steps).assertEqual(2000);

      const second = computeDailySteps(first.state, makeReading(2300, at(DAY2, 10, 0), at(DAY2, 7, 0)), DAY2);
      expect(second.steps).assertEqual(2300);
      expect(second.rebased).assertEqual(false);
      expect(second.steps - first.steps).assertEqual(300);
    });

    it('跨天_上次读数在零点前_按时间比例拆分', 0, () => {
      // 前一天 23:00 读到 1000 步，基线为 0
      const d1 = computeDailySteps(null, makeReading(1000, at(DAY1, 23, 0), at(DAY1, 7, 0)), DAY1);
      expect(d1.steps).assertEqual(1000);

      // 次日 01:00 读到 1600 步：这 2 小时里走了 600 步，其中前 1 小时在零点前
      // → 零点前的 300 步归昨天，基线 = 1000 + 300 = 1300，今天 = 1600 - 1300 = 300
      const d2 = computeDailySteps(d1.state, makeReading(1600, at(DAY2, 1, 0), at(DAY1, 7, 0)), DAY2);
      expect(d2.steps).assertEqual(300);
      expect(d2.rebased).assertEqual(true);
      expect(d2.state.baselineCumulative).assertEqual(1300);
    });

    it('跨天_上次读数已在零点后_零点整点区间不计入', 0, () => {
      // 构造防御分支：基线日期还是昨天，但上次读数已经落在今天零点之后
      const state = new StepBaselineState(DAY1, 1000, 1050, at(DAY2, 0, 10), 0, DEFAULT_TIMESTAMP_UNIT);
      const r = computeDailySteps(state, makeReading(1100, at(DAY2, 0, 30), at(DAY1, 22, 0)), DAY2);
      expect(r.steps).assertEqual(50);
      expect(r.state.baselineCumulative).assertEqual(1050);
    });

    it('计数回退_设备今日重启_重启后步数重新累计', 0, () => {
      const state = new StepBaselineState(DAY2, 0, 5000, at(DAY2, 10, 0), 0, DEFAULT_TIMESTAMP_UNIT);
      const r = computeDailySteps(state, makeReading(100, at(DAY2, 10, 30), at(DAY2, 9, 0)), DAY2);
      expect(r.rebased).assertEqual(true);
      expect(r.state.baselineCumulative).assertEqual(0);
      expect(r.steps).assertEqual(100);
    });

    it('计数回退_设备昨日重启_重启前步数找不回', 0, () => {
      const state = new StepBaselineState(DAY2, 0, 5000, at(DAY2, 10, 0), 0, DEFAULT_TIMESTAMP_UNIT);
      const r = computeDailySteps(state, makeReading(100, at(DAY2, 10, 30), at(DAY1, 22, 0)), DAY2);
      expect(r.rebased).assertEqual(true);
      expect(r.state.baselineCumulative).assertEqual(100);
      expect(r.steps).assertEqual(0);
    });

    it('开机时间离谱到不可信_保守建基线_今日从0开始', 0, () => {
      // timestamp 大到反推出的开机时刻是几万年以前
      const now = at(DAY2, 12, 0);
      const bad = new StepReading(3000, 1e18, now);
      const r = computeDailySteps(null, bad, DAY2);
      expect(r.steps).assertEqual(0);
      expect(r.state.baselineCumulative).assertEqual(3000);
    });

    it('时间戳单位自标定_设备按毫秒上报_不会把昨天步数算进今天', 0, () => {
      // 设备实际按毫秒上报 timestamp（文档说的是纳秒）
      const boot = at(DAY1, 20, 0);
      const r1 = computeDailySteps(null, makeReadingMs(1000, at(DAY1, 23, 0), boot), DAY1);
      // 第一次还只有默认值 1e6，按纳秒解读会以为"刚刚开机"，先记下
      expect(r1.state.timestampUnit).assertEqual(DEFAULT_TIMESTAMP_UNIT);

      // 第二次读数：Δtimestamp / Δ墙上时钟 = 7200000 / 7200000 = 1 → 单位是毫秒
      const r2 = computeDailySteps(r1.state, makeReadingMs(1600, at(DAY2, 1, 0), boot), DAY2);
      expect(r2.state.timestampUnit).assertEqual(1);
      // 单位变了 → 旧基线作废，今天从当前读数重新起算，绝不把 1600 步当成今天的
      expect(r2.rebased).assertEqual(true);
      expect(r2.steps).assertEqual(0);
      expect(r2.state.baselineCumulative).assertEqual(1600);

      // 第三次：单位已标定为毫秒，开机时刻算得对，同日走差值
      const r3 = computeDailySteps(r2.state, makeReadingMs(2000, at(DAY2, 2, 0), boot), DAY2);
      expect(r3.steps).assertEqual(400);
    });

    it('步数为负时钳制为0', 0, () => {
      const state = new StepBaselineState(DAY2, 1000, 500, at(DAY2, 9, 0), 0, DEFAULT_TIMESTAMP_UNIT);
      const r = computeDailySteps(state, makeReading(600, at(DAY2, 10, 0), at(DAY2, 7, 0)), DAY2);
      expect(r.steps).assertEqual(0);
    });

    it('stepsBeforeMidnight_整段在零点前_全部归前一天', 0, () => {
      const from = at(DAY1, 22, 0);
      const now = at(DAY1, 23, 0);
      const got = stepsBeforeMidnight(1000, from, startOfDayMs(DAY2), now);
      expect(got).assertEqual(1000);
    });

    it('stepsBeforeMidnight_整段在零点后_全部归今天', 0, () => {
      const from = at(DAY2, 0, 30);
      const now = at(DAY2, 1, 0);
      const got = stepsBeforeMidnight(1000, from, startOfDayMs(DAY2), now);
      expect(got).assertEqual(0);
    });

    it('stepsBeforeMidnight_跨零点_按时间比例拆分', 0, () => {
      const from = at(DAY1, 23, 0);
      const now = at(DAY2, 1, 0);
      const got = stepsBeforeMidnight(600, from, startOfDayMs(DAY2), now);
      expect(got).assertEqual(300);
    });

    it('stepsBeforeMidnight_步数为0或时间跨度非正_返回0', 0, () => {
      expect(stepsBeforeMidnight(0, at(DAY1, 23, 0), startOfDayMs(DAY2), at(DAY2, 1, 0))).assertEqual(0);
      expect(stepsBeforeMidnight(100, at(DAY2, 1, 0), startOfDayMs(DAY2), at(DAY2, 1, 0))).assertEqual(0);
    });

    it('measureTimestampUnit_按实测比值标定', 0, () => {
      // 纳秒实现：1 小时 = 3.6e9 纳秒
      expect(measureTimestampUnit(3600000000000, HOUR)).assertEqual(1000000);
      // 毫秒实现：1 小时 = 3.6e6 毫秒
      expect(measureTimestampUnit(3600000, HOUR)).assertEqual(1);
      // 微秒实现：1 小时 = 3.6e9 微秒
      expect(measureTimestampUnit(3600000000, HOUR)).assertEqual(1000);
      // 差值非正或越界 → 无法标定
      expect(measureTimestampUnit(0, HOUR)).assertEqual(-1);
      expect(measureTimestampUnit(100, 0)).assertEqual(-1);
      // 1e15 / 1h = 2.78e8 单位/毫秒，远超上限
      expect(measureTimestampUnit(1e15, HOUR)).assertEqual(-1);
      // 1 / 1h ≈ 2.8e-7 单位/毫秒，远低于下限
      expect(measureTimestampUnit(1, HOUR)).assertEqual(-1);
    });

    it('isBootTimePlausible_开机时间在未来或过久都判为不可信', 0, () => {
      const now = at(DAY2, 12, 0);
      expect(isBootTimePlausible(now - HOUR, now)).assertEqual(true);
      expect(isBootTimePlausible(now - 10 * 24 * HOUR, now)).assertEqual(true);
      expect(isBootTimePlausible(now + HOUR, now)).assertEqual(false);
      expect(isBootTimePlausible(now - 40 * 24 * HOUR, now)).assertEqual(false);
    });

    it('startOfDayMs_返回本地零点', 0, () => {
      const midnight = startOfDayMs(DAY2);
      const expected = new Date(2026, 9, 20, 0, 0, 0, 0).getTime();
      expect(midnight).assertEqual(expected);
      expect(new Date(midnight).getHours()).assertEqual(0);
    });

    it('跨天拆分_只把零点之后那段算进今天', 0, () => {
      // 昨天 20:00 开机并读到 2000 步（基线 0），今天 08:00 读到 5000 步
      // 昨天 20:00 → 今天 08:00 共 12 小时，其中 4 小时在零点前
      // 这段走了 3000 步，零点前占 4/12 → 1000 步归昨天，2000 步归今天
      const d1 = computeDailySteps(null, makeReading(2000, at(DAY1, 20, 0), at(DAY1, 20, 0)), DAY1);
      const d2 = computeDailySteps(d1.state, makeReading(5000, at(DAY2, 8, 0), at(DAY1, 20, 0)), DAY2);
      expect(d2.steps).assertEqual(2000);
      expect(d2.steps).assertLess(5000);
    });
  });
}
