//
//  WLAudioRecorder.h
//  WLAudioCenter
//
//  Created by 王亮 on 13-9-11.
//  Copyright (c) 2013年 王亮. All rights reserved.
//

#import <Foundation/Foundation.h>
@class WLAudioObject;

@interface WLAudioRecorder : NSObject
@property (nonatomic, assign) NSTimeInterval maxRecordTime;

- (void)startRecordingWithHandlerOnStart:(void (^)(NSError *error, WLAudioObject *obj))startHandler
                                  OnStop:(void (^)(NSError *error, WLAudioObject *obj))stopHandler
                        OnProgressUpdate:(void (^)(float recordProgress, float peakPower, float averagePower, WLAudioObject *obj))progressHandler;
- (void)stop;
- (BOOL)isRecording;
@end
