//
//  FFmpegWrapper.m
//  FFmpegWrapper
//
//  Created by William.Weng on 2026/3/27.
//

#import "FFmpegWrapper.h"
#import "Model.h"

@interface FFmpegWrapper ()

@property (nonatomic, strong) dispatch_queue_t rtspQueue;
@property (nonatomic, strong) dispatch_queue_t rtspLayerQueue;
@property (nonatomic, strong) dispatch_queue_t rtspPixelQueue;

@property (atomic, assign) BOOL rtspShouldStop;
@property (atomic, assign) BOOL rtspLayerShouldStop;
@property (atomic, assign) BOOL rtspPixelShouldStop;

@property (nonatomic, weak) AVSampleBufferDisplayLayer *currentDisplayLayer;
@property (nonatomic, copy) FFmpegPixelBufferCallback pixelCallback;

@end

@implementation FFmpegWrapper

/// 單例
+ (instancetype)shared {
    
    static FFmpegWrapper *instance = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{ instance = [[FFmpegWrapper alloc] init]; });
    
    return instance;
}

/// 初始化
- (instancetype)init {
    
    self = [super init];
    
    if (self) {
        
        avformat_network_init();
        
        _rtspLayerQueue = dispatch_queue_create("ffmpeg.rtsp.displaylayer.queue", DISPATCH_QUEUE_SERIAL);
        _rtspQueue = dispatch_queue_create("ffmpeg.rtsp.queue", DISPATCH_QUEUE_SERIAL);
        _rtspPixelQueue = dispatch_queue_create("ffmpeg.rtsp.pixel.queue", DISPATCH_QUEUE_SERIAL);
    }
    
    return self;
}

// MARK: - 公開函數
/// 取得FFMpeg版本
- (NSString *)version {
    return [NSString stringWithUTF8String:av_version_info()];
}

