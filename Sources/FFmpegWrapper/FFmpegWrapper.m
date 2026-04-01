//
//  FFmpegWrapper.m
//  FFmpegWrapper
//
//  Created by William.Weng on 2026/3/27.
//

#import <CoreImage/CoreImage.h>
#import "FFmpegWrapper.h"
#import "StreamPlayer.h"
#import "Utility.h"

@interface FFmpegWrapper ()

@property (nonatomic, strong) dispatch_queue_t rtspQueue;
@property (nonatomic, strong) dispatch_queue_t rtspLayerQueue;
@property (nonatomic, strong) dispatch_queue_t rtspPixelQueue;
@property (nonatomic, strong) dispatch_queue_t rtspAudioQueue;

@property (atomic, assign) BOOL rtspShouldStop;
@property (atomic, assign) BOOL rtspLayerShouldStop;
@property (atomic, assign) BOOL rtspPixelShouldStop;

@property (nonatomic, strong) Utility *util;
@property (nonatomic, weak) AVSampleBufferDisplayLayer *currentDisplayLayer;
@property (nonatomic, copy) FFmpegPixelBufferCallback pixelCallback;

@property (nonatomic, assign) SwrContext *swrCtx;

@end

@implementation FFmpegWrapper

/// 單例
+ (instancetype)shared {
    
    static FFmpegWrapper *instance = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{ instance = [[FFmpegWrapper alloc] init]; });
        
    return instance;
}

typedef NS_ENUM(NSInteger, FFmpegStreamType) {
    FFmpegStreamTypeVideo,
    FFmpegStreamTypeAudio
};

/// 初始化
- (instancetype)init {
    
    self = [super init];
    
    if (self) {
        
        _util = [Utility new];
        
        av_log_set_level(AV_LOG_ERROR);
        avformat_network_init();
        
        _rtspLayerQueue = dispatch_queue_create("ffmpeg.rtsp.displaylayer.queue", DISPATCH_QUEUE_SERIAL);
        _rtspQueue = dispatch_queue_create("ffmpeg.rtsp.queue", DISPATCH_QUEUE_SERIAL);
        _rtspPixelQueue = dispatch_queue_create("ffmpeg.rtsp.pixel.queue", DISPATCH_QUEUE_SERIAL);
        _rtspAudioQueue = dispatch_queue_create("ffmpeg.rtsp.audio.queue", DISPATCH_QUEUE_SERIAL);
    }
    
    return self;
}

// MARK: - 公開函數
/// 取得FFMpeg版本
- (NSString *)version {
    return [NSString stringWithUTF8String:av_version_info()];
}

/// 取得編碼ID名稱 - AVCodecID(rawValue: 86018) => aac
/// - Parameter codecID: enum AVCodecID
- (NSString*)codecNameWithId:(enum AVCodecID)codecID {
    return [NSString stringWithUTF8String:avcodec_get_name(codecID)];
}

// MARK: - 公開函數
/// 取得該URL的影音長度 (0: 錯誤 / -1: RTSP直播 => 無限長) => ffmpeg -rtsp_transport tcp -i rtsp://xxx
/// - Parameters:
///   - url: NSURL
///   - error: NSError
- (NSTimeInterval)durationAtURL:(NSURL *)url error:(NSError **)error {
    
    if (!url) { if (error) { *error = [[self util] errorMessage:nil code:FFmpegVideoErrorInvalidURL]; } return 0; }
    if (![(NSString *)[url absoluteString] length]) { if (error) { *error = [[self util] errorMessage:nil code:FFmpegVideoErrorInvalidURL]; } return 0; }
    
    AVFormatContext *formatContext = NULL;
    NSDictionary<NSString *, NSString *> *parameters = @{ @"rtsp_transport": @"tcp" };
    
    *error = [[self util] checkStreamInputWithURL:url formatContext:&formatContext parameters:parameters];
    if (*error) { avformat_close_input(formatContext); return 0; }
    
    int64_t duration = formatContext->duration;
    avformat_close_input(&formatContext);
    
    if (duration > 0) { return (NSTimeInterval)duration / AV_TIME_BASE; }
    return -1;
}

