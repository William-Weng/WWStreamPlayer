//
//  Utility.h
//  WWStreamPlayer
//
//  Created by William.Weng on 2026/4/1.
//

#import <UIKit/UIKit.h>
#import "Model.h"

#import <libavcodec/avcodec.h>
#import <libswscale/swscale.h>
#import <libavutil/imgutils.h>

NS_ASSUME_NONNULL_BEGIN

@interface Utility : NSObject

- (int)streamIndexFromFormatContext:(AVFormatContext *)formatContext mediaType:(enum AVMediaType)mediaType;

- (UIImage *)yuvToImage:(AVFrame *)frame;
- (UIImage *)seekFrameAtSecond:(NSTimeInterval)second context:(AVFormatContext *)formatCtx streamIndex:(int)videoStreamIndex;
- (CMTime)timeFromFrame:(AVFrame *)frame stream:(AVStream *)stream;
- (CVReturn)createPixelBuffer:(CVPixelBufferRef *)pixelBuffer codecContext:(AVCodecContext *)codecContext useMetal:(BOOL)useMetal;
- (OSStatus)convertPixelBuffer:(CVPixelBufferRef)pixelBuffer to:(CMSampleBufferRef *)sampleBuffer time:(CMTime)timeStamp;

- (FFmpegSrcBuffer)prepareSwsSrcFromFrame:(AVFrame *)frame;

- (AVDictionary*)avDictionaryWithParameters:(NSDictionary *)parameters;
- (AVCodecContext *)createCodecContextForStream:(AVStream *)stream formatContext:(AVFormatContext *)formatContext;
- (struct SwsContext *)softwareScalerContextWithCodecContext:(AVCodecContext*)codecContext outputFormat:(enum AVPixelFormat)dstFormat scalerFlags:(int)scalerFlags;
- (void)copyDestinationBuffer:(FFmpegDstBuffer)dstBuffer to:(CVPixelBufferRef)pixelBuffer codecContext:(AVCodecContext *)codecContext;

- (NSError *)checkStreamInputWithURL:(NSURL *)url formatContext:(AVFormatContext *)formatContext parameters:(NSDictionary<NSString *, NSString *> *)parameters;
- (NSError *)errorMessage:(NSString *)message code:(FFmpegVideoError)code;
- (NSError *)errorMessageResult:(int)result code:(FFmpegVideoError)code;

@end

NS_ASSUME_NONNULL_END
