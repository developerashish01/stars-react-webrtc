//
//  JitsiDispatcher.h
//  react-native-webrtc
//
//  Created by Amzad Khan on 15/10/25.
//

#import <Foundation/Foundation.h>
#import "WebRTC/RTCDispatcher.h"

NS_ASSUME_NONNULL_BEGIN

@interface JitsiDispatcher : RTCDispatcher
+ (dispatch_queue_t)dispatchQueueForType:(RTCDispatcherQueueType)dispatchType;
@end

NS_ASSUME_NONNULL_END

/*

@interface AVCaptureSession (DevicePosition)
// Check the image's EXIF for the camera the image came from.
+ (AVCaptureDevicePosition)devicePositionForSampleBuffer:
    (CMSampleBufferRef)sampleBuffer;
@end
*/
