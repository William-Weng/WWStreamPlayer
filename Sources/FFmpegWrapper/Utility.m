//
//  Utility.m
//  WWStreamPlayer
//
//  Created by William.Weng on 2026/4/1.
//

#import <AVFoundation/AVFoundation.h>
#import "Utility.h"

NS_ASSUME_NONNULL_BEGIN

@implementation Utility

// MARK: - 開放函式
/// 測試影片路徑是否正確 (能不能打開 / 找不找得到)
/// - Parameters:
///   - url: NSURL
///   - formatContext: AVFormatContext
///   - parameters: NSDictionary*
- (NSError *)checkStreamInputWithURL:(NSURL *)url formatContext:(AVFormatContext **)formatContext parameters:(NSDictionary<NSString *, NSString *> *)parameters {
    
    int result = [self openRemoteInputWithContext:formatContext parameters:parameters url:url];
    if (result < 0) { return [self errorMessageResult:result code:FFmpegErrorVideoOpenFailed]; }
    
    result = [self findStreamInformationWithContext:*formatContext];
    if (result < 0) { return [self errorMessageResult:result code:FFmpegErrorVideoStreamInfoFailed]; }
    
    return nil;
}

/// 取得影片時間 (CMTime)
/// - Parameters:
///   - frame: AVFrame
///   - stream: AVStream
- (CMTime)timeFromFrame:(AVFrame *)frame stream:(AVStream *)stream {
    
    AVRational timeBase = stream->time_base;
    int64_t bestTimestamp = frame->best_effort_timestamp;
    CMTime timeStamp = CMTimeMake(bestTimestamp * timeBase.num, timeBase.den);
    
    return timeStamp;
}

/// 找出類型的串流index (AVMEDIA_TYPE_VIDEO / AVMEDIA_TYPE_AUDIO)
- (int)streamIndexFromFormatContext:(AVFormatContext *)formatContext mediaType:(enum AVMediaType)mediaType {
    
    for (int index = 0; index < formatContext->nb_streams; index++) {
        
        AVStream *stream = formatContext->streams[index];
        AVCodecParameters *codecpar = stream->codecpar;
        
        if (codecpar && codecpar->codec_type == mediaType) { return index; }
    }
    
    return -1;
}

/// 來源資料緩衝從視訊幀 (YUV → BGRA)
/// - Parameter frame: AVFrame
- (FFmpegSrcBuffer)prepareSwsSrcFromFrame:(AVFrame *)frame {
    
    FFmpegSrcBuffer buffer = {0};
    
    for (int index = 0; index < AV_NUM_DATA_POINTERS; index++) {
        buffer.slice[index] = frame->data[index];
        buffer.stride[index] = frame->linesize[index];
    }
    
    return buffer;
}

/// 根據指定的串流的Index及已開啟的 AVFormatContext，建立並開啟對應串流的 AVCodecContext
/// - Parameters:
///   - stream: AVStream
///   - formatContext: AVFormatContext
- (AVCodecContext *)createCodecContextForStream:(AVStream *)stream formatContext:(AVFormatContext *)formatContext {
    
    AVCodecParameters *par = stream->codecpar;

    const AVCodec *codec = avcodec_find_decoder(par->codec_id);
    if (!codec) { return NULL; }

    AVCodecContext *codecContext = avcodec_alloc_context3(codec);
    if (!codecContext) { return NULL; }

    if (avcodec_parameters_to_context(codecContext, par) < 0) {
        avcodec_free_context(&codecContext);
        return NULL;
    }

    if (avcodec_open2(codecContext, codec, NULL) < 0) {
        avcodec_free_context(&codecContext);
        return NULL;
    }
    
    return codecContext;
}

