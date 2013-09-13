//
//  RVAudioPlayer.m
//  Dubbler
//
//  Created by miniM on 12-9-17.
//  Copyright (c) 2012年 Appsurdity, Inc. All rights reserved.
//

#import "WLAudioPlayer.h"
#import "WLFileManager.h"
#define AudioQueueBufSize 0x4000
#define AudioQueuePacketDescs 512
static NSInteger cacheMaxCacheAge = 60*60*24*7;
static NSInteger minAudioBufferlength = 50000;
static NSString *errAudioDomain = @"errorAudioDomain";
static NSString *diskAudioCachePath = nil;

NSInteger g_taskTag = 0;
AudioStreamPacketDescription audioPacketDescs[AudioQueuePacketDescs];

typedef enum
{
	WLAudioTaskState_Downing = 0,
    WLAudioTaskState_ReadyForPlay,      // >= 5k data
	WLAudioTaskState_Cached,
	WLAudioTaskState_Error
} WLAudioTaskState;


OSStatus MyAudioFile_ReadProc (void *inClientData, SInt64 inPosition, UInt32 requestCount, void *buffer, UInt32 *actualCount);
SInt64 MyAudioFile_GetSizeProc (void *inClientData);

#pragma mark -   RVAudioTask

@interface WLAudioTask : NSObject{
    NSData *gapAudioData;
    
    UInt64 audioFileOffset;
    UInt64 packetIndex;
    
    UInt64 audioDataBytes;
    UInt64 audioDataPackages;
    
    float _expectDuration;
    
    NSUInteger _maxReadTimes;
    BOOL  bFlagFileError;
}
@property (nonatomic, assign) NSUInteger readTimes;
@property (nonatomic, readonly) NSUInteger maxReadTimes;
@property (nonatomic, assign) NSUInteger tag;
@property (nonatomic, strong) NSMutableData *audioData;
@property (nonatomic, strong) NSString *url;
@property (nonatomic, assign) WLAudioTaskState state;
@property (nonatomic, readonly) NSInteger downloadSize;
@property (nonatomic, assign) NSInteger expectSize;
@property (nonatomic, readonly) Float64 expectDuration;
@property (nonatomic, strong) NSURLConnection *connect;
@property (nonatomic, strong) NSURLRequest *request;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, assign) AudioFileID audioFileID;
@property (nonatomic, assign) AudioFileTypeID audioType;
@property (nonatomic, readonly) AudioStreamBasicDescription format;
@property (nonatomic, strong) NSData *magicCookie;
@property (nonatomic, readonly) UInt32 maxPacketSize;
@end

@implementation WLAudioTask
- (id)init{
    self = [super init];
    if (self) {
        g_taskTag++;
        _tag = g_taskTag;
        _readTimes = 0;
        _maxReadTimes = 0;
        
        gapAudioData = nil;
        audioFileOffset = 0;
        packetIndex = 0;
        _expectDuration = 0;
        audioDataBytes = 0;
        audioDataPackages = 0;
        
        bFlagFileError = NO;
    }
    return self;
}

- (void)dealloc{
    [self stopTask];
}

- (NSUInteger)maxReadTimes{
    if (_state != WLAudioTaskState_Cached && _state != WLAudioTaskState_Error) {
        _maxReadTimes = self.audioData.length*20/1000 + 1000;
    }
    return _maxReadTimes;
}

- (void)setUrl:(NSString *)url{
    _url =url;
    _audioType = [self hintForFileExtension:[[[NSURL URLWithString:url] path] pathExtension]];
    _expectDuration = 0.0;
}

- (NSInteger)downloadSize{
    if (self.state == WLAudioTaskState_Cached) {
        return self.expectSize;
    }
    if (self.audioData)
        return self.audioData.length;
    return 0;
}

- (float)caclulateDuration:(AudioFileID)audioid{
    if (packetIndex > 50) {
        double averagePacketByteSize = audioFileOffset / packetIndex;
        double bitrate = averagePacketByteSize / (_format.mFramesPerPacket/_format.mSampleRate);
        return self.expectSize/bitrate;
    }
    return 1000000;
}

- (float)getDuration:(AudioFileID)audioid{
    if (!audioid) {
        return 0.0;
    }
    
    Float64 durationSec;
    UInt32 byteCountSize = sizeof(Float64);
    OSStatus status = AudioFileGetProperty(self.audioFileID, kAudioFilePropertyEstimatedDuration, &byteCountSize, &durationSec);
    if (status != noErr) {
        WLLog(@"get audio file duration error");
        return 0.0;
    }
    
    float newDuration = 0.0;
    if (kAudioFormatLinearPCM == _format.mFormatID){
        newDuration = durationSec;
    }

    if (kAudioFormatLinearPCM == _format.mFormatID) {
        newDuration -= MIN(0.06,newDuration);
    }else{
        newDuration -= MIN(0.03,newDuration);
    }
    return newDuration;
}

- (Float64)expectDuration{
    if (!self.audioFileID) {
        return 0.0;
    }
    if (self.state != WLAudioTaskState_Cached) {
        return [self caclulateDuration:self.audioFileID];
    }else if(0 == _expectDuration){
        _expectDuration = [self getDuration:self.audioFileID];
    }
    return _expectDuration;
}

