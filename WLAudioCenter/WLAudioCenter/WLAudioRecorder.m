//
//  WLAudioRecorder.m
//  WLAudioCenter
//
//  Created by 王亮 on 13-9-11.
//  Copyright (c) 2013年 王亮. All rights reserved.
//

#import "WLAudioRecorder.h"
#import "WLAudioObject.h"
#import "WLFileManager.h"

#define kWLAudioSample 16000
#define kWLAudioChannel 1
#define kWLAudioQueueBufSize 0x4000

@interface WLAudioRecorder()
{
    AudioFileID cafFileID;
    AudioStreamBasicDescription audioformat;
    
	AudioQueueRef audioQueue;
	AudioQueueBufferRef audioQueueBuffer[kWLAudioQueueBufs];
    
    AudioQueueLevelMeterState *chanLevl;
    double currentPacket;
    
    NSTimer *_displayTimer;
    
    float lastProgress;
    float averagePower;
    float peakPower;
    
    void (^blockStart)(NSError *error, WLAudioObject *obj);
    void (^blockStop)(NSError *error, WLAudioObject *obj);
    void (^blockProgress)(float recordProgress, float peakPower, float averagePower, WLAudioObject *obj);
}
@property (nonatomic, strong) WLAudioObject *recordingAudio;
- (void)startError:(NSError *)error;
- (void)stopInternalWithError:(NSError *)error;

- (void)audioQueueInputwithQueue:(AudioQueueRef)audioQue
                     queueBuffer:(AudioQueueBufferRef)audioQueueBuf
                       timeStamp:(const AudioTimeStamp *)inStartTime
                         numPack:(UInt32)inNumberPacketDescriptions
                 withDescription:(const AudioStreamPacketDescription *)inPacketDescs;
@end

#pragma mark - AVFoundation Callback
void AudioInputCallback(void * inUserData,  
                        AudioQueueRef inAQ,
                        AudioQueueBufferRef inBuffer,
                        const AudioTimeStamp * inStartTime,
                        UInt32 inNumberPacketDescriptions,
                        const AudioStreamPacketDescription * inPacketDescs)
{    
    WLAudioRecorder* recorder = (__bridge WLAudioRecorder*)inUserData;
    [recorder audioQueueInputwithQueue:inAQ
                           queueBuffer:inBuffer
                             timeStamp:inStartTime
                               numPack:inNumberPacketDescriptions
                       withDescription:inPacketDescs];
    
}

void RecordAudioQueueIsRunningCallback(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    WLAudioRecorder* recorder = (__bridge WLAudioRecorder*)inUserData;
    UInt32 *isRunning;
    UInt32 dataSize = sizeof(UInt32);
    OSStatus ret = AudioQueueGetProperty(inAQ, inID, &isRunning, &dataSize);
    if (isRunning == 0 || ret != noErr) {
        [recorder stopInternalWithError:nil];
    }
}

static NSString *errAudioRecordDomain = @"errorAudioRecordDomain";
static NSString *errAudioRecordKey = @"errAudioRecordKey";

@implementation WLAudioRecorder

- (id) init
{
    self = [super init];
    if (self) {
        [self setupAudioFormat:&audioformat];
        
        self.maxRecordTime = kWLMaxRecoderTime;
    }
    return self;
}

- (void)dealloc
{
    if (chanLevl) {
        free(chanLevl);
        chanLevl = NULL;
    }
    [_displayTimer invalidate];
    _displayTimer = nil;
    [self stop];
}

- (void)setupAudioFormat:(AudioStreamBasicDescription*)format
{
	format->mSampleRate = kWLAudioSample;
	format->mFormatID = kAudioFormatLinearPCM;
	format->mFramesPerPacket = 1;
	format->mChannelsPerFrame = kWLAudioChannel;
	format->mBytesPerFrame = 2;
	format->mBytesPerPacket = 2;
	format->mBitsPerChannel = 16;
	format->mReserved = 0;
	format->mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
}

