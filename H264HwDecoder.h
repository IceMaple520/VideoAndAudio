//
//  H264HwDecoder.h
//  MobileLogic
//
//  Created by ZB on 2018/1/2.
//  Copyright © 2018年 lancelet. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVSampleBufferDisplayLayer.h>
#import "LogicMacro.h"
typedef struct H264_HW_PARAM
{
    int did;
    int channel;
    int streamType;
    VFRAME_INFO *vframe;
    LOGIC_TIME *time;
}HW_PARAM;

@protocol H264HwDecoderImplDelegate <NSObject>

- (void)displayDecodedFrame:(CVImageBufferRef )imageBuffer withParam:(HW_PARAM *)param;

@end
@interface H264HwDecoder : NSObject
@property (weak, nonatomic) id<H264HwDecoderImplDelegate> delegate;
@property (nonatomic,retain) NSLock *m_lock;

-(BOOL)decodeWithData:(NSData *)data width:(int)width hight:(int)hight param:(HW_PARAM *)param;
-(BOOL)isUsedHwDecoder;
-(void)uninit;

@end
