//
//  WLAudioConfig.h
//  WLAudioCenter
//
//  Created by 王亮 on 13-9-11.
//  Copyright (c) 2013年 王亮. All rights reserved.
//

#ifndef WLAudioCenter_WLAudioCenterConfig_h
#define WLAudioCenter_WLAudioCenterConfig_h

#define kWLTmpMp3Ex  @"tmp"
#define kWLFilePrefix @"Test"

#define kWLAudioQueueBufs  3

#define kWLMaxRecoderTime 60.0*1000.f

#define Debug 1
#if Debug
#define WLLog(format,...) printf("[AudioCenterDebug]: %s\n", [[NSString stringWithFormat:format,## __VA_ARGS__] UTF8String])
#else
#define WLLog(format,...)
#endif


#endif
