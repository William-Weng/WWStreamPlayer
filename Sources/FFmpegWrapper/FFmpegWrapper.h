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
#import <libswresample/swresample.h>
#include <libavutil/opt.h>

#import "Model.h"
#import "Utility.h"

NS_ASSUME_NONNULL_BEGIN

@interface FFmpegWrapper : NSObject

typedef void (^FFmpegPixelBufferCallback)(CVPixelBufferRef pixelBuffer, CMTime timestamp);
typedef void (^FFmpegFrameWithTimeCallback)(UIImage *frame, CMTime timestamp);
typedef void (^FFmpegPCMCallback)(NSData *pcmData, int sampleRate, int channels);
typedef void (^FFmpegDecodeCallback)(AVFormatContext *formatContext, NSInteger audioStreamIndex);

- (NSString *)version;
- (NSTimeInterval)durationAtURL:(NSURL *)url error:(NSError **)error;
- (UIImage *)frameAtURL:(NSURL *)url second:(NSTimeInterval)second;
- (NSArray<UIImage *> *)thumbnailsAtURL:(NSURL *)url count:(int)count;

- (NSString*)codecNameWithId:(enum AVCodecID)codecID;

- (void)playRTSPWithURL:(NSURL *)url frame:(FFmpegFrameWithTimeCallback)frameCallback error:(void (^)(NSError *error))errorCallback  completion:(void (^)(BOOL isFinished))completionCallback;
- (void)stopRTSPPlay;

- (void)playRTSPWithURL:(NSURL *)url displayLayer:(AVSampleBufferDisplayLayer *)displayLayer timeStamp:(void (^)(CMTime time))timeCallback error:(void (^)(NSError *error))errorCallback completion:(void (^)(BOOL isFinished))completionCallback;
- (void)stopRTSPPlayOnDisplayLayer;

- (void)playRTSPWithURL:(NSURL *)url pixelBuffer:(FFmpegPixelBufferCallback)pixelBufferCallback error:(void (^)(NSError *error))errorCallback completion:(void (^)(BOOL isFinished))completionCallback;
- (void)stopRTSPPlayWithPixelBuffer;

- (void)decodeAudioStream:(NSURL *)url codec:(void (^)(AVCodecParameters *parameters))codecCallback pcm:(FFmpegPCMCallback)pcmCallback error:(void (^)(NSError *error))errorCallback completion:(void (^)(int frameCount))completionCallback;
- (void)playPCM:(NSData *)pcmData sampleRate:(int)sampleRate channels:(int)channels;
- (void)stopPCM;

@end

NS_ASSUME_NONNULL_END
