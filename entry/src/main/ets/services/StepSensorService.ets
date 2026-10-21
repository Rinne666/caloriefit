/**
 * 计步传感器服务。
 *
 * 数据来源：`sensor.SensorId.PEDOMETER`（计步传感器，sensorId 266）。
 * 它给的是**开机以来的累计步数**，当日步数由 StepBaseline 做基线差值得到。
 *
 * 权限：`ohos.permission.ACTIVITY_MOTION`，实测为 **user_grant**，
 * 声明后仍需运行时弹窗申请，否则 `sensor.on` 直接抛 201。
 *
 * 启动策略分两种，**不要在冷启动时弹权限框**：
 *   · start(ctx, false) —— 静默尝试。已授权就直接订阅；没授权就置为
 *     NEED_PERMISSION，**不弹框**。EntryAbility 走这条。
 *   · start(ctx, true)  —— 用户主动点「开启自动采集」时走这条，
 *     才会弹权限申请框。ActivityPage 走这条。
 *
 * 订阅用 `on` 拿推送，再加一个慢速 `once` 轮询兜底：
 * 部分实现只在计步器数值变化时才上报推送，静止时可能长时间没有回调。
 */

import { sensor } from '@kit.SensorServiceKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { StepBaselineRepository } from '../repositories/StepBaselineRepository';
import { ActivityRepository } from '../repositories/ActivityRepository';
import { StepReading, StepBaselineState, computeDailySteps, DEFAULT_TIMESTAMP_UNIT } from './StepBaseline';
import { ConsentState } from './ConsentState';
import { todayKey } from '../common/DateUtils';

const DOMAIN = 0x0003;
const TAG = 'CalorieFitStep';
/**
 * Permissions 是**字符串字面量联合类型**，不能声明成 string，
 * 否则 requestPermissionsFromUser 的入参类型不匹配（编译期就报）。
 */
const PERMISSION_ACTIVITY_MOTION: Permissions = 'ohos.permission.ACTIVITY_MOTION';
/** 轮询兜底间隔（毫秒） */
const POLL_INTERVAL_MS: number = 60000;
/**
 * 落库节流间隔（毫秒）。
 *
 * 实测：模拟器上的计步传感器**每 150 ms 就推一次**（真机是计步器数值变化才推，
 * 但不能指望所有实现都这样）。不节流的话每 150 ms 写一次数据库，
 * 既费电又会把 RDB 写坏。
 *
 * 节流方式用「尾沿 + 保留最新值」：任何时候来读数都先存成 pending，
 * 每隔 FLUSH_INTERVAL_MS 把**最新那个值**落库。这样既限住了写入频率，
 * 又不会丢掉最后一次读数（如果只做丢弃式节流，最后一段步数会永远少算）。
 */
const FLUSH_INTERVAL_MS: number = 10000;

export enum StepSensorStatus {
  /** 尚未启动 */
  IDLE = 'idle',
  /** 设备没有计步传感器 */
  UNSUPPORTED = 'unsupported',
  /** 需要用户授予动作权限 */
  NEED_PERMISSION = 'need_permission',
  /** 用户拒绝了权限 */
  DENIED = 'denied',
  /** 已订阅，正在采集 */
  RUNNING = 'running',
  /** 其他错误 */
  ERROR = 'error'
}

export class StepSensorService {
  private static status: StepSensorStatus = StepSensorStatus.IDLE;
  private static statusDetail: string = '';
  private static lastSteps: number = 0;
  private static lastReason: string = '';
  private static subscribed: boolean = false;
  private static pollTimer: number = -1;
  private static flushTimer: number = -1;
  /** 最新一条待落库的读数 */
  private static pending: StepReading | null = null;
  private static ctx: common.UIAbilityContext | null = null;
  /** 订阅回调必须持有同一引用，off 时才能退订 */
  private static sensorCallback: ((data: sensor.PedometerResponse) => void) | null = null;
  /** 页面回调，同一时刻只保留一个（目前只有运动页需要） */
  private static listener: ((steps: number) => void) | null = null;

  static getStatus(): StepSensorStatus {
    return StepSensorService.status;
  }

  static getStatusDetail(): string {
    return StepSensorService.statusDetail;
  }

  static getLastSteps(): number {
    return StepSensorService.lastSteps;
  }

  /** 最近一次基线重建的原因，界面用它解释"为什么今天从 0 开始" */
  static getLastReason(): string {
    return StepSensorService.lastReason;
  }

  static setListener(fn: ((steps: number) => void) | null): void {
    StepSensorService.listener = fn;
  }

  private static setStatus(s: StepSensorStatus, detail: string): void {
    StepSensorService.status = s;
    StepSensorService.statusDetail = detail;
    hilog.info(DOMAIN, TAG, 'status=%{public}s detail=%{public}s', s, detail);
  }

