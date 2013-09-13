//
//  WLAudioCenter.m
//  WLAudioCenter
//
//  Created by 王亮 on 13-9-11.
//  Copyright (c) 2013年 王亮. All rights reserved.
//

#import "WLAudioCenter.h"
#import <UIKit/UIKit.h>
#import "WLAudioObject.h"
#import "lame.h"

#define AUDIO_BUFFER_SIZE 16384
#define kWLAudioPlayerErrDomain @"WLAudioPlayerError"
#define KWLAudioQueuePacketDescs 512
#define kWLCacheMaxCacheAge 60*60*24*7 // 1 week
#define kWLMinAudioBufferlength 50000

static unsigned char _processbuffer[AUDIO_BUFFER_SIZE];

@interface WLAudioCenter ()
{
    NSOperationQueue *_processOperationQueue;
    WLAudioObject *_audioObject;
}
@property (nonatomic, strong) WLAudioObject *recordingAudioObject;
- (void)handleInterruptionChangeToState:(AudioQueuePropertyID)inInterruptionState;
- (void)startPlayingOrPause;
@end

static BOOL bWakeMusic = YES;

@implementation WLAudioCenter

void MyAudioSessionInterruptionListener(void *inClientData, UInt32 inInterruptionState)
{
	[WLAudio handleInterruptionChangeToState:inInterruptionState];
}

+(WLAudioCenter*)shareInstance
{
    static WLAudioCenter *audioCenter = nil;
    static dispatch_once_t once_t;
    
    dispatch_once(&once_t, ^{
        audioCenter = [[self alloc] init];});
    
    return audioCenter;
}

- (id)init
{
    self = [super init];
    if (self) {
        
#if TARGET_OS_IPHONE
        [self initAudioSession];
#endif
        
        _audioRecorder = [[WLAudioRecorder alloc] init];
        _audioPlayer = [[WLAudioPlayer alloc] init];
        _processOperationQueue = [[NSOperationQueue alloc] init];
        _processOperationQueue.maxConcurrentOperationCount = 1;
        
        // 监听程序进入后台动作
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification){
            [self finishPlaying];
            [self finishRecord];
        }];
    }
    return self;
}

- (void)dealloc
{
    [self finishPlaying];
    [self finishRecord];
    self.recorderDelegate = nil;
    self.playerDelegate = nil;
}

- (void)initAudioSession
{
    AudioSessionInitialize (
                            NULL,
                            NULL,
                            MyAudioSessionInterruptionListener,
                            (__bridge void *)(self)
                            );
    
    UInt32 sessionCategory = kAudioSessionCategory_PlayAndRecord;
    AudioSessionSetProperty (kAudioSessionProperty_AudioCategory,
                             sizeof (sessionCategory),
                             &sessionCategory
                             );
    
    UInt32 enbaleBluetooth = 1;
    AudioSessionSetProperty (kAudioSessionProperty_OverrideCategoryEnableBluetoothInput,
                             sizeof (enbaleBluetooth),
                             &enbaleBluetooth
                             );
}

- (void)handleInterruptionChangeToState:(AudioQueuePropertyID)inInterruptionState
{
    if (inInterruptionState == kAudioSessionBeginInterruption){
        [self finishPlaying];
        [self finishRecord];
    }
    else if (inInterruptionState == kAudioSessionEndInterruption){
#if TARGET_OS_IPHONE
        UInt32 sessionCategory = kAudioSessionCategory_PlayAndRecord;
        AudioSessionSetProperty (kAudioSessionProperty_AudioCategory,
                                 sizeof (sessionCategory),
                                 &sessionCategory
                                 );
#endif
    }
}

- (void)enableSession
{
#if TARGET_OS_IPHONE
    AudioSessionSetActive(YES);
    [[AVAudioSession sharedInstance] setActive:NO withFlags:AVAudioSessionSetActiveFlags_NotifyOthersOnDeactivation error:NULL];
    AudioSessionSetActive(YES);
#endif
}

- (void)disableSession{
#if TARGET_OS_IPHONE
    if (bWakeMusic) {
        WLLog(@"wake music");
        [[AVAudioSession sharedInstance] setActive:NO withFlags:AVAudioSessionSetActiveFlags_NotifyOthersOnDeactivation error:NULL];
    }else{
        WLLog(@"no wake music");
    }
#endif
}

