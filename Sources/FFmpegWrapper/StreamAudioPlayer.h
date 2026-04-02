//
//  StreamAudioPlayer.h
//  WWStreamPlayer
//
//  Created by William.Weng on 2026/4/1.
//

#import <AudioToolbox/AudioToolbox.h>

@interface StreamAudioPlayer : NSObject

- (void)playPCM:(NSData *)pcmData sampleRate:(int)sampleRate channels:(int)channels error:(NSError **)error;
- (void)stop;

@end
