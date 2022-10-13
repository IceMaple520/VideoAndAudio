//
//  MNVideoPlayer.m
//  GoWindUI
//
//  Created by 王静 on 15/7/28.
//  Copyright (c) 2015年 ZhiLing. All rights reserved.
//

#import "GWPublic.h"
#import "MNVideoPlayer.h"
#import "AppDelegate.h"
@interface MNVideoPlayer(){
    AppDelegate *appDelegate;
}

//还有没有清空的数据导致关视图沙漏，在这里定义一个添加变量
@property(nonatomic,assign) int intervalTime;

@end
@implementation MNVideoPlayer


+(Class)layerClass{
    return [CAGradientLayer class];
}

-(void)initWithMode:(MANNIU_DRAW_MODE)mode isLayer:(BOOL)isLayer{

    m_bNeedData = YES;
    
    UIPinchGestureRecognizer *pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchRecognizer:)];
    [pinchRecognizer setDelegate:self];
    [pinchRecognizer setCancelsTouchesInView:NO];
    [self addGestureRecognizer:pinchRecognizer];
    
    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapRecognizer:)];
    [tapRecognizer setDelegate:self];
    [tapRecognizer setCancelsTouchesInView:NO];
    [tapRecognizer setNumberOfTapsRequired:2];
    [self addGestureRecognizer:tapRecognizer];

    if (mode == MANNIU_DRAW_MODE_SPHERE_CIRCLE)
    {
        self.userInteractionEnabled = YES;
    }
    if (mode == MANNIU_DRAW_MODE_RECTANGLE) {
        self.userInteractionEnabled = NO;
    }

    self.intervalTime = 0;
    
    m_bHD = NO;
    
    appDelegate = [AppDelegate shareAppDelegate];
    if(isLayer && !appDelegate.isBackground)
    {
        m_pEAGLLayerEx = [[AAPLEAGLLayerEx alloc] initWithFrame:CGRectMake(0, 0, 316, 258) drawMode:mode];
        [self.layer addSublayer:m_pEAGLLayerEx];
    }
    m_pMessageLabel = [[UILabel alloc] init];
    [m_pMessageLabel setText:@""];
    [m_pMessageLabel setTextColor:[UIColor whiteColor]];
    [m_pMessageLabel setFont:[UIFont fontWithName:@"Verdana" size:13.0]];
    [m_pMessageLabel.layer setCornerRadius:3.f];
    [m_pMessageLabel setClipsToBounds:YES];
    [m_pMessageLabel setBackgroundColor:[UIColor redColor]];
    
    [self addSubview:m_pMessageLabel];

}


-(void)layoutSubviews{
    [super layoutSubviews];
    
    CGFloat duration = [UIApplication sharedApplication].statusBarOrientationAnimationDuration;
    
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:duration];
    [m_pEAGLLayerEx setFrame:self.bounds];
    [UIView commitAnimations];
    
    [m_pMessageLabel setCenter:self.center];
}

-(void)pause{

}


-(void)stop{

}

#pragma mark - UIGestureRecognizerDelegate
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return ![gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]];
}

-(void)pinchRecognizer:(UIPinchGestureRecognizer *)sender{
    CGFloat fScale = [sender scale];        //1.0 - (mLastScale - [sender scale]);
    
    NSLog(@"+++++++++++++%f\n", fScale);
    
    CGPoint centerPoint;
    
    if ([sender numberOfTouches] == 2){
        CGPoint p1 = [sender locationOfTouch:0 inView:self];
        CGPoint p2 = [sender locationOfTouch:1 inView:self];
        
        centerPoint = CGPointMake((p1.x + p2.x) / 2, (p1.y + p2.y) / 2);
    }
    
    if (m_pEAGLLayerEx != nil){
        // if (m_pEAGLLayerEx->mMode != MANNIU_DRAW_MODE_RECTANGLE){
            m_pEAGLLayerEx->mPinch = YES;
            [m_pEAGLLayerEx onScale:fScale atPosition:centerPoint];
        // }
    }
    
    self.mLastScale = [(UIPinchGestureRecognizer *)sender scale];
}

-(void)tapRecognizer:(UITapGestureRecognizer *)sender{
//    if (m_pEAGLLayerEx != nil){
//        [m_pEAGLLayerEx onTapped];
//    }
}

-(void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    UITouch *touch = [touches anyObject];
    
    CGPoint current = [touch locationInView:self];
    CGPoint previous = [touch previousLocationInView:self];
    
    CGPoint offset = CGPointMake(current.x - previous.x, current.y - previous.y);
    
    NSLog(@"x = %lf, y = %lf\n", offset.x, offset.y);
    
    if (m_pEAGLLayerEx != nil){
        
        
        [m_pEAGLLayerEx onTouchMoved:offset];
    }
}

-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    NSLog(@"touchesBegan");
    
    if (m_pEAGLLayerEx != nil){
        [m_pEAGLLayerEx onTouchBegin];
    }
}

-(void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    NSLog(@"touchesEnded");
    if (m_pEAGLLayerEx != nil){
        [m_pEAGLLayerEx onTouchEnd];
        m_pEAGLLayerEx->mPinch = NO;
    }
}

-(void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    NSLog(@"touchesCancelled");
    
    if (m_pEAGLLayerEx != nil){
        [m_pEAGLLayerEx onTouchEnd];
        m_pEAGLLayerEx->mPinch = NO;
    }
}

-(void)showMessage:(NSString *)msg{
    
    [m_pMessageLabel setText:msg];
    
    [m_pMessageLabel sizeToFit];
    
    CGSize size = [m_pMessageLabel bounds].size;
    
    int x = (self.bounds.size.width - size.width) / 2;
    int y = (self.bounds.size.height - size.height) / 2;
    
    [m_pMessageLabel setFrame:CGRectMake(x, y, size.width, size.height)];
}

-(int)renderYuv420pData:(unsigned char *)pYuvData width:(int)nWidth height:(int)nHeight length:(int)nLength{
    int nRetCode = -1;
    
    int a = self.bounds.size.width;
    a = self.bounds.size.height;
    
    GW_PROCESS_ERROR(pYuvData != NULL);
    self.intervalTime ++;
    
    if (m_pEAGLLayerEx != nil){
        
        [m_pEAGLLayerEx setVideoWidth:nWidth height:nHeight];
        
        nRetCode = [m_pEAGLLayerEx renderYUV420pData:(void *)pYuvData length:nLength];
    }
    
    
Exit0:
    return 0;
}


-(void)uninit{
    
    if(m_pEAGLLayerEx != nil)
    {
        [m_pEAGLLayerEx removeFromSuperlayer];
        [m_pEAGLLayerEx uninit];
        m_pEAGLLayerEx = nil;
    }
}

-(void)BlackScreen
{
    [m_pEAGLLayerEx removeFromSuperlayer];
}

-(void)ResumeScreen:(BOOL)hd
{
    if (hd != m_bHD)
    {
        [self uninit];
        m_bHD = NO;
    }
    if(m_pEAGLLayerEx == nil && !appDelegate.isBackground)
    {
        if (hd)
        {
            m_pEAGLLayerEx = [[AAPLEAGLLayerEx alloc] initWithFrame:CGRectMake(0, 0, 316*2, 258*2) drawMode:m_mode];
        }
        else
        {
            m_pEAGLLayerEx = [[AAPLEAGLLayerEx alloc] initWithFrame:CGRectMake(0, 0, 316, 258) drawMode:m_mode];
        }
        m_bHD = hd;
        [self.layer addSublayer:m_pEAGLLayerEx];
    }
}

@end
