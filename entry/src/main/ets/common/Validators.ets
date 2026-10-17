/**
 * 集中输入校验。所有页面的输入规则都从这里走，禁止各页面自定规则。
 */

import { LIMITS } from './Constants';

export interface ParseResult {
  ok: boolean;
  value: number;
  message: string;
}

function fail(message: string): ParseResult {
  const r: ParseResult = { ok: false, value: 0, message: message };
  return r;
}

function pass(value: number): ParseResult {
  const r: ParseResult = { ok: true, value: value, message: '' };
  return r;
}

/** 通用数值解析：非空、有限数值，再由调用方检查范围 */
function parseNumber(input: string): ParseResult {
  const trimmed = input.trim();
  if (trimmed.length === 0) {
    return fail('输入不能为空');
  }
  const n = Number(trimmed);
  if (!isFinite(n) || isNaN(n)) {
    return fail('请输入有效数字');
  }
  return pass(n);
}

/** 最多一位小数 */
function hasAtMostOneDecimal(input: string): boolean {
  const trimmed = input.trim();
  const dot = trimmed.indexOf('.');
  if (dot < 0) {
    return true;
  }
  return (trimmed.length - dot - 1) <= 1;
}

function isInteger(n: number): boolean {
  return Number.isInteger(n);
}

// ---------- 食物 ----------

export function validateFoodName(input: string): ParseResult {
  const name = input.trim();
  if (name.length < 1 || name.length > LIMITS.foodNameMax) {
    return fail(`食物名称需为 1-${LIMITS.foodNameMax} 字`);
  }
  return pass(0);
}

export function validateWeight(input: string): ParseResult {
  const p = parseNumber(input);
  if (!p.ok) {
    return p;
  }
  if (!hasAtMostOneDecimal(input)) {
    return fail('重量最多一位小数');
  }
  if (p.value <= 0 || p.value > LIMITS.weightMax) {
    return fail(`重量需大于 0 且不超过 ${LIMITS.weightMax}g`);
  }
  return pass(p.value);
}

export function validateKcalPer100g(input: string): ParseResult {
  const p = parseNumber(input);
  if (!p.ok) {
    return p;
  }
  if (!hasAtMostOneDecimal(input)) {
    return fail('每100g热量最多一位小数');
  }
  if (p.value < 0 || p.value > LIMITS.kcalPer100gMax) {
    return fail(`每100g热量需在 0-${LIMITS.kcalPer100gMax} kcal 之间`);
  }
  return pass(p.value);
}

// ---------- 运动 ----------

export function validateDuration(input: string): ParseResult {
  const p = parseNumber(input);
  if (!p.ok) {
    return p;
  }
  if (!isInteger(p.value)) {
    return fail('时长需为整数分钟');
  }
  if (p.value < 1 || p.value > LIMITS.durationMax) {
    return fail(`时长需在 1-${LIMITS.durationMax} 分钟之间`);
  }
  return pass(p.value);
}

export function validateBurned(input: string): ParseResult {
  const p = parseNumber(input);
  if (!p.ok) {
    return p;
  }
  if (!isInteger(p.value)) {
    return fail('消耗热量需为整数');
  }
  if (p.value < 0 || p.value > LIMITS.burnedMax) {
    return fail(`消耗热量需在 0-${LIMITS.burnedMax} kcal 之间`);
  }
  return pass(p.value);
}

export function validateSteps(input: string): ParseResult {
  const p = parseNumber(input);
  if (!p.ok) {
    return p;
  }
  if (!isInteger(p.value)) {
    return fail('步数需为整数');
  }
  if (p.value < 0 || p.value > LIMITS.stepsMax) {
    return fail(`步数需在 0-${LIMITS.stepsMax} 之间`);
  }
  return pass(p.value);
}

// ---------- 目标 ----------

export function validateBudget(input: string): ParseResult {
  const p = parseNumber(input);
  if (!p.ok) {
    return p;
  }
  if (!isInteger(p.value) || p.value < 1 || p.value > LIMITS.budgetMax) {
    return fail(`饮食预算需为 1-${LIMITS.budgetMax} 的整数`);
  }
  return pass(p.value);
}

export function validateStepsGoal(input: string): ParseResult {
  const p = parseNumber(input);
  if (!p.ok) {
    return p;
  }
  if (!isInteger(p.value) || p.value < 1 || p.value > LIMITS.stepsGoalMax) {
    return fail(`步数目标需为 1-${LIMITS.stepsGoalMax} 的整数`);
  }
  return pass(p.value);
}

export function validateMinutesGoal(input: string): ParseResult {
  const p = parseNumber(input);
  if (!p.ok) {
    return p;
  }
  if (!isInteger(p.value) || p.value < 1 || p.value > LIMITS.minutesGoalMax) {
    return fail(`运动时长目标需为 1-${LIMITS.minutesGoalMax} 的整数`);
  }
  return pass(p.value);
}

export function validateActivityKcalGoal(input: string): ParseResult {
  const p = parseNumber(input);
  if (!p.ok) {
    return p;
  }
  if (!isInteger(p.value) || p.value < 1 || p.value > LIMITS.activityKcalGoalMax) {
    return fail(`活动热量目标需为 1-${LIMITS.activityKcalGoalMax} 的整数`);
  }
  return pass(p.value);
}
