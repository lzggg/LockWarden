/**
 * 设备是否支持扫码。
 *
 * 注意 syscap 名称是 SDK 里 @syscap 标明的值：
 *   - scanBarcode -> SystemCapability.Multimedia.Scan.ScanBarcode
 *   - scanCore    -> SystemCapability.Multimedia.Scan.Core
 * 之前把 syscap 名写成了不存在的 "ScanKit"，在真机上恒为 false，
 * 导致支持扫码的手机也提示"不支持"。
 */
export function scanSupported(): boolean {
  return canIUse('SystemCapability.Multimedia.Scan.ScanBarcode') &&
    canIUse('SystemCapability.Multimedia.Scan.Core');
}
