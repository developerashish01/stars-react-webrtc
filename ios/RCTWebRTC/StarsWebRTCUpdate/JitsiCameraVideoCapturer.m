//
//  JitsiCameraVideoCapturer.m
//  Pods
//
//  Created by Amzad Khan on 11/10/25.
//
#import <React/RCTLog.h>
#import "JitsiCameraVideoCapturer.h"
#import "JitsiCaptureInjector.h"
#import <AVFoundation/AVFoundation.h>

//--------------
#import <Foundation/Foundation.h>
#import "WebRTC/RTCLogging.h"
#import "WebRTC/RTCVideoFrameBuffer.h"
#import <WebRTC/RTCCVPixelBuffer.h>
#if TARGET_OS_IPHONE
#import "WebRTC/UIDevice+RTCDevice.h"

#endif
//#import "RTCDispatcher+Private.h"
#import "JitsiDispatcher.h"
#import "AVCaptureSession_Jitsi.h"

const int64_t kNanosecondsPerSecond = 1000000000;
//static inline BOOL IsMediaSubTypeSupported(FourCharCode mediaSubType) {
//    return (mediaSubType == kCVPixelFormatType_420YpCbCr8PlanarFullRange ||
//            mediaSubType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
//}

static inline BOOL IsMediaSubTypeSupported(FourCharCode mediaSubType) {
    return (mediaSubType == kCVPixelFormatType_32BGRA);
}

@interface JitsiCameraVideoCapturer ()<AVCaptureVideoDataOutputSampleBufferDelegate>
@property(nonatomic, readonly) dispatch_queue_t frameQueue;
@end


@implementation JitsiCameraVideoCapturer {
    AVCaptureVideoDataOutput *_videoDataOutput;
    AVCaptureSession *_captureSession;
    AVCaptureDevice *_currentDevice;
    BOOL _hasRetriedOnFatalError;
    BOOL _isRunning;
    FourCharCode _preferredOutputPixelFormat;
    FourCharCode _outputPixelFormat;
    RTCVideoRotation _rotation;
    
    // Will the session be running once all asynchronous operations have been completed?
    BOOL _willBeRunning;
#if TARGET_OS_IPHONE
    UIDeviceOrientation _orientation;
#endif
}


@synthesize frameQueue = _frameQueue;
@synthesize captureSession = _captureSession;
- (instancetype)initWithDelegate:(__weak id<RTCVideoCapturerDelegate>)delegate {
    if (self = [super initWithDelegate:delegate]) {
        // Create the capture session and all relevant inputs and outputs. We need
        // to do this in init because the application may want the capture session
        // before we start the capturer for e.g. AVCapturePreviewLayer. All objects
        // created here are retained until dealloc and never recreated.
        if (![self setupCaptureSession]) {
            return nil;
        }
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
#if TARGET_OS_IPHONE
        _orientation = UIDeviceOrientationPortrait;
        _rotation = RTCVideoRotation_90;
        [center addObserver:self
                   selector:@selector(deviceOrientationDidChange:)
                       name:UIDeviceOrientationDidChangeNotification
                     object:nil];
        [center addObserver:self
                   selector:@selector(handleCaptureSessionInterruption:)
                       name:AVCaptureSessionWasInterruptedNotification
                     object:_captureSession];
        [center addObserver:self
                   selector:@selector(handleCaptureSessionInterruptionEnded:)
                       name:AVCaptureSessionInterruptionEndedNotification
                     object:_captureSession];
        [center addObserver:self
                   selector:@selector(handleApplicationDidBecomeActive:)
                       name:UIApplicationDidBecomeActiveNotification
                     object:[UIApplication sharedApplication]];
#endif
        [center addObserver:self
                   selector:@selector(handleCaptureSessionRuntimeError:)
                       name:AVCaptureSessionRuntimeErrorNotification
                     object:_captureSession];
        [center addObserver:self
                   selector:@selector(handleCaptureSessionDidStartRunning:)
                       name:AVCaptureSessionDidStartRunningNotification
                     object:_captureSession];
        [center addObserver:self
                   selector:@selector(handleCaptureSessionDidStopRunning:)
                       name:AVCaptureSessionDidStopRunningNotification
                     object:_captureSession];
    }
    return self;
}

