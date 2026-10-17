/**
 * 图片获取服务：
 * - 相册选图：PhotoViewPicker（安全组件，无需相册权限）
 * - 拍照：cameraPicker（系统托管安全组件，无需 ohos.permission.CAMERA）
 * 取消/失败返回 null 或抛可识别错误。
 */

import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { camera } from '@kit.CameraKit';
import cameraPicker from '@ohos.multimedia.cameraPicker';
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

  static async captureImage(context: Context): Promise<string | null> {
    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
      };
      const result = await cameraPicker.pick(context,
        [cameraPicker.PickerMediaType.PHOTO], profile);
      if (result.resultCode === 0 && result.resultUri.length > 0) {
        return result.resultUri;
      }
      // 用户取消或未产出图片
      return null;
    } catch (e) {
      throw new AiError(AiErrorCode.CAMERA_UNAVAILABLE);
    }
  }
}