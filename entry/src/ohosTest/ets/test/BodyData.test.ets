/**
 * 体征档案输入校验与换算的单元测试。
 *
 * 跑的是**真实的生产代码** `common/Validators.ets` 与 `models/Calculation.ets`。
 *
 * 重点是 `bodyFatPercentText`：体脂率用 `toFixed(1)` 会产出 "22.0"，而
 * `InputType.NUMBER_DECIMAL` 的输入框会把小数点吞掉 —— 实测 0.22 回显成
 * "220"，0.20 回显成 "200"，手动输入 22.5 变成 "225"。220 会被当成 220%
 * 存回去（→ 2.2），超出合法范围后保存直接被拒。这个函数就是那条防线。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  validateBodyWeight, validateBodyHeight, validateBodyAge, validateBodyFat
} from '../../../main/ets/common/Validators';
import { bodyFatPercentText } from '../../../main/ets/models/Calculation';

export default function bodyDataTest() {
  describe('BodyDataTest', () => {

    it('体脂率_整数值_不带多余小数位', 0, () => {
      // 0.22 → "22"，不能是 "22.0"（小数点会被输入框吞掉）
      expect(bodyFatPercentText(0.22)).assertEqual('22');
      expect(bodyFatPercentText(0.2)).assertEqual('20');
      expect(bodyFatPercentText(0.225)).assertEqual('22.5');
      expect(bodyFatPercentText(0.155)).assertEqual('15.5');
    });

    it('体脂率_空值_返回空串', 0, () => {
      expect(bodyFatPercentText(null)).assertEqual('');
    });

    it('体脂率_结果不含尾零小数', 0, () => {
      // 回归防线：任何情况下都不该出现 "22.0" 这种尾零
      expect(bodyFatPercentText(0.22).indexOf('.0')).assertEqual(-1);
    });

    it('体重_接受合理值', 0, () => {
      expect(validateBodyWeight('68').ok).assertTrue();
      expect(validateBodyWeight('68.5').ok).assertTrue();
      expect(validateBodyWeight('68.5').value).assertEqual(68.5);
    });

    it('体重_拒绝空与非数字', 0, () => {
      expect(validateBodyWeight('').ok).assertFalse();
      expect(validateBodyWeight('abc').ok).assertFalse();
    });

    it('体重_拒绝越界与两位小数', 0, () => {
      expect(validateBodyWeight('0').ok).assertFalse();
      expect(validateBodyWeight('-5').ok).assertFalse();
      expect(validateBodyWeight('301').ok).assertFalse();
      expect(validateBodyWeight('68.55').ok).assertFalse();
    });

    it('身高_接受整数', 0, () => {
      expect(validateBodyHeight('175').ok).assertTrue();
      expect(validateBodyHeight('175').value).assertEqual(175);
    });

    it('身高_拒绝小数空与越界', 0, () => {
      expect(validateBodyHeight('175.5').ok).assertFalse();
      expect(validateBodyHeight('').ok).assertFalse();
      expect(validateBodyHeight('0').ok).assertFalse();
      expect(validateBodyHeight('251').ok).assertFalse();
    });

    it('年龄_接受合理值', 0, () => {
      expect(validateBodyAge('32').ok).assertTrue();
      expect(validateBodyAge('32').value).assertEqual(32);
    });

    it('年龄_拒绝小数空与越界', 0, () => {
      expect(validateBodyAge('32.5').ok).assertFalse();
      expect(validateBodyAge('').ok).assertFalse();
      expect(validateBodyAge('0').ok).assertFalse();
      expect(validateBodyAge('121').ok).assertFalse();
    });

    it('体脂率_留空视为未填', 0, () => {
      expect(validateBodyFat('').ok).assertTrue();
      expect(validateBodyFat('   ').ok).assertTrue();
    });

    it('体脂率_接受合理区间', 0, () => {
      expect(validateBodyFat('22').ok).assertTrue();
      expect(validateBodyFat('22.5').ok).assertTrue();
    });

    it('体脂率_拒绝0与70以上', 0, () => {
      expect(validateBodyFat('0').ok).assertFalse();
      expect(validateBodyFat('70').ok).assertFalse();
      expect(validateBodyFat('75').ok).assertFalse();
    });

    it('体脂率_拒绝非数字', 0, () => {
      expect(validateBodyFat('abc').ok).assertFalse();
    });
  });
}
