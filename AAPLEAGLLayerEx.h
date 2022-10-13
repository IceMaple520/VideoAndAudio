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

typedef enum{
    MANNIU_DRAW_MODE_RECTANGLE = 0,         // 画矩形
    MANNIU_DRAW_MODE_SPHERE_CIRCLE,         // 画球面(圆形纹理映射到球面)
    MANNIU_DRAW_MODE_SPHERE_RECTANGLE,      // 画球面(矩形纹理映射到球面)
    
    MANNIU_DRAW_MODE_COUNT,
}MANNIU_DRAW_MODE;

typedef enum{
    ZOOM_NONE,
    
    ZOOM_IN,
    ZOOM_OUT,
    
}SCALE_ANIMATION_TYPE;


@interface AAPLEAGLLayerEx: CAEAGLLayer{
@public
    GLsizei m_videoW;
    GLsizei m_videoH;
    GLsizei m_vertexNum;
    GLsizei mLargeEdge;
    
    ksMatrix4 mModelViewMatrix;
    ksMatrix4 mProjectionMatrix;
    
    GLKVector3 vertexCoords[256];
    GLKVector2 textureCoords[256];
    
    GLfloat mAngleH;                // 水平角度
    GLfloat mAngleV;                // 垂直角度
    
    GLfloat mTranslateZ;
    GLfloat mModeRectangleScale;
    GLfloat mModeRectangleTransX;
    GLfloat mModeRectangleTransY;
    
    CGPoint mRotateOffset;
    
    unsigned char *m_pByYuv420Data;
    //unsigned char *mpExpendYuv420Data;
    
    CADisplayLink *m_pDisplayLink;
    
    MANNIU_DRAW_MODE mMode;
    
    GLuint mBlackTexYId;
    GLuint mBlackTexCbId;
    GLuint mBlackTexCrId;
    
    BOOL mOnTouched;
    BOOL mOrigin;
    BOOL mPinch;
    
    int ANGLE;
@public
    SCALE_ANIMATION_TYPE mScaleType;
    
    // 我们将使用points数组来存放网格各顶点独立的x，y，z坐标。这里网格由45×45点形成，
    // 换句话说也就是由44格×44格的小方格子依次组成了。
    float texture[36][360][2];
    float m_points[36][360][3]; // Points网格顶点数组
}

-(void)uninit;
-(id)initWithFrame:(CGRect)frame drawMode:(MANNIU_DRAW_MODE)mode;
-(int)renderYUV420pData:(void *)pYuv420pData length:(int)nLength;
-(int)setVideoWidth:(int)width height:(int)height;

-(void)onRotateWithOffset:(CGPoint)offset;
-(void)onScale:(CGFloat)scale atPosition:(CGPoint)point;
-(void)onTranslate:(CGPoint)point;
-(void)onScale;
-(void)onTapped;
-(void)onTouchBegin;
-(void)onTouchEnd;
-(void)onTouchMoved:(CGPoint)offset;


@end

#endif //__AAPLEAGLLAYER_EX_H__
