//
//  WLFileManager.m
//  WLAudioCenter
//
//  Created by 王亮 on 13-9-13.
//  Copyright (c) 2013年 王亮. All rights reserved.
//

#import "WLFileManager.h"
#import <CommonCrypto/CommonDigest.h>

#define kWLAudioRecordFilterAndPlayDirectory [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask, YES) objectAtIndex:0]
#define kWLAudioCache          @"video/mmAudioCache"

@implementation WLFileManager

+ (NSString *)getFilePath:(NSString *)subPath
{
    NSString* filepath = [kWLAudioRecordFilterAndPlayDirectory stringByAppendingPathComponent:subPath];
    if (![self createPath:filepath]) {
        return nil;
    }
    
    return filepath;
}

+ (BOOL)createPath:(NSString *)path
{
    BOOL bCreate = true;
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:path])
    {
        bCreate = [fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    return bCreate;
}

+(NSString *) voiceFilePathAtCache:(NSString *) fileName
{
    return [self filePathAtCache:kWLAudioCache filename:fileName bMd5:YES];
    
}

+(NSString *) filePathAtCache:(NSString *) path filename:(NSString *) filename bMd5:(BOOL)bMd5
{
    if (!filename || filename.length == 0) {
        return nil;
    }
    
    if ([filename hasPrefix:@"/"])
        return filename;
    
    NSString* filepath = [self getFilePath:path filename:filename bMd5:bMd5];
    if (![[NSFileManager defaultManager] fileExistsAtPath:filepath]) {
//        return nil;
    }
    return filepath;
}

+(NSString *) getFilePath:(NSString *) path filename:(NSString *) filename bMd5:(BOOL) bMd5
{
    NSString *filepath = kWLAudioRecordFilterAndPlayDirectory;
    
    if (path && path.length > 0) {
        filepath = [filepath stringByAppendingPathComponent:path];
    }
    
    if (filename && filename.length > 0) {
        if (bMd5) {
            filepath = [filepath stringByAppendingPathComponent:[self md5HexDigest:filename]];
        }
        else
        {
            filepath = [filepath stringByAppendingPathComponent:filename];
        }
    }
    
    return filepath;
}

+(BOOL) writeVoiceToCache:(NSData *)data filePath:(NSString *) filePath
{
    return [self writeDataToCache:filePath data:data bMd5:NO];
}

+ (BOOL)writeDataToCache:(NSString *) filePath data:(NSData *) data bMd5:(BOOL)bMd5
{
    if (!filePath || filePath.length == 0 || !data) {
        return false;
    }
    
    NSString *path = nil;
    NSString *filename = [filePath lastPathComponent];
    NSUInteger index = filePath.length - filename.length;
    path = [filePath substringWithRange:NSMakeRange(0, index)];
    
    if (![self createPath:path]) {
        return false;
    }
    
    if (bMd5) {
        path = [path stringByAppendingPathComponent:[self md5HexDigest:filename]];
    }
    else
    {
        path = filePath;
    }
    
    return [data writeToFile:path atomically:YES];
}



+ (BOOL)deleteVoiceWithFilePath:(NSString *) filePath
{
    return [self deleteFileFromCache:filePath bMd5:NO];
}

+ (BOOL) deleteFileFromCache:(NSString *) filePath bMd5:(BOOL)bMd5
{
    if (!filePath || filePath.length == 0) {
        return false;
    }
    
    NSString *path = nil;
    if (bMd5) {
        path = [self dealFilePath:filePath];
    }
    else
    {
        path = filePath;
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    return [fileManager removeItemAtPath:path error:nil];
}

+ (NSString *) dealFilePath:(NSString *)filePath
{
    NSString* filename = [filePath lastPathComponent];
    NSUInteger index = filePath.length - filename.length;
    NSString* path = [filePath substringWithRange:NSMakeRange(0, index)];
    return [path stringByAppendingPathComponent:[self md5HexDigest:filename]];
}

+ (BOOL)voicefileExistatLocalWithPath:(NSString *)filePath
{
    return [self fileExistAtCache:filePath bMd5:false];
}

+ (BOOL)fileExistAtCache:(NSString *)filePath bMd5:(BOOL)bMd5
{
    if (!filePath || filePath.length == 0) {
        return false;
    }
    
    NSString *path = nil;
    if (bMd5) {
        path = [self dealFilePath:filePath];
    }
    else
    {
        path = filePath;
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    return [fileManager fileExistsAtPath:path];
}

#pragma mark - MD5
+ (NSString *)md5HexDigest:(NSString *)input
{
    const char* str = [input UTF8String];
	unsigned char result[CC_MD5_DIGEST_LENGTH];
	CC_MD5(str, strlen(str), result);
    NSMutableString *returnHashSum = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH*2];
    for (int i=0; i<CC_MD5_DIGEST_LENGTH; i++) {
        [returnHashSum appendFormat:@"%02x", result[i]];
    }
	return returnHashSum;
}
@end
