//
//  ViewController.m
//  WLAudioExample
//
//  Created by 王亮 on 13-9-11.
//  Copyright (c) 2013年 王亮. All rights reserved.
//

#import "ViewController.h"
#import "WLAudioCenter.h"
#import "WLAudioCenterProcotols.h"
@interface ViewController ()<WLAudioCenterPlayerDelegate>

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)play:(id)sender {
    [[WLAudioCenter shareInstance] playSingleAudioWithURL:@"http://xx.ting30.com/2012/%E5%90%AC%E4%B8%89%E9%9B%B6%E9%9F%B3%E4%B9%90%E7%BD%911%E6%9C%88%E5%A5%BD%E6%AD%8C%E6%8E%A8%E5%B9%BF/%E9%A2%84%E8%B0%8B-%E8%AE%B8%E4%BD%B3%E6%85%A7.mp3" delegate:self];
}

- (void)didStartPlayingAudio:(WLAudioObject *)audio
{
    NSLog(@"start");
}
- (void)didPausePlayingAudio:(WLAudioObject *)audio
{
    NSLog(@"pause");
}
- (void)didStartBufferingAudio:(WLAudioObject *)audio
{
    NSLog(@"buffering");
}
- (void)didReStartPlayingAudio:(WLAudioObject *)audio
{
    
}
- (void)didFinishedPlaying
{
    NSLog(@"finish");
}
- (void)didTimeElapsed:(NSTimeInterval)timeElapsed playingAudio:(WLAudioObject *)audio
{
    NSLog(@"%f",timeElapsed);
}
- (void)didFailedPlayingAudio:(WLAudioObject *)audio withError:(NSError *)error
{
    NSLog(@"error:%@",[error description]);
}
@end