/// 取得本地端影音該時段的畫面
/// - Parameters:
///   - url: NSURL
///   - second: NSTimeInterval
- (UIImage *)frameAtURL:(NSURL *)url second:(NSTimeInterval)second {
    return [self getFrameAtURL:url second:second];
}

/// 尋找縮圖 (平均時間)
/// - Parameters:
///   - url: NSURL
///   - count: 縮圖張數
- (NSArray<UIImage *> *)thumbnailsAtURL:(NSURL *)url count:(int)count {
    
    NSTimeInterval duration = [self durationAtURL:url error:nil];
    if (duration <= 0) return @[];
    
    NSMutableArray *thumbnails = [NSMutableArray array];
    NSTimeInterval interval = duration / count;
    
    for (int index = 0; index < count; index++) {
        NSTimeInterval second = interval * (index + 0.5);
        UIImage *thumbnail = [self frameAtURL:url second:second];
        if (thumbnail) { [thumbnails addObject:thumbnail]; }
    }
    
    return thumbnails;
}

// MARK: - 公開函數
/// 播放RTSP串流 => 使用frame圖片
/// - Parameters:
///   - url: NSURL
///   - frameCallback: 返回畫面 + 時間
///   - errorCallback: 返回錯誤
///   - completionCallback: 播放完成
- (void)playRTSPWithURL:(NSURL *)url frame:(FFmpegFrameWithTimeCallback)frameCallback error:(void (^)(NSError *error))errorCallback  completion:(void (^)(BOOL isFinished))completionCallback {
    
    [self getFrameRTSPWithURL:url frame:^(UIImage * _Nonnull frame, CMTime timestamp) {
        dispatch_async(dispatch_get_main_queue(), ^{ frameCallback(frame, timestamp); });
    } error:^(NSError *error) {
        errorCallback(error);
    } completion:^(BOOL isFinished) {
        completionCallback(isFinished);
    }];
}

/// 播放RTSP串流 => 使用AVSampleBufferDisplayLayer
/// - Parameters:
///   - url: NSURL
///   - displayLayer: AVSampleBufferDisplayLayer
///   - timeCallback: 時間
///   - errorCallback: 返回錯誤
///   - completionCallback: 播放完成
- (void)playRTSPWithURL:(NSURL *)url displayLayer:(AVSampleBufferDisplayLayer *)displayLayer timeStamp:(void (^)(CMTime time))timeCallback error:(void (^)(NSError *error))errorCallback completion:(void (^)(BOOL isFinished))completionCallback {
    
    [self startRTSPPlayWithURL:url displayLayer:displayLayer timeStamp:^(CMTime time) {
        dispatch_async(dispatch_get_main_queue(), ^{ timeCallback(time); });
    } error:^(NSError *error) {
        errorCallback(error);
    } completion:^(BOOL isFinished) {
        completionCallback(isFinished);
    }];
}

/// 播放RTSP串流 => 使用CVPixelBuffer
/// - Parameters:
///   - url: NSURL
///   - pixelBufferCallback: 返回CVPixelBuffer + 時間
///   - errorCallback: 返回錯誤
///   - completionCallback: 播放完成
- (void)playRTSPWithURL:(NSURL *)url pixelBuffer:(FFmpegPixelBufferCallback)pixelBufferCallback error:(void (^)(NSError *error))errorCallback completion:(void (^)(BOOL isFinished))completionCallback {
    
    [self startRTSPPlayWithURL:url pixelBufferCallback:^(CVPixelBufferRef  _Nonnull pixelBuffer, CMTime timeStamp) {
        pixelBufferCallback(pixelBuffer, timeStamp);
    } error:^(NSError * _Nonnull error) {
        errorCallback(error);
    } completion:^(BOOL isFinished) {
        completionCallback(isFinished);
    }];
}

/// 停止播放RTSP串流 => 使用frame圖片
- (void)stopRTSPPlay {
    self.rtspShouldStop = true;
}

