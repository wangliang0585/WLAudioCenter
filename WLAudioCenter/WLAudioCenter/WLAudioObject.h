//
//  WLAudioObject.h
//  WLAudioCenter
//
//  Created by 王亮 on 13-9-11.
//  Copyright (c) 2013年 王亮. All rights reserved.
//

#import <Foundation/Foundation.h>

#define kWLDOC_CAF  @"caf"
#define kWLDOC_MP3   @"mp3"

@interface WLAudioObject : NSObject
@property (nonatomic, copy) NSString * sourceURL;                      //音频的url地址
@property (nonatomic, assign) NSTimeInterval duration;                 //音频的总长度，单位是秒
@property (nonatomic, assign) NSTimeInterval createTime;               //音频的创建时间
@property (nonatomic, copy) NSString * recordingFileName;              //音频录制结束存储文件的名称
@property (nonatomic, copy) NSString * mp3ProcessedFileName;           //音频成功经过mp3转换后储文件的名称
@property (nonatomic, strong) NSString *cafFilePath;                    // caf 文件目录
@property (nonatomic, strong) NSString *mp3FilePath;                    // mp3 文件目录

- (id)initAudioWithURL:(NSString *)URL;      //通过给定的URL地址，生成一个RVAudioObject对象
@end
