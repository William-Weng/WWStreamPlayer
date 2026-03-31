#import <AudioToolbox/AudioToolbox.h>
#import "StreamPlayer.h"
#import "AVFoundation/AVFoundation.h"

// WWStreamPlayer.m
//@implementation StreamPlayer: NSObject {
//    AudioQueueRef _audioQueue;
//    AudioStreamBasicDescription _asbd;
//    AudioQueueBufferRef _buffers[3];  // 3 buffers 輪詢
//    int _bufferIndex;
//    BOOL _isInitialized;
//    dispatch_queue_t _queue;
//}
//
//+ (instancetype)shared {
//    static StreamPlayer *shared = nil;
//    static dispatch_once_t onceToken;
//    dispatch_once(&onceToken, ^{
//        shared = [[StreamPlayer alloc] init];
//    });
//    return shared;
//}
//
//- (instancetype)init {
//    self = [super init];
//    if (self) {
//        _queue = dispatch_queue_create("audio.queue", DISPATCH_QUEUE_SERIAL);
//        _bufferIndex = 0;
//    }
//    return self;
//}
//
//- (void)playPCM:(NSData *)pcmData sampleRate:(int)sampleRate channels:(int)channels {
//    NSLog(@"✅ PCM %lu bytes", pcmData.length);
//    
//    NSMutableData *wav = [NSMutableData dataWithCapacity:pcmData.length + 44];
//    
//    // **正確 Big Endian WAV**（htonl/htons）
//    uint32_t riff; riff = CFSwapInt32HostToBig('RIFF');
//    [wav appendBytes:&riff length:4];
//    uint32_t size = CFSwapInt32HostToBig((uint32_t)(pcmData.length + 36));
//    [wav appendBytes:&size length:4];
//    uint32_t wave; wave = CFSwapInt32HostToBig('WAVE');
//    [wav appendBytes:&wave length:4];
//    
//    uint32_t fmt; fmt = CFSwapInt32HostToBig('fmt ');
//    [wav appendBytes:&fmt length:4];
//    uint32_t fmtlen = CFSwapInt32HostToBig(16);
//    [wav appendBytes:&fmtlen length:4];
//    
//    uint16_t pcm = CFSwapInt16HostToBig(1);  // PCM format
//    [wav appendBytes:&pcm length:2];
//    uint16_t ch = CFSwapInt16HostToBig(channels);
//    [wav appendBytes:&ch length:2];
//    uint32_t sr = CFSwapInt32HostToBig(sampleRate);
//    [wav appendBytes:&sr length:4];
//    uint32_t bps = CFSwapInt32HostToBig(sampleRate * channels * 2);
//    [wav appendBytes:&bps length:4];
//    uint16_t align = CFSwapInt16HostToBig(channels * 2);
//    [wav appendBytes:&align length:2];
//    uint16_t bits = CFSwapInt16HostToBig(16);
//    [wav appendBytes:&bits length:2];
//    
//    uint32_t data; data = CFSwapInt32HostToBig('data');
//    [wav appendBytes:&data length:4];
//    uint32_t datalen = CFSwapInt32HostToBig(pcmData.length);
//    [wav appendBytes:&datalen length:4];
//    
//    [wav appendData:pcmData];
//    
//    NSError *error;
//    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithData:wav error:&error];
//    if (!error) {
//        player.volume = 1.0;
//        [player play];
//        NSLog(@"🔊 播放中...");
//    } else {
//        NSLog(@"❌ AVAudioPlayer: %@", error);
//    }
//}
//
//- (void)setupAudioQueueWithSampleRate:(int)sampleRate channels:(int)channels {
//    NSLog(@"🔧 %d Hz %d ch", sampleRate, channels);
//    [self teardownAudioQueue];
//    
//    // **Session 先啟動**
//    NSError *error = nil;
//    AVAudioSession *session = [AVAudioSession sharedInstance];
//    
//    // 播放 + 混音 + 背景
//    [session setCategory:AVAudioSessionCategoryPlayback
//                    mode:AVAudioSessionModeDefault
//                 options:AVAudioSessionCategoryOptionMixWithOthers |
//                         AVAudioSessionCategoryOptionDuckOthers
//                  error:&error];
//    
//    NSLog(@"Category: %@", error ? error : @"OK");
//    
//    [session setActive:YES error:&error];
//    NSLog(@"Active: %@", error ? error : @"OK");
//    
//    if (error) {
//        NSLog(@"❌ Session 失敗，試無混音");
//        [session setCategory:AVAudioSessionCategoryPlayback error:NULL];
//        [session setActive:YES error:NULL];
//    }
//    
//    // **標準 ASBD**（Apple 示例）
//    memset(&_asbd, 0, sizeof(_asbd));
//    _asbd.mSampleRate = sampleRate;
//    _asbd.mChannelsPerFrame = channels;
//    _asbd.mFormatID = kAudioFormatLinearPCM;
//    _asbd.mBitsPerChannel = 16;
//    _asbd.mBytesPerFrame = 2 * channels;
//    _asbd.mFramesPerPacket = 1;
//    _asbd.mBytesPerPacket = 2 * channels;
//    _asbd.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
//    
//    OSStatus status = AudioQueueNewOutput(&_asbd, NULL, (__bridge void*)self,
//                                         CFSTR("PCM"), 0, NULL, &_audioQueue);
//    NSLog(@"NewOutput: %d", (int)status);
//    
//    if (status == noErr) {
//        AudioQueueAllocateBuffer(_audioQueue, 4096, &_buffers[0]);
//        AudioQueueAllocateBuffer(_audioQueue, 4096, &_buffers[1]);
//        AudioQueueAllocateBuffer(_audioQueue, 4096, &_buffers[2]);
//        AudioQueueStart(_audioQueue, NULL);
//        NSLog(@"✅ 成功");
//    }
//}
//
//- (void)teardownAudioQueue {
//    if (_audioQueue) {
//        AudioQueueStop(_audioQueue, YES);
//        AudioQueueDispose(_audioQueue, YES);
//        _audioQueue = NULL;
//    }
//    for (int i = 0; i < 3; i++) {
//        _buffers[i] = NULL;  // 清空指標
//    }
//    _isInitialized = NO;
//}