/// 停止播放RTSP串流 => 使用AVSampleBufferDisplayLayer
- (void)stopRTSPPlayOnDisplayLayer {
    self.rtspLayerShouldStop = YES;
    AVSampleBufferDisplayLayer *layer = self.currentDisplayLayer;
    if (layer) { dispatch_async(dispatch_get_main_queue(), ^{ [layer flushAndRemoveImage]; });}
}

/// 停止播放RTSP串流 => 使用CVPixelBuffer
- (void)stopRTSPPlayWithPixelBuffer {
    self.rtspPixelShouldStop = YES;
    self.pixelCallback = nil;
}

// MARK: - 🈲 小工具
/// 取得本地端影音該時段的畫面
/// - Parameters:
///   - url: NSURL
///   - second: NSTimeInterval
- (UIImage *)getFrameAtURL:(NSURL *)url second:(NSTimeInterval)second {
    
    AVFormatContext *formatContext = NULL;
    
    NSError *error = [[self util] checkStreamInputWithURL:url formatContext:&formatContext parameters:nil];
    if (error) { return nil; }
    
    int videoStreamIndex = [[self util] streamIndexFromFormatContext:formatContext mediaType:AVMEDIA_TYPE_VIDEO];
    if (videoStreamIndex < 0) { avformat_close_input(&formatContext); return nil; }
    
    int64_t timestamp = av_rescale_q((int64_t)(second * AV_TIME_BASE), (AVRational){1, AV_TIME_BASE}, formatContext->streams[videoStreamIndex]->time_base);
    av_seek_frame(formatContext, videoStreamIndex, timestamp, AVSEEK_FLAG_BACKWARD);
    
    AVCodecContext *codecCtx = avcodec_alloc_context3(NULL);
    AVCodecParameters *parameter = formatContext->streams[videoStreamIndex]->codecpar;
    
    avcodec_parameters_to_context(codecCtx, parameter);
    avcodec_open2(codecCtx, avcodec_find_decoder(parameter->codec_id), NULL);
    av_seek_frame(formatContext, videoStreamIndex, timestamp, AVSEEK_FLAG_BACKWARD);
    avcodec_flush_buffers(codecCtx);
    
    UIImage *image = [[self util] seekFrameAtSecond:second context:formatContext streamIndex:videoStreamIndex];
    avformat_close_input(&formatContext);
    
    return image;
}

/// 取得RTSP串流畫面
/// - Parameters:
///   - url: NSURL
///   - frameCallback: 返回畫面
///   - errorCallback: 返回錯誤
///   - completionCallback: 播放完成
- (void)getFrameRTSPWithURL:(NSURL *)url frame:(FFmpegFrameWithTimeCallback)frameCallback error:(void (^)(NSError *error))errorCallback completion:(void (^)(BOOL isFinished))completionCallback {
    
    if (!url) { return; }
    if (!errorCallback) { return; }
    if (!frameCallback) { return; }
    
    self.rtspShouldStop = false;
    
    __weak typeof(self) weakSelf = self;
    
    dispatch_async(self.rtspQueue, ^{
        
        __strong typeof(self) this = weakSelf;
        if (!this) { return; }
        
        AVFormatContext *formatContext = NULL;
        
        NSDictionary<NSString *, NSString *> *parameters = @{
            @"rtsp_transport": @"tcp",
            @"stimeout": @"5000000",
        };
        
        NSError *error = [[this util] checkStreamInputWithURL:url formatContext:&formatContext parameters:parameters];
        if (error) { avformat_close_input(&formatContext); errorCallback(error); return; }
        
        int videoStreamIndex = [[this util] streamIndexFromFormatContext:formatContext mediaType:AVMEDIA_TYPE_VIDEO];
        
        if (videoStreamIndex < 0) {
            errorCallback([[this util] errorMessage:nil code:FFmpegVideoErrorStreamInfoFailed]);
            avformat_close_input(&formatContext);
            return;
        }
        
        AVStream *stream = formatContext->streams[videoStreamIndex];
        AVCodecContext *codecContext = [[this util] createCodecContextForStream:stream formatContext: formatContext];
        if (codecContext == NULL) { return; }
        
        AVPacket *packet = av_packet_alloc();
        AVFrame *frame = av_frame_alloc();
        
        while (av_read_frame(formatContext, packet) >= 0) {
            
            if (this.rtspShouldStop) { return; }
            if (packet->stream_index != videoStreamIndex) { av_packet_unref(packet); continue; }
            
            avcodec_send_packet(codecContext, packet);
            
            while (avcodec_receive_frame(codecContext, frame) == 0) {
                
                @autoreleasepool {
                    CMTime timeStamp = [[this util] timeFromFrame:frame stream:stream];
                    UIImage *image = [[this util] yuvToImage:frame];
                    frameCallback(image, timeStamp);
                    av_frame_unref(frame);
                }
            }
            
            av_packet_unref(packet);
        }
        
        av_frame_free(&frame);
        av_packet_free(&packet);
        avcodec_free_context(&codecContext);
        avformat_close_input(&formatContext);
        
        completionCallback(true);
    });
}

