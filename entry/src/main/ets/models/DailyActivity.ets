/**
 * 每日模拟步数。date 为主键，每天最多一条记录。
 */

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
