//
//  MNVideoPlayerController.h
//  GoWindUI
//
//  Created by 王静 on 15/7/28.
//  Copyright (c) 2015年 ZhiLing. All rights reserved.
//

#ifndef __MN_VIDEO_PLAYER_H__
#define __MN_VIDEO_PLAYER_H__

#import "AAPLEAGLLayerEx.h"


@interface MNVideoPlayer: UIControl<UIGestureRecognizerDelegate>{
    BOOL m_bHD;
    AAPLEAGLLayerEx *m_pEAGLLayerEx;
    BOOL m_bNeedData;
    BOOL m_bPaused;
    
//    CGFloat mLastScale;
    MANNIU_DRAW_MODE m_mode;
    UILabel *m_pMessageLabel;
    
    
}
@property (nonatomic, assign) CGFloat mLastScale;
@property (nonatomic, assign) BOOL isDraw;
-(void)initWithMode:(MANNIU_DRAW_MODE)mode isLayer:(BOOL)isLayer;
-(void)pause;
-(void)stop;
-(void)uninit;
-(int)renderYuv420pData:(unsigned char *)pYuvData width:(int)nWidth height:(int)nHeight length:(int)nLength;
-(void)showMessage:(NSString *)msg;
-(void)BlackScreen;
-(void)ResumeScreen:(BOOL)hd;

@end

#endif // __MN_VIDEO_PLAYER_H__
