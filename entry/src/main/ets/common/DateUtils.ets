/**
 * 本地日期工具。业务日期统一用本地日历日期 YYYY-MM-DD。
 * 禁止使用 toISOString()（UTC 跨日偏差）。
 */

export function toDateKey(date: Date): string {
  const y = date.getFullYear();
  const m = (date.getMonth() + 1).toString().padStart(2, '0');
  const d = date.getDate().toString().padStart(2, '0');
  return `${y}-${m}-${d}`;
}

export function todayKey(): string {
  return toDateKey(new Date());
}

/** dateKey 必须是合法的 YYYY-MM-DD */
export function parseDateKey(key: string): Date {
  const parts = key.split('-');
  const y = parseInt(parts[0], 10);
  const mo = parseInt(parts[1], 10) - 1;
  const d = parseInt(parts[2], 10);
  return new Date(y, mo, d);
}

/** 是否为未来日期（不允许添加未来记录） */
export function isFutureDate(key: string): boolean {
  return key > todayKey();
}

/** 格式化为 "2026年10月17日 · 星期六" */
export function displayDate(key: string): string {
  const date = parseDateKey(key);
  const weekdays: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
  const y = date.getFullYear();
  const m = date.getMonth() + 1;
  const d = date.getDate();
  const w = weekdays[date.getDay()];
  return `${y}年${m}月${d}日 · ${w}`;
}

/** 千分位格式化整数 */
export function formatNumber(n: number): string {
  const fixed = Math.round(n).toString();
  return fixed.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}