- (void)setState:(WLAudioTaskState)state{
    OSStatus status;
    NSURL *url;
    
    if (state == _state) {
        return;
    }
    bFlagFileError = NO;
    _state = state;
    switch (state) {
        case WLAudioTaskState_ReadyForPlay:{
            NSAssert(self.audioData.length>=minAudioBufferlength, @"audio file can not be played when less than 50000 bytes");
            status = AudioFileOpenWithCallbacks((__bridge void *)(self), MyAudioFile_ReadProc, NULL, MyAudioFile_GetSizeProc, NULL, self.audioType, &_audioFileID);
            if (status != noErr) {
                self.error = [NSError errorWithDomain:errAudioDomain code:status userInfo:nil];
                bFlagFileError = YES;
                break;
            }
            
            UInt32 size = sizeof(_format);
            status = AudioFileGetProperty(self.audioFileID, kAudioFilePropertyDataFormat, &size, &_format);
            if (status != noErr) {
                self.error = [NSError errorWithDomain:errAudioDomain code:status userInfo:nil];
                bFlagFileError = YES;
                break;
            }
            
            AudioFileGetProperty(self.audioFileID, kAudioFilePropertyMagicCookieData, &size, nil);
            if (size >0) {
                void *cookie=malloc(sizeof(char)*size);
                AudioFileGetProperty(self.audioFileID, kAudioFilePropertyMagicCookieData, &size, cookie);
                self.magicCookie = [NSData dataWithBytes:cookie length:size];
                free(cookie);
            }
            
            if (_format.mBytesPerPacket==0 || _format.mFramesPerPacket==0) {
                size=sizeof(_maxPacketSize);
                AudioFileGetProperty(self.audioFileID, kAudioFilePropertyPacketSizeUpperBound, &size, &_maxPacketSize);
            }else {
                _maxPacketSize = _format.mBytesPerPacket;
            }
            
            size = sizeof(audioDataBytes);
            AudioFileGetProperty(self.audioFileID, kAudioFilePropertyAudioDataByteCount, &size, &audioDataBytes);
            size = sizeof(audioDataPackages);
            AudioFileGetProperty(self.audioFileID, kAudioFilePropertyAudioDataPacketCount, &size, &audioDataPackages);
        }
            break;
            
        case WLAudioTaskState_Cached: {
            if (self.audioFileID) {
                AudioFileClose(self.audioFileID);
                self.audioFileID = NULL;
            }
            
            NSString *path = [WLFileManager voiceFilePathAtCache:self.url];
            if (path && path.length) {
                [WLFileManager writeVoiceToCache:self.audioData filePath:path];
            }
            
            self.audioData = nil;
            NSDictionary *attri = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
            self.expectSize = [[attri valueForKey:NSFileSize] integerValue];
            url = [NSURL fileURLWithPath:path];
            status= AudioFileOpenURL((__bridge CFURLRef)(url), kAudioFileReadPermission, 0, &_audioFileID);
            if (status != noErr) {
                [self stopTask];
                self.error = [NSError errorWithDomain:errAudioDomain code:status userInfo:nil];
                bFlagFileError = YES;
                break;
            }
            
            UInt32 size = sizeof(_format);
            status = AudioFileGetProperty(self.audioFileID, kAudioFilePropertyDataFormat, &size, &_format);
            if (status != noErr) {
                [self stopTask];
                self.error = [NSError errorWithDomain:errAudioDomain code:status userInfo:nil];
                bFlagFileError = YES;
                break;
            }
            
            AudioFileGetProperty(self.audioFileID, kAudioFilePropertyMagicCookieData, &size, nil);
            if (size >0) {
                void *cookie=malloc(sizeof(char)*size);
                AudioFileGetProperty(self.audioFileID, kAudioFilePropertyMagicCookieData, &size, cookie);
                self.magicCookie = [NSData dataWithBytes:cookie length:size];
                free(cookie);
            }
            if (_format.mBytesPerPacket==0 || _format.mFramesPerPacket==0) {
                size=sizeof(_maxPacketSize);
                AudioFileGetProperty(self.audioFileID, kAudioFilePropertyPacketSizeUpperBound, &size, &_maxPacketSize);
            }else {
                _maxPacketSize = _format.mBytesPerPacket;
            }
            
            size = sizeof(audioDataBytes);
            AudioFileGetProperty(self.audioFileID, kAudioFilePropertyAudioDataByteCount, &size, &audioDataBytes);
            size = sizeof(audioDataPackages);
            AudioFileGetProperty(self.audioFileID, kAudioFilePropertyAudioDataPacketCount, &size, &audioDataPackages);
            _expectDuration = [self getDuration:self.audioFileID];
        }
            break;
            
        case WLAudioTaskState_Error:
            break;
            
        default:
            NSAssert(self.audioFileID==NULL, @"audiofile should not exist now");
            break;
    }
}

- (void)stopTask{
    [self.connect cancel];
    if (self.audioFileID){
        AudioFileClose(self.audioFileID);
        self.audioFileID = NULL;
    }
}

