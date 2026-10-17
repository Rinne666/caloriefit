/**
 * 运动数据来源接口。未来接入 Health Service Kit 时新增实现即可，不改 UI。
 */

import { DailyActivity } from '../models/DailyActivity';

export interface ActivityDataSource {
  getDailyActivity(date: string): Promise<DailyActivity>;
}