#pragma mark - Recoder
- (void)startRecordWithDelegate:(id<WLAudioCenterRecorderDelegate>)delegate
{
    [self setMaxRecordTime:kWLMaxRecoderTime];
    
    self.recorderDelegate = delegate;
    __block id<WLAudioCenterRecorderDelegate> rDelegate = self.recorderDelegate;
    
    if (self.audioPlayer.isPlaying) {
        bWakeMusic = NO;
        [self finishPlaying];
    }
    
    [_audioRecorder startRecordingWithHandlerOnStart:^(NSError *error, WLAudioObject *obj) {
        self.recordingAudioObject = nil;
        if (error) {
            [self performSelector:@selector(disableSession) withObject:nil afterDelay:1.f];
            WLLog(@"！！！录音启动失败！%@", [error localizedDescription]);

            if (rDelegate && [rDelegate respondsToSelector:@selector(didFailedRecordingAudio:withError:)]) {
                [rDelegate didFailedRecordingAudio:obj withError:error];
            }
            
            rDelegate = nil;
        } else {
            if (rDelegate && [rDelegate respondsToSelector:@selector(didStartRecordingAudio:)]) {
                [rDelegate didStartRecordingAudio:obj];
            }
        }
    } OnStop:^(NSError *error, WLAudioObject *obj) {
        if (error) {
            WLLog(@"！！！录音过程失败！%@", [error localizedDescription]);
            if (rDelegate && [rDelegate respondsToSelector:@selector(didFailedRecordingAudio:withError:)]) {
                [rDelegate didFailedRecordingAudio:obj withError:error];
            }
        } else {
            if (rDelegate && [rDelegate respondsToSelector:@selector(didFinishedRecordAudio:)]) {
                [rDelegate didFinishedRecordAudio:obj];
            }
            self.recordingAudioObject = obj;
        }
        
        rDelegate = nil;
        [self disableSession];
    } OnProgressUpdate:^(float recordProgress, float peakPower, float averagePower, WLAudioObject *obj) {
        if (rDelegate && [rDelegate respondsToSelector:@selector(didTimeElapsed:audioPower:recordingAudio:)]) {
            [rDelegate didTimeElapsed:recordProgress audioPower:[NSString stringWithFormat:@"%f",averagePower] recordingAudio:obj];
        }
    }];
}

- (void)finishRecord
{
    if ([_audioRecorder isRecording]) {
        [_audioRecorder stop];
    }
}

- (void)setMaxRecordTime:(NSTimeInterval)maxTime
{
    if (maxTime > 0.f) {
        _audioRecorder.maxRecordTime = maxTime;
    }else{
        _audioRecorder.maxRecordTime = kWLMaxRecoderTime;
    }
}

#pragma mark - Player
- (WLAudioObject *)playingAudioObject
{
    return _audioObject;
}

- (void)playSingleAudio:(WLAudioObject *)audioObject delegate:(id<WLAudioCenterPlayerDelegate>)delegate
{
    if (self.audioPlayer.isPlaying  || self.audioPlayer.state == WLP_BUFFERING) {
        bWakeMusic = NO;
        [self finishPlaying];
    }
    
    self.playerDelegate = delegate;
    [self playAudio:audioObject fromTime:0];
}

- (void)playSingleAudioWithURL:(NSString*)url delegate:(id<WLAudioCenterPlayerDelegate>)delegate
{
    if (!url) {
        return;
    }
    
    WLAudioObject *audio = [[WLAudioObject alloc] init];
    audio.sourceURL = url;
    
    [self playSingleAudio:audio delegate:delegate];
}