- (void)startTimer{
    [_displayTimer invalidate];
    _displayTimer = nil;
    
    _displayTimer = [NSTimer timerWithTimeInterval:1/60.f target:self selector:@selector(notifyProcess) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_displayTimer forMode:NSRunLoopCommonModes];
}

- (void)startRecordingWithHandlerOnStart:(void (^)(NSError *error, WLAudioObject *obj))startHandler
                                  OnStop:(void (^)(NSError *error, WLAudioObject *obj))stopHandler
                        OnProgressUpdate:(void (^)(float recordProgress, float peakPower, float averagePower, WLAudioObject *obj))progressHandler{
    [self stopInternalWithError:nil];
    
    blockStart = startHandler;
    [self prepareNewRecording];
    
    if (blockStart) {
        blockProgress = progressHandler;
        blockStop = stopHandler;
    }
    
}

- (void)stop
{
    if (![self isRecording]) {
        return;
    }
    AudioQueueStop(audioQueue, TRUE);
    [self stopInternalWithError:nil];
}

- (BOOL)isRecording
{
    if (audioQueue || blockStop || blockStart) {
        return YES;
    }
    return NO;
}

- (void)prepareNewRecording{
    [self stopInternalWithError:nil];
    
    peakPower = 0.0;
    averagePower = 0.0;
    currentPacket = 0;
    lastProgress = 0.0;
    
    [self setupAudioFormat:&audioformat];
    [self createRecordAudioObjectwithUid:kWLFilePrefix];
    if([self initAudioQueue]){
        if (blockStart) {
            blockStart(nil, self.recordingAudio);
        }
    }
}

- (void) createRecordAudioObjectwithUid: (NSString *)userId{
    NSDate * currentDate = [NSDate new];
    NSDateFormatter *format = [[NSDateFormatter alloc] init];
    [format setDateFormat:@"-yyyyMMddHHmmss-"];
    NSString * recordStr = [userId stringByAppendingString:[format stringFromDate:currentDate]];
    NSString * recordFileName = [recordStr stringByAppendingString:@"original.caf"];
    NSString * mp3FileName = [[recordStr stringByAppendingString:@"filted.mp3"] stringByAppendingPathExtension:kWLTmpMp3Ex];
    
    self.recordingAudio = [[WLAudioObject alloc] init];
    self.recordingAudio.recordingFileName = recordFileName;
    self.recordingAudio.mp3ProcessedFileName = mp3FileName;

    self.recordingAudio.mp3FilePath = [WLFileManager getFilePath:kWLDOC_MP3];       /// Documents/MP3/  目录
    self.recordingAudio.cafFilePath = [WLFileManager getFilePath:kWLDOC_CAF];      /// Documents/Temp/ 目录
    if (!self.recordingAudio.cafFilePath || self.recordingAudio.cafFilePath.length == 0 || !self.recordingAudio.mp3FilePath || self.recordingAudio.mp3FilePath.length == 0) {
        NSString *errmsg = @"no enough disk space";
        NSError *error = [NSError errorWithDomain:errAudioRecordDomain code:-1 userInfo:@{errAudioRecordKey:errmsg}];
        [self startError:error];
    }
}

- (void)startError:(NSError *)error{
    if (error){
        blockStart(error, self.recordingAudio);
        [self deInitAudioQueue];
        if (self.recordingAudio.recordingFileName.length > 0)
            unlink([self.recordingAudio.recordingFileName UTF8String]);
        
        blockStop = nil;
        blockStart = nil;
        blockProgress = nil;
    }else{
        [self startTimer];
    }
}

