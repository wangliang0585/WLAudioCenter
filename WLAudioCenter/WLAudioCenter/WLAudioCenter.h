//
//  WLAudioCenter.h
//  WLAudioCenter
//
//  Created by 王亮 on 13-9-11.
//  Copyright (c) 2013年 王亮. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "WLAudioCenterConfig.h"
#import "WLAudioCenterProcotols.h"
#import "WLAudioRecorder.h"
#import "WLAudioPlayer.h"

@class WLAudioObject;

#define WLAudio [WLAudioCenter shareInstance]

@interface WLAudioCenter : NSObject
@property(nonatomic,weak)id<WLAudioCenterRecorderDelegate> recorderDelegate;
@property(nonatomic,weak)id<WLAudioCenterPlayerDelegate> playerDelegate;
@property(nonatomic,readonly)WLAudioRecorder *audioRecorder;
@property(nonatomic,readonly)WLAudioPlayer *audioPlayer;

+ (WLAudioCenter*)shareInstance;
- (void)enableSession;

#pragma mark - Recoder
- (void)startRecordWithDelegate:(id<WLAudioCenterRecorderDelegate>)delegate;
- (void)finishRecord;
- (void)setMaxRecordTime:(NSTimeInterval)maxTime;

#pragma mark - Player
- (WLAudioObject *)playingAudioObject;
- (void)playSingleAudio:(WLAudioObject *)audioObject delegate:(id<WLAudioCenterPlayerDelegate>)delegate;
- (void)playSingleAudioWithURL:(NSString*)url delegate:(id<WLAudioCenterPlayerDelegate>)delegate;
- (void)finishPlaying;

#pragma mark - Status
- (BOOL)isPlaying;
- (BOOL)isRecording;

+ (BOOL)cafFile:(NSString *)cafFile toMp3File:(NSString *)mp3File;
@end