- (void)playAudio:(WLAudioObject*)audio fromTime:(NSTimeInterval)time {
    if (audio) {
        if (_audioObject != audio) {
            [_audioPlayer stop];
            _audioObject = audio;
        }
        
        __block id <WLAudioCenterPlayerDelegate> pDelegate = self.playerDelegate;
        
        if (!audio.sourceURL) {
            if (audio.cafFilePath) {
                audio.sourceURL = [audio.cafFilePath stringByAppendingPathComponent:audio.recordingFileName];
            }
            if (!audio.sourceURL && audio.mp3FilePath) {
                audio.sourceURL = [audio.mp3FilePath stringByAppendingPathComponent:audio.mp3ProcessedFileName];
            }
        }
        
        [_audioPlayer playWithPath:audio.sourceURL andProcess:^(float playproc, float loadproc) {
            if (pDelegate && [pDelegate respondsToSelector:@selector(didTimeElapsed:playingAudio:)]) {
                [pDelegate didTimeElapsed:playproc playingAudio:_audioObject];
            }
            pDelegate = nil;
        } onStateChanged:^(WLPlayerState state, WLPlayerStopReason reason) {
            switch (state) {
                case WLP_INITIALIZED:
                    WLLog(@"WLP_INITIALIZED");
                    break;
                case WLP_PLAYING:
                    WLLog(@"WLP_PLAYING");
                    if (pDelegate && [pDelegate respondsToSelector:@selector(didStartPlayingAudio:)]) {
                        [pDelegate didStartPlayingAudio:_audioObject];
                    }
                    break;
                case WLP_BUFFERING:
                    WLLog(@"WLP_BUFFERING");
                    if (pDelegate && [pDelegate respondsToSelector:@selector(didStartBufferingAudio:)]) {
                        [pDelegate didStartBufferingAudio:_audioObject];
                    }
                    break;
                case WLP_PAUSED:
                    WLLog(@"WLP_PAUSED");
                    if (pDelegate && [pDelegate respondsToSelector:@selector(didPausePlayingAudio:)]) {
                        [pDelegate didPausePlayingAudio:_audioObject];
                    }
                    break;
                case WLP_STOPPING:
                    WLLog(@"WLP_STOPPING");
                    break;
                case WLP_STOPPED:
                    WLLog(@"WLP_STOPPED");
                    [self handlePlaybackStopReason:reason];
                    [self disableSession];
                    bWakeMusic = YES;
                    break;
                case WLP_REPLAY:
                    WLLog(@"WLP_REPLAY");
                    if (pDelegate && [pDelegate respondsToSelector:@selector(didReStartPlayingAudio:)]) {
                        [pDelegate didReStartPlayingAudio:_audioObject];
                    }
                    break;

                default:
                    break;
            }
        }];
    }
}

- (void)handlePlaybackStopReason:(WLPlayerStopReason)stopReason {
    id <WLAudioCenterPlayerDelegate> pDelegate = self.playerDelegate;
    
    if (stopReason != WLP_NO_STOP &&
        stopReason != WLP_STOPPING_EOF &&
        stopReason != WLP_STOPPING_USER_ACTION &&
        stopReason != WLP_STOPPING_URL_ERROR) {
        [self enableSession];
    }
    
    switch (stopReason) {
        case WLP_NO_STOP:
            WLLog(@"WLP_NO_STOP");
            break;
        case WLP_STOPPING_EOF:
            WLLog(@"WLP_STOPPING_EOF");
            [self handleDidPlayingStoped];
            break;
        case WLP_STOPPING_USER_ACTION:
            WLLog(@"WLP_STOPPING_USER_ACTION");
            [self handleDidPlayingStoped];
            break;
        case WLP_STOPPING_INTERNAL_ERROR:
            WLLog(@"WLP_STOPPING_INTERNAL_ERROR");
            if (pDelegate && [pDelegate respondsToSelector:@selector(didFailedPlayingAudio:withError:)]) {
                [pDelegate didFailedPlayingAudio:_audioObject withError:[NSError errorWithDomain:kWLAudioPlayerErrDomain code:-101 userInfo:@{NSLocalizedDescriptionKey : @"Audio stoped due to an internal error caused by audio player."}]];
            }
            [self handleDidPlayingStoped];
            break;
        case WLP_STOPPING_FILEFORMAT_ERROR:
            WLLog(@"WLP_STOPPING_FILEFORMAT_ERROR");
            if (pDelegate && [pDelegate respondsToSelector:@selector(didFailedPlayingAudio:withError:)]) {
                [pDelegate didFailedPlayingAudio:_audioObject withError:[NSError errorWithDomain:kWLAudioPlayerErrDomain code:-101 userInfo:@{NSLocalizedDescriptionKey : @"Audio stoped due to unrecogernized audio file."}]];
            }
            [self handleDidPlayingStoped];
            break;
        case WLP_STOPPING_NETWORK_ERROR:
            WLLog(@"WLP_STOPPING_NETWORK_ERROR");
            if (pDelegate && [pDelegate respondsToSelector:@selector(didFailedPlayingAudio:withError:)]) {
                [pDelegate didFailedPlayingAudio:_audioObject withError:[NSError errorWithDomain:kWLAudioPlayerErrDomain code:-100 userInfo:@{NSLocalizedDescriptionKey : @"Audio stoped due to network error."}]];
            }
            [self handleDidPlayingStoped];
        case WLP_STOPPING_URL_ERROR:
            WLLog(@"WLP_STOPPING_NETWORK_ERROR");
            if (pDelegate && [pDelegate respondsToSelector:@selector(didFailedPlayingAudio:withError:)]) {
                [pDelegate didFailedPlayingAudio:_audioObject withError:[NSError errorWithDomain:kWLAudioPlayerErrDomain code:-100 userInfo:@{NSLocalizedDescriptionKey : @"Audio stoped due to URL error."}]];
            }
            [self handleDidPlayingStoped];
            break;
        default:
            WLLog(@"WLP_STOPPING_NETWORK_ERROR");
            if (pDelegate && [pDelegate respondsToSelector:@selector(didFailedPlayingAudio:withError:)]) {
                [pDelegate didFailedPlayingAudio:_audioObject withError:[NSError errorWithDomain:kWLAudioPlayerErrDomain code:-100 userInfo:@{NSLocalizedDescriptionKey : @"Audio stoped due to unknown error."}]];
            }
            [self handleDidPlayingStoped];
            break;
    }
    
}

