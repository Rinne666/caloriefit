/**
 * 计步基线计算 —— 纯逻辑，不碰传感器、数据库与界面，便于单独验证。
 *
 * 背景：`sensor.SensorId.PEDOMETER` 给的是**开机以来的累计步数**，不是当日步数。
 * 要得到"今天走了多少步"，必须自己做基线差值。
 *
 * 这里处理三类会让基线失效的情况：
 *   1. 首次使用 —— 没有任何历史基线
 *   2. 跨天     —— 基线归属日期变了
 *   3. 计数回退 —— 设备重启或传感器复位，累计值被清零
 *
 * 跨天时不能简单地把"当前累计值"当成新基线，那样会把当天 0 点到首次读取
 * 之间走过的步数全部丢掉。这里按**均匀步速**把跨越午夜的那一段拆开：
 * 上次读数落在午夜前多少，那一段按比例留给前一天，其余归今天。
 *
 * 已知局限（写清楚，别让它被当成精确值）：
 *   · 均匀步速是假设。夜里不走路、白天集中走，实际分布并不均匀，
 *     午夜前后的拆分必然有误差。这是估算，不是测量。
 *   · 设备重启会清零累计值，重启前的步数找不回来，只能从重启后重新累计。
 *   · 首次使用且设备昨天就开过机时，午夜时刻的累计值无从得知，
 *     只能用"开机至今均匀步速"倒推，同样是估算。
 */

/** 一次传感器读数 */
export class StepReading {
  /** 传感器累计步数（开机以来） */
  cumulative: number;
  /** 开机后经过的纳秒数，即 sensor Response.timestamp */
  bootTimestampNs: number;
  /** 读取时刻，Date.now() 毫秒 */
  wallClockMs: number;

  constructor(cumulative: number, bootTimestampNs: number, wallClockMs: number) {
    this.cumulative = cumulative;
    this.bootTimestampNs = bootTimestampNs;
    this.wallClockMs = wallClockMs;
  }
}

/**
 * timestamp 的默认单位：每毫秒对应多少个 timestamp 单位。
 * SDK 文档写的是纳秒，所以默认 1e6。
 */
export const DEFAULT_TIMESTAMP_UNIT: number = 1000000;

/** 持久化的基线状态 */
export class StepBaselineState {
  /** 基线归属日期，YYYY-MM-DD */
  baselineDate: string;
  /** 基线时刻的传感器累计值 */
  baselineCumulative: number;
  /** 上一次读到的累计值，用于识别计数回退 */
  lastCumulative: number;
  /** 上一次读取时刻（毫秒），用于跨天时按时间比例拆分 */
  lastWallClockMs: number;
  /** 上一次读到的 timestamp，用于标定它的单位 */
  lastTimestamp: number;
  /**
   * 已标定的 timestamp 单位（每毫秒多少单位）。
   * 标定方法见 computeDailySteps —— 不靠文档，靠相邻两次读数的比值实测。
   */
  timestampUnit: number;

  constructor(baselineDate: string, baselineCumulative: number,
    lastCumulative: number, lastWallClockMs: number,
    lastTimestamp: number, timestampUnit: number) {
    this.baselineDate = baselineDate;
    this.baselineCumulative = baselineCumulative;
    this.lastCumulative = lastCumulative;
    this.lastWallClockMs = lastWallClockMs;
    this.lastTimestamp = lastTimestamp;
    this.timestampUnit = timestampUnit;
  }
}

/** 一次计算的结果 */
export class StepBaselineResult {
  /** 当日步数 */
  steps: number;
  /** 更新后的基线状态，调用方需要把它持久化 */
  state: StepBaselineState;
  /** 本次是否重建了基线 */
  rebased: boolean;
  /** 重建原因，用于界面说明与日志 */
  reason: string;

  constructor(steps: number, state: StepBaselineState, rebased: boolean, reason: string) {
    this.steps = steps;
    this.state = state;
    this.rebased = rebased;
    this.reason = reason;
  }
}

