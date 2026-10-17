/**
 * 统一弹窗服务：封装 @pura/harmony-dialog，业务页面不直接依赖第三方库。
 * 若组件库异常，退回系统 Toast/AlertDialog 语义（此处直接包装，异常向上抛出由页面兜底）。
 */

import { DialogHelper, LoadingOptions, AlertOptions } from '@pura/harmony-dialog';
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

  /** 危险操作确认（取消 / 确认），onAction: 0=左侧取消 1=右侧确认 */
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
        if (action === 1) {
          onConfirm();
        }
      }
    };
    DialogHelper.showAlertDialog(options);
  }
}