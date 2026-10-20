/**
 * 每日步数记录。date 为主键，每天最多一条。
 *
 * source 区分这个数是怎么来的：
 *   · SENSOR_PEDOMETER —— 由计步传感器自动采集
 *   · MANUAL_SIMULATED —— 用户手动填写/校正
 *
 * 手动值优先级更高：一旦当天被手动改过，传感器就不再覆盖，
 * 除非用户主动点「恢复自动采集」。
 */

/** 计步传感器自动采集 */
export const STEP_SOURCE_SENSOR: string = 'SENSOR_PEDOMETER';
/** 用户手动填写或校正 */
export const STEP_SOURCE_MANUAL: string = 'MANUAL_SIMULATED';

export class DailyActivity {
  date: string;
  steps: number;
  source: string;
  updatedAt: number;

  constructor(date: string, steps: number, source: string, updatedAt: number) {
    this.date = date;
    this.steps = steps;
    this.source = source;
    this.updatedAt = updatedAt;
  }
}

/** 界面上的来源角标文案 */
export function stepSourceLabel(source: string): string {
  if (source === STEP_SOURCE_SENSOR) {
    return '传感器自动';
  }
  if (source === STEP_SOURCE_MANUAL) {
    return '手动校正';
  }
  return '未采集';
}
