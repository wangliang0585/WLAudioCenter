//
//  WLAudioObject.m
//  WLAudioCenter
//
//  Created by 王亮 on 13-9-11.
//  Copyright (c) 2013年 王亮. All rights reserved.
//

#import "WLAudioObject.h"
#import "WLFileManager.h"
@implementation WLAudioObject

- (id)init{
    if (self=[super init]) {
        _createTime = [[NSDate dateWithTimeIntervalSinceNow:0] timeIntervalSince1970];
    }
    return self;
}

- (id)initAudioWithURL:(NSString *)URL
{
    self = [self init];
    
    if (self) {
        _cafFilePath = [WLFileManager getFilePath:kWLDOC_CAF];
        _mp3FilePath = [WLFileManager getFilePath:kWLDOC_MP3];
        _sourceURL = URL ? [URL copy] : @"";
        WLLog(@"RVAudioObject init with URL: %@", URL);
    }
    
    return  self;
}

- (id) initWithDictionary:(NSDictionary *) dictionary {
    self = [self init];
    if (self) {
        _sourceURL = [dictionary objectForKey:@"soundUrl"] ? [[dictionary objectForKey:@"soundUrl"] copy] : @"";
        _duration = [[dictionary objectForKey:@"duration"] floatValue] * 0.001;// 从毫秒换算成秒
        _recordingFileName = [dictionary objectForKey:@"recordingFileName"]?[[dictionary objectForKey:@"recordingFileName"]copy]:@"";
        _cafFilePath = [dictionary objectForKey:@"cafFilePath"]?[[dictionary objectForKey:@"cafFilePath"]copy]:@"";
        _mp3FilePath = [dictionary objectForKey:@"mp3FilePath"]?[[dictionary objectForKey:@"mp3FilePath"]copy]:@"";
        _mp3ProcessedFileName = [dictionary objectForKey:@"mp3ProcessedFileName"]?[[dictionary objectForKey:@"mp3ProcessedFileName"]copy]:@"";
    }
    return self;
}

- (NSDictionary *) toDictionary {
    NSMutableDictionary * dict = [NSMutableDictionary dictionaryWithCapacity:10];
    [dict setValue:_sourceURL ? _sourceURL : @"" forKey:@"soundUrl"];
    [dict setValue:[NSNumber numberWithFloat:_duration*1000] forKey:@"duration"];//从秒转换成毫秒
    [dict setValue:_recordingFileName?_recordingFileName : @"" forKey:@"recordingFileName"];
    [dict setValue:_cafFilePath?_cafFilePath:@"" forKey:@"cafFilePath"];
    [dict setValue:_mp3FilePath?_mp3FilePath:@"" forKey:@"mp3FilePath"];
    [dict setValue:_mp3ProcessedFileName forKey:@"mp3ProcessedFileName"];
    return dict;
}

- (id)copyItem{
    return [[WLAudioObject alloc] initWithDictionary:[self toDictionary]];
}

@end
