/**
 * 统一弹窗服务：封装 @pura/harmony-dialog，业务页面不直接依赖第三方库。
 * 若组件库异常，退回系统 Toast/AlertDialog 语义（此处直接包装，异常向上抛出由页面兜底）。
 */

import { DialogHelper, DialogAction, LoadingOptions, AlertOptions } from '@pura/harmony-dialog';
import { color, fontSize } from '../common/DesignTokens';

export class AppDialogService {
  /** 显示加载弹窗，返回 dialogId 用于关闭 */
  static showLoading(text: string): string {
    const options: LoadingOptions = {
      content: text,
      loadSize: 52,
      loadColor: color.primary,
      fontSize: fontSize.body,
      fontColor: color.text
    };
    return DialogHelper.showLoadingDialog(options);
  }

  static closeLoading(dialogId: string): void {
    DialogHelper.closeDialog(dialogId);
  }

  static toast(message: string): void {
    DialogHelper.showToast(message);
  }

  /**
   * 危险操作确认（取消 / 确认）。
   *
   * ## action 的取值不是「0/1」
   * `@pura/harmony-dialog` 的 `onAction` 约定是：
   *   · action < 0  → 按钮的 `DialogAction` 枚举值
   *   · action >= 0 → 选项索引（仅选择型弹窗）
   * 确认按钮（`secondaryButton`）回调的是 `DialogAction.TWO = -2`，
   * 取消按钮（`primaryButton`）回调 `DialogAction.ONE = -1`。
   *
   * 之前这里判的是 `action === 1`，永远不成立 —— 于是**所有**走这个封装的
   * 确认框点了「确认」都没反应（删记录、清除 API Key、退出登录都受影响）。
   * 必须用依赖导出的 `DialogAction.SURE`，不要写魔法数字。
   */
  static confirm(title: string, message: string,
    confirmText: string, onConfirm: () => void): void {
    const options: AlertOptions = {
      primaryTitle: title,
      content: message,
      primaryButton: {
        value: '取消',
        fontColor: color.textSecondary
      },
      secondaryButton: {
        value: confirmText,
        fontColor: color.danger
      },
      onAction: (action: number, dialogId: string) => {
        if (action === DialogAction.SURE) {
          onConfirm();
        }
      }
    };
    DialogHelper.showAlertDialog(options);
  }
}