/// 播放RTSP串流 => 使用CVPixelBuffer
/// - Parameters:
///   - url: NSURL
///   - pixelBufferCallback: 返回CVPixelBufferRef
///   - errorCallback: 返回錯誤
///   - completionCallback: 播放完成
- (void)startRTSPPlayWithURL:(NSURL *)url pixelBufferCallback:(FFmpegPixelBufferCallback)callback error:(void (^)(NSError *error))errorCallback completion:(void (^)(BOOL isFinished))completionCallback {
    
    if (!url) { return; }
    if (!callback) { return; }
    
    self.rtspPixelShouldStop = NO;
    self.pixelCallback = [callback copy];
    
    __weak typeof(self) weakSelf = self;
    
    dispatch_async(self.rtspPixelQueue, ^{
        
        __strong typeof(self) this = weakSelf;
        if (!this) { return; }
        
        AVFormatContext *formatContext = NULL;
        
        NSDictionary<NSString *, NSString *> *parameters = @{
            @"rtsp_transport": @"tcp",
            @"stimeout": @"5000000"
        };
        
        NSError *error = [[this util] checkStreamInputWithURL:url formatContext:&formatContext parameters:parameters];
        if (error) { avformat_close_input(&formatContext); errorCallback(error); return; }
        
        int videoStreamIndex = [[this util] streamIndexFromFormatContext:formatContext mediaType:AVMEDIA_TYPE_VIDEO];
        if (videoStreamIndex < 0) { avformat_close_input(&formatContext); return; }
        
        AVStream* stream = formatContext->streams[videoStreamIndex];
        AVCodecContext *codecContext = [[this util] createCodecContextForStream:stream formatContext: formatContext];
        if (codecContext == NULL) { return; }
        
        enum AVPixelFormat pixelFormat = AV_PIX_FMT_BGRA;
        struct SwsContext *swsContext = [[this util] softwareScalerContextWithCodecContext:codecContext outputFormat:pixelFormat scalerFlags:SWS_BILINEAR];
        
        AVPacket *packet = av_packet_alloc();
        AVFrame *frame = av_frame_alloc();
        
        FFmpegDstBuffer dstBuffer = {0};
        int result = av_image_alloc(dstBuffer.data, dstBuffer.linesize, codecContext->width, codecContext->height, pixelFormat, 1);
        
        if (result < 0) {
            errorCallback([[this util] errorMessageResult:result code:FFmpegVideoErrorImageAllocFailed]);
            av_freep(&dstBuffer.data[0]);
            return;
        }
        
        while (av_read_frame(formatContext, packet) >= 0) {
            
            if (this.rtspPixelShouldStop) { return; }
            if (packet->stream_index != videoStreamIndex) { av_packet_unref(packet); continue; }
            
            avcodec_send_packet(codecContext, packet);
            
            while (avcodec_receive_frame(codecContext, frame) == 0) {
                
                FFmpegSrcBuffer srcBuf = [[this util] prepareSwsSrcFromFrame:frame];
                sws_scale(swsContext, (const uint8_t * const *)srcBuf.slice, srcBuf.stride, 0, codecContext->height, dstBuffer.data, dstBuffer.linesize);
                
                CVPixelBufferRef pixelBuffer = NULL;
                CVReturn cvReturn = [[this util] createPixelBuffer:&pixelBuffer codecContext:codecContext useMetal: true];

                if (cvReturn != kCVReturnSuccess) { continue; }
                if (!pixelBuffer) { continue; }
                
                [[this util] copyDestinationBuffer:dstBuffer to:pixelBuffer codecContext:codecContext];
                
                FFmpegPixelBufferCallback callback = this.pixelCallback;
                
                if (callback) {
                    
                    CFRetain(pixelBuffer);
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        CMTime timeStamp = [[this util] timeFromFrame:frame stream:stream];
                        callback(pixelBuffer, timeStamp);
                        CFRelease(pixelBuffer);
                    });
                }
                
                CVPixelBufferRelease(pixelBuffer);
            }
            av_packet_unref(packet);
        }
        
        av_freep(&dstBuffer.data[0]);
        sws_freeContext(swsContext);
        av_frame_free(&frame);
        av_packet_free(&packet);
        avcodec_free_context(&codecContext);
        avformat_close_input(&formatContext);
        
        completionCallback(true);
    });
}

