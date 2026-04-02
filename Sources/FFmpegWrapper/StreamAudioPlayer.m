//
//  StreamAudioPlayer.m
//  WWStreamPlayer
//
//  Created by William.Weng on 2026/4/1.
//

#import <AudioToolbox/AudioToolbox.h>
#import "AVFoundation/AVFoundation.h"
#import "StreamAudioPlayer.h"
#import "Model.h"
#import "Utility.h"

@implementation StreamAudioPlayer {
    AVAudioPlayer *_player;
}

// MARK: - 公開函數
/// 播放PCM (轉成WAV)
/// - Parameters:
///   - pcmData: PCM資料
///   - sampleRate: 聲音取樣頻率 (22000Hz / 44100Hz)
///   - channels: 聲音通道數 (單 / 雙通道)
///   - error: NSError
/// - Returns: Result<Bool, Error>
- (void)playPCM:(NSData *)pcmData sampleRate:(int)sampleRate channels:(int)channels error:(NSError **)error {
    
    NSMutableData *wavData = [self createWavFromPCM:pcmData sampleRate:sampleRate channels:channels];
    AVAudioPlayer *newPlayer = [[AVAudioPlayer alloc] initWithData:wavData error:error];
    
    if (!error) { return; }
    
    newPlayer.volume = 1.0;
    newPlayer.enableRate = YES;
    [newPlayer prepareToPlay];
    [newPlayer play];
    
    [_player stop];
    _player = newPlayer;
}

/// 停止播放
- (void)stop {
    [_player stop];
    _player = nil;
}

// MARK: - 小工具
/// 16-bit integer PCM
static inline void WWWriteLE16(uint8_t *dst, uint16_t value) {
    dst[0] = (uint8_t)(value & 0xFF);
    dst[1] = (uint8_t)((value >> 8) & 0xFF);
}

/// 32-bit integer PCM
static inline void WWWriteLE32(uint8_t *dst, uint32_t value) {
    dst[0] = (uint8_t)(value & 0xFF);
    dst[1] = (uint8_t)((value >> 8) & 0xFF);
    dst[2] = (uint8_t)((value >> 16) & 0xFF);
    dst[3] = (uint8_t)((value >> 24) & 0xFF);
}

/// 把PCM => WAV
/// - Parameters:
///   - pcm: PCM資料
///   - sampleRate: 聲音取樣頻率 (22000Hz / 44100Hz)
///   - channels: 聲音通道數 (單 / 雙通道)
- (nullable NSData *)createWavFromPCM:(NSData * _Nonnull)pcmData sampleRate:(int)sampleRate channels:(int)channels {
    
    const uint16_t bitsPerSample = 16;
    const uint16_t bytesPerSample = bitsPerSample / 8;

    if (pcmData.length == 0) { return nil; }
    if (sampleRate <= 0 || channels <= 0) { return nil; }

    uint32_t blockAlign32 = (uint32_t)channels * bytesPerSample;
    if (blockAlign32 == 0 || blockAlign32 > UINT16_MAX) { return nil; }

    if (pcmData.length % blockAlign32 != 0) { return nil; }

    if (pcmData.length > UINT32_MAX - 44) { return nil; }

    uint32_t pcmSize = (uint32_t)pcmData.length;
    uint32_t byteRate = (uint32_t)sampleRate * blockAlign32;

    NSMutableData *wav = [NSMutableData dataWithCapacity:(NSUInteger)(44 + pcmSize)];
    if (!wav) { return nil; }

    uint8_t header[44] = {0};

    memcpy(header + 0,  "RIFF", 4);
    WWWriteLE32(header + 4, 36u + pcmSize);
    memcpy(header + 8,  "WAVE", 4);

    memcpy(header + 12, "fmt ", 4);
    WWWriteLE32(header + 16, 16);
    WWWriteLE16(header + 20, 1);
    WWWriteLE16(header + 22, (uint16_t)channels);
    WWWriteLE32(header + 24, (uint32_t)sampleRate);
    WWWriteLE32(header + 28, byteRate);
    WWWriteLE16(header + 32, (uint16_t)blockAlign32);
    WWWriteLE16(header + 34, bitsPerSample);

    memcpy(header + 36, "data", 4);
    WWWriteLE32(header + 40, pcmSize);

    [wav appendBytes:header length:sizeof(header)];
    [wav appendData:pcmData];

    return [wav copy];
}

@end
