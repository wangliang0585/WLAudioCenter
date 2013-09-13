//
//  WLFileManager.h
//  WLAudioCenter
//
//  Created by 王亮 on 13-9-13.
//  Copyright (c) 2013年 王亮. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface WLFileManager : NSObject
+ (NSString *)getFilePath:(NSString *)subPath;
+ (NSString *)voiceFilePathAtCache:(NSString *)fileName;
+ (BOOL)writeVoiceToCache:(NSData *)data filePath:(NSString *)filePath;
+ (BOOL)deleteVoiceWithFilePath:(NSString *)filePath;
+ (BOOL)voicefileExistatLocalWithPath:(NSString *)filePath;
+ (NSString *)md5HexDigest:(NSString *)input;
@end