/// 播放RTSP串流 => 使用AVSampleBufferDisplayLayer
/// - Parameters:
///   - url: NSURL
///   - errorCallback: 返回錯誤
///   - frameCallback: 返回畫面
///   - completionCallback: 播放完成
- (void)startRTSPPlayWithURL:(NSURL *)url displayLayer:(AVSampleBufferDisplayLayer *)displayLayer timeStamp:(void (^)(CMTime time))timeCallback error:(void (^)(NSError *error))errorCallback completion:(void (^)(BOOL isFinished))completionCallback {
    
    if (!url) { return; }
    if (!displayLayer) { return; }

    self.rtspLayerShouldStop = NO;
    self.currentDisplayLayer = displayLayer;
    
    __weak typeof(self) weakSelf = self;
    
    dispatch_async(self.rtspLayerQueue, ^{
        
        __strong typeof(self) this = weakSelf;
        if (!this) { return; }
        
        AVFormatContext *formatContext = NULL;
        
        NSDictionary<NSString *, NSString *> *parameters = @{
            @"rtsp_transport": @"tcp",
            @"stimeout": @"5000000"
        };
        
        NSError *error = [[this util] checkStreamInputWithURL:url formatContext:&formatContext parameters:parameters];
        if (error) { avformat_close_input(&formatContext); errorCallback(error); return; }
        
        int videoStreamIndex = [[this util] streamIndexFromFormatContext:formatContext mediaType:AVMEDIA_TYPE_VIDEO];
        if (videoStreamIndex < 0) {
            errorCallback([[this util] errorMessage:nil code:FFmpegVideoErrorStreamInfoFailed]);
            avformat_close_input(&formatContext);
            return;
        }
        
        AVStream* stream = formatContext->streams[videoStreamIndex];
        AVCodecContext *codecContext = [[this util] createCodecContextForStream:stream formatContext: formatContext];
        if (codecContext == NULL) { return; }
        
        enum AVPixelFormat pixelFormat = AV_PIX_FMT_BGRA;
        struct SwsContext *swsContext = [[this util] softwareScalerContextWithCodecContext:codecContext outputFormat:pixelFormat scalerFlags:SWS_BILINEAR];
        
        AVPacket *packet = av_packet_alloc();
        AVFrame *frame = av_frame_alloc();
        
        FFmpegDstBuffer dstBuffer = {0};
        int result = av_image_alloc(dstBuffer.data, dstBuffer.linesize, codecContext->width, codecContext->height, pixelFormat, 1);
        
        if (result < 0) {
            errorCallback([[this util] errorMessageResult:result code:FFmpegVideoErrorImageAllocFailed]);
            av_freep(&dstBuffer.data[0]);
            return;
        }
        
        AVRational timeBase = stream->time_base;
        
        while (av_read_frame(formatContext, packet) >= 0) {
            
            if (this.rtspLayerShouldStop) { return; }
            if (packet->stream_index != videoStreamIndex) { av_packet_unref(packet); continue; }
            
            avcodec_send_packet(codecContext, packet);
            
            while (avcodec_receive_frame(codecContext, frame) == 0) {
                
                FFmpegSrcBuffer srcBuf = [[this util] prepareSwsSrcFromFrame:frame];
                sws_scale(swsContext, (const uint8_t * const *)srcBuf.slice, srcBuf.stride, 0, codecContext->height, dstBuffer.data, dstBuffer.linesize);
                
                CVPixelBufferRef pixelBuffer = NULL;
                CVReturn cvReturn = [[this util] createPixelBuffer:&pixelBuffer codecContext:codecContext useMetal: false];
                
                if (cvReturn != kCVReturnSuccess) { continue; }
                if (!pixelBuffer) { continue; }
                
                [[this util] copyDestinationBuffer:dstBuffer to:pixelBuffer codecContext:codecContext];
                
                CMTime timeStamp = [[this util] timeFromFrame:frame stream:stream];
                CMSampleBufferRef sampleBuffer = NULL;
                
                OSStatus status = [[this util] convertPixelBuffer:pixelBuffer to:&sampleBuffer time:timeStamp];
                CVPixelBufferRelease(pixelBuffer);
                
                timeCallback(timeStamp);
                
                if (status != noErr) { continue; }
                if (!sampleBuffer) { continue; }
                
                AVSampleBufferDisplayLayer *displayLayer = this.currentDisplayLayer;
                
                if (displayLayer) {
                    
                    CFRetain(sampleBuffer);
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        
                        if (this.rtspLayerShouldStop) { CFRelease(sampleBuffer); return; }
                        AVSampleBufferDisplayLayer *strongLayer = this.currentDisplayLayer;
                        
                        if (!strongLayer) { CFRelease(sampleBuffer); return; }
                        if (strongLayer.status == AVQueuedSampleBufferRenderingStatusFailed) { [strongLayer flushAndRemoveImage]; }
                        if (strongLayer.isReadyForMoreMediaData) { [strongLayer enqueueSampleBuffer:sampleBuffer]; }
                        
                        CFRelease(sampleBuffer);
                    });
                }
                
                CFRelease(sampleBuffer);
            }
            
            av_packet_unref(packet);
        }
        
        av_freep(&dstBuffer.data[0]);
        sws_freeContext(swsContext);
        av_frame_free(&frame);
        av_packet_free(&packet);
        avcodec_free_context(&codecContext);
        avformat_close_input(&formatContext);
        
        completionCallback(true);
    });
}