/// 取得該URL的影音長度 (0: 錯誤 / -1: RTSP直播 => 無限長) => ffmpeg -rtsp_transport tcp -i rtsp://xxx
/// - Parameters:
///   - url: NSURL
///   - error: NSError
- (NSTimeInterval)durationAtURL:(NSURL *)url error:(NSError **)error {
    
    if (!url) {
        if (error) { *error = [self errorMessage:nil code:FFmpegVideoErrorInvalidURL]; }
        return 0;
    }
    
    if (![(NSString *)[url absoluteString] length]) {
        if (error) { *error = [self errorMessage:nil code:FFmpegVideoErrorInvalidURL]; }
        return 0;
    }
    
    AVFormatContext *formatContext = NULL;
    NSDictionary<NSString *, NSString *> *parameters = @{ @"rtsp_transport": @"tcp" };
    
    *error = [self checkStreamInputWithURL:url formatContext:&formatContext parameters:parameters];
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
    
    AVFormatContext *formatContext = NULL;
    
    NSError *error = [self checkStreamInputWithURL:url formatContext:&formatContext parameters:nil];
    if (error) { return nil; }
    
    int videoStreamIndex = [self videoStreamIndexWithFormatContext:formatContext];
    if (videoStreamIndex < 0) { avformat_close_input(&formatContext); return nil; }
    
    int64_t timestamp = av_rescale_q((int64_t)(second * AV_TIME_BASE), (AVRational){1, AV_TIME_BASE}, formatContext->streams[videoStreamIndex]->time_base);
    av_seek_frame(formatContext, videoStreamIndex, timestamp, AVSEEK_FLAG_BACKWARD);
    
    AVCodecContext *codecCtx = avcodec_alloc_context3(NULL);
    AVCodecParameters *parameter = formatContext->streams[videoStreamIndex]->codecpar;
    
    avcodec_parameters_to_context(codecCtx, parameter);
    avcodec_open2(codecCtx, avcodec_find_decoder(parameter->codec_id), NULL);
    av_seek_frame(formatContext, videoStreamIndex, timestamp, AVSEEK_FLAG_BACKWARD);
    avcodec_flush_buffers(codecCtx);
    
    UIImage *image = [self seekFrameAtSecond:second context:formatContext streamIndex:videoStreamIndex];
    avformat_close_input(&formatContext);
    
    return image;
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
        UIImage *thumb = [self frameAtURL:url second:second];
        if (thumb) { [thumbnails addObject:thumb]; }
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

// MARK: - 小工具
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
            @"stimeout": @"5_000_000",
        };
        
        NSError *error = [self checkStreamInputWithURL:url formatContext:&formatContext parameters:parameters];
        if (error) { avformat_close_input(&formatContext); errorCallback(error); return; }
        
        int videoStreamIndex = [this videoStreamIndexWithFormatContext:formatContext];
        
        if (videoStreamIndex < 0) {
            errorCallback([this errorMessage:nil code:FFmpegVideoErrorStreamInfoFailed]);
            avformat_close_input(&formatContext);
            return;
        }
        
        AVStream *stream = formatContext->streams[videoStreamIndex];
        AVCodecContext *codecContext = [this createCodecContextForStream:stream formatContext: formatContext];
        if (codecContext == NULL) { return; }
        
        AVPacket *packet = av_packet_alloc();
        AVFrame *frame = av_frame_alloc();
        
        while (av_read_frame(formatContext, packet) >= 0) {
            
            if (this.rtspShouldStop) { return; }
            if (packet->stream_index != videoStreamIndex) { av_packet_unref(packet); continue; }
            
            avcodec_send_packet(codecContext, packet);
            
            while (avcodec_receive_frame(codecContext, frame) == 0) {
                
                @autoreleasepool {
                    CMTime timeStamp = [this timeFromFrame:frame stream:stream];
                    UIImage *image = [self yuvToImage:frame];
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
            @"stimeout": @"5_000_000"
        };
        
        NSError *error = [self checkStreamInputWithURL:url formatContext:&formatContext parameters:parameters];
        if (error) { avformat_close_input(&formatContext); errorCallback(error); return; }
        
        int videoStreamIndex = [this videoStreamIndexWithFormatContext:formatContext];
        if (videoStreamIndex < 0) { avformat_close_input(&formatContext); return; }
        
        AVStream* stream = formatContext->streams[videoStreamIndex];
        AVCodecContext *codecContext = [this createCodecContextForStream:stream formatContext: formatContext];
        if (codecContext == NULL) { return; }
        
        enum AVPixelFormat pixelFormat = AV_PIX_FMT_BGRA;
        struct SwsContext *swsContext = [this softwareScalerContextWithCodecContext:codecContext outputFormat:pixelFormat scalerFlags:SWS_BILINEAR];
        
        AVPacket *packet = av_packet_alloc();
        AVFrame *frame = av_frame_alloc();
        
        FFmpegDstBuffer dstBuffer = {0};
        int result = av_image_alloc(dstBuffer.data, dstBuffer.linesize, codecContext->width, codecContext->height, pixelFormat, 1);
        
        if (result < 0) {
            errorCallback([this errorMessageResult:result code:FFmpegVideoErrorImageAllocFailed]);
            av_freep(&dstBuffer.data[0]);
            return;
        }
        
        while (av_read_frame(formatContext, packet) >= 0) {
            
            if (this.rtspPixelShouldStop) { return; }
            if (packet->stream_index != videoStreamIndex) { av_packet_unref(packet); continue; }
            
            avcodec_send_packet(codecContext, packet);
            
            while(avcodec_receive_frame(codecContext, frame) == 0) {
                
                FFmpegSrcBuffer srcBuf = [this prepareSwsSrcFromFrame:frame];
                sws_scale(swsContext, (const uint8_t * const *)srcBuf.slice, srcBuf.stride, 0, codecContext->height, dstBuffer.data, dstBuffer.linesize);
                
                CVPixelBufferRef pixelBuffer = NULL;
                CVReturn cvReturn = [this createMetalPixelBuffer:&pixelBuffer codecContext:codecContext];

                if (cvReturn != kCVReturnSuccess) { continue; }
                if (!pixelBuffer) { continue; }
                
                [this copyDestinationBuffer:dstBuffer to:pixelBuffer codecContext:codecContext];
                
                FFmpegPixelBufferCallback callback = this.pixelCallback;
                
                if (callback) {
                    
                    CFRetain(pixelBuffer);
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        CMTime timeStamp = [this timeFromFrame:frame stream:stream];
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
            @"stimeout": @"5_000_000"
        };
        
        NSError *error = [self checkStreamInputWithURL:url formatContext:&formatContext parameters:parameters];
        if (error) { avformat_close_input(&formatContext); errorCallback(error); return; }
        
        int videoStreamIndex = [this videoStreamIndexWithFormatContext:formatContext];
        if (videoStreamIndex < 0) {
            errorCallback([this errorMessage:nil code:FFmpegVideoErrorStreamInfoFailed]);
            avformat_close_input(&formatContext);
            return;
        }
        
        AVStream* stream = formatContext->streams[videoStreamIndex];
        AVCodecContext *codecContext = [this createCodecContextForStream:stream formatContext: formatContext];
        if (codecContext == NULL) { return; }
        
        enum AVPixelFormat pixelFormat = AV_PIX_FMT_BGRA;
        struct SwsContext *swsContext = [this softwareScalerContextWithCodecContext:codecContext outputFormat:pixelFormat scalerFlags:SWS_BILINEAR];
        
        AVPacket *packet = av_packet_alloc();
        AVFrame *frame = av_frame_alloc();
        
        FFmpegDstBuffer dstBuffer = {0};
        int result = av_image_alloc(dstBuffer.data, dstBuffer.linesize, codecContext->width, codecContext->height, pixelFormat, 1);
        
        if (result < 0) {
            errorCallback([this errorMessageResult:result code:FFmpegVideoErrorImageAllocFailed]);
            av_freep(&dstBuffer.data[0]);
            return;
        }
        
        AVRational timeBase = stream->time_base;
        
        while (av_read_frame(formatContext, packet) >= 0) {
            
            if (this.rtspLayerShouldStop) { return; }
            if (packet->stream_index != videoStreamIndex) { av_packet_unref(packet); continue; }
            
            avcodec_send_packet(codecContext, packet);
            
            while (avcodec_receive_frame(codecContext, frame) == 0) {
                
                FFmpegSrcBuffer srcBuf = [this prepareSwsSrcFromFrame:frame];
                sws_scale(swsContext, (const uint8_t * const *)srcBuf.slice, srcBuf.stride, 0, codecContext->height, dstBuffer.data, dstBuffer.linesize);
                
                CVPixelBufferRef pixelBuffer = NULL;
                CVReturn cvReturn = [this createPixelBuffer: &pixelBuffer codecContext:codecContext];
                
                if (cvReturn != kCVReturnSuccess) { continue; }
                if (!pixelBuffer) { continue; }
                
                [this copyDestinationBuffer:dstBuffer to:pixelBuffer codecContext:codecContext];
                                
                CMTime timeStamp = [this timeFromFrame:frame stream:stream];
                CMSampleBufferRef sampleBuffer = NULL;
                
                OSStatus status = [this convertPixelBuffer:pixelBuffer to:&sampleBuffer time:timeStamp];
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
/// 尋找該秒的Frame (畫面)
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

/// 找出哪一條 stream 是視訊，並回傳那條 stream 的 index
/// - Parameter formatContext: AVFormatContext
- (int)videoStreamIndexWithFormatContext:(AVFormatContext *)formatContext {
    
    for (int index = 0; index < formatContext->nb_streams; index++) {
        
        AVStream *stream = formatContext->streams[index];
        AVCodecParameters *codecpar = stream->codecpar;
        
        if (codecpar && codecpar->codec_type == AVMEDIA_TYPE_VIDEO) { return index; }
    }
    
    return -1;
}

// MARK: - 小工具 (FFMpeg)
/// 測試影片路徑是否正確 (能不能打開 / 讀不讀得到)
/// - Parameters:
///   - url: NSURL
///   - formatContext: AVFormatContext
///   - parameters: NSDictionary*
- (NSError *)checkStreamInputWithURL:(NSURL *)url formatContext:(AVFormatContext **)formatContext parameters:(NSDictionary<NSString *, NSString *> *)parameters {
    
    int result = [self openRemoteInputWithContext:formatContext parameters:parameters url:url];
    if (result < 0) { return [self errorMessageResult:result code:FFmpegVideoErrorOpenFailed]; }
    
    result = [self findStreamInformationWithContext:*formatContext];
    if (result < 0) { return [self errorMessageResult:result code:FFmpegVideoErrorStreamInfoFailed]; }
    
    return nil;
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

/// 產生SwsContext
/// - Parameters:
///   - frame: AVFrame
///   - dstFormat: 像素格式
///   - scalerFlags: 轉換時的插值算法
- (struct SwsContext *)softwareScalerContextWithFrame:(AVFrame*)frame outputFormat:(enum AVPixelFormat)dstFormat scalerFlags:(int)scalerFlags {
    enum AVPixelFormat srcFmt = frame->format;
    return sws_getContext(frame->width, frame->height, srcFmt, frame->width, frame->height, dstFormat, scalerFlags, NULL, NULL, NULL);
}

/// 產生SwsContext =>  轉成 BGRA，方便塞進 CVPixelBuffer (kCVPixelFormatType_32BGRA)
/// - Parameters:
///   - codecContext: AVCodecContext
///   - dstFormat: 像素格式
///   - scalerFlags: 轉換時的插值算法
- (struct SwsContext *)softwareScalerContextWithCodecContext:(AVCodecContext*)codecContext outputFormat:(enum AVPixelFormat)dstFormat scalerFlags:(int)scalerFlags {
    enum AVPixelFormat srcFmt = codecContext->pix_fmt;
    return sws_getContext(codecContext->width, codecContext->height, srcFmt, codecContext->width, codecContext->height, dstFormat, scalerFlags, NULL, NULL, NULL);
}

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

/// 取得影片時間 (CMTime)
/// - Parameters:
///   - frame: AVFrame
///   - stream: AVStream
- (CMTime)timeFromFrame:(AVFrame *)frame stream:(AVStream *)stream {
    
    // CMTime timeStamp = CMTimeMake(frame->best_effort_timestamp * timeBase.num, timeBase.den);
    
    AVRational timeBase = stream->time_base;
    int64_t bestTimestamp = frame->best_effort_timestamp;
    CMTime timeStamp = CMTimeMake(bestTimestamp * timeBase.num, timeBase.den);
    
    return timeStamp;
}

/// 取得影片時間 (Second)
/// - Parameters:
///   - frame: AVFrame
///   - stream: AVFrame
- (NSTimeInterval)secondFromFrame:(AVFrame *)frame stream:(AVFrame *)stream {
    CMTime time = [self timeFromFrame:frame stream:stream];
    return  CMTimeGetSeconds(time);
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

/// 設定AVDictionary
/// - Parameter parameters: NSDictionary *
- (AVDictionary*)avDictionaryWithParameters:(NSDictionary *)parameters {
    
    AVDictionary *options = NULL;
    
    for (NSString *key in parameters) {
        NSString *value = parameters[key];
        av_dict_set(&options, [key UTF8String], [value UTF8String], 0);
    }
    
    return options;
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

/// 建立CVPixelBuffer
/// - Parameters:
///   - pixelBuffer: CVPixelBufferRef
///   - codecContext: AVCodecContext
- (CVReturn)createPixelBuffer:(CVPixelBufferRef *)pixelBuffer codecContext:(AVCodecContext *)codecContext {
    
    NSDictionary *attributes = @{
        (__bridge NSString *)kCVPixelBufferCGImageCompatibilityKey : @YES,
        (__bridge NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES
    };
    
    CVReturn cvReturn = CVPixelBufferCreate(kCFAllocatorDefault, codecContext->width, codecContext->height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attributes, pixelBuffer);
    return cvReturn;
}

/// 建立CVPixelBuffer (for MetalKit)
/// - Parameters:
///   - pixelBuffer: CVPixelBufferRef
///   - codecContext: AVCodecContext
- (CVReturn)createMetalPixelBuffer:(CVPixelBufferRef *)pixelBuffer codecContext:(AVCodecContext *)codecContext {
    
    NSDictionary *attributes = @{
        (__bridge NSString *)kCVPixelBufferCGImageCompatibilityKey : @YES,
        (__bridge NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
        (__bridge NSString *)kCVPixelBufferMetalCompatibilityKey : @YES
    };
    
    CVReturn cvReturn = CVPixelBufferCreate(kCFAllocatorDefault, codecContext->width, codecContext->height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attributes, pixelBuffer);
    return cvReturn;
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

// MARK: - 小工具
/// 產生錯誤訊息
/// - Parameters:
///   - message: NSString
///   - code: FFmpegVideoError
- (NSError *)errorMessage:(NSString *)message code:(FFmpegVideoError)code {

    NSString *localizedDescription;
    
    switch (code) {
        case FFmpegVideoErrorInvalidURL: localizedDescription = @"Invalid URL"; break;
        case FFmpegVideoErrorOpenFailed: localizedDescription = @"Could not open stream"; break;
        case FFmpegVideoErrorStreamInfoFailed: localizedDescription = @"Failed to read stream info"; break;
        default: localizedDescription = message; break;
    }
    
    NSDictionary* userInfo = @{
        NSLocalizedDescriptionKey: localizedDescription,
        @"ffmpegError": message
    };
    
    NSError *error = [NSError errorWithDomain:@"FFmpegVideoErrorDomain" code:code userInfo:userInfo];
    return error;
}

/// 產生錯誤訊息 (av_err2str)
/// - Parameters:
///   - result: int
///   - code: FFmpegVideoError
- (NSError *)errorMessageResult:(int)result code:(FFmpegVideoError)code {
    NSString *message = [NSString stringWithUTF8String: av_err2str(result)];
    return [self errorMessage:message code:code];
}

@end