  /** 设备是否带计步传感器。装了传感器但系统不提供该能力时同样返回 false。 */
  private static async hasPedometer(): Promise<boolean> {
    try {
      const list = await sensor.getSensorList();
      for (let i = 0; i < list.length; i++) {
        if (list[i].sensorId === sensor.SensorId.PEDOMETER) {
          return true;
        }
      }
      return false;
    } catch (e) {
      const err = e as Error;
      hilog.error(DOMAIN, TAG, 'getSensorList failed: %{public}s', err.message);
      return false;
    }
  }

  /** 弹窗申请动作权限。返回是否授权成功。 */
  private static async requestPermission(ctx: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(ctx, [PERMISSION_ACTIVITY_MOTION]);
      // authResults: 0 = 已授权，-1 = 被拒，2 = 请求非法（多半是没在 module.json5 声明）
      if (result.authResults.length > 0 && result.authResults[0] === 0) {
        return true;
      }
      hilog.warn(DOMAIN, TAG, 'permission denied, authResults=%{public}s',
        JSON.stringify(result.authResults));
      return false;
    } catch (e) {
      const err = e as Error;
      hilog.error(DOMAIN, TAG, 'requestPermission failed: %{public}s', err.message);
      return false;
    }
  }

  /**
   * 启动采集。
   * @param requestPermission true = 允许弹权限框；false = 静默尝试
   */
  static async start(ctx: common.UIAbilityContext, requestPermission: boolean): Promise<StepSensorStatus> {
    StepSensorService.ctx = ctx;
    if (StepSensorService.subscribed) {
      return StepSensorService.status;
    }

    /**
     * 同意态闸门。
     *
     * 用户撤回健康信息同意后，系统权限可能还在（权限是用户单独授予的），
     * 但**同意已经没了**，这时采集步数就是没依据的。
     * 所以订阅之前先看同意状态。
     */
    if (!ConsentState.isAccepted(ctx)) {
      StepSensorService.setStatus(StepSensorStatus.IDLE, '未获得健康信息同意，不采集');
      return StepSensorService.status;
    }

    const has = await StepSensorService.hasPedometer();
    if (!has) {
      StepSensorService.setStatus(StepSensorStatus.UNSUPPORTED, '设备没有计步传感器');
      return StepSensorService.status;
    }

    if (requestPermission) {
      const granted = await StepSensorService.requestPermission(ctx);
      if (!granted) {
        StepSensorService.setStatus(StepSensorStatus.DENIED, '未获得动作权限');
        return StepSensorService.status;
      }
    }

    try {
      const cb = (data: sensor.PedometerResponse) => {
        StepSensorService.handleReading(data);
      };
      StepSensorService.sensorCallback = cb;
      sensor.on(sensor.SensorId.PEDOMETER, cb);
      StepSensorService.subscribed = true;
      StepSensorService.setStatus(StepSensorStatus.RUNNING, '计步传感器已订阅');

      // 立刻取一次，把基线建起来；否则用户要等到第一次真实走动才有数
      sensor.once(sensor.SensorId.PEDOMETER, (data: sensor.PedometerResponse) => {
        StepSensorService.handleReading(data);
      });

      StepSensorService.startPolling();
    } catch (e) {
      const err = e as BusinessError;
      if (err.code === 201) {
        // 权限不足，sensor 层直接拒绝
        StepSensorService.setStatus(StepSensorStatus.NEED_PERMISSION, '需要动作权限');
      } else {
        StepSensorService.setStatus(StepSensorStatus.ERROR, `订阅失败：${err.message}`);
      }
      StepSensorService.subscribed = false;
      StepSensorService.sensorCallback = null;
    }
    return StepSensorService.status;
  }

  /** 慢速轮询兜底：静止时计步器可能不推数据。 */
  private static startPolling(): void {
    StepSensorService.stopPolling();
    StepSensorService.pollTimer = setInterval(() => {
      try {
        sensor.once(sensor.SensorId.PEDOMETER, (data: sensor.PedometerResponse) => {
          StepSensorService.handleReading(data);
        });
      } catch (e) {
        const err = e as Error;
        hilog.warn(DOMAIN, TAG, 'poll read failed: %{public}s', err.message);
      }
    }, POLL_INTERVAL_MS);
  }

  private static stopPolling(): void {
    if (StepSensorService.pollTimer !== -1) {
      clearInterval(StepSensorService.pollTimer);
      StepSensorService.pollTimer = -1;
    }
  }

  /**
   * 重新校准：把「当前累计值」当作今日零点，今日步数从 0 重新起算。
   *
   * 什么时候需要：用户觉得今天显示的步数明显不对（比如换机、换手、
   * 系统迁移导致累计值对不上）。这时候与其猜，不如给一个显式的重置入口。
   */
  static async recalibrate(ctx: common.UIAbilityContext): Promise<boolean> {
    StepSensorService.ctx = ctx;
    const reading = await StepSensorService.readCurrent();
    if (reading === null) {
      return false;
    }
    const today = todayKey();
    const state = new StepBaselineState(today, reading.cumulative, reading.cumulative,
      Date.now(), reading.bootTimestampNs, DEFAULT_TIMESTAMP_UNIT);
    await StepBaselineRepository.save(ctx, state);
    await ActivityRepository.setSensorSteps(today, 0);
    StepSensorService.lastSteps = 0;
    StepSensorService.lastReason = '已重新校准：今日步数从 0 开始';
    hilog.info(DOMAIN, TAG, 'recalibrated, cumulative=%{public}d', reading.cumulative);
    if (StepSensorService.listener !== null) {
      StepSensorService.listener(0);
    }
    return true;
  }

  /** 读一次当前累计值 */
  private static async readCurrent(): Promise<StepReading | null> {
    return new Promise<StepReading | null>((resolve) => {
      try {
        sensor.once(sensor.SensorId.PEDOMETER, (data: sensor.PedometerResponse) => {
          resolve(new StepReading(data.steps, data.timestamp, Date.now()));
        });
      } catch (e) {
        const err = e as Error;
        hilog.warn(DOMAIN, TAG, 'readCurrent failed: %{public}s', err.message);
        resolve(null);
      }
    });
  }

  static stop(): void {
    StepSensorService.stopPolling();
    if (StepSensorService.flushTimer !== -1) {
      clearInterval(StepSensorService.flushTimer);
      StepSensorService.flushTimer = -1;
    }
    // 停之前把还没落库的那一条补上，别丢掉最后一段步数
    StepSensorService.flush();
    if (StepSensorService.subscribed && StepSensorService.sensorCallback !== null) {
      try {
        sensor.off(sensor.SensorId.PEDOMETER, StepSensorService.sensorCallback);
      } catch (e) {
        const err = e as Error;
        hilog.warn(DOMAIN, TAG, 'sensor.off failed: %{public}s', err.message);
      }
    }
    StepSensorService.subscribed = false;
    StepSensorService.sensorCallback = null;
    StepSensorService.setStatus(StepSensorStatus.IDLE, '已停止');
  }

  /**
   * 收到一次传感器读数。
   *
   * 这里只做「收下最新值」，不直接落库 —— 落库由 flush() 按固定节流间隔做。
   * 直接在这里写库会在模拟器上变成每 150 ms 写一次。
   */
  private static handleReading(data: sensor.PedometerResponse): void {
    StepSensorService.pending = new StepReading(data.steps, data.timestamp, Date.now());
    if (StepSensorService.flushTimer === -1) {
      StepSensorService.flush();
      StepSensorService.flushTimer = setInterval(() => {
        StepSensorService.flush();
      }, FLUSH_INTERVAL_MS);
    }
  }

  /**
   * 把最新读数换算成当日步数并落库。
   *
   * 这条链路是幂等的：同一个累计值重复上报不会改变结果。
   */
  private static async flush(): Promise<void> {
    const reading = StepSensorService.pending;
    if (reading === null) {
      return;
    }
    StepSensorService.pending = null;
    const ctx = StepSensorService.ctx;
    if (ctx === null) {
      return;
    }
    /**
     * 落库前再校验一次同意态。
     *
     * 撤回同意可能发生在采集期间（用户在别的页面撤的），
     * 所以每次写库前都要确认同意还在，否则撤回后数据还在长。
     */
    if (!ConsentState.isAccepted(ctx)) {
      hilog.info(DOMAIN, TAG, 'consent revoked, drop pending reading');
      return;
    }
    try {
      const state = await StepBaselineRepository.load(ctx);
      const result = computeDailySteps(state, reading, todayKey());
      await StepBaselineRepository.save(ctx, result.state);

      const written = await ActivityRepository.setSensorSteps(todayKey(), result.steps);
      StepSensorService.lastSteps = result.steps;
      StepSensorService.lastReason = result.reason;
      hilog.info(DOMAIN, TAG,
        'cumulative=%{public}d steps=%{public}d rebased=%{public}s reason=%{public}s written=%{public}s',
        reading.cumulative, result.steps, `${result.rebased}`, result.reason, `${written}`);

      if (StepSensorService.listener !== null) {
        StepSensorService.listener(result.steps);
      }
    } catch (e) {
      const err = e as Error;
      hilog.error(DOMAIN, TAG, 'flush failed: %{public}s', err.message);
    }
  }
}