- (void)dealloc {
    NSAssert(
             !_willBeRunning,
             @"Session was still running in RTCCameraVideoCapturer dealloc. Forgot to call stopCapture?");
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
+ (NSArray<AVCaptureDevice *> *)captureDevices {
    //return [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    // 1. Define the device types you are interested in
    NSArray<AVCaptureDeviceType> *deviceTypes = @[
        AVCaptureDeviceTypeBuiltInWideAngleCamera,
        AVCaptureDeviceTypeBuiltInTelephotoCamera,
        //AVCaptureDeviceTypeExternalUnknown // Include external devices
    ];

    // 2. Create the discovery session
    AVCaptureDeviceDiscoverySession *discoverySession =
        [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:deviceTypes
                                                              mediaType:AVMediaTypeVideo
                                                               position:AVCaptureDevicePositionUnspecified];

    // 3. Get the array of available devices
    return discoverySession.devices;
}
- (FourCharCode)preferredOutputPixelFormat {
  return _preferredOutputPixelFormat;
}

+ (NSArray<AVCaptureDeviceFormat *> *)supportedFormatsForDevice:(AVCaptureDevice *)device {
    NSMutableArray<AVCaptureDeviceFormat *> *eligibleDeviceFormats = [NSMutableArray array];
    for (AVCaptureDeviceFormat *format in device.formats) {
        // Filter out subTypes that we currently don't support in the stack
        FourCharCode mediaSubType = CMFormatDescriptionGetMediaSubType(format.formatDescription);
        if (IsMediaSubTypeSupported(mediaSubType)) {
            [eligibleDeviceFormats addObject:format];
        }
    }
    return eligibleDeviceFormats;
}
- (void)startCaptureWithDevice:(AVCaptureDevice *)device
                        format:(AVCaptureDeviceFormat *)format
                           fps:(NSInteger)fps {
    _willBeRunning = YES;
    [JitsiDispatcher
     dispatchAsyncOnType:RTCDispatcherTypeCaptureSession
     block:^{
        RTCLogInfo("startCaptureWithDevice %@ @ %ld fps", format, (long)fps);
#if TARGET_OS_IPHONE
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
#endif
        _currentDevice = device;
        NSError *error = nil;
        if (![_currentDevice lockForConfiguration:&error]) {
            RTCLogError(
                        @"Failed to lock device %@. Error: %@", _currentDevice, error.userInfo);
            return;
        }
        [self reconfigureCaptureSessionInput];
        [self updateOrientation];
        [self updateDeviceCaptureFormat:format fps:fps];
        [_captureSession startRunning];
        [_currentDevice unlockForConfiguration];
        _isRunning = YES;
    }];
}
- (void)startCaptureWithDevice:(AVCaptureDevice *)device
                        format:(AVCaptureDeviceFormat *)format
                           fps:(NSInteger)fps
             completionHandler:(nullable void (^)(NSError *))completionHandler {
    _willBeRunning = YES;
    [JitsiDispatcher
     dispatchAsyncOnType:RTCDispatcherTypeCaptureSession
     block:^{
        RTCLogInfo("startCaptureWithDevice %@ @ %ld fps", format, (long)fps);
#if TARGET_OS_IPHONE
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
#endif
        _currentDevice = device;
        NSError *error = nil;
        if (![_currentDevice lockForConfiguration:&error]) {
            RTCLogError(
                        @"Failed to lock device %@. Error: %@", _currentDevice, error.userInfo);
            if (completionHandler) {
                completionHandler(error);
            }
            return;
        }
        [self reconfigureCaptureSessionInput];
        [self updateOrientation];
        [self updateDeviceCaptureFormat:format fps:fps];
        [self updateVideoDataOutputPixelFormat:format];
        [_captureSession startRunning];
        [_currentDevice unlockForConfiguration];
        _isRunning = YES;
        if (completionHandler) {
            completionHandler(nil);
        }
    }];
}
- (void)stopCapture {
    _willBeRunning = NO;
    [JitsiDispatcher
     dispatchAsyncOnType:RTCDispatcherTypeCaptureSession
     block:^{
        RTCLogInfo("Stop");
        _currentDevice = nil;
        for (AVCaptureDeviceInput *oldInput in [_captureSession.inputs copy]) {
            [_captureSession removeInput:oldInput];
        }
        [_captureSession stopRunning];
#if TARGET_OS_IPHONE
        [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
#endif
        _isRunning = NO;
    }];
}
- (void)stopCaptureWithCompletionHandler:(nullable void (^)())completionHandler {
  _willBeRunning = NO;
  [JitsiDispatcher
      dispatchAsyncOnType:RTCDispatcherTypeCaptureSession
                    block:^{
                      RTCLogInfo("Stop");
                      _currentDevice = nil;
                      for (AVCaptureDeviceInput *oldInput in [_captureSession.inputs copy]) {
                        [_captureSession removeInput:oldInput];
                      }
                      [_captureSession stopRunning];
#if TARGET_OS_IPHONE
                      [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
#endif
                      _isRunning = NO;
                      if (completionHandler) {
                        completionHandler();
                      }
                    }];
}

#pragma mark iOS notifications
#if TARGET_OS_IPHONE
- (void)deviceOrientationDidChange:(NSNotification *)notification {
    [JitsiDispatcher dispatchAsyncOnType:RTCDispatcherTypeCaptureSession
                                   block:^{
        [self updateOrientation];
    }];
}
#endif
#pragma mark AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    NSParameterAssert(captureOutput == _videoDataOutput);
    if (CMSampleBufferGetNumSamples(sampleBuffer) != 1 || !CMSampleBufferIsValid(sampleBuffer) ||
        !CMSampleBufferDataIsReady(sampleBuffer)) {
        return;
    }
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (pixelBuffer == nil) {
        return;
    }
#if TARGET_OS_IPHONE
    // Default to portrait orientation on iPhone.
    RTCVideoRotation rotation = RTCVideoRotation_90;
    BOOL usingFrontCamera = NO;
    // Check the image's EXIF for the camera the image came from as the image could have been
    // delayed as we set alwaysDiscardsLateVideoFrames to NO.
    AVCaptureDevicePosition cameraPosition =
    [AVCaptureSession devicePositionForSampleBuffer:sampleBuffer];
    if (cameraPosition != AVCaptureDevicePositionUnspecified) {
        usingFrontCamera = AVCaptureDevicePositionFront == cameraPosition;
    } else {
        AVCaptureDeviceInput *deviceInput =
        (AVCaptureDeviceInput *)((AVCaptureInputPort *)connection.inputPorts.firstObject).input;
        usingFrontCamera = AVCaptureDevicePositionFront == deviceInput.device.position;
    }
    switch (_orientation) {
        case UIDeviceOrientationPortrait:
            rotation = RTCVideoRotation_90;
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            rotation = RTCVideoRotation_270;
            break;
        case UIDeviceOrientationLandscapeLeft:
            rotation = usingFrontCamera ? RTCVideoRotation_180 : RTCVideoRotation_0;
            break;
        case UIDeviceOrientationLandscapeRight:
            rotation = usingFrontCamera ? RTCVideoRotation_0 : RTCVideoRotation_180;
            break;
        case UIDeviceOrientationFaceUp:
        case UIDeviceOrientationFaceDown:
        case UIDeviceOrientationUnknown:
            // Ignore.
            break;
    }
    _rotation = rotation;
#else
    // No rotation on Mac.
    RTCVideoRotation rotation = RTCVideoRotation_0;
#endif
    RTCCVPixelBuffer *rtcPixelBuffer = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:pixelBuffer];
    int64_t timeStampNs = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) *
    kNanosecondsPerSecond;
    RTCVideoFrame *videoFrame = [[RTCVideoFrame alloc] initWithBuffer:rtcPixelBuffer
                                                             rotation:rotation
                                                          timeStampNs:timeStampNs];
    
    RTCVideoFrame *videoFrame2 = [[[JitsiCaptureInjector shared] cameraVideoCapturerSource] processframeCaptured:videoFrame];
    
    if(videoFrame2 != nil) {
        [self.delegate capturer:self didCaptureVideoFrame:videoFrame2];
    }else {
        [self.delegate capturer:self didCaptureVideoFrame:videoFrame];
    }
}
- (void)captureOutput:(AVCaptureOutput *)captureOutput
  didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    RTCLogError(@"Dropped sample buffer.");
}
#pragma mark - AVCaptureSession notifications
- (void)handleCaptureSessionInterruption:(NSNotification *)notification {
    NSString *reasonString = nil;
#if defined(__IPHONE_9_0) && defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && \
__IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_9_0

    if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){9, 0, 0}]) {
        NSNumber *reason = notification.userInfo[AVCaptureSessionInterruptionReasonKey];
        if (reason) {
            switch (reason.intValue) {
                case AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableInBackground:
                    reasonString = @"VideoDeviceNotAvailableInBackground";
                    break;
                case AVCaptureSessionInterruptionReasonAudioDeviceInUseByAnotherClient:
                    reasonString = @"AudioDeviceInUseByAnotherClient";
                    break;
                case AVCaptureSessionInterruptionReasonVideoDeviceInUseByAnotherClient:
                    reasonString = @"VideoDeviceInUseByAnotherClient";
                    break;
                case AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableWithMultipleForegroundApps:
                    reasonString = @"VideoDeviceNotAvailableWithMultipleForegroundApps";
                    break;
            }
        }
    }
    
    if (@available(iOS 16.0, *)) {
            NSNumber *reason = notification.userInfo[AVCaptureSessionInterruptionReasonKey];

            // Check for the specific reason that occurs when backgrounding without a proper PiP/Camera entitlement setup.
            // Since the entitlement IS present, we consider this interruption harmless for PiP.
            if (reason && reason.intValue == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableInBackground) {
                
                // Check if multitasking access is enabled (which you've confirmed it is).
                if (_captureSession.multitaskingCameraAccessEnabled) {
                    
                    // 🛑 CRITICAL: Do NOT process this interruption further.
                    // The AVFoundation session might stop, but the expectation is that
                    // the PiP system will immediately take over and resume it using the
                    // multitasking capability.
                    RTCLogWarning(@"Ignoring 'VideoDeviceNotAvailableInBackground' for PiP.");
                    return;
                }
            }
        }
    
