//
//  FFmpegWrapper.h
//  FFmpegWrapper
//
//  Created by William.Weng on 2026/3/27.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#import <libavformat/avformat.h>
#import <libavcodec/avcodec.h>
#import <libavutil/imgutils.h>
#import <libswscale/swscale.h>
#import <libavutil/error.h>

#import "Model.h"

NS_ASSUME_NONNULL_BEGIN

@interface FFmpegWrapper : NSObject

typedef void (^FFmpegPixelBufferCallback)(CVPixelBufferRef pixelBuffer, CMTime timestamp);
typedef void (^FFmpegFrameWithTimeCallback)(UIImage *frame, CMTime timestamp);

+ (instancetype)shared;

- (NSString *)version;
- (NSTimeInterval)durationAtURL:(NSURL *)url error:(NSError **)error;
- (UIImage *)frameAtURL:(NSURL *)url second:(NSTimeInterval)second;
- (NSArray<UIImage *> *)thumbnailsAtURL:(NSURL *)url count:(int)count;

- (void)playRTSPWithURL:(NSURL *)url frame:(FFmpegFrameWithTimeCallback)frameCallback error:(void (^)(NSError *error))errorCallback  completion:(void (^)(BOOL isFinished))completionCallback;
- (void)stopRTSPPlay;

- (void)playRTSPWithURL:(NSURL *)url displayLayer:(AVSampleBufferDisplayLayer *)displayLayer timeStamp:(void (^)(CMTime time))timeCallback error:(void (^)(NSError *error))errorCallback completion:(void (^)(BOOL isFinished))completionCallback;
- (void)stopRTSPPlayOnDisplayLayer;

- (void)playRTSPWithURL:(NSURL *)url pixelBuffer:(FFmpegPixelBufferCallback)pixelBufferCallback error:(void (^)(NSError *error))errorCallback completion:(void (^)(BOOL isFinished))completionCallback;
- (void)stopRTSPPlayWithPixelBuffer;

@end

NS_ASSUME_NONNULL_END