- (BOOL)canPlay{
    if (bFlagFileError)
        return NO;
    
    switch (self.state) {
        case WLAudioTaskState_Downing:
            return NO;
        case WLAudioTaskState_ReadyForPlay:
            return YES;            
        case WLAudioTaskState_Cached:
            return YES;
        case WLAudioTaskState_Error:
            if (self.audioData.length >= minAudioBufferlength &&
                self.readTimes < self.maxReadTimes) {
                return YES;
            }
            break;
            
        default:
            break;
    }
    return NO;
}

- (BOOL)isReachEOF{
    if ((audioFileOffset>=audioDataBytes && audioDataBytes > 0) ||
        (packetIndex >= audioDataPackages && audioDataPackages > 0)) {
        return YES;
    }
    return NO;
}

- (void)replay{
    audioFileOffset = 0;
    packetIndex = 0;
}

- (void)filterAudioData{
    unsigned char originAudioData[4096];
    UInt32 numBytes = sizeof(originAudioData);
    
    if (kAudioFormatLinearPCM != _format.mFormatID){
        gapAudioData = nil;
        return;
    }
    if (gapAudioData.length > 0){
        return;
    }
    
    do{
        OSStatus status = AudioFileReadBytes(self.audioFileID, NO, audioFileOffset, &numBytes, originAudioData);
        if (status != noErr){
            if (status == kAudioFileEndOfFileError)
                WLLog(@"读取CAF文件完毕！");
            else{
                WLLog(@"读取CAF文件失败！");
                numBytes = 0;
            }
        }
        
        if (numBytes > 0) {
            audioFileOffset += numBytes;
            gapAudioData = [NSMutableData dataWithBytes:originAudioData length:numBytes];
        }else
            break;
    }while (gapAudioData.length == 0);
    
}

- (BOOL)fillAudioQueue:(AudioQueueRef)audioQueue withBuffer:(AudioQueueBufferRef)audioQueueBuffer{
    OSStatus status;
    audioQueueBuffer->mAudioDataByteSize=0;
    
    if (kAudioFormatLinearPCM == _format.mFormatID) {
        do{
            if (gapAudioData.length > 0) {
                int len = MIN(audioQueueBuffer->mAudioDataBytesCapacity-audioQueueBuffer->mAudioDataByteSize, gapAudioData.length);
                [gapAudioData getBytes:audioQueueBuffer->mAudioData+audioQueueBuffer->mAudioDataByteSize length:len];
                audioQueueBuffer->mAudioDataByteSize += len;
                
                if (len < gapAudioData.length)
                    gapAudioData = [gapAudioData subdataWithRange:NSMakeRange(len, gapAudioData.length-len)];
                else{
                    gapAudioData = nil;
                    [self filterAudioData];
                }
            }else
                [self filterAudioData];
        }while (gapAudioData.length>0 && audioQueueBuffer->mAudioDataByteSize<audioQueueBuffer->mAudioDataBytesCapacity);
        
        if (audioQueueBuffer->mAudioDataByteSize > 0){
            AudioQueueEnqueueBuffer(audioQueue, audioQueueBuffer, 0, NULL);
            return YES;
        }
        else{
            return NO;
        }
    }
    else{
        UInt32 numBytes=0;
        UInt32 numPackets = audioQueueBuffer->mAudioDataBytesCapacity / self.maxPacketSize;
        status = AudioFileReadPackets(self.audioFileID, NO, &numBytes, audioPacketDescs, packetIndex, &numPackets, audioQueueBuffer->mAudioData);
        if (status != noErr){
            if (status == kAudioFileEndOfFileError)
                WLLog(@"读取mp3文件完毕！");
            else{
                WLLog(@"读取mp3文件失败！");
                numBytes = 0;
            }
        }
        if(numPackets >0){
            audioQueueBuffer->mAudioDataByteSize=numBytes;
            packetIndex += numPackets;
            audioFileOffset += numBytes;
        }
        
        if (audioQueueBuffer->mAudioDataByteSize>0){
            AudioQueueEnqueueBuffer(audioQueue, audioQueueBuffer, numPackets, audioPacketDescs);
            return YES;
        }else{
            return NO;
        }
    }
    return NO;
}

- (AudioFileTypeID)hintForFileExtension:(NSString *)fileExtension{
	AudioFileTypeID fileTypeHint = kAudioFileAAC_ADTSType;
	if ([fileExtension isEqual:@"mp3"])
	{
		fileTypeHint = kAudioFileMP3Type;
	}
	else if ([fileExtension isEqual:@"wav"])
	{
		fileTypeHint = kAudioFileWAVEType;
	}
	else if ([fileExtension isEqual:@"aifc"])
	{
		fileTypeHint = kAudioFileAIFCType;
	}
	else if ([fileExtension isEqual:@"aiff"])
	{
		fileTypeHint = kAudioFileAIFFType;
	}
	else if ([fileExtension isEqual:@"m4a"])
	{
		fileTypeHint = kAudioFileM4AType;
	}
	else if ([fileExtension isEqual:@"mp4"])
	{
		fileTypeHint = kAudioFileMPEG4Type;
	}
	else if ([fileExtension isEqual:@"caf"])
	{
		fileTypeHint = kAudioFileCAFType;
	}
	else if ([fileExtension isEqual:@"aac"])
	{
		fileTypeHint = kAudioFileAAC_ADTSType;
	}
	return fileTypeHint;
}

@end

