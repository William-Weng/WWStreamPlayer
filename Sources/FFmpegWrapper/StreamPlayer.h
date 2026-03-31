// WWStreamPlayer.h
#import <AudioToolbox/AudioToolbox.h>

typedef void (^FFmpegPCMCallback)(NSData *pcmData, int sampleRate, int channels);

@interface StreamPlayer : NSObject

+ (instancetype)shared;

- (void)playPCM:(NSData *)pcmData sampleRate:(int)sampleRate channels:(int)channels;
- (void)stop;

@end