// MARK: - 小工具
/// TODO: 播放聲音
- (void)playPCM:(NSData *)pcmData sampleRate:(int)sampleRate channels:(int)channels {
    [[StreamPlayer shared] playPCM:pcmData sampleRate:sampleRate channels:channels];
}

- (void)decodeAudioStream:(NSURL *)url codecCallback:(void (^)(AVCodecParameters *parameters))codecCallback pcmCallback:(FFmpegPCMCallback)pcmCallback {
    
    [self findAudioStream:url codecCallback:codecCallback decodeCallback:^(AVFormatContext * _Nonnull formatContext, NSInteger audioStreamIndex) {
        [self startAudioDecodeLoop:formatContext audioStreamIndex:audioStreamIndex pcmCallback:pcmCallback];
    }];
}

- (void)findAudioStream:(NSURL *)url codecCallback:(void (^)(AVCodecParameters *parameters))codecCallback decodeCallback:(FFmpegDecodeCallback)decodeCallback {
    
    AVFormatContext *formatContext = NULL;
    
    int result = avformat_open_input(&formatContext, [[url absoluteString] UTF8String], NULL, NULL);
    
    if (result < 0) {
        char errbuf[256];
        av_strerror(result, errbuf, sizeof(errbuf));
        NSLog(@"開啟失敗: %s", errbuf);
        return;
    }
    
    if (avformat_find_stream_info(formatContext, NULL) < 0) { return; }
    
    NSInteger audioStreamIndex = -1;
    NSString *codecName = nil;
    
    for (NSInteger index = 0; index < formatContext->nb_streams; index++) {
        if (formatContext->streams[index]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            audioStreamIndex = index;
            codecName = [NSString stringWithUTF8String:avcodec_get_name(formatContext->streams[index]->codecpar->codec_id)];
            NSLog(@"音訊串流: %ld, %@", (long)index, codecName);
            break;
        }
    }
    
    if (audioStreamIndex < 0) { avformat_close_input(&formatContext); return; }
    
    if (codecCallback) {
        AVStream *audioStream = formatContext->streams[audioStreamIndex];
        codecCallback(audioStream->codecpar);
    }
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (decodeCallback) {
            decodeCallback(formatContext, audioStreamIndex);
        }
    });
}

