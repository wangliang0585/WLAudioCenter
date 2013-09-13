//
//  WLAudioCenterProcotols.h
//  WLAudioCenter
//
//  Created by 王亮 on 13-9-11.
//  Copyright (c) 2013年 王亮. All rights reserved.
//

#ifndef WLAudioCenter_WLAudioCenterProcotols_h
#define WLAudioCenter_WLAudioCenterProcotols_h
@class WLAudioObject;
@protocol WLAudioCenterPlayerDelegate <NSObject>
@optional
- (void)didStartPlayingAudio:(WLAudioObject *)audio;
- (void)didPausePlayingAudio:(WLAudioObject *)audio;
- (void)didStartBufferingAudio:(WLAudioObject *)audio;
- (void)didReStartPlayingAudio:(WLAudioObject *)audio;
- (void)didFinishedPlaying;
- (void)didTimeElapsed:(NSTimeInterval)timeElapsed playingAudio:(WLAudioObject *)audio;
- (void)didFailedPlayingAudio:(WLAudioObject *)audio withError:(NSError *)error;
@end

@protocol WLAudioCenterRecorderDelegate <NSObject>
@optional
- (void)didStartRecordingAudio:(WLAudioObject *)audio;
- (void)didFinishedRecordAudio:(WLAudioObject *)audio;
- (void)didTimeElapsed:(NSTimeInterval)timeElapsed audioPower: (NSString *)averagePower recordingAudio:(WLAudioObject *)audio;
- (void)didFailedRecordingAudio:(WLAudioObject *)audio withError:(NSError *)error;
@end

#endif