#pragma mark -   WLAudioPlayer
@interface WLAudioPlayer()<UIAccelerometerDelegate,NSURLConnectionDelegate,NSURLConnectionDataDelegate>{
    WLAudioTask *currentTask;
    NSMutableDictionary *taskDic;
    
    void (^blockProcess)(float playproc, float loadproc);
    void (^blockStateChange)(WLPlayerState state, WLPlayerStopReason reason);
    
	AudioQueueRef audioQueue;
	AudioQueueBufferRef audioQueueBuffer[kWLAudioQueueBufs];
    NSMutableArray *unQueueAudioBufferArray;
    
    Float64  lastProgress;
    CADisplayLink *_displayLink;
}

- (BOOL)audioQueueOutputWithQueue:(AudioQueueRef)audioQueue queueBuffer:(AudioQueueBufferRef)audioQueueBuffer;
- (void)_setState:(WLPlayerState)aStatus;
- (void)_setReason:(WLPlayerStopReason)reason;
- (void)resetOutputTarget;
- (void)setupProximityMonitor;
- (void)closeProximityMonitor;
- (void)stopInternal;

@end

#pragma mark -   C Functions for callback
OSStatus MyAudioFile_ReadProc (void *inClientData, SInt64 inPosition, UInt32 requestCount, void *buffer, UInt32 *actualCount){
    WLAudioTask *task = (__bridge WLAudioTask *)inClientData;
    if (![task canPlay]) {
        return -1;  // cannot play now
    }
    if (task.readTimes>task.maxReadTimes) {
        return -1;
    }
    
    UInt32 length = MIN(requestCount, task.audioData.length-inPosition-1);
    if (task.audioData.length <= inPosition) {
        length = 0;
    }
    if (length > 0) {
        memcpy(buffer, [task.audioData bytes]+inPosition, length);
    }
    if (actualCount) {
        *actualCount = length;
    }
    task.readTimes++;
    return noErr;
}

SInt64 MyAudioFile_GetSizeProc (void *inClientData){
    WLAudioTask *task = (__bridge WLAudioTask *)inClientData;
    return task.expectSize;
}

void MyAudioSessionRouteChange(void *inClientData, AudioSessionPropertyID inID, UInt32 inDataSize, const void * inData){
    if (inID == kAudioSessionProperty_AudioRouteChange) {
        WLAudioPlayer* player = (__bridge WLAudioPlayer *)inClientData;
        CFDictionaryRef    routeChangeDictionary = inData;
        CFNumberRef routeChangeReasonRef =
        CFDictionaryGetValue (routeChangeDictionary, CFSTR (kAudioSession_AudioRouteChangeKey_Reason));
        SInt32 routeChangeReason;
        CFNumberGetValue (routeChangeReasonRef, kCFNumberSInt32Type, &routeChangeReason);
        if (routeChangeReason != kAudioSessionRouteChangeReason_CategoryChange &&
            routeChangeReason != kAudioSessionRouteChangeReason_Override &&
            routeChangeReason != kAudioSessionRouteChangeReason_WakeFromSleep) {
            [player setupProximityMonitor];
            [player resetOutputTarget];
        }
    }
}

void MyAudioQueueBufferCallback(void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef buffer) {
    WLAudioPlayer* player = (__bridge WLAudioPlayer*)inUserData;
    [player audioQueueOutputWithQueue:inAQ queueBuffer:buffer];
}

void MyAudioQueueIsRunningCallback(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID){
    WLAudioPlayer* player = (__bridge WLAudioPlayer*)inUserData;
    UInt32 *isRunning;
    UInt32 dataSize = sizeof(UInt32);
    OSStatus ret = AudioQueueGetProperty(inAQ, inID, &isRunning, &dataSize);
    if (isRunning == 0 || ret != noErr) {
        [player stopInternal];
    }
}

#pragma mark - RVAudioPlayer implementation

@implementation WLAudioPlayer
- (id)init{
    if ((self = [super init])) {
#if TARGET_OS_IPHONE
        AudioSessionAddPropertyListener(kAudioSessionProperty_AudioRouteChange,
                                        MyAudioSessionRouteChange,
                                        (__bridge void *)(self));
#endif
        
        [self resetOutputTarget];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ProxyStateNoti:) name:UIDeviceProximityStateDidChangeNotification object:nil];
        taskDic = [NSMutableDictionary new];
        unQueueAudioBufferArray = [NSMutableArray new];
        
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(notifyProcess)];
        _displayLink.frameInterval = 1;
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        
        _isReplay = NO;
    }
    return self;
}

- (void)dealloc{
    [_displayLink invalidate];
    [self clearTask];
    [self stop];
}

- (Float64)duration{
    if ([currentTask canPlay]) {
        return currentTask.expectDuration;
    }
    return 0.0;
}

- (Float64)processSec{
    if (self.state != WLP_PLAYING && self.state != WLP_STOPPING)
        return lastProgress;
    OSStatus status;
    AudioTimeStamp queueTime;
    Boolean discontinuity;
    status = AudioQueueGetCurrentTime(audioQueue, NULL, &queueTime, &discontinuity);
    if (status != noErr) {
        if (status != kAudioQueueErr_InvalidRunState)
            WLLog(@"get audio queue time error.");
        return 0.0;
    }
    lastProgress = queueTime.mSampleTime / currentTask.format.mSampleRate;
    return lastProgress;
}

