//
//  Model.h
//  WWStreamPlayer
//
//  Created by William.Weng on 2026/3/27.
//

#import <Foundation/Foundation.h>
#import <libavformat/avformat.h>

#define WWLog(fmt, ...) NSLog((@"\n🚩%@:%d => %s\n\t✅ " fmt), [[NSString stringWithUTF8String: __FILE__] lastPathComponent], __LINE__, __PRETTY_FUNCTION__, ##__VA_ARGS__);

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FFmpegVideoError) {
    FFmpegVideoErrorInvalidURL,
    FFmpegVideoErrorOpenFailed,
    FFmpegVideoErrorStreamInfoFailed,
    FFmpegVideoErrorImageAllocFailed,
};

typedef struct {
    uint8_t * _Nonnull data[AV_NUM_DATA_POINTERS];
    int      linesize[AV_NUM_DATA_POINTERS];
} FFmpegDstBuffer;

typedef struct {
    uint8_t * _Nonnull slice[AV_NUM_DATA_POINTERS];
    int stride[AV_NUM_DATA_POINTERS];
} FFmpegSrcBuffer;

@interface Model : NSObject

@end

NS_ASSUME_NONNULL_END

