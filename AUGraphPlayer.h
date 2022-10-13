//
//  AUGraphPlayer.h
//  VSSMobile
//
//  Created by lancelet on 2017/7/26.
//  Copyright © 2017年 Fun. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AUGraphPlayer : NSObject

//必须初始化在录音的前面，不然无法录音
-(void) initPlayer:(int)sample;
-(void) uninitPlayer;
-(void) sendData:(const void*)data len:(int)len;

//内部函数
-(void) onInputCallback:(void*)data len:(int)len;

@end