- (BOOL)isPlaying{
    return (currentTask!=nil);
}

- (float)process{
    if (self.duration == 0.0)
        return 0.0;
    return [self processSec] / self.duration;
}

- (float)loadpercent{
    if (!currentTask || currentTask.state==WLAudioTaskState_Cached) {
        return 1.0;
    }
    if (currentTask.expectSize == 0) {
        return 0.0;
    }
    return (float)[currentTask downloadSize]/(float)currentTask.expectSize;
}

- (void)_setReason:(WLPlayerStopReason)reason{
    _reason = reason;
}

- (void)_setState:(WLPlayerState)aStatus{
    OSStatus status;
    if (_state != aStatus)
    {
        _state = aStatus;
        if (blockStateChange) {
            if ([NSThread isMainThread]){
                if (_isReplay) {
                    _isReplay = NO;
                    WLPlayerState state = WLP_REPLAY;
                    blockStateChange(state, _reason);
                }else{
                    blockStateChange(_state, _reason);
                }
                switch (aStatus) {
                    case WLP_PLAYING:
                        status = AudioQueueStart(audioQueue, nil);
                        if (status != noErr) {
                            WLLog(@"errorcode: %ld AudioQueueStart", status);
                            _reason = WLP_STOPPING_INTERNAL_ERROR;
                            [self stopInternal];
                        }
                        [self setupProximityMonitor];
                        break;
                        
                    case WLP_BUFFERING:
                    case WLP_PAUSED:
                        if (audioQueue) {
                            status = AudioQueuePause(audioQueue);
                            if (status != noErr) {
                                WLLog(@"errorcode: %ld AudioQueuePause", status);
                                _reason = WLP_STOPPING_INTERNAL_ERROR;
                                [self stopInternal];
                            }
                        }
                        break;
                        
                    case WLP_STOPPED:
                        if (_reason == WLP_STOPPING_NETWORK_ERROR || _reason == WLP_STOPPING_FILEFORMAT_ERROR) {
                            NSString *cachpath = [WLFileManager voiceFilePathAtCache:currentTask.url];
                            [WLFileManager deleteVoiceWithFilePath:cachpath];
                        }
                        blockStateChange = nil;
                        currentTask = nil;
                        blockProcess = nil;
                        [self closeProximityMonitor];
                        break;
                        
                    default:
                        break;
                }
            }else{
                NSAssert(NO, @"this selector expect to be called in main thread");
            }
        }
    }
}

- (void)notifyProcess{
    if (blockProcess && currentTask) {
        if ([NSThread isMainThread]){
            if (self.process > 0.0)
                blockProcess(self.process, self.loadpercent);
            if (self.process >= 1.0) {
                blockProcess = nil;
                [self stopInternal];
            }
        }else{
            NSAssert(NO, @"this selector expect to be called in main thread");
            dispatch_async(dispatch_get_main_queue(), ^{
                if (blockProcess && currentTask) {
                    blockProcess(self.process, self.loadpercent);
                }
            });
        }
    }
}

- (void)initForplay{
    if (self.state != WLP_INITIALIZED) {
        [self stop];
        AudioSessionSetActive(YES);
        [self _setState:WLP_INITIALIZED];
        _reason = WLP_NO_STOP;
        lastProgress = 0.0;
    }
}

- (void)playWithPath:(NSString *)path andProcess:(void (^)(float, float))proc onStateChanged:(void (^)(WLPlayerState, WLPlayerStopReason))change{
    [self initForplay];
    
    @synchronized(self){
        blockStateChange = change;
        blockProcess = proc;
        currentTask = [self audioTaskForPath:path];
    }
    if (!currentTask) {
        _reason = WLP_STOPPING_URL_ERROR;
        dispatch_async(dispatch_get_main_queue(), ^(){
            [self stopInternal];
        });
        return;
    }
    [self enqueueWithData];
}

- (void)replay{
    [currentTask replay];
    [self enqueueWithData];
}

- (void)stopInternal{
    [self deInitAudioQueue];
    [self _setState:WLP_STOPPED];
}

- (void)stop{
    if (self.state != WLP_STOPPED && self.state != WLP_INITIALIZED) {
        _reason = WLP_STOPPING_USER_ACTION;
        [self stopInternal];
    }
}

static WLPlayerState previousState = WLP_INITIALIZED;
- (void)pause{
    if (self.isPlaying) {
        if (self.state != WLP_PAUSED) {
            previousState = self.state;
            [self _setState:WLP_PAUSED];
        }else{
            if (previousState == WLP_BUFFERING && [unQueueAudioBufferArray count] < kWLAudioQueueBufs) {
                [self _setState:WLP_PLAYING];
            }else{
                [self _setState:previousState];
            }
        }
    }
}

