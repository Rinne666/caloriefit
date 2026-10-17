/**
 * 图片处理：读取 Picker URI → 缩放至长边 ≤1280 → 转 JPEG → 压缩至 ≤2MB → Base64 Data URL。
 */

import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { AiImagePayload } from '../models/AiImagePayload';
import { AiErrorCode, AiError, AiImageLimits } from '../common/AiConstants';

export class ImageProcessor {
  static async prepareImage(uri: string): Promise<AiImagePayload> {
    let file = null as fileIo.File | null;
    try {
      file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    } catch (e) {
      throw new AiError(AiErrorCode.IMAGE_INVALID);
    }
    const source = image.createImageSource(file.fd);
    if (source === undefined || source === null) {
      fileIo.closeSync(file);
      throw new AiError(AiErrorCode.IMAGE_INVALID);
    }
    try {
      const info = await source.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;
      const maxSide = Math.max(width, height);
      let desiredSize: image.Size | undefined = undefined;
      if (maxSide > AiImageLimits.MAX_LONG_SIDE) {
        const scale = AiImageLimits.MAX_LONG_SIDE / maxSide;
        desiredSize = {
          width: Math.max(1, Math.round(width * scale)),
          height: Math.max(1, Math.round(height * scale))
        };
      }
      const decodingOptions: image.DecodingOptions = {
        desiredSize: desiredSize
      };
      const pixelMap = await source.createPixelMap(decodingOptions);
      const packer = image.createImagePacker();
      let quality = AiImageLimits.INITIAL_QUALITY;
      let packed = await packer.packToData(pixelMap, {
        format: 'image/jpeg',
        quality: quality
      });
      while (packed.byteLength > AiImageLimits.MAX_BYTES && quality > AiImageLimits.MIN_QUALITY) {
        quality -= 25;
        packed = await packer.packToData(pixelMap, {
          format: 'image/jpeg',
          quality: quality
        });
      }
      const finalWidth = desiredSize !== undefined ? desiredSize.width : width;
      const finalHeight = desiredSize !== undefined ? desiredSize.height : height;
      packer.release();
      pixelMap.release();
      source.release();
      if (packed.byteLength > AiImageLimits.MAX_BYTES) {
        throw new AiError(AiErrorCode.IMAGE_TOO_LARGE);
      }
      const helper = new util.Base64Helper();
      const base64 = helper.encodeToStringSync(new Uint8Array(packed));
      return new AiImagePayload(
        'image/jpeg',
        `data:image/jpeg;base64,${base64}`,
        finalWidth,
        finalHeight,
        packed.byteLength
      );
    } catch (e) {
      if (e instanceof AiError) {
        throw e;
      }
      source.release();
      throw new AiError(AiErrorCode.IMAGE_INVALID);
    } finally {
      fileIo.closeSync(file);
    }
  }
}