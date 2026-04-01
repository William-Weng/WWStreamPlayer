//
//  StreamPlayer.m
//  WWStreamPlayer
//
//  Created by William.Weng on 2026/4/1.
//

#import <AudioToolbox/AudioToolbox.h>
#import "AVFoundation/AVFoundation.h"
#import "StreamPlayer.h"

@implementation StreamPlayer {
    AVAudioPlayer *_player;
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
