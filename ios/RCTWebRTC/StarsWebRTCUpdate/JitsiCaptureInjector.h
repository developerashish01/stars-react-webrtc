//
//  JitsiCaptureInjector.h
//  react-native-webrtc
//
//  Created by Amzad Khan on 11/10/25.
//


#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "JitsiCameraVideoCapturer.h"
#import <WebRTC/RTCVideoFrame.h>
#import <WebRTC/RTCVideoTrack.h>
#import <WebRTC/RTCPeerConnection.h>
#import <CoreMedia/CoreMedia.h>
#import "PIPController.h"
#import <WebRTC/RTCI420Buffer.h>
NS_ASSUME_NONNULL_BEGIN

@protocol JitsiCameraVideoCapturerDataSource <NSObject>
-(RTCVideoFrame *)processframeCaptured:(RTCVideoFrame *)videoFrame;
-(JitsiCameraVideoCapturer *_Nullable)videoCapturerFrom:(RTCVideoSource *)videoSource;
-(void)localCameraDidStartTrack:(RTCVideoTrack *)videoTrack;
-(void)mediaTrackDidAdded:(RTCRtpReceiver *)rtpReceiver data:(NSDictionary *_Nonnull)data;
-(void)mediaTrackDidRemoved:(RTCRtpReceiver *)rtpReceiver data:(NSDictionary *_Nonnull)data;

@end

@interface JitsiCaptureInjector : NSObject
@property(nonatomic, nullable, strong)JitsiCameraVideoCapturer *capturer;
@property(nonatomic, nullable, weak)id<JitsiCameraVideoCapturerDataSource> cameraVideoCapturerSource;
@property(nonatomic, nullable, weak) id<RTCPeerConnectionDelegate> peerConnectionDelegate;
+(instancetype _Nonnull)shared;

@end


NS_ASSUME_NONNULL_END