#endif
    RTCLog(@"Capture session interrupted: %@", reasonString);
}
- (void)handleCaptureSessionInterruptionEnded:(NSNotification *)notification {
    RTCLog(@"Capture session interruption ended.");
    
}
- (void)handleCaptureSessionRuntimeError:(NSNotification *)notification {
    NSError *error = [notification.userInfo objectForKey:AVCaptureSessionErrorKey];
    RTCLogError(@"Capture session runtime error: %@", error);
    [JitsiDispatcher dispatchAsyncOnType:RTCDispatcherTypeCaptureSession
                                   block:^{
#if TARGET_OS_IPHONE
        if (error.code == AVErrorMediaServicesWereReset) {
            [self handleNonFatalError];
        } else {
            [self handleFatalError];
        }
#else
        [self handleFatalError];
#endif
    }];
}
- (void)handleCaptureSessionDidStartRunning:(NSNotification *)notification {
    RTCLog(@"Capture session started.");
    [JitsiDispatcher dispatchAsyncOnType:RTCDispatcherTypeCaptureSession
                                   block:^{
        // If we successfully restarted after an unknown error,
        // allow future retries on fatal errors.
        _hasRetriedOnFatalError = NO;
    }];
}
- (void)handleCaptureSessionDidStopRunning:(NSNotification *)notification {
    RTCLog(@"Capture session stopped.");
}
- (void)handleFatalError {
    [JitsiDispatcher
     dispatchAsyncOnType:RTCDispatcherTypeCaptureSession
     block:^{
        if (!_hasRetriedOnFatalError) {
            RTCLogWarning(@"Attempting to recover from fatal capture error.");
            [self handleNonFatalError];
            _hasRetriedOnFatalError = YES;
        } else {
            RTCLogError(@"Previous fatal error recovery failed.");
        }
    }];
}
- (void)handleNonFatalError {
    [JitsiDispatcher dispatchAsyncOnType:RTCDispatcherTypeCaptureSession
                                   block:^{
        RTCLog(@"Restarting capture session after error.");
        if (_isRunning) {
            [_captureSession startRunning];
        }
    }];
}
#if TARGET_OS_IPHONE
#pragma mark - UIApplication notifications
- (void)handleApplicationDidBecomeActive:(NSNotification *)notification {
    [JitsiDispatcher dispatchAsyncOnType:RTCDispatcherTypeCaptureSession
                                   block:^{
        if (_isRunning && !_captureSession.isRunning) {
            RTCLog(@"Restarting capture session on active.");
            [_captureSession startRunning];
        }
    }];
}
#endif  // TARGET_OS_IPHONE
#pragma mark - Private
- (dispatch_queue_t)frameQueue {
    if (!_frameQueue) {
        _frameQueue =
        dispatch_queue_create("org.webrtc.avfoundationvideocapturer.video", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(_frameQueue,
                                  dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    }
    return _frameQueue;
}

- (BOOL)activateAudioSession {
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];

    // 1. Set the Category, Mode, and Options
    // These settings are CRITICAL for background camera access (PiP).
    BOOL setCategorySuccess = [session setCategory:AVAudioSessionCategoryPlayAndRecord
                                             mode:AVAudioSessionModeVideoChat
                                          options:AVAudioSessionCategoryOptionAllowBluetooth | AVAudioSessionCategoryOptionAllowBluetoothA2DP
                                            error:&error];

    if (!setCategorySuccess || error) {
        RTCLogError(@"🚨 Failed to set audio session category/mode: %@", error.localizedDescription);
        return NO;
    }

    // 2. Explicitly Activate the Session and check for errors
    // Since we can't check 'isActive', we attempt to activate it and rely on the result.
    BOOL setActiveSuccess = [session setActive:YES error:&error];
    
    if (setActiveSuccess) {
        RCTLogInfo(@"✅ AVAudioSession successfully activated.");
        // You may set a property here (e.g., self.isSessionActive = YES)
        // if you absolutely must track the state internally.
        return YES;
    } else {
        // Activation failed. This is likely why your capture session stops automatically.
        RTCLogError(@"🚨 Failed to activate audio session: %@", error.localizedDescription);
        return NO;
    }
}

- (BOOL)setupCaptureSession {
    NSAssert(_captureSession == nil, @"Setup capture session called twice.");
    _captureSession = [[AVCaptureSession alloc] init];
#if defined(WEBRTC_IOS)
    _captureSession.sessionPreset = AVCaptureSessionPresetInputPriority;
    _captureSession.usesApplicationAudioSession = NO;
#endif
    
    //automaticallyConfiguresApplicationAudioSession
    if (@available(iOS 16.0, *)) {
        if([_captureSession isMultitaskingCameraAccessSupported]) {
            RCTLogWarn(@"[VideoCaptureController] isMultitaskingCameraAccessSupported");
            [_captureSession beginConfiguration];
            [_captureSession setAutomaticallyConfiguresApplicationAudioSession:NO];
            _captureSession.multitaskingCameraAccessEnabled = true;
            [_captureSession commitConfiguration];
        }
    } else {
        // Fallback on earlier versions
        RCTLogWarn(@"[VideoCaptureController] NOT isMultitaskingCameraAccessSupported");
    }
    
    [self setupVideoDataOutput];
    // Add the output.
    if (![_captureSession canAddOutput:_videoDataOutput]) {
        RTCLogError(@"Video data output unsupported.");
        return NO;
    }
    [_captureSession addOutput:_videoDataOutput];
    //[self activateAudioSession];
    return YES;
}
- (void)setupVideoDataOutput {
    NSAssert(_videoDataOutput == nil, @"Setup video data output called twice.");
    // Make the capturer output NV12. Ideally we want I420 but that's not
    
    AVCaptureVideoDataOutput *videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    
    // `videoDataOutput.availableVideoCVPixelFormatTypes` returns the pixel
    // formats supported by the device with the most efficient output format
    // first. Find the first format that we support.
    NSSet<NSNumber *> *supportedPixelFormats =
    [RTC_OBJC_TYPE(RTCCVPixelBuffer) supportedPixelFormats];
    NSMutableOrderedSet *availablePixelFormats = [NSMutableOrderedSet
                                                  orderedSetWithArray:videoDataOutput.availableVideoCVPixelFormatTypes];
    [availablePixelFormats intersectSet:supportedPixelFormats];
    NSNumber *pixelFormat = availablePixelFormats.firstObject;
    NSAssert(pixelFormat, @"Output device has no supported formats.");
    
    // currently supported on iPhone / iPad.
    _preferredOutputPixelFormat = [pixelFormat unsignedIntValue];
    _outputPixelFormat = _preferredOutputPixelFormat;
    
    //AVCaptureVideoDataOutput *videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    videoDataOutput.videoSettings = @{
        (NSString *)
        // TODO(denicija): Remove this color conversion and use the original capture format directly.
        //kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)
        
        
    };
    videoDataOutput.alwaysDiscardsLateVideoFrames = NO;
    [videoDataOutput setSampleBufferDelegate:self queue:self.frameQueue];
    _videoDataOutput = videoDataOutput;
}
#pragma mark - Private, called inside capture queue
- (void)updateDeviceCaptureFormat:(AVCaptureDeviceFormat *)format fps:(NSInteger)fps {
    NSAssert([JitsiDispatcher isOnQueueForType:RTCDispatcherTypeCaptureSession],
             @"updateDeviceCaptureFormat must be called on the capture queue.");
    @try {
        _currentDevice.activeFormat = format;
        _currentDevice.activeVideoMinFrameDuration = CMTimeMake(1, fps);
    } @catch (NSException *exception) {
        RTCLogError(@"Failed to set active format!\n User info:%@", exception.userInfo);
        return;
    }
}

