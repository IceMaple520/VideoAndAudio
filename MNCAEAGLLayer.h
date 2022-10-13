/*
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 
 This CAEAGLLayer subclass demonstrates how to draw a CVPixelBufferRef using OpenGLES and display the timecode associated with that pixel buffer in the top right corner.
 
 */

#ifndef __AAPLEAGLLAYER_EX_H__
#define __AAPLEAGLLAYER_EX_H__

#include <GLKit/GLKit.h>
#include <CoreVideo/CoreVideo.h>
#include <QuartzCore/QuartzCore.h>

#include "ksMatrix.h"

#define MAX_RAD_NUM     12
#define MAX_ROTATE_NUM  180

typedef enum{
    MN_DRAW_MODE_RECTANGLE = 0,         // 画矩形
    MN_DRAW_MODE_SPHERE_CIRCLE,         // 画球面(圆形纹理映射到球面)
    MN_DRAW_MODE_SPHERE_RECTANGLE,      // 画球面(矩形纹理映射到球面)
    
    MN_DRAW_MODE_COUNT,
}MN_DRAW_MODE;

typedef enum{
    ZOOM_NONE,
    
    ZOOM_IN,
    ZOOM_OUT,
    
}SCALE_ANIMATION_TYPE;


@interface MNCAEAGLLayer: CAEAGLLayer{
@public
    GLsizei mVideoW;
    GLsizei mVideoH;
    GLsizei mLargeEdge;
    
    ksMatrix4 mModelViewMatrix;
    ksMatrix4 mProjectionMatrix;
    
    GLfloat mAngleH;                // 水平角度
    GLfloat mAngleV;                // 垂直角度
    
    GLfloat mTranslateZ;
    GLfloat mModeRectangleScale;
    GLfloat mModeRectangleTransX;
    GLfloat mModeRectangleTransY;
    
    CGPoint mRotateOffset;
    
    NSLock *mYuvDataLock;           // 用于保证GL绘制时，YUV数据不被修改
    NSLock *mGLCommandCommitLock;   // 用于保证调用pause后不再提交GL 命令
    
    unsigned char *mYuv420Data;
    unsigned char *mLastTimeData;
    unsigned char *mpExpendYuv420Data;
    
    CADisplayLink *mDisplayLink;
    
    
    
    GLuint mBlackTexYId;
    GLuint mBlackTexCbId;
    GLuint mBlackTexCrId;
    
    BOOL mOnTouched;
    BOOL mOrigin;
    BOOL mPinch;
    
    BOOL mPaused;
    
    int ANGLE;
@public
    SCALE_ANIMATION_TYPE mScaleType;
    
    // 我们将使用points数组来存放网格各顶点独立的x，y，z坐标。这里网格由45×45点形成，
    // 换句话说也就是由44格×44格的小方格子依次组成了。
    float texture[MAX_RAD_NUM][MAX_ROTATE_NUM][2];
    float m_points[MAX_RAD_NUM][MAX_ROTATE_NUM][3]; // Points网格顶点数组
}

@property (nonatomic, assign) MN_DRAW_MODE mMode;

-(void)uninit;
-(id)initWithFrame:(CGRect)frame drawMode:(MN_DRAW_MODE)mode;
-(int)renderYuv420pData:(CVPixelBufferRef)pixelBuffer;
-(int)renderYUV420pData:(void *)pYuv420pData length:(int)nLength;
-(int)renderYuv420p:(unsigned char *)y u:(unsigned char *)u v:(unsigned char *)v width:(int)nWidth height:(int)nHeight length:(int)nLength;
-(int)setVideoWidth:(int)width height:(int)height;

-(void)onRotateWithOffset:(CGPoint)offset;
-(void)onScale:(CGFloat)scale atPosition:(CGPoint)point;
-(void)onTranslate:(CGPoint)point;
-(void)onScale;
-(void)onTapped;
-(void)onTouchBegin;
-(void)onTouchEnd;
-(void)onTouchMoved:(CGPoint)offset;
-(void)pause;
-(void)resume;
-(BOOL)isPaused;
-(unsigned char *)getYuv420pData;
-(CVPixelBufferRef)getCVPixelBufferRef;

@end

#endif //__AAPLEAGLLAYER_EX_H__