@implementation StreamPlayer {
    AVAudioPlayer *_player;
}

+ (instancetype)shared {
    static StreamPlayer *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[StreamPlayer alloc] init];
    });
    return shared;
}

- (void)saveWAV:(NSData*)wavData {
    
    // **存檔驗證**
    NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"test_audio.wav"];
    BOOL success = [wavData writeToFile:filePath atomically:YES];
    NSLog(@"💾 WAV 存檔: %@ (%@)", filePath, success ? @"成功" : @"失敗");
    
    // 用 Files.app 或 Finder 開
    NSLog(@"用 VLC/Audacity 開: %@", filePath);
}

- (void)playPCM:(NSData *)pcmData sampleRate:(int)sampleRate channels:(int)channels {
    NSLog(@"✅ PCM %lu bytes @ %d Hz %d ch", (unsigned long)pcmData.length, sampleRate, channels);
    
    // **方案 2：即時 WAV**
    NSMutableData *wavData = [self createWavFromPCM:pcmData sampleRate:sampleRate channels:channels];
    
    NSError *error;
    AVAudioPlayer *newPlayer = [[AVAudioPlayer alloc] initWithData:wavData error:&error];
    
    [self saveWAV:wavData];
    
    if (!error && newPlayer) {
        newPlayer.volume = 1.0;
        newPlayer.enableRate = YES;
        [newPlayer prepareToPlay];
        [newPlayer play];
        NSLog(@"🔊 AVAudioPlayer 播放");
        
        // 釋放舊 player
        [_player stop];
        _player = newPlayer;
    } else {
        NSLog(@"❌ AVAudioPlayer 失敗: %@", error);
    }
}

- (NSData *)createWavFromPCM:(NSData *)pcmData sampleRate:(int)sampleRate channels:(int)channels {
    
    NSUInteger pcmSize = pcmData.length;
    if (pcmSize == 0 || pcmSize % (channels * 2) != 0) return nil;
    
    NSMutableData *wav = [NSMutableData dataWithLength:44 + pcmSize];
    uint8_t *header = wav.mutableBytes;
    
    // **Little Endian 直接寫**（移除所有 CFSwap）
    memcpy(header + 0,  "RIFF", 4);
    *(uint32_t*)(header + 4)  = (uint32_t)(36u + pcmSize);  // Little!
    memcpy(header + 8,  "WAVE", 4);
    memcpy(header + 12, "fmt ", 4);
    *(uint32_t*)(header + 16) = 16;
    *(uint16_t*)(header + 20) = 1;   // PCM
    *(uint16_t*)(header + 22) = (uint16_t)channels;
    *(uint32_t*)(header + 24) = (uint32_t)sampleRate;
    uint32_t byteRate = (uint32_t)(sampleRate * channels * 2);
    *(uint32_t*)(header + 28) = byteRate;
    *(uint16_t*)(header + 32) = (uint16_t)(channels * 2);
    *(uint16_t*)(header + 34) = 16;  // 16 bit
    
    memcpy(header + 36, "data", 4);
    *(uint32_t*)(header + 40) = (uint32_t)pcmSize;
    
    memcpy(header + 44, pcmData.bytes, pcmSize);
    return wav;
}

- (void)stop {
    [_player stop];
    _player = nil;
}

@end
