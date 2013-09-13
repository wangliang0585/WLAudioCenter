//
//  WLAudioPlayer.h
//  WLAudioCenter
//
//  Created by 王亮 on 13-9-11.
//  Copyright (c) 2013年 王亮. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef enum
{
	WLP_INITIALIZED = 0,
	WLP_PLAYING,                       // 正在播放
	WLP_BUFFERING,                     // 缓冲
	WLP_PAUSED,                        // 手动暂停
	WLP_STOPPING,                      // 即将停止
	WLP_STOPPED,                       // 已停止播放
    WLP_REPLAY                         //听筒模式重播
} WLPlayerState;

typedef enum
{
	WLP_NO_STOP = 0,
	WLP_STOPPING_EOF,
	WLP_STOPPING_USER_ACTION,
	WLP_STOPPING_FILEFORMAT_ERROR,
    WLP_STOPPING_INTERNAL_ERROR,
	WLP_STOPPING_NETWORK_ERROR,
	WLP_STOPPING_URL_ERROR
} WLPlayerStopReason;

@interface WLAudioPlayer : NSObject <UIAccelerometerDelegate>

@property (nonatomic, readonly) Float64 duration;     // seconds
@property (nonatomic, readonly) float process;      // 0.0-1.0
@property (nonatomic, readonly) float loadpercent;  // 0.0-1.0

@property (nonatomic, readonly) WLPlayerState state;
@property (nonatomic, readonly) WLPlayerStopReason reason;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, readonly) BOOL isReplay;

- (void)playWithPath:(NSString *)path
          andProcess:(void (^)(float playproc, float loadproc))proc
      onStateChanged:(void (^)(WLPlayerState state, WLPlayerStopReason reason))change;


- (void)replay;
- (void)stop;
- (void)pause;
@end