- (void)enqueueWithData{
    if (!currentTask) {
        return;
    }
    
    if (![currentTask canPlay]){
        switch (currentTask.state) {
            case WLAudioTaskState_Downing:
                [self _setState:WLP_BUFFERING];
                break;
            case WLAudioTaskState_Error:
                _reason = WLP_STOPPING_NETWORK_ERROR;
                [self stopInternal];
                break;
                
            case WLAudioTaskState_ReadyForPlay:
                [self _setState:WLP_BUFFERING];
                break;
            case WLAudioTaskState_Cached:
                _reason = WLP_STOPPING_FILEFORMAT_ERROR;
                [self stopInternal];
                break;
            default:
                NSAssert(0, @"shouldn't run here");
                break;
        }
        return;
    }
    if (!audioQueue && ![self initAudioQueue]) {
        [self deInitAudioQueue];
        return;
    }
    while ([unQueueAudioBufferArray count]>0) {
        NSValue *value = [unQueueAudioBufferArray objectAtIndex:0];
        [unQueueAudioBufferArray removeObject:value];
        AudioQueueBufferRef audioQueueBuf = [value pointerValue];
        if (![self audioQueueOutputWithQueue:audioQueue queueBuffer:audioQueueBuf]) {
            break;
        }
    }
}

#pragma mark  audioqueue about
- (BOOL)initAudioQueue{
    [self deInitAudioQueue];
    if (!currentTask.audioFileID || !currentTask.format.mFormatID)
        return NO;
    
    AudioStreamBasicDescription format = currentTask.format;
    NSAssert((format.mFormatID == kAudioFormatLinearPCM) || (format.mFormatID == kAudioFormatMPEGLayer3) , @"audio format expect to be mp3 or caf");
    OSStatus status = AudioQueueNewOutput(&format, MyAudioQueueBufferCallback, (__bridge void *)(self), CFRunLoopGetMain(), nil, 0, &audioQueue);
    if (status != noErr) {
        WLLog(@"errorcode: %ld AudioQueueNewOutput", status);
        _reason = WLP_STOPPING_INTERNAL_ERROR;
        [self stopInternal];
        return NO;
    }
    
    status = AudioQueueAddPropertyListener(audioQueue, kAudioQueueProperty_IsRunning, MyAudioQueueIsRunningCallback, (__bridge void *)(self));
    if (status != noErr) {
        WLLog(@"errorcode: %ld AudioQueueAddPropertyListener", status);
        _reason = WLP_STOPPING_INTERNAL_ERROR;
        [self stopInternal];
        return NO;
    }
    
    if (currentTask.magicCookie) {
        AudioQueueSetProperty(audioQueue, kAudioQueueProperty_MagicCookie, [currentTask.magicCookie bytes], currentTask.magicCookie.length);
    }
        
    for (int i = 0; i <kWLAudioQueueBufs; i++) {
        OSStatus status = AudioQueueAllocateBuffer(audioQueue, AudioQueueBufSize, &audioQueueBuffer[i]);
        if (status != noErr) {
            WLLog(@"errorcode: %ld AudioQueueAllocateBuffer", status);
            _reason = WLP_STOPPING_INTERNAL_ERROR;
            [self stopInternal];
            return NO;
        }
        [unQueueAudioBufferArray addObject:[NSValue valueWithPointer:audioQueueBuffer[i]]];
    }
    
    status = AudioQueueSetParameter (audioQueue, kAudioQueueParam_Volume, 1);
    if (status != noErr) {
        WLLog(@"errorcode: %ld AudioQueueSetParameter", status);
        _reason = WLP_STOPPING_INTERNAL_ERROR;
        [self stopInternal];
        return NO;
    }
    return YES;
}

- (BOOL)deInitAudioQueue{
    [unQueueAudioBufferArray removeAllObjects];
    if (audioQueue) {
        AudioQueueRemovePropertyListener(audioQueue, kAudioQueueProperty_IsRunning, MyAudioQueueIsRunningCallback, (__bridge void *)(self));
        AudioQueueStop(audioQueue, TRUE);
        AudioQueueDispose(audioQueue, TRUE);
        audioQueue = nil;
        for (int i=0; i<kWLAudioQueueBufs; i++) {
            audioQueueBuffer[i] = NULL;
        }
    }
    return YES;
}

- (BOOL)audioQueueOutputWithQueue:(AudioQueueRef)audioQue queueBuffer:(AudioQueueBufferRef)audioQueueBuf{
    if(![currentTask fillAudioQueue:audioQue withBuffer:audioQueueBuf]){
        [unQueueAudioBufferArray addObject:[NSValue valueWithPointer:audioQueueBuf]];
        if (currentTask.state == WLAudioTaskState_Cached) {
            if ([currentTask isReachEOF]) {
                _reason = WLP_STOPPING_EOF;
                [self _setState:WLP_STOPPING];
                AudioQueueStop(audioQueue, NO);
            }else{
                _reason = WLP_STOPPING_FILEFORMAT_ERROR;
                AudioQueueStop(audioQueue, YES);
                [self _setState:WLP_STOPPED];
            }
        }else if(currentTask.state == WLAudioTaskState_Error){
            _reason = WLP_STOPPING_NETWORK_ERROR;
            [self _setState:WLP_STOPPING];
            AudioQueueStop(audioQueue, NO);
        }else if ([unQueueAudioBufferArray count] == kWLAudioQueueBufs){
            [self _setState:WLP_BUFFERING];
        }
        return NO;
    }else{
        [self _setState:WLP_PLAYING];
        return YES;
    }
}

#pragma mark  download and cache management
- (BOOL)initCache{
    return [WLAudioPlayer cachePath:@"http://www.baidu.com"].length > 0;
}

