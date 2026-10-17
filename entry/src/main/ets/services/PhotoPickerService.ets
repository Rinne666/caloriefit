/**
 * 相册选图服务：PhotoViewPicker 单张图片，取消返回 null。
 */

import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AiErrorCode, AiError } from '../common/AiConstants';

export class PhotoPickerService {
  static async selectOneImage(): Promise<string | null> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });
      if (result.photoUris.length === 0) {
        return null;
      }
      return result.photoUris[0];
    } catch (e) {
      throw new AiError(AiErrorCode.IMAGE_INVALID);
    }
  }
}