- (void)startAudioDecodeLoop:(AVFormatContext *)formatContext
             audioStreamIndex:(NSInteger)audioStreamIndex
                 pcmCallback:(FFmpegPCMCallback)pcmCallback {
    
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {  // 防洩漏 [cite:2]
            __strong typeof(self) self = weakSelf;
            if (!self) return;
            
            AVStream *audioStream = formatContext->streams[audioStreamIndex];
            AVCodecParameters *codecpar = audioStream->codecpar;
            
            AVCodec *decoder = avcodec_find_decoder(codecpar->codec_id);
            if (!decoder) {
                NSLog(@"找不到解碼器");
                goto cleanup;
            }
            
            AVCodecContext *decCtx = avcodec_alloc_context3(decoder);
            avcodec_parameters_to_context(decCtx, codecpar);
            if (avcodec_open2(decCtx, decoder, NULL) < 0) {
                NSLog(@"開啟解碼器失敗");
                goto cleanup;
            }
            
            AVPacket *pkt = av_packet_alloc();
            AVFrame *frame = av_frame_alloc();
            
            int ret;
            while ((ret = av_read_frame(formatContext, pkt)) >= 0) {
                if (pkt->stream_index == audioStreamIndex) {
                    ret = avcodec_send_packet(decCtx, pkt);
                    if (ret < 0 && ret != AVERROR(EAGAIN)) continue;
                    
                    while ((ret = avcodec_receive_frame(decCtx, frame)) == 0) {
                        // 手動交錯（無 SWR，穩定）
                        int channels = decCtx->ch_layout.nb_channels ?: codecpar->ch_layout.nb_channels;
                        int pcmSize = frame->nb_samples * channels * 2;  // S16
                        uint8_t *pcmBuf = malloc(pcmSize);
                        int16_t *dst = (int16_t*)pcmBuf;
                        
                        if (channels == 1) {
                            memcpy(dst, frame->data[0], pcmSize);
                        } else if (channels == 2) {
                            int16_t *left = (int16_t*)frame->data[0];
                            int16_t *right = (int16_t*)frame->data[1];
                            for (int i = 0; i < frame->nb_samples; i++) {
                                dst[i*2] = left[i];
                                dst[i*2+1] = right[i];
                            }
                        } else {
                            free(pcmBuf); continue;  // 暫不支援 >2ch
                        }
                        
                        if (pcmCallback) {
                            NSData *pcmData = [NSData dataWithBytesNoCopy:pcmBuf
                                                                   length:pcmSize
                                                         freeWhenDone:YES];
                            pcmCallback(pcmData, decCtx->sample_rate, channels);
                        }
                        
                        av_frame_unref(frame);
                    }
                }
                av_packet_unref(pkt);
            }
            
        cleanup:
            av_packet_free(&pkt);
            av_frame_free(&frame);
            if (decCtx) avcodec_free_context(&decCtx);
            avformat_close_input(&formatContext);  // **這裡關閉**
        }
    });
}


@end



