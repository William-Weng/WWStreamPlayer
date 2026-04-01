//
//  Model.h
//  WWStreamPlayer
//
//  Created by William.Weng on 2026/3/27.
//

#import <Foundation/Foundation.h>
#import <libavformat/avformat.h>

NS_ASSUME_NONNULL_BEGIN

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

