//
//  JitsiDispatcher.m
//  react-native-webrtc
//
//  Created by Amzad Khan on 15/10/25.
//

#import "JitsiDispatcher.h"

NS_ASSUME_NONNULL_BEGIN
static dispatch_queue_t kAudioSessionQueue = nil;
static dispatch_queue_t kCaptureSessionQueue = nil;
@implementation JitsiDispatcher
+ (void)initialize {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    kAudioSessionQueue = dispatch_queue_create(
        "org.webrtc.RTCDispatcherAudioSession",
        DISPATCH_QUEUE_SERIAL);
    kCaptureSessionQueue = dispatch_queue_create(
        "org.webrtc.RTCDispatcherCaptureSession",
        DISPATCH_QUEUE_SERIAL);
  });
}
+ (void)dispatchAsyncOnType:(RTCDispatcherQueueType)dispatchType
                      block:(dispatch_block_t)block {
  dispatch_queue_t queue = [self dispatchQueueForType:dispatchType];
  dispatch_async(queue, block);
}
#pragma mark - Private
+ (dispatch_queue_t)dispatchQueueForType:(RTCDispatcherQueueType)dispatchType {
    switch (dispatchType) {
        case RTCDispatcherTypeMain:
            return dispatch_get_main_queue();
        case RTCDispatcherTypeCaptureSession:
            return kCaptureSessionQueue;
        case RTCDispatcherTypeAudioSession:
            return kAudioSessionQueue;
        case RTCDispatcherTypeNetworkMonitor:
            return dispatch_get_main_queue();
    }
}
@end

NS_ASSUME_NONNULL_END
