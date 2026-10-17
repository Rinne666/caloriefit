/**
 * 上传给模型的图片负载。Base64 仅存在于识别过程的内存中。
 */

export class AiImagePayload {
  mimeType: string;
  base64DataUrl: string;
  width: number;
  height: number;
  byteLength: number;

  constructor(mimeType: string, base64DataUrl: string,
    width: number, height: number, byteLength: number) {
    this.mimeType = mimeType;
    this.base64DataUrl = base64DataUrl;
    this.width = width;
    this.height = height;
    this.byteLength = byteLength;
  }
}