/** 把 YYYY-MM-DD 转成本地零点的毫秒时间戳 */
export function startOfDayMs(dateKey: string): number {
  const parts = dateKey.split('-');
  const y = parseInt(parts[0], 10);
  const mo = parseInt(parts[1], 10) - 1;
  const d = parseInt(parts[2], 10);
  return new Date(y, mo, d, 0, 0, 0, 0).getTime();
}

/**
 * 把 [fromMs, nowMs] 这一段里走的 totalSteps 步，按时间比例拆成
 * "午夜之前"和"午夜之后"两部分，返回落在午夜之前的那部分。
 *
 * fromMs 早于午夜时，午夜之前的时长占比就是分给前一天的比例。
 * 若整段都在午夜之后（fromMs 已经 >= 午夜），全部归今天，返回 0。
 */
export function stepsBeforeMidnight(totalSteps: number, fromMs: number,
  midnightMs: number, nowMs: number): number {
  if (totalSteps <= 0) {
    return 0;
  }
  const span = nowMs - fromMs;
  if (span <= 0) {
    return 0;
  }
  const toMidnight = midnightMs - fromMs;
  if (toMidnight <= 0) {
    // 整段都在午夜之后，没有属于前一天的部分
    return 0;
  }
  if (toMidnight >= span) {
    // 整段都在午夜之前，全部属于前一天
    return totalSteps;
  }
  return totalSteps * toMidnight / span;
}

/**
 * 开机时刻的可信上限。
 *
 * 算出来的开机时刻不能比现在更晚，也不能早于 30 天，否则基线跟着算飞。
 */
const MAX_BOOT_AGE_MS: number = 30 * 24 * 60 * 60 * 1000;

/** 开机时刻是否可信 */
export function isBootTimePlausible(bootWallMs: number, nowMs: number): boolean {
  if (!isFinite(bootWallMs) || !isFinite(nowMs)) {
    return false;
  }
  if (bootWallMs > nowMs) {
    return false;
  }
  return nowMs - bootWallMs <= MAX_BOOT_AGE_MS;
}

/**
 * 实测 timestamp 的单位。
 *
 * SDK 文档说 `Response.timestamp` 是纳秒，但只靠"开机后经过的时间"这一个数
 * 是**验不出单位对不对的** —— 设备若按毫秒上报，14 小时的真实时长会被读成
 * 14 小时的"纳秒数"，除以 1e6 后只剩 50 毫秒，看起来就像"刚刚开机"，
 * 于是基线取 0，把昨天的步数全算进今天，静默多算几千步。
 *
 * 可靠办法是**用相邻两次读数的比值实测**：
 *   unit = Δtimestamp / Δ墙上时钟(毫秒)
 * 纳秒实现得到 1e6，毫秒实现得到 1，微秒实现得到 1e3。
 *
 * @param dt 相邻两次读数的 timestamp 差
 * @param dw 相邻两次读数的墙上时钟差（毫秒）
 * @return 标定出的单位；无法标定时返回 -1
 */
export function measureTimestampUnit(dt: number, dw: number): number {
  if (!(dt > 0) || !(dw > 0)) {
    return -1;
  }
  const ratio = dt / dw;
  // 合理区间：0.5（毫秒）到 2e6（纳秒）
  if (ratio < 0.5 || ratio > 2000000) {
    return -1;
  }
  return ratio;
}

/**
 * 核心计算：给定基线状态与一次读数，算出当日步数，并给出新的基线状态。
 *
 * state 为 null 表示首次使用（还没建立过基线）。
 */