- (void)stopInternalWithError:(NSError *)error
{
    self.recordingAudio.duration = lastProgress;
    [self deInitAudioQueue];
    if (blockStop) {
        if (error) {
            if (self.recordingAudio.recordingFileName.length > 0)
                unlink([self.recordingAudio.recordingFileName UTF8String]);
            blockStop(error, nil);
        }
        else{
            blockStop(nil, self.recordingAudio);
        }
        [_displayTimer invalidate];
        _displayTimer = nil;
        blockStop = nil;
        blockStart = nil;
        blockProgress = nil;
    }
}
#pragma mark - Audioqueue
- (BOOL)initAudioQueue{
    [self deInitAudioQueue];
    
    NSAssert(self.recordingAudio.cafFilePath.length>0, @"audioobject should be initilaized");
    
    OSStatus status;
    status = AudioQueueNewInput(&audioformat, AudioInputCallback, (__bridge void *)(self), CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &audioQueue);
    if (status != noErr) {
        NSString *errmsg = @"AudioQueueNewOutput error";
        [self startError:[NSError errorWithDomain:errAudioRecordDomain code:status userInfo:@{errAudioRecordKey : errmsg, NSLocalizedDescriptionKey : errmsg}]];
        return NO;
    }
    
    status = AudioQueueAddPropertyListener(audioQueue, kAudioQueueProperty_IsRunning, RecordAudioQueueIsRunningCallback, (__bridge void *)(self));
    if (status != noErr) {
        NSString *errmsg = @"AudioQueueAddPropertyListener called with kAudioQueueProperty_IsRunning error";
        [self startError:[NSError errorWithDomain:errAudioRecordDomain code:status userInfo:@{errAudioRecordKey : errmsg, NSLocalizedDescriptionKey : errmsg}]];
        return NO;
    }
    
    for (int i = 0; i <kWLAudioQueueBufs; i++) {
        OSStatus status = AudioQueueAllocateBuffer(audioQueue, kWLAudioQueueBufSize, &audioQueueBuffer[i]);
        if (status != noErr) {
            NSString *errmsg = @"AudioQueueAllocateBuffer error";
            [self startError:[NSError errorWithDomain:errAudioRecordDomain code:status userInfo:@{errAudioRecordKey : errmsg, NSLocalizedDescriptionKey : errmsg}]];
            return NO;
        }
        status = AudioQueueEnqueueBuffer(audioQueue, audioQueueBuffer[i], 0, NULL);
        if (status != noErr) {
            NSString *errmsg = @"AudioQueueEnqueueBuffer error";
            [self startError:[NSError errorWithDomain:errAudioRecordDomain code:status userInfo:@{errAudioRecordKey : errmsg, NSLocalizedDescriptionKey : errmsg}]];
            return NO;
        }
    }
    
    UInt32 val = 1;
    status = AudioQueueSetProperty(audioQueue, kAudioQueueProperty_EnableLevelMetering, &val, sizeof(UInt32));
    if (status != noErr) {
        NSString *errmsg = @"AudioQueueSetProperty called with kAudioQueueProperty_EnableLevelMetering error";
        [self startError:[NSError errorWithDomain:errAudioRecordDomain code:status userInfo:@{errAudioRecordKey : errmsg, NSLocalizedDescriptionKey : errmsg}]];
        return NO;
    }
    
    NSString *path = [self.recordingAudio.cafFilePath stringByAppendingPathComponent:self.recordingAudio.recordingFileName];
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (UInt8 *)[path UTF8String], path.length, false);
    status = AudioFileCreateWithURL(url, kAudioFileCAFType, &audioformat, kAudioFileFlags_EraseFile, &cafFileID);
    CFRelease(url);
    if (status != noErr) {
        NSString *errmsg = @"AudioFileCreateWithURL error";
        [self startError:[NSError errorWithDomain:errAudioRecordDomain code:status userInfo:@{errAudioRecordKey : errmsg, NSLocalizedDescriptionKey : errmsg}]];
        return NO;
    }
    
    currentPacket = 0;
    lastProgress = 0;
    status = AudioQueueStart(audioQueue, NULL);
    if (status != noErr) {
        NSString *errmsg = @"AudioQueueStart error";
        [self startError:[NSError errorWithDomain:errAudioRecordDomain code:status userInfo:@{errAudioRecordKey : errmsg, NSLocalizedDescriptionKey : errmsg}]];
        return NO;
    }
    
    chanLevl =  (AudioQueueLevelMeterState*)realloc(chanLevl, audioformat.mChannelsPerFrame * sizeof(AudioQueueLevelMeterState));
    if (!chanLevl) {
        NSString *errmsg = @"malloc AudioQueueLevelMeterState error";
        [self startError:[NSError errorWithDomain:errAudioRecordDomain code:-1 userInfo:@{errAudioRecordKey : errmsg, NSLocalizedDescriptionKey : errmsg}]];
        return NO;
    }
    
    [self startError:nil];
    return YES;
}

