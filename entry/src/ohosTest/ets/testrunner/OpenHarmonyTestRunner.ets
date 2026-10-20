import { abilityDelegatorRegistry, TestRunner } from '@kit.TestKit';
import { UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

let abilityDelegator: abilityDelegatorRegistry.AbilityDelegator;
let abilityDelegatorArguments: abilityDelegatorRegistry.AbilityDelegatorArgs;
const TAG = 'testTag';
/** ohosTest 模块名，与 entry/src/ohosTest/module.json5 里的 module.name 一致 */
const TEST_MODULE_NAME: string = 'entry_test';

async function onAbilityCreateCallback(data: UIAbility) {
  hilog.info(0x0000, TAG, 'onAbilityCreateCallback, data: %{public}s', JSON.stringify(data));
}

async function addAbilityMonitorCallback(err: BusinessError) {
  // 成功时 err 是 null，直接读 err.message 会抛 TypeError 把整个测试进程带走
  if (err !== null && err !== undefined) {
    hilog.info(0x0000, TAG, 'addAbilityMonitorCallback : %{public}s', err.message);
  }
}

export default class OpenHarmonyTestRunner implements TestRunner {
  constructor() {
  }

  onPrepare() {
    hilog.info(0x0000, TAG, '%{public}s', 'OpenHarmonyTestRunner OnPrepare');
  }

  async onRun() {
    abilityDelegatorArguments = abilityDelegatorRegistry.getArguments();
    abilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();

    // 把命令行动参整个打出来。aa test 的参数解析在不同版本上不一致，
    // '-m' 有时取不到，直接崩在 startAbility 上，日志都不剩一条。
    hilog.info(0x0000, TAG, 'arguments: %{public}s', JSON.stringify(abilityDelegatorArguments));

    // '-m' 缺失时用模块名兜底，别让整个测试因为一个参数挂掉
    let moduleName: string = TEST_MODULE_NAME;
    const params = abilityDelegatorArguments.parameters;
    if (params !== undefined && params['-m'] !== undefined && params['-m'].length > 0) {
      moduleName = params['-m'];
    }
    const bundleName: string = abilityDelegatorArguments.bundleName;
    hilog.info(0x0000, TAG, 'bundle=%{public}s module=%{public}s', bundleName, moduleName);

    const testAbilityName: string = 'TestAbility';
    const lMonitor: abilityDelegatorRegistry.AbilityMonitor = {
      abilityName: testAbilityName,
      onAbilityCreate: onAbilityCreateCallback,
      moduleName: moduleName
    };
    abilityDelegator.addAbilityMonitor(lMonitor, addAbilityMonitorCallback);

    const want: Want = {
      bundleName: bundleName,
      abilityName: testAbilityName,
      moduleName: moduleName
    };
    try {
      abilityDelegator.startAbility(want, (err: BusinessError) => {
        // 成功时 err 为 null，不能无条件读 err.message
        if (err !== null && err !== undefined) {
          hilog.error(0x0000, TAG, 'startAbility : err : %{public}s', err.message);
        } else {
          hilog.info(0x0000, TAG, '%{public}s', 'startAbility : ok');
        }
      });
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, TAG, 'startAbility failed: code=%{public}d %{public}s', err.code, err.message);
    }
    hilog.info(0x0000, TAG, '%{public}s', 'OpenHarmonyTestRunner onRun end');
  }
}