- (void)clearCache{
    if (diskAudioCachePath) {
        [[NSFileManager defaultManager] removeItemAtPath:diskAudioCachePath error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:diskAudioCachePath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
    }
}

- (void)clearTask{
    [taskDic removeAllObjects];
}

- (WLAudioTask *) audioTaskForPath:(NSString *)path{
    NSString *cachePath = [WLFileManager voiceFilePathAtCache:path];
    if (!cachePath)
        return nil;
    
    WLAudioTask *task = [taskDic valueForKey:path];
    if (task)
        return task;
    
    if ([WLFileManager voicefileExistatLocalWithPath:cachePath]) {
        
        WLAudioTask *task = [WLAudioTask new];
        task.url = path;
        task.state = WLAudioTaskState_Cached;
        if ([task canPlay])
            return task;
        [WLFileManager deleteVoiceWithFilePath:cachePath];
    }

    task = [WLAudioTask new];
    task.url = path;
    task.audioData = [NSMutableData dataWithCapacity:0];
    task.expectSize = -1;
    task.request = [NSURLRequest requestWithURL:[NSURL URLWithString:path]];
    task.connect = [[NSURLConnection alloc] initWithRequest:task.request delegate:self];
    task.state = WLAudioTaskState_Downing;
    [taskDic setValue:task forKey:path];
    return task;
}

#pragma mark download Callback
- (void)connection:(NSURLConnection *)aConn didReceiveResponse:(NSURLResponse *)response{
    NSURLRequest *req = [aConn currentRequest];
    WLAudioTask *task = [taskDic valueForKey:[[req URL] absoluteString]];
    NSAssert([task isKindOfClass:[WLAudioTask class]], @"task should be found in task pool");
    
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
    if ([response respondsToSelector:@selector(allHeaderFields)]){
        NSDictionary* httpHeaders = [httpResponse allHeaderFields];
        task.expectSize = [[httpHeaders objectForKey:@"Content-Length"] integerValue];
    }
}
- (void)connection:(NSURLConnection *)aConn didReceiveData:(NSData *)data{
    NSURLRequest *req = [aConn currentRequest];
    WLAudioTask *task = [taskDic valueForKey:[[req URL] absoluteString]];
    NSAssert([task isKindOfClass:[WLAudioTask class]], @"task should be found in task pool");
    [task.audioData appendData:data];
    
    if (task.audioData.length > minAudioBufferlength)
        task.state = WLAudioTaskState_ReadyForPlay;
    
    if(task == currentTask)
        [self enqueueWithData];
}

- (void)connection:(NSURLConnection *)aConn didFailWithError:(NSError *)error{
    NSURLRequest *req = [aConn currentRequest];
    NSString *url = [[req URL] absoluteString];
    WLAudioTask *task = [taskDic valueForKey:url];
    if (!task || url.length == 0) {
        for (id k in [taskDic allKeys]) {
            WLAudioTask *t = [taskDic valueForKey:k];
            if (t.connect == aConn) {
                task = t;
                url = k;
                break;
            }
        }
    }
    NSAssert([task isKindOfClass:[WLAudioTask class]], @"task should be found in task pool");
    task.request = nil;
    task.connect = nil;
    task.error = error;
    task.state = WLAudioTaskState_Error;
    
    if (url.length > 0)
        [taskDic removeObjectForKey:url];
    if(task == currentTask){
        _reason = WLP_STOPPING_NETWORK_ERROR;
        [self stopInternal];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)aConn{
    NSURLRequest *req = [aConn currentRequest];
    WLAudioTask *task = [taskDic valueForKey:[[req URL] absoluteString]];
    NSAssert([task isKindOfClass:[WLAudioTask class]], @"task should be found in task pool");
    
    task.request = nil;
    task.connect = nil;
    task.state = WLAudioTaskState_Cached;
    
    [taskDic removeObjectForKey:[req.URL absoluteString]];
    if(task == currentTask){
        [self enqueueWithData];
    }
}

#pragma mark  Proximity Sensor
- (void)proximityMoniterReplay{
    float duration =  [self duration];
    
    if (self.isPlaying && duration <= 5.f) {
        [currentTask replay];
        
        if (self.state == WLP_PLAYING || self.state == WLP_STOPPING) {
            _isReplay = YES;
            void (^blkProcTmp)(float playproc, float loadproc) = blockProcess;
            void (^blkChgTmp)(WLPlayerState state, WLPlayerStopReason reason) = blockStateChange;
            blockStateChange = nil;
            blockProcess = nil;
            [self playWithPath:currentTask.url andProcess:blkProcTmp onStateChanged:blkChgTmp];
        }
    }
}

- (void)ProxyStateNoti:(NSNotification *)note{
    if ([UIDevice currentDevice].proximityState == YES) {
        WLLog(@"inner");
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(delayCloseProximityMoniter) object:nil];
        const CFStringRef audioRouteOverride = kAudioSessionOutputRoute_BuiltInReceiver;
        AudioSessionSetProperty(kAudioSessionProperty_OverrideAudioRoute, sizeof(audioRouteOverride), &audioRouteOverride);
        
        [self proximityMoniterReplay];
    } else {
        if (!self.isPlaying) {
            [[UIDevice currentDevice] setProximityMonitoringEnabled:NO];
            [self resetOutputTarget];
        }else{
            [self delayCloseProximityMoniter];
            [self resetOutputTarget];
            
            [self proximityMoniterReplay];
        }
    }
}

- (void)delayEnableProximityMoniter{
    if (![UIDevice currentDevice].proximityMonitoringEnabled) {
        [[UIDevice currentDevice] setProximityMonitoringEnabled:YES];
        
        UIAccelerometer* theAccelerometer = [UIAccelerometer sharedAccelerometer];
        theAccelerometer.delegate = nil;
    }
}

- (void)delayCloseProximityMoniter{
    if ([UIDevice currentDevice].proximityMonitoringEnabled) {
        [[UIDevice currentDevice] setProximityMonitoringEnabled:NO];
        
        UIAccelerometer* theAccelerometer = [UIAccelerometer sharedAccelerometer];
        theAccelerometer.updateInterval = 1 / 20;
        theAccelerometer.delegate = self;
    }
}

- (void)accelerometer:(UIAccelerometer *)accelerometer didAccelerate:(UIAcceleration *)acceleration {
    if (fabs(sqrtf(acceleration.z*acceleration.z + acceleration.y*acceleration.y + acceleration.x*acceleration.x)-1.0) > 0.05) {
        [self delayEnableProximityMoniter];
        
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(delayCloseProximityMoniter) object:nil];
        [self performSelector:@selector(delayCloseProximityMoniter) withObject:nil afterDelay:0.6];
    }
}