/// 建立CVPixelBuffer
/// - Parameters:
///   - pixelBuffer: CVPixelBufferRef
///   - codecContext: AVCodecContext
///   - useMetal: for MetalKit加速
- (CVReturn)createPixelBuffer:(CVPixelBufferRef *)pixelBuffer codecContext:(AVCodecContext *)codecContext useMetal:(BOOL)useMetal {
    
    NSDictionary *attributes = @{
        (__bridge NSString *)kCVPixelBufferCGImageCompatibilityKey : @YES,
        (__bridge NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
        (__bridge NSString *)kCVPixelBufferMetalCompatibilityKey : @(useMetal)
    };
    
    CVReturn cvReturn = CVPixelBufferCreate(kCFAllocatorDefault, codecContext->width, codecContext->height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attributes, pixelBuffer);
    return cvReturn;
}

/// 將AVFrame => UIImage (bytesPerRow要對齊16的倍數值)
/// - Parameter frame: AVFrame
- (UIImage *)yuvToImage:(AVFrame *)frame {
    
    struct SwsContext *swsCtx = [self softwareScalerContextWithFrame:frame outputFormat:AV_PIX_FMT_RGBA scalerFlags:SWS_BILINEAR];
    
    int rgbSize = av_image_get_buffer_size(AV_PIX_FMT_RGBA, frame->width, frame->height, 1);
    int rgbLinesize[4] = {frame->width * 4};
    size_t bytesPerRow = (frame->width * 4 + 15) & ~15;
    uint8_t *rgbBuffer = av_malloc(rgbSize);
    uint8_t *rgbPlanes[4] = {rgbBuffer};
    
    const uint8_t *const srcData[4] = {frame->data[0], frame->data[1], frame->data[2]};
    const int srcLinesize[4] = {frame->linesize[0], frame->linesize[1], frame->linesize[2]};
    
    sws_scale(swsCtx, srcData, srcLinesize, 0, frame->height, rgbPlanes, rgbLinesize);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef cgCtx = CGBitmapContextCreate(rgbBuffer, frame->width, frame->height, 8, bytesPerRow, colorSpace, kCGImageAlphaPremultipliedLast);
    
    CGImageRef cgImg = CGBitmapContextCreateImage(cgCtx);
    UIImage *image = [UIImage imageWithCGImage:cgImg];
    
    CGImageRelease(cgImg);
    CGContextRelease(cgCtx);
    CGColorSpaceRelease(colorSpace);
    
    av_free(rgbBuffer);
    sws_freeContext(swsCtx);
    
    return image;
}

/// 產生SwsContext => 轉成 BGRA，方便塞進 CVPixelBuffer (kCVPixelFormatType_32BGRA)
/// - Parameters:
///   - codecContext: AVCodecContext
///   - dstFormat: 像素格式
///   - scalerFlags: 轉換時的插值算法
- (struct SwsContext *)softwareScalerContextWithCodecContext:(AVCodecContext*)codecContext outputFormat:(enum AVPixelFormat)dstFormat scalerFlags:(int)scalerFlags {
    enum AVPixelFormat srcFmt = codecContext->pix_fmt;
    return sws_getContext(codecContext->width, codecContext->height, srcFmt, codecContext->width, codecContext->height, dstFormat, scalerFlags, NULL, NULL, NULL);
}

/// BGRA → CVPixelBuffer
/// - Parameters:
///   - dstBuffer: FFmpegDstBuffer
///   - pixelBuffer: CVPixelBufferRef
///   - codecContext: AVCodecContext
- (void)copyDestinationBuffer:(FFmpegDstBuffer)dstBuffer to:(CVPixelBufferRef)pixelBuffer codecContext:(AVCodecContext *)codecContext {
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *dstBase = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t dstBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    
    for (int y = 0; y < codecContext->height; y++) {
        memcpy((uint8_t *)dstBase + y * dstBytesPerRow, dstBuffer.data[0] + y * dstBuffer.linesize[0], codecContext->width * 4);
    }
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
}

/// CVPixelBuffer => CMSampleBuffer (用 ImageBuffer 建 SampleBuffer)
/// - Parameters:
///   - pixelBuffer: CVPixelBufferRef
///   - sampleBuffer: CMSampleBufferRef
///   - time: timeStamp
- (OSStatus)convertPixelBuffer:(CVPixelBufferRef)pixelBuffer to:(CMSampleBufferRef *)sampleBuffer time:(CMTime)timeStamp {
    
    if (!pixelBuffer) { return kCMSampleBufferError_RequiredParameterMissing; }
    if (!sampleBuffer) { return kCMSampleBufferError_RequiredParameterMissing; }
        
    CMVideoFormatDescriptionRef formatDesc = NULL;
    OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &formatDesc);
    
    *sampleBuffer = NULL;
    
    if (status != noErr) { return status; }
    if (!formatDesc) { return status; }

    CMSampleTimingInfo timingInfo = kCMTimingInfoInvalid;
    timingInfo.presentationTimeStamp = timeStamp;
    
    status = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, true, NULL, NULL, formatDesc, &timingInfo, sampleBuffer);
    if (formatDesc) { CFRelease(formatDesc); }
    
    return status;
}

// 尋找該秒的Frame (畫面)
/// - Parameters:
///   - second: 秒數
///   - formatCtx: AVFormatContext
///   - videoStreamIndex: 影片的StreamIndex
- (UIImage *)seekFrameAtSecond:(NSTimeInterval)second context:(AVFormatContext *)formatCtx streamIndex:(int)videoStreamIndex {
    
    if (!formatCtx) { return nil; }
    if (videoStreamIndex < 0) { return nil; }
    if (videoStreamIndex >= formatCtx->nb_streams) { return nil; }
    if (second < 0) { return nil; }
    if (isfinite(second) == 0) { return nil; }
    
    AVCodecContext *codecCtx = avcodec_alloc_context3(NULL);
    AVStream *stream = formatCtx->streams[videoStreamIndex];
    AVRational time_base = stream->time_base;
    AVCodecParameters *parameter = stream->codecpar;
    
    avcodec_parameters_to_context(codecCtx, parameter);
    const AVCodec *codec = avcodec_find_decoder(parameter->codec_id);
    
    if (!codec || avcodec_open2(codecCtx, codec, NULL) < 0) { avcodec_free_context(&codecCtx); return nil; }

    int64_t baseTs = (int64_t)(second * AV_TIME_BASE);
    int64_t timestamp = av_rescale_q(baseTs, (AVRational){1, AV_TIME_BASE}, time_base);
    
    av_seek_frame(formatCtx, videoStreamIndex, timestamp, AVSEEK_FLAG_BACKWARD);
    avcodec_flush_buffers(codecCtx);

    UIImage* image = [self seekFrameAtStreamIndex:videoStreamIndex maxPacketCount:300 formatContext:formatCtx codecContext:codecCtx];
    
    return image;
}

