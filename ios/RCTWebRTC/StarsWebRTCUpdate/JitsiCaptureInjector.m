//
//  JitsiCaptureInjector.m
//  react-native-webrtc
//
//  Created by Amzad Khan on 11/10/25.
//

#import "JitsiCaptureInjector.h"

NS_ASSUME_NONNULL_BEGIN
@implementation JitsiCaptureInjector
+ (instancetype)shared {
    static JitsiCaptureInjector *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[JitsiCaptureInjector alloc] init];
    });
    return sharedInstance;
}

@end
NS_ASSUME_NONNULL_END
