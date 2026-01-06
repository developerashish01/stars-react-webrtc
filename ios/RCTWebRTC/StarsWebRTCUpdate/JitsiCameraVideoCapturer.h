//
//  JitsiCameraVideoCapturer.h
//  Pods
//
//  Created by Amzad Khan on 11/10/25.
//

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <WebRTC/RTCMacros.h>
#import <WebRTC/RTCVideoCapturer.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A custom capturer that overrides key RTCCameraVideoCapturer methods.
 * This class serves as a blueprint for a fully customized capture implementation.
 *
 */
@interface JitsiCameraVideoCapturer : RTCVideoCapturer

// Capture session that is used for capturing. Valid from initialization to dealloc.
@property(readonly, nonatomic) AVCaptureSession *captureSession;
// Returns list of available capture devices that support video capture.
+ (NSArray<AVCaptureDevice *> *)captureDevices;
// Returns list of formats that are supported by this class for this device.
+ (NSArray<AVCaptureDeviceFormat *> *)supportedFormatsForDevice:(AVCaptureDevice *)device;
// Returns the most efficient supported output pixel format for this capturer.
- (FourCharCode)preferredOutputPixelFormat;
// Starts the capture session asynchronously and notifies callback on completion.
// The device will capture video in the format given in the `format` parameter. If the pixel format
// in `format` is supported by the WebRTC pipeline, the same pixel format will be used for the
// output. Otherwise, the format returned by `preferredOutputPixelFormat` will be used.
- (void)startCaptureWithDevice:(AVCaptureDevice *)device
                        format:(AVCaptureDeviceFormat *)format
                           fps:(NSInteger)fps
             completionHandler:(nullable void (^)(NSError *_Nullable))completionHandler;
// Stops the capture session asynchronously and notifies callback on completion.
- (void)stopCaptureWithCompletionHandler:(nullable void (^)(void))completionHandler;
// Starts the capture session asynchronously.
- (void)startCaptureWithDevice:(AVCaptureDevice *)device
                        format:(AVCaptureDeviceFormat *)format
                           fps:(NSInteger)fps;
// Stops the capture session asynchronously.
- (void)stopCapture;
- (BOOL)setupCaptureSession;

@end

NS_ASSUME_NONNULL_END