- (void)handleDidPlayingStoped {
    
    id <WLAudioCenterPlayerDelegate> pDelegate = self.playerDelegate;
    
    if (pDelegate && [pDelegate respondsToSelector:@selector(didFinishedPlaying)]) {
        [pDelegate didFinishedPlaying];
    }
    
    _audioObject = nil;
    self.playerDelegate = nil;
}

- (void)finishPlaying
{
    if ([self.audioRecorder isRecording]) {
        [self.audioRecorder stop];
    }
}

#pragma mark - Status
- (BOOL)isPlaying
{
    return [self.audioPlayer isPlaying];
}

- (BOOL)isRecording
{
    return [self.audioRecorder isRecording];
}

#pragma mark - Remote Control
- (void) remoteControlReceivedWithEvent:(UIEvent *)receiveEvent
{
    if (receiveEvent.type == UIEventTypeRemoteControl) {
        switch (receiveEvent.subtype) {
            case UIEventSubtypeRemoteControlTogglePlayPause:
                [self startPlayingOrPause];
                break;

            default:
                break;
        }
    }
}

- (void)startPlayingOrPause
{
    if (_audioObject) {
        if (_audioPlayer.isPlaying) {
            [_audioPlayer pause];
        }else{
            [self playSingleAudio:_audioObject delegate:self.playerDelegate];
        }
    }
}

+ (BOOL)cafFile:(NSString *)cafFile toMp3File:(NSString *)mp3File
{
    BOOL ret = NO;
    ret = [self cafFile:cafFile toMp3File:mp3File];
    return ret;
}