- (BOOL)deInitAudioQueue{
    if (audioQueue) {
        AudioQueueRemovePropertyListener(audioQueue, kAudioQueueProperty_IsRunning, RecordAudioQueueIsRunningCallback, (__bridge void *)(self));
        AudioQueueStop(audioQueue, TRUE);
        AudioQueueDispose(audioQueue, TRUE);
        audioQueue = nil;
        for (int i=0; i<kWLAudioQueueBufs; i++) {
            audioQueueBuffer[i] = NULL;
        }
        
        if (cafFileID) {
            AudioFileClose(cafFileID);
            cafFileID = nil;
            currentPacket = 0;
        }
    }
    return YES;
}

- (void)audioQueueInputwithQueue:(AudioQueueRef)audioQue
                     queueBuffer:(AudioQueueBufferRef)audioQueueBuf
                       timeStamp:(const AudioTimeStamp *)inStartTime
                         numPack:(UInt32)inNumberPacketDescriptions
                 withDescription:(const AudioStreamPacketDescription *)inPacketDescs{
    
    OSStatus status = AudioFileWritePackets(cafFileID,
                                            false,
                                            audioQueueBuf->mAudioDataByteSize,
                                            inPacketDescs,
                                            currentPacket,
                                            &inNumberPacketDescriptions,
                                            audioQueueBuf->mAudioData);
    if (status != noErr) {
        NSString *errmsg = @"AudioFileWritePackets error";
        [self stopInternalWithError:[NSError errorWithDomain:errAudioRecordDomain code:status userInfo:@{errAudioRecordKey : errmsg, NSLocalizedDescriptionKey : errmsg}]];
    }else{
        currentPacket += inNumberPacketDescriptions;
        AudioQueueEnqueueBuffer(audioQueue, audioQueueBuf, 0, NULL);
    }
}

#pragma mark - Timer
- (void)notifyProcess{
    if (blockProgress && [self isRecording]) {
        [self updatePower];
        blockProgress([self processSec], peakPower, averagePower, self.recordingAudio);
        if ([self processSec]*1000 >= self.maxRecordTime) {
            [self stop];
        }
    }
}
- (Float64)processSec{
    if (!cafFileID) {
        return 0.0;
    }
    UInt64 audioFileDataLeng;
    UInt32 propsize = sizeof(UInt64);
    OSStatus readStatus = AudioFileGetProperty(cafFileID, kAudioFilePropertyAudioDataByteCount, &propsize, &audioFileDataLeng);
    if (readStatus != noErr) {
        return 0.0;
    }
    UInt32 bitsRate;
    propsize = sizeof(UInt32);
    readStatus = AudioFileGetProperty(cafFileID, kAudioFilePropertyBitRate, &propsize, &bitsRate);
    if (readStatus != noErr) {
        return 0.0;
    }
    if (bitsRate > 0)
        lastProgress = (float)audioFileDataLeng/(bitsRate*0.125);

    return lastProgress;
}
- (void)updatePower{
    if (!audioQueue) {
        averagePower = 0.0;
        peakPower = 0.0;
        return;
    }
    UInt32 data_sz = sizeof(AudioQueueLevelMeterState) * audioformat.mChannelsPerFrame;
    OSErr status = AudioQueueGetProperty(audioQueue, kAudioQueueProperty_CurrentLevelMeterDB, chanLevl, &data_sz);
    if (status == noErr) {
        averagePower = chanLevl[0].mAveragePower;
        peakPower = chanLevl[0].mPeakPower;
    }
}
@end
