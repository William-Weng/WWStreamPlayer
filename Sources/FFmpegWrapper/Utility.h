//
//  Utility.h
//  WWStreamPlayer
//
//  Created by William.Weng on 2026/4/1.
//

#import <UIKit/UIKit.h>
#import "Model.h"
#import "StreamAudioPlayer.h"

#import <libavcodec/avcodec.h>
#import <libswscale/swscale.h>
#import <libavutil/imgutils.h>
#import <libswresample/swresample.h>

#define WWLog(fmt, ...) NSLog((@"\n🚩%@:%d => %s\n\t✅ " fmt), [[NSString stringWithUTF8String: __FILE__] lastPathComponent], __LINE__, __PRETTY_FUNCTION__, ##__VA_ARGS__);

NS_ASSUME_NONNULL_BEGIN

@interface Utility : NSObject

// MARK: - 🎥 Video
- (int)streamIndexFromFormatContext:(AVFormatContext *)formatContext mediaType:(enum AVMediaType)mediaType;

- (UIImage *)yuvToImage:(AVFrame *)frame;
- (UIImage *)seekFrameAtSecond:(NSTimeInterval)second context:(AVFormatContext *)formatCtx streamIndex:(int)videoStreamIndex;
- (CMTime)timeFromFrame:(AVFrame *)frame stream:(AVStream *)stream;
- (CVReturn)createPixelBuffer:(CVPixelBufferRef _Nonnull * _Nonnull)pixelBuffer codecContext:(AVCodecContext * _Nonnull)codecContext useMetal:(BOOL)useMetal;
- (OSStatus)convertPixelBuffer:(CVPixelBufferRef _Nonnull)pixelBuffer to:(CMSampleBufferRef _Nonnull * _Nonnull)sampleBuffer time:(CMTime)timeStamp;

- (FFmpegSrcBuffer)prepareSwsSrcFromFrame:(AVFrame *)frame;

- (AVDictionary*)avDictionaryWithParameters:(NSDictionary *)parameters;
- (AVCodecContext *)createCodecContextForStream:(AVStream *)stream formatContext:(AVFormatContext *)formatContext;
- (struct SwsContext *)softwareScalerContextWithCodecContext:(AVCodecContext*)codecContext outputFormat:(enum AVPixelFormat)dstFormat scalerFlags:(int)scalerFlags;
- (void)copyDestinationBuffer:(FFmpegDstBuffer)dstBuffer to:(CVPixelBufferRef)pixelBuffer codecContext:(AVCodecContext *)codecContext;

- (NSError *)checkStreamInputWithURL:(NSURL *)url formatContext:(AVFormatContext *)formatContext parameters:(NSDictionary<NSString *, NSString *> *)parameters;
- (NSError *)errorMessage:(NSString *)message code:(FFmpegError)code;
- (NSError *)errorMessageResult:(int)result code:(FFmpegError)code;

// MARK: - 🔊 Audio
- (void)findAudioStream:(NSURL *)url codecCallback:(void (^)(AVCodecParameters *parameters))codecCallback decodeCallback:(FFmpegDecodeCallback)decodeCallback;
- (void)startAudioDecodeLoop:(AVFormatContext *)formatContext audioStreamIndex:(NSInteger)audioStreamIndex pcmCallback:(FFmpegPCMCallback)pcmCallback errorCallback:(void (^)(NSError *error))errorCallback completion:(void (^)(int frameCount))completionCallback;
- (SwrContext *)softwareResampleFromDecoderContext:(AVCodecContext *)decoderContext layout:(AVChannelLayout)layout error:(NSError **)error;
- (AVCodecContext *)audioDecoderContextForStream:(AVStream *)audioStream error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