- (BOOL)cafFile:(NSString *)cafFile toMp3File:(NSString *)mp3File
{    
    BOOL ret = NO;
    
    if (!cafFile || !mp3File)
        return NO;
    
    NSURL *cafFileUrl = [NSURL fileURLWithPath:cafFile];
    AudioFileID cafFileID = NULL;
    OSStatus readStatus;
    SInt64 readOffset = 0;
    
    UInt32 numBytes = 0;
    UInt8 *writeBuffer = NULL;
    int writesize = 0;
    int writebuffersize = 0;
    
    AudioStreamBasicDescription fileFormat={};
    UInt32 propsize = sizeof(AudioStreamBasicDescription);
    
    lame_t lame = lame_init();
    UInt32 audioFileDataLeng = 0;
    UInt32 audioSamples = 0;
    
    FILE* fdMp3 = NULL;
    
    if (!access([mp3File UTF8String], F_OK))
        unlink([mp3File UTF8String]);
    
    readStatus = AudioFileOpenURL((__bridge CFURLRef)(cafFileUrl), kAudioFileReadPermission, kAudioFileCAFType, &cafFileID);
    if (readStatus != noErr) {
        WLLog(@"CAF文件打开失败！");
        goto cafFiletoMp3File_Exit;
    }
    readStatus = AudioFileGetProperty(cafFileID, kAudioFilePropertyDataFormat, &propsize, &fileFormat);
    if (readStatus != noErr) {
        WLLog(@"CAF文件格式获取失败！");
        goto cafFiletoMp3File_Exit;
    }
    if (fileFormat.mChannelsPerFrame != 1) {
        WLLog(@"CAF文件转换不支持多声道！");
        goto cafFiletoMp3File_Exit;
    }
    readStatus = AudioFileGetUserDataSize(cafFileID, 'data', 0, &audioFileDataLeng);
    if (readStatus != noErr) {
        WLLog(@"get audio file data chunck length error");
        goto cafFiletoMp3File_Exit;
    }
    // init buffer
    writeBuffer = malloc(AUDIO_BUFFER_SIZE * 2);
    writesize = AUDIO_BUFFER_SIZE * 2;
    if (!writeBuffer) {
        WLLog(@"buffer分配失败！");
        goto cafFiletoMp3File_Exit;
    }
    
    fdMp3 = fopen([mp3File UTF8String], "w+");
    if (fdMp3 == NULL) {
        WLLog(@"mp3文件创建失败！");
        goto cafFiletoMp3File_Exit;
    }
    
    lame_set_in_samplerate(lame, fileFormat.mSampleRate);
    lame_set_num_channels(lame, fileFormat.mChannelsPerFrame);
    lame_set_brate(lame, 32);
    lame_set_quality(lame, 5);  // default 5  2=high  5 = medium  7=low
    lame_init_params(lame);
    
    while (true) {
        readOffset += numBytes;
        numBytes = sizeof(_processbuffer);
        
        // read data
        readStatus = AudioFileReadBytes(cafFileID, NO, readOffset, &numBytes, _processbuffer);
        if (readStatus == kAudioFileEndOfFileError) {
            // process end
            ret = YES;
        }else if (readStatus != noErr){
            // error
            WLLog(@"caf 文件读取失败");
            goto cafFiletoMp3File_Exit;
        }
        
        if (ret) {
            if (writebuffersize < 7200){
                writebuffersize = 7200;
                writeBuffer = realloc(writeBuffer, writebuffersize);
                if (!writeBuffer) {
                    WLLog(@"buffer分配失败！");
                    goto cafFiletoMp3File_Exit;
                }
            }
            
            short *src = (short *)_processbuffer;
            int nsamples = numBytes*8/fileFormat.mBitsPerChannel;
            if (numBytes >= 128) {
                writesize = lame_encode_buffer(lame, src, src, nsamples, writeBuffer, writebuffersize);
                fwrite(writeBuffer, 1, writesize, fdMp3);
            }
            
            writesize = lame_encode_flush(lame, writeBuffer, writebuffersize);
        }else{
            NSAssert(numBytes>0, @"not reach file's end, bytes got should greater than 0");
            
            short *src = (short *)_processbuffer;
            int nsamples = numBytes*8/fileFormat.mBitsPerChannel;
             
            if (writebuffersize < nsamples*1.25+7200) {
                writebuffersize = nsamples*1.25+7200;
                writeBuffer = realloc(writeBuffer, writebuffersize);
                if (!writeBuffer) {
                    WLLog(@"buffer分配失败！");
                    goto cafFiletoMp3File_Exit;
                }
            }
            writesize = lame_encode_buffer(lame, src, src, nsamples, writeBuffer, writebuffersize);
            audioSamples += nsamples;
        }
        
        if (writesize == -1) {
            WLLog(@"mp3 buffer不够");
            goto cafFiletoMp3File_Exit;
        }else if(writesize < 0) {
            WLLog(@"mp3 encoder 错误");
            goto cafFiletoMp3File_Exit;
        }
        if(fwrite(writeBuffer, 1, writesize, fdMp3) != writesize){
            WLLog(@"数据写入错误");
            goto cafFiletoMp3File_Exit;
        }
        if (ret)
            break;
    }
    lame_mp3_tags_fid(lame, fdMp3);
    
    //deinit
cafFiletoMp3File_Exit:
    if (writeBuffer)
        free(writeBuffer);
    if (cafFileID)
        AudioFileClose(cafFileID);
    if (fdMp3)
        fclose(fdMp3);
    if (!ret)
        unlink([mp3File UTF8String]);
    if (ret) {
//        NSDate *start = [NSDate date];
//        float cafToMp3TotalTime = [[NSDate date] timeIntervalSinceDate:start];
        //        float recordCafFileCostTime = (float)audioSamples/(float)(fileFormat.mSampleRate*fileFormat.mChannelsPerFrame);
        //   printf("* CAF->Mp3 compress: %.1f %.3f => %.3f => %.3f\n", cafToMp3TotalTime, [RVUtility getMP3Timelength:cafFile], recordCafFileCostTime, [RVUtility getMP3Timelength:mp3File]);
    }
    
    lame_close(lame);
    return ret;
}
@end