/// 產生錯誤訊息
/// - Parameters:
///   - message: NSString
///   - code: FFmpegErrorVideo
- (NSError *)errorMessage:(NSString *)message code:(FFmpegError)code {

    NSString *localizedDescription;
    
    switch (code) {
        case FFmpegErrorVideoInvalidURL: localizedDescription = @"Invalid URL"; break;
        case FFmpegErrorVideoOpenFailed: localizedDescription = @"Could not open stream"; break;
        case FFmpegErrorVideoStreamInfoFailed: localizedDescription = @"Failed to read stream info"; break;
        default: localizedDescription = message; break;
    }
    
    NSMutableDictionary* userInfo = [NSMutableDictionary new];
    
    [userInfo setValue:localizedDescription forKey:NSLocalizedDescriptionKey];
    [userInfo setValue:message forKey:@"message"];
    
    NSError *error = [NSError errorWithDomain:@"FFmpegErrorVideoDomain" code:code userInfo:userInfo];
    return error;
}

/// 產生錯誤訊息 (av_err2str)
/// - Parameters:
///   - result: int
///   - code: FFmpegErrorVideo
- (NSError *)errorMessageResult:(int)result code:(FFmpegError)code {
    NSString *message = [NSString stringWithUTF8String: av_err2str(result)];
    return [self errorMessage:message code:code];
}

// MARK: - 🈲 小工具
/// 開啟檔案
/// - Parameters:
///   - formatContext: AVFormatContext
///   - parameters: NSDictionary
///   - url: NSURL
- (int)openRemoteInputWithContext:(AVFormatContext**)formatContext parameters:(NSDictionary*)parameters url:(NSURL*)url {
    
    AVDictionary *options = [self avDictionaryWithParameters:parameters];
    int result = avformat_open_input(formatContext, [[url absoluteString] UTF8String], NULL, &options);
    av_dict_free(&options);
    
    return result;
}

/// 尋找檔案資訊
/// - Parameter formatContext: AVFormatContext
- (int)findStreamInformationWithContext:(AVFormatContext*)formatContext {
    int result = avformat_find_stream_info(formatContext, NULL);
    return result;
}

/// 設定AVDictionary參數值
/// - Parameter parameters: NSDictionary *
- (AVDictionary*)avDictionaryWithParameters:(NSDictionary *)parameters {
    
    AVDictionary *options = NULL;
    
    for (NSString *key in parameters) {
        NSString *value = parameters[key];
        av_dict_set(&options, [key UTF8String], [value UTF8String], 0);
    }
    
    return options;
}

/// 產生SwsContext
/// - Parameters:
///   - frame: AVFrame
///   - dstFormat: 像素格式
///   - scalerFlags: 轉換時的插值算法
- (struct SwsContext *)softwareScalerContextWithFrame:(AVFrame*)frame outputFormat:(enum AVPixelFormat)dstFormat scalerFlags:(int)scalerFlags {
    enum AVPixelFormat srcFmt = frame->format;
    return sws_getContext(frame->width, frame->height, srcFmt, frame->width, frame->height, dstFormat, scalerFlags, NULL, NULL, NULL);
}

/// 尋找該秒的Frame (畫面)
/// - Parameters:
///   - videoStreamIndex: 影片的StreamIndex
///   - maxPacketCount: 搜尋的最大封包數
///   - formatCtx: AVFormatContext
///   - codecCtx: AVCodecContext
- (UIImage *)seekFrameAtStreamIndex:(int)videoStreamIndex maxPacketCount:(int)maxPacketCount formatContext:(AVFormatContext *)formatCtx codecContext: (AVCodecContext *)codecCtx {
    
    AVPacket packet;
    AVFrame *frame = av_frame_alloc();
    UIImage *image = nil;
    
    for (int index = 0; index < maxPacketCount; index++) {
        
        if (av_read_frame(formatCtx, &packet) < 0) { break; }

        if (packet.stream_index == videoStreamIndex) {
            avcodec_send_packet(codecCtx, &packet);
            
            while (avcodec_receive_frame(codecCtx, frame) == 0) {
                image = [self yuvToImage:frame];
                if (image) { break; }
            }

            if (image) { break; }
        }

        av_packet_unref(&packet);
    }

    avcodec_flush_buffers(codecCtx);
    av_frame_free(&frame);
    avcodec_free_context(&codecCtx);
    
    return image;
}

@end

NS_ASSUME_NONNULL_END
