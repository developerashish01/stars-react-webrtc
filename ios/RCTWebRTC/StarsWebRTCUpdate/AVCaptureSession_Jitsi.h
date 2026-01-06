//
//  AVCaptureSession_Jitsi.h
//  react-native-webrtc
//
//  Created by Amzad Khan on 15/10/25.
//

#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
NS_ASSUME_NONNULL_BEGIN

@interface AVCaptureSession (Jitsi)
// Check the image's EXIF for the camera the image came from.
+ (AVCaptureDevicePosition)devicePositionForSampleBuffer:
    (CMSampleBufferRef)sampleBuffer;
@end


NS_ASSUME_NONNULL_END