- (void)setupProximityMonitor{
    if ([self hasHeadset]){
        [self closeProximityMonitor];
        return;
    }
    if ([UIDevice currentDevice].proximityMonitoringEnabled)
        return;
    
    WLLog(@"setupProximityMonitor");
    UIAccelerometer* theAccelerometer = [UIAccelerometer sharedAccelerometer];
    theAccelerometer.updateInterval = 1 / 20;
    theAccelerometer.delegate = self;
    
    [self delayCloseProximityMoniter];
    [self resetOutputTarget];
}

- (void)closeProximityMonitor{
    WLLog(@"closeProximityMonitor");
    UIAccelerometer* theAccelerometer = [UIAccelerometer sharedAccelerometer];
    theAccelerometer.delegate = nil;
    
    if ([UIDevice currentDevice].proximityMonitoringEnabled && ![UIDevice currentDevice].proximityState) {
        [[UIDevice currentDevice] setProximityMonitoringEnabled:NO];
        [self resetOutputTarget];
    }
}

- (BOOL)hasHeadset{
#if TARGET_IPHONE_SIMULATOR
    return NO;
#else
    CFStringRef route = nil;
    UInt32 propertySize = sizeof(CFStringRef);
    AudioSessionGetProperty(kAudioSessionProperty_AudioRoute, &propertySize, &route);
    NSString *routeStr = (__bridge NSString *)route;
    if(routeStr.length != 0){
        /* Known values of route:
         * "Headset"
         * "Headphone"
         * "Speaker"
         * "SpeakerAndMicrophone"
         * "HeadphonesAndMicrophone"
         * "HeadsetInOut"
         * "ReceiverAndMicrophone"
         * "Lineout"
         */
        NSRange headphoneRange = [routeStr rangeOfString : @"Headphone"];
        NSRange headsetRange = [routeStr rangeOfString : @"Headset"];
        CFRelease(route);
        if (headphoneRange.location != NSNotFound) {
            return YES;
        } else if(headsetRange.location != NSNotFound) {
            return YES;
        }
    }
    return NO;
#endif
}

- (void)resetOutputTarget {
    WLLog(@" --> Outter");
    BOOL hasHeadset = [self hasHeadset];
    UInt32 audioRouteOverride = hasHeadset ? kAudioSessionOverrideAudioRoute_None : kAudioSessionOverrideAudioRoute_Speaker;
    AudioSessionSetProperty(kAudioSessionProperty_OverrideAudioRoute, sizeof(audioRouteOverride), &audioRouteOverride);
}

#pragma mark other utility function
+ (NSString *)cachePath:(NSString *)path{
    if (!diskAudioCachePath) {
        BOOL ret = NO;
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        diskAudioCachePath = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"AudioCache"];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:diskAudioCachePath]){
            ret = [[NSFileManager defaultManager] createDirectoryAtPath:diskAudioCachePath
                                            withIntermediateDirectories:YES
                                                             attributes:nil
                                                                  error:NULL];
        }
        
        if (!ret){
            return nil;
        }
        
        NSDate *expirationDate = [NSDate dateWithTimeIntervalSinceNow:-cacheMaxCacheAge];
        NSDirectoryEnumerator *fileEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:diskAudioCachePath];
        for (NSString *fileName in fileEnumerator)
        {
            NSString *filePath = [diskAudioCachePath stringByAppendingPathComponent:fileName];
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
            if ([[[attrs fileModificationDate] laterDate:expirationDate] isEqualToDate:expirationDate])
            {
                [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
            }
        }
    }
    
    if (!path || [path length] <= 0)
        return nil;
    if ([path hasPrefix:@"/"])
        return path;
    
    NSString *filename = [WLFileManager md5HexDigest:path];
    
    return [diskAudioCachePath stringByAppendingPathComponent:filename];
}

@end