- (void)updateVideoDataOutputPixelFormat:(AVCaptureDeviceFormat *)format {
    FourCharCode mediaSubType =
    CMFormatDescriptionGetMediaSubType(format.formatDescription);
    if (![[RTC_OBJC_TYPE(RTCCVPixelBuffer) supportedPixelFormats]
          containsObject:@(mediaSubType)]) {
        mediaSubType = _preferredOutputPixelFormat;
    }
    
    if (mediaSubType != _outputPixelFormat) {
        _outputPixelFormat = mediaSubType;
    }
    // Update videoSettings with dimensions, as some virtual cameras, e.g. Snap
    // Camera, may not work otherwise.
    CMVideoDimensions dimensions =
    CMVideoFormatDescriptionGetDimensions(format.formatDescription);
    _videoDataOutput.videoSettings = @{
        (id)kCVPixelBufferWidthKey : @(dimensions.width),
        (id)kCVPixelBufferHeightKey : @(dimensions.height),
        (id)kCVPixelBufferPixelFormatTypeKey : @(_outputPixelFormat),
    };
}

- (void)reconfigureCaptureSessionInput {
    NSAssert([JitsiDispatcher isOnQueueForType:RTCDispatcherTypeCaptureSession],
             @"reconfigureCaptureSessionInput must be called on the capture queue.");
    NSError *error = nil;
    AVCaptureDeviceInput *input =
    [AVCaptureDeviceInput deviceInputWithDevice:_currentDevice error:&error];
    if (!input) {
        RTCLogError(@"Failed to create front camera input: %@", error.localizedDescription);
        return;
    }
    [_captureSession beginConfiguration];
    for (AVCaptureDeviceInput *oldInput in [_captureSession.inputs copy]) {
        [_captureSession removeInput:oldInput];
    }
    if ([_captureSession canAddInput:input]) {
        [_captureSession addInput:input];
    } else {
        RTCLogError(@"Cannot add camera as an input to the session.");
    }
    [_captureSession commitConfiguration];
}
- (void)updateOrientation {
    NSAssert([JitsiDispatcher isOnQueueForType:RTCDispatcherTypeCaptureSession],
             @"updateOrientation must be called on the capture queue.");
#if TARGET_OS_IPHONE
    _orientation = [UIDevice currentDevice].orientation;
#endif
}
@end
