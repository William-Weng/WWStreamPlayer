//
//  StreamPlayer.h
//  WWStreamPlayer
//
//  Created by William.Weng on 2026/4/1.
//

#import <AudioToolbox/AudioToolbox.h>

typedef void (^FFmpegPCMCallback)(NSData *pcmData, int sampleRate, int channels);

@interface StreamPlayer : NSObject

- (void)playPCM:(NSData *)pcmData sampleRate:(int)sampleRate channels:(int)channels;
- (void)stop;

@end
