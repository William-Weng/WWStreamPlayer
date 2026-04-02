//
//  Model.h
//  WWStreamPlayer
//
//  Created by William.Weng on 2026/3/27.
//

#import <Foundation/Foundation.h>
#import <libavformat/avformat.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^FFmpegPixelBufferCallback)(CVPixelBufferRef pixelBuffer, CMTime timestamp);
typedef void (^FFmpegFrameWithTimeCallback)(UIImage *frame, CMTime timestamp);
typedef void (^FFmpegPCMCallback)(NSData *pcmData, int sampleRate, int channels);
typedef void (^FFmpegDecodeCallback)(AVFormatContext *formatContext, NSInteger audioStreamIndex);
typedef void (^FFmpegPCMCallback)(NSData *pcmData, int sampleRate, int channels);

typedef NS_ENUM(NSInteger, FFmpegError) {
    FFmpegErrorVideoInvalidURL,
    FFmpegErrorVideoOpenFailed,
    FFmpegErrorVideoStreamInfoFailed,
    FFmpegErrorVideoImageAllocFailed,
    FFmpegErrorAudioInvalidURL,
    FFmpegErrorAudioDecoderInvalid,
    FFmpegErrorAudioSoftwareResampleInvalid,
    FFmpegErrorAudioAllocFailed,
    FFmpegErrorAudioStreamInfoFailed,
};

typedef struct {
    uint8_t * _Nonnull data[AV_NUM_DATA_POINTERS];
    int linesize[AV_NUM_DATA_POINTERS];
} FFmpegDstBuffer;

typedef struct {
    uint8_t * _Nonnull slice[AV_NUM_DATA_POINTERS];
    int stride[AV_NUM_DATA_POINTERS];
} FFmpegSrcBuffer;

@interface Model : NSObject

@end

NS_ASSUME_NONNULL_END