export function computeDailySteps(state: StepBaselineState | null,
  reading: StepReading, todayKey: string): StepBaselineResult {
  const midnightMs = startOfDayMs(todayKey);
  const nowMs = reading.wallClockMs;

  // ---- 1. 标定 timestamp 单位 ----
  let unit: number = state !== null ? state.timestampUnit : DEFAULT_TIMESTAMP_UNIT;
  if (!isFinite(unit) || unit <= 0) {
    unit = DEFAULT_TIMESTAMP_UNIT;
  }
  let unitChanged = false;
  if (state !== null) {
    const measured = measureTimestampUnit(reading.bootTimestampNs - state.lastTimestamp,
      nowMs - state.lastWallClockMs);
    if (measured > 0 && Math.abs(measured - unit) > unit * 0.5) {
      // 实测单位与记录值差一倍以上 → 之前的基线是按错误单位算的，必须重建
      unit = measured;
      unitChanged = true;
    } else if (measured > 0) {
      unit = measured;
    }
  }

  // ---- 2. 由开机时长反推开机时刻 ----
  const elapsedMs = reading.bootTimestampNs / unit;
  const rawBootWallMs = nowMs - elapsedMs;
  const bootKnown = isBootTimePlausible(rawBootWallMs, nowMs);
  const bootWallMs = bootKnown ? rawBootWallMs : 0;

  let base: number;
  let reason: string;
  let rebased: boolean;

  if (state === null) {
    // 首次使用。设备今天开过机 → 累计值全部属于今天，基线取 0；
    // 否则按"开机至今均匀步速"倒推午夜时刻的累计值（估算）。
    if (!bootKnown) {
      base = reading.cumulative;
      reason = '首次建立基线：开机时间不可信，按当前累计值建立基线，今日步数从 0 开始';
    } else if (bootWallMs >= midnightMs) {
      base = 0;
      reason = '首次建立基线：设备今日开机，累计值全部计入今天';
    } else {
      base = reading.cumulative - stepsBeforeMidnight(reading.cumulative, bootWallMs, midnightMs, nowMs);
      reason = '首次建立基线：按开机至今的均匀步速倒推今日零点，累计值为估算';
    }
    rebased = true;
  } else if (unitChanged) {
    // 单位变了，之前所有基于它的推算全部作废，今天从当前读数重新起算
    base = reading.cumulative;
    reason = '检测到传感器时间戳单位变化，已重建基线，今日步数从 0 开始';
    rebased = true;
  } else if (reading.cumulative < state.lastCumulative) {
    // 累计值回退 = 设备重启或传感器复位，计数器被清零
    if (bootKnown && bootWallMs >= midnightMs) {
      base = 0;
      reason = '传感器计数回退：设备今日重启，重启后的步数重新累计';
    } else {
      base = reading.cumulative;
      reason = '传感器计数回退：设备曾重启，重启前的步数无法找回';
    }
    rebased = true;
  } else if (state.baselineDate !== todayKey) {
    // 跨天。用上次读数到本次读数这一段做时间比例拆分
    if (state.lastWallClockMs < midnightMs) {
      const delta = reading.cumulative - state.lastCumulative;
      const before = stepsBeforeMidnight(delta, state.lastWallClockMs, midnightMs, nowMs);
      base = state.lastCumulative + before;
      reason = '跨天重建基线：零点前后的步数按时间比例拆分';
    } else {
      // 上次读数已经落在今天零点之后，零点整点那一段无从得知
      base = state.lastCumulative;
      reason = '跨天重建基线：上次读取已在今日零点之后，零点整点区间的步数未计入';
    }
    rebased = true;
  } else {
    base = state.baselineCumulative;
    reason = '沿用当日基线';
    rebased = false;
  }

  let steps = reading.cumulative - base;
  if (steps < 0) {
    // 计数器抖动或基线与读数不同源，宁可显示 0 也不显示负数
    steps = 0;
  }

  const next = new StepBaselineState(todayKey, base, reading.cumulative, nowMs,
    reading.bootTimestampNs, unit);
  return new StepBaselineResult(Math.round(steps), next, rebased, reason);
}
