  

/*
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 
 This CAEAGLLayer subclass demonstrates how to draw a CVPixelBufferRef using OpenGLES and display the timecode associated with that pixel buffer in the top right corner.
 
 */

#import <OpenGLES/EAGL.h>
#import <mach/mach_time.h>
#import <UIKit/UIScreen.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <AVFoundation/AVUtilities.h>
#import <AVFoundation/AVFoundation.h>

#import "GWPublic.h"
#import "AAPLEAGLLayerEx.h"
#import "AppDelegate.h"

// Uniform index.
enum
{
    UNIFORM_Y,
    UNIFORM_U,
    UNIFORM_V,
    
    UNIFORM_MODELVIEW,
    UNIFORM_PROJECTION,
    
    UNIFORM_ROTATION_ANGLE,
    UNIFORM_COLOR_CONVERSION_MATRIX,
    
    UNIFORM_CLIP_PLANE,
    NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];

// Attribute index.
enum
{
    ATTRIB_VERTEX,
    ATTRIB_TEXCOORD,
    NUM_ATTRIBUTES
};

//按照720P分辨率标定结果，我们相机目前的参数是：
//HC=454;WC=630.6
//a0=381.5958
//a2=-0.0011
//a3=8.7080e-7
//a4=-1.8838e-9

//1080P的参数：xc=680.64；yc=946；
//a0=567.4797
//a2=-7.1035e-4
//a3=3.4579e-7
//a4=-5.1822e-10


//float Image_H=1080.f;
//float Image_W=1920.f;
//float HC=680.64;
//float WC=946;
//double a0=567.4797;
//double a2=-7.1035e-4;
//double a3=3.4579e-7;
//double a4=-5.1822e-10;
//double W_div=Image_W/44.0f;
//double H_div=Image_H/44.0f;

float Image_H=1080.0f;//图像高度（pixels）
float Image_W=1920.0f;//图像宽度（pixels）
float HC=680.64f;//畸变中心的H方向坐标，左上角为原点（pixels）
float WC=946.0f;//畸变中心的W方向坐标，左上角为原点（pixels）
double a0=567.4797f;//多项式0次项系数
double a2=-7.1035e-4;//多项式2次项系数
double a3=3.4579e-7;//多项式3次项系数
double a4=-5.1822e-10;//多项式4次项系数
double W_div=Image_W/72.0f;//纹理坐标与图像像素坐标转换系数
double H_div=Image_H/72.0f;//纹理坐标与图像像素坐标转换系数


@interface AAPLEAGLLayerEx(){
    EAGLContext *m_pContext;
    
    GLuint m_textureY;
    GLuint m_textureU;
    GLuint m_textureV;
    
    GLint m_nBackingWidth;
    GLint m_nBackingHeight;
    
    GLuint m_uFrameBufferHandle;
    GLuint m_uColorBufferHandle;
    
    GLfloat mAngle;
    MANNIU_DRAW_MODE mDrawMode;
    NSLock *mLock;
    AppDelegate *appDelegate;
}
@property GLuint program;

@end

@implementation AAPLEAGLLayerEx

-(instancetype)initWithFrame:(CGRect)frame drawMode:(MANNIU_DRAW_MODE)mode{
    self = [super init];
    if (self) {
        CGFloat scale = [[UIScreen mainScreen] scale];
        self.contentsScale = scale;
        self.opaque = TRUE;
        self.drawableProperties = @{kEAGLDrawablePropertyRetainedBacking:[NSNumber numberWithBool:YES]};
        
        [self setFrame:frame];
        
        m_pContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        GW_PROCESS_ERROR(m_pContext != nil);
        
        mMode = mode;
        appDelegate = [AppDelegate shareAppDelegate];
        [self setupGL:mode];
        
        [self initalizeGL];
        
        m_pDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(draw)];
        [m_pDisplayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        
        [m_pDisplayLink setFrameInterval:3];    // CADisplayLink 默认每秒运行60次，将它的frameInterval属性设置为2，意味CADisplayLink每隔一帧运行一次，有效的使游戏逻辑每秒运行30次
        [m_pDisplayLink setPaused:YES];
        
        m_pByYuv420Data = NULL;
        
        m_videoW = 0;
        m_videoH = 0;
        
        mBlackTexYId  = 0;
        mBlackTexCrId = 0;
        mBlackTexCbId = 0;
        
        mOrigin = YES;
        
        mModeRectangleScale = 1.0;
        
        mModeRectangleTransX = 0.0;
        mModeRectangleTransY = 0.0;
        
        ANGLE = 80;
        
        mLock = [[NSLock alloc] init];
    }
    
Exit0:
    
    return self;
}

-(void)initalizeGL{
    for(int rad = 0; rad < 36; rad++)                                   // 径向量
    {
        // 径向由内到外
        for(int rotate=0; rotate<36; rotate++)                          // 旋转量
        {
            float theta=float(rotate)*10.0f*3.141592654f*2.0f/360.0f;   // 弧度值
            float r_pixel=float(rad+1)*0.97*Image_W/(2*36.0f);          // 注意：rad+1。径向值，像素为单位，Image_W后期调试可以更改其值，改变的是纹理区域的范围
            
            /*****************构建球面向量*****************/
            float X_pixel=r_pixel*sin(theta);                           // X方向值，像素为单位//围绕坐标轴顺时针转动
            float Y_pixel=r_pixel*cos(theta);                           // Y方向值，像素为单位
            float Z_pixel=a0+a2*r_pixel*r_pixel+a3*r_pixel*r_pixel*r_pixel+a4*r_pixel*r_pixel*r_pixel*r_pixel;//Z方向值，像素为单位
            float R_pixel=sqrt(X_pixel*X_pixel+Y_pixel*Y_pixel+Z_pixel*Z_pixel);//三维向量的模
            float X_sphere=X_pixel/R_pixel;                             // 归一化
            float Y_sphere=Y_pixel/R_pixel;                             // 归一化
            float Z_sphere=Z_pixel/R_pixel;                             // 归一化
            
            /*****************根据畸变中心就对应上述球面顶点的纹理坐标*****************/
            float x_texture=(WC+X_pixel)/Image_W;                       // 纹理坐标（0,1），原点在左下角
            float y_texture=(HC-Y_pixel)/Image_H;                       // 方向纹理坐标（0,1），原点在左下角
            m_points[rad][rotate][0]=X_sphere;                          // 三维数组存储三维向量
            m_points[rad][rotate][1]=Y_sphere;
            m_points[rad][rotate][2]=-Z_sphere;
            
            texture[rad][rotate][0]=x_texture;                          // 三维数组存储与此相对应的纹理坐标
            texture[rad][rotate][1]=y_texture;
        }
    }
}

-(void)paintGL{
    for (int rad = 0; rad < 36; rad++)                  // 径向量
    {
        // Y平面循环
        for (int rotate = 0; rotate < 36; rotate++)     // 旋转量
        {
            if(rad == 0)
            {
                if(rotate == 35)
                {
                    GLfloat texCoords[] = {
                        WC/Image_W, HC/Image_H,
                        texture[rad][rotate][0], texture[rad][rotate][1],
                        texture[rad][0][0], texture[rad][0][1],
                    };
                    
                    GLfloat VertexCoords[] = {
                        0, 0, -1,
                        m_points[rad][rotate][0],m_points[rad][rotate][1],m_points[rad][rotate][2],
                        m_points[rad][0][0],m_points[rad][0][1],m_points[rad][0][2],
                    };
                    
                    glVertexAttribPointer(ATTRIB_VERTEX, 3, GL_FLOAT, 0, 0, VertexCoords);
                    glEnableVertexAttribArray(ATTRIB_VERTEX);
                    
                    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, texCoords);
                    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
                    
                    glDrawArrays(GL_TRIANGLES, 0, 3);
                }
                else
                {
                    GLfloat texCoords[] = {
                        WC/Image_W, HC/Image_H,
                        texture[rad][rotate][0], texture[rad][rotate][1],
                        texture[rad][rotate+1][0], texture[rad][rotate+1][1],
                    };
                    
                    GLfloat VertexCoords[] = {
                        0, 0, -1,
                        m_points[rad][rotate][0],m_points[rad][rotate][1],m_points[rad][rotate][2],
                        m_points[rad][rotate+1][0],m_points[rad][rotate+1][1],m_points[rad][rotate+1][2],
                    };
                    
                    glVertexAttribPointer(ATTRIB_VERTEX, 3, GL_FLOAT, 0, 0, VertexCoords);
                    glEnableVertexAttribArray(ATTRIB_VERTEX);
                    
                    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, texCoords);
                    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
                    
                    glDrawArrays(GL_TRIANGLES, 0, 3);
                }
            }
            else
            {
                if(rotate==35)
                {
                    GLfloat texCoords[] = {
                        texture[rad-1][rotate][0], texture[rad-1][rotate][1],
                        texture[rad][rotate][0], texture[rad][rotate][1],
                        texture[rad][0][0], texture[rad][0][1],
                    };
                    
                    GLfloat VertexCoords[] = {
                        m_points[rad-1][rotate][0],m_points[rad-1][rotate][1],m_points[rad-1][rotate][2],
                        m_points[rad][rotate][0],m_points[rad][rotate][1],m_points[rad][rotate][2],
                        m_points[rad][0][0],m_points[rad][0][1],m_points[rad][0][2],
                    };
                    
                    glVertexAttribPointer(ATTRIB_VERTEX, 3, GL_FLOAT, 0, 0, VertexCoords);
                    glEnableVertexAttribArray(ATTRIB_VERTEX);
                    
                    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, texCoords);
                    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
                    
                    glDrawArrays(GL_TRIANGLES, 0, 3);
                    
                    
                    GLfloat texCoords2[] = {
                        texture[rad-1][rotate][0], texture[rad-1][rotate][1],
                        texture[rad][0][0], texture[rad][0][1],
                        texture[rad-1][0][0], texture[rad-1][0][1],
                    };
                    
                    GLfloat VertexCoords2[] = {
                        m_points[rad-1][rotate][0],m_points[rad-1][rotate][1],m_points[rad-1][rotate][2],
                        m_points[rad][0][0],m_points[rad][0][1],m_points[rad][0][2],
                        m_points[rad-1][0][0],m_points[rad-1][0][1],m_points[rad-1][0][2],
                    };
                    
                    glVertexAttribPointer(ATTRIB_VERTEX, 3, GL_FLOAT, 0, 0, VertexCoords2);
                    glEnableVertexAttribArray(ATTRIB_VERTEX);
                    
                    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, texCoords2);
                    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
                    
                    glDrawArrays(GL_TRIANGLES, 0, 3);
                }
                else
                {
                    GLfloat texCoords[] = {
                        texture[rad-1][rotate][0], texture[rad-1][rotate][1],
                        texture[rad][rotate][0], texture[rad][rotate][1],
                        texture[rad][rotate+1][0], texture[rad][rotate+1][1],
                    };
                    
                    GLfloat VertexCoords[] = {
                        m_points[rad-1][rotate][0],m_points[rad-1][rotate][1],m_points[rad-1][rotate][2],
                        m_points[rad][rotate][0],m_points[rad][rotate][1],m_points[rad][rotate][2],
                        m_points[rad][rotate+1][0],m_points[rad][rotate+1][1],m_points[rad][rotate+1][2],
                    };
                    
                    glVertexAttribPointer(ATTRIB_VERTEX, 3, GL_FLOAT, 0, 0, VertexCoords);
                    glEnableVertexAttribArray(ATTRIB_VERTEX);
                    
                    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, texCoords);
                    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
                    
                    glDrawArrays(GL_TRIANGLES, 0, 3);
                    
                    
                    GLfloat texCoords2[] = {
                        texture[rad-1][rotate][0], texture[rad-1][rotate][1],
                        texture[rad][rotate+1][0], texture[rad][rotate+1][1],
                        texture[rad-1][rotate+1][0], texture[rad-1][rotate+1][1],
                    };
                    
                    GLfloat VertexCoords2[] = {
                        m_points[rad-1][rotate][0],m_points[rad-1][rotate][1],m_points[rad-1][rotate][2],
                        m_points[rad][rotate+1][0],m_points[rad][rotate+1][1],m_points[rad][rotate+1][2],
                        m_points[rad-1][rotate+1][0],m_points[rad-1][rotate+1][1],m_points[rad-1][rotate+1][2],
                    };
                    
                    glVertexAttribPointer(ATTRIB_VERTEX, 3, GL_FLOAT, 0, 0, VertexCoords2);
                    glEnableVertexAttribArray(ATTRIB_VERTEX);
                    
                    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, texCoords2);
                    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
                    
                    glDrawArrays(GL_TRIANGLES, 0, 3);
                    
                }
            }
        }
    }
    
    // 四边形绘制结束
    //上面几行使用glTexCoord2f()和glVertex3f()载入数据。提醒一点：四边形是逆时针绘制的。
    //这就是说，您开始所见到的表面是背面。后表面完全填充了，前表面由线条组成。
    //如果您按顺时针顺序绘制的话，您初始时见到的可能是前表面。也就是说您将看到网格型的纹理效果而不是完全填充的。
}

-(void)draw{
    if(m_pByYuv420Data == NULL || appDelegate.isBackground)
    {
        return;
    }

    [self onScale];
    
    [self modeSphereCircleAdjustAngle];
    
    [self modeRectangleAdjustTrans];
    
    if (!mOnTouched){
        if (mMode == MANNIU_DRAW_MODE_SPHERE_CIRCLE){
            if (mOrigin){
                if (fabs(mTranslateZ - -1.2) > 0.000001){
                    mTranslateZ = -1.2;
                }
            }
        }else if (mMode == MANNIU_DRAW_MODE_RECTANGLE){
            if (mModeRectangleScale < 1.0){
                mModeRectangleTransX = 0;
                mModeRectangleTransY = 0;
                
                [self onScale:1.01 atPosition:CGPointMake(0, 0)];
            }
            
            
        }
        
        
        
//        if (mTranslateZ >= 2.0){
//            [self onScale:0.98 atPosition:CGPointMake(0, 0)];
//        }
//        
//        if (mMode == MANNIU_DRAW_MODE_RECTANGLE){
//            if (mTranslateZ+1.01*0.02 <= 0.15){
//                [self onScale:1.01 atPosition:CGPointMake(0, 0)];
//            }
//        }else{
////            if (mTranslateZ+1.01*0.02 <= 0.0){
////                [self onScale:1.01 atPosition:CGPointMake(0, 0)];
////            }
//        }
//        
//        if (mAngleH >= 50.f){
//            ksMatrixLoadIdentity(&mModelViewMatrix);
//            
//            mAngleH = 50.f;
//            mAngleV = 0;
//            ksMatrixTranslate(&mModelViewMatrix, 0, 0, -1.2f);
//            ksMatrixTranslate(&mModelViewMatrix, 0, 0, mTranslateZ);
//            ksMatrixRotate(&mModelViewMatrix, 50.f, 0, 1.0, 0);
//            
//            //[self onRotateWithOffset:CGPointMake(-(mAngleH - 50), 0)];
//        }else if (mAngleH <= -50.f){
//            ksMatrixLoadIdentity(&mModelViewMatrix);
//            
//            mAngleH = 0;
//            mAngleV = 0;
//            ksMatrixTranslate(&mModelViewMatrix, 0, 0, -1.2f);
//            ksMatrixTranslate(&mModelViewMatrix, 0, 0, mTranslateZ);
//            ksMatrixRotate(&mModelViewMatrix, -50.f, 0, 1.0, 0);
//            
//            
//            
//            //[self onRotateWithOffset:CGPointMake((-mAngleH - 50), 0)];
//        }
//        
//        if (mAngleV >= 12.f){
//            [self onRotateWithOffset:CGPointMake(0, -(mAngleV - 12))];
//        }else if (mAngleV <= 0.f){
//            [self onRotateWithOffset:CGPointMake(0, -mAngleV)];
//        }
    }
    
    
    GW_PROCESS_ERROR(YES == [EAGLContext setCurrentContext:m_pContext]);
    
    [mLock lock];
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, m_textureY);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RED_EXT, m_videoW, m_videoH, 0, GL_RED_EXT, GL_UNSIGNED_BYTE, m_pByYuv420Data);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, m_textureU);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RED_EXT, m_videoW / 2, m_videoH / 2, 0, GL_RED_EXT, GL_UNSIGNED_BYTE, (char *)m_pByYuv420Data + m_videoW * m_videoH);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glActiveTexture(GL_TEXTURE2);
    glBindTexture(GL_TEXTURE_2D, m_textureV);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RED_EXT, m_videoW / 2, m_videoH / 2, 0, GL_RED_EXT, GL_UNSIGNED_BYTE, (char *)m_pByYuv420Data + m_videoW * m_videoH * 5 / 4);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    [mLock unlock];
    
    glViewport(0, 0, m_nBackingWidth, m_nBackingHeight);
    glClearColor(0.0, 0.0, 0.0, 1.0);
    
    // 方向横屏
    static const GLfloat rectCoords[] = {
        -1, -1, 0.0,
        1, -1, 0.0,
        -1, 1, 0.0,
        1, 1, 0.0,
    };
    
    static const GLfloat texCoords[] = {
        0.0f, 1.0f,
        1.0f, 1.0f,
        0.0f,  0.0f,
        1.0f,  0.0f,
    };
    
    glClear(GL_COLOR_BUFFER_BIT);
    glUseProgram(self.program);
    
    
    glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEW], 1, GL_FALSE, (GLfloat*)&mModelViewMatrix.m[0][0]);
    
    glUniform1i(uniforms[UNIFORM_Y], 0);
    glUniform1i(uniforms[UNIFORM_U], 1);
    glUniform1i(uniforms[UNIFORM_V], 2);
    
    
    if (mMode == MANNIU_DRAW_MODE_RECTANGLE)            // 平面矩形
    {
        glVertexAttribPointer(ATTRIB_VERTEX, 3, GL_FLOAT, 0, 0, rectCoords);
        glEnableVertexAttribArray(ATTRIB_VERTEX);
        
        glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, texCoords);
        glEnableVertexAttribArray(ATTRIB_TEXCOORD);
        
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    }
    else if (mMode == MANNIU_DRAW_MODE_SPHERE_CIRCLE)   // 圆形映射到球面
    {
        if (mOrigin){
            
            ksMatrixLoadIdentity(&mModelViewMatrix);
            ksMatrixTranslate(&mModelViewMatrix, 0, 0, mTranslateZ);
            
            ksMatrixLoadIdentity(&mProjectionMatrix);
            ksPerspective(&mProjectionMatrix, 80.0, 1.0, 0.1f, 80.0f);
            glUniformMatrix4fv(uniforms[UNIFORM_PROJECTION], 1, GL_FALSE, (GLfloat*)&mProjectionMatrix.m[0][0]);
            
            glVertexAttribPointer(ATTRIB_VERTEX, 3, GL_FLOAT, 0, 0, rectCoords);
            glEnableVertexAttribArray(ATTRIB_VERTEX);
            
            glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, texCoords);
            glEnableVertexAttribArray(ATTRIB_TEXCOORD);
            
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        }else{
            ksMatrixLoadIdentity(&mProjectionMatrix);
            ksPerspective(&mProjectionMatrix, ANGLE, 1.40, 0.1f, 80.0f);     // TODO: 1.4??
            glUniformMatrix4fv(uniforms[UNIFORM_PROJECTION], 1, GL_FALSE, (GLfloat*)&mProjectionMatrix.m[0][0]);
            
            ksMatrixLoadIdentity(&mModelViewMatrix);
            ksMatrixTranslate(&mModelViewMatrix, 0, 0, mTranslateZ);
            ksMatrixRotate(&mModelViewMatrix, mAngleV, 1, 0, 0);
            ksMatrixRotate(&mModelViewMatrix, mAngleH, 0, 1, 0);
            
            glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEW], 1, GL_FALSE, (GLfloat*)&mModelViewMatrix.m[0][0]);
            
            [self paintGL];
        }
    }
    if ([EAGLContext currentContext] == m_pContext) {
        [m_pContext presentRenderbuffer:GL_RENDERBUFFER];
    }
    
    glFlush();

Exit0:
    return ;
}

-(void)onTouchBegin{
    mOnTouched = YES;
    mRotateOffset = CGPointMake(0, 0);
}

-(void)onTouchEnd{
    mOnTouched = NO;
}

-(void)uninit{
    if (!m_pContext || ![EAGLContext setCurrentContext:m_pContext]) {
        return;
    }
    
    [self cleanUpTextures];
    
    if (self.program) {
        glDeleteProgram(self.program);
        self.program = 0;
    }
    if(m_pContext) {
        m_pContext = nil;
    }
    
    [m_pDisplayLink setPaused:YES];
    NSString* version = [[UIDevice currentDevice] systemVersion];
    if ([version isEqualToString:@"8.3"])
    {
        //解决IOS 8.3 版本实时预览退出崩溃，对8.3版本做特殊处理
        //[m_pDisplayLink removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        //[m_pDisplayLink invalidate];
    }
    else
    {
        [m_pDisplayLink invalidate];
    }
    m_pDisplayLink = nil;
    
    
    GW_DELETE_ARRAY(m_pByYuv420Data);
    //GW_DELETE_ARRAY(mpExpendYuv420Data);
}

-(void)setupBuffers{
    glEnable(GL_DEPTH_TEST);
    
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
    
    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
    
    glGenFramebuffers(1, &m_uFrameBufferHandle);
    glBindFramebuffer(GL_FRAMEBUFFER, m_uFrameBufferHandle);
    
    glGenRenderbuffers(1, &m_uColorBufferHandle);
    glBindRenderbuffer(GL_RENDERBUFFER, m_uColorBufferHandle);
    
    [m_pContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:self];
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &m_nBackingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &m_nBackingHeight);
    
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, m_uColorBufferHandle);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
    }
}

-(void)setupGL:(MANNIU_DRAW_MODE)mode{
    
    GW_PROCESS_ERROR(m_pContext != nil);
    GW_PROCESS_ERROR([EAGLContext setCurrentContext:m_pContext]);
    
    [self setupBuffers];
    [self loadShaders];
    
    glUseProgram(self.program);
    
    ksMatrixLoadIdentity(&mProjectionMatrix);
    
    if (mode == MANNIU_DRAW_MODE_RECTANGLE){
        ksPerspective(&mProjectionMatrix, 80.0, 1.0, 0.1f, 40.0f);
    }else{
        ksPerspective(&mProjectionMatrix, 80.0, 1.40, 0.1f, 40.0f);     // TODO: 1.4??
    }
    glUniformMatrix4fv(uniforms[UNIFORM_PROJECTION], 1, GL_FALSE, (GLfloat*)&mProjectionMatrix.m[0][0]);
    

    ksMatrixLoadIdentity(&mModelViewMatrix);
    if (mode == MANNIU_DRAW_MODE_RECTANGLE){
        mTranslateZ = -1.2;
        ksMatrixTranslate(&mModelViewMatrix, 0, 0, mTranslateZ);
    }else{
        mTranslateZ = -1.2;
        
        ksMatrixTranslate(&mModelViewMatrix, 0, 0, mTranslateZ);
    }
    
    glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEW], 1, GL_FALSE, (GLfloat*)&mModelViewMatrix.m[0][0]);
    
    
    glGenTextures(1, &m_textureY);
    glGenTextures(1, &m_textureU);
    glGenTextures(1, &m_textureV);
    
Exit0:
    return ;
}

-(void)modeRectangleAdjustTrans{
    if (mOnTouched) return ;
    
    
    mModeRectangleTransX = mModeRectangleTransX > 160 ? 160 : mModeRectangleTransX;
    mModeRectangleTransY = mModeRectangleTransY > 160 ? 160 : mModeRectangleTransY;
    
    mModeRectangleTransX = mModeRectangleTransX < -160 ? -160 : mModeRectangleTransX;
    mModeRectangleTransY = mModeRectangleTransY < -160 ? -160 : mModeRectangleTransY;
    
    ksMatrixLoadIdentity(&mModelViewMatrix);
    ksMatrixScale(&mModelViewMatrix, mModeRectangleScale, mModeRectangleScale, 1.0);
    
    ksMatrixTranslate(&mModelViewMatrix, mModeRectangleTransX / 200, mModeRectangleTransY / 200, mTranslateZ);
    
    ksMatrixRotate(&mModelViewMatrix, mAngleH, 0, 1.0, 0);
    ksMatrixRotate(&mModelViewMatrix, mAngleV, 1.0, 0, 0);
}

-(void)modeSphereCircleAdjustAngle{
    if (MANNIU_DRAW_MODE_SPHERE_CIRCLE){
        if (!mOrigin){
            if (!mOnTouched){
                
                static GLfloat table[][9] = {
                    //       左              右                  上              下
//                    {0.2,    56,     80,     -60,    -88,       45,     30,     -15,     -18},
//                    {0.4,    65,     90,     -72,    -80,       38,     50,     -6,     -18},
//                    {0.6,    77,     92,     -60,    -80,       25,     30,     -6,     -18},
//                    {0.8,    87,     96,     -60,    -80,       25,     30,     -6,     -18},
//                    {1.0,    87,     96,     -60,    -80,       25,     30,     -6,     -18},
                    
                    
//                    {0.36,    67,     80,     -68,    -88,       25,     30,     -6,     -18},
//                    {0.36,    67,     80,     -60,    -88,       25,     30,     -6,     -18},
//                    {0.36,    67,     80,     -60,    -88,       25,     30,     -6,     -18},
                    
                    
                    {17,     86,     90,     -85,    -80,       61,     50,     -31,     -18},
                    {21,     56,     80,     -60,    -88,       45,     30,     -15,     -18},
                    {42,     72,     80,     -70,    -88,       50,     30,     -20,     -18},
                    {54,     65,     92,     -62,    -80,       50,     30,     -16,     -18},
                    {80,     53,     96,     -52,    -80,       36,     30,     -6,     -18},
                    
                    
                    
                };
                
                
                
                
                for (int i = 0; i < 5; i++){
                    if (ANGLE <= table[i][0]){
                        if (mAngleH > table[i][1]){
                            mAngleH = table[i][1];
                            
                            ksMatrixLoadIdentity(&mModelViewMatrix);
                            
                            ksMatrixTranslate(&mModelViewMatrix, 0, 0, mTranslateZ);
                            
                            ksMatrixRotate(&mModelViewMatrix, mAngleH, 0, 1.0, 0);
                            ksMatrixRotate(&mModelViewMatrix, mAngleV, 1.0, 0, 0);
                        }
                        
                        if (mAngleH < table[i][3]){
                            mAngleH = table[i][3];
                            
                            ksMatrixLoadIdentity(&mModelViewMatrix);
                            
                            ksMatrixTranslate(&mModelViewMatrix, 0, 0, mTranslateZ);
                            
                            ksMatrixRotate(&mModelViewMatrix, mAngleH, 0, 1.0, 0);
                            ksMatrixRotate(&mModelViewMatrix, mAngleV, 1.0, 0, 0);
                        }
                        
                        if (mAngleV > table[i][5]){
                            mAngleV = table[i][5];
                            
                            ksMatrixLoadIdentity(&mModelViewMatrix);
                            
                            ksMatrixTranslate(&mModelViewMatrix, 0, 0, mTranslateZ);
                            
                            ksMatrixRotate(&mModelViewMatrix, mAngleH, 0, 1.0, 0);
                            ksMatrixRotate(&mModelViewMatrix, mAngleV, 1.0, 0, 0);
                        }
                        
                        if (mAngleV < table[i][7]){
                            mAngleV = table[i][7];
                            
                            ksMatrixLoadIdentity(&mModelViewMatrix);
                            
                            ksMatrixTranslate(&mModelViewMatrix, 0, 0, mTranslateZ);
                            
                            ksMatrixRotate(&mModelViewMatrix, mAngleH, 0, 1.0, 0);
                            ksMatrixRotate(&mModelViewMatrix, mAngleV, 1.0, 0, 0);
                        }
                        
                        break;
                    }
                }
                
            }
        }
    }
}

-(void)onTouchMoved:(CGPoint)offset{
    if (mMode == MANNIU_DRAW_MODE_SPHERE_CIRCLE){
        [self onRotateWithOffset:offset];
    }else if (mMode == MANNIU_DRAW_MODE_RECTANGLE){
        [self onTranslate:offset];
        
        
        
    }
}

-(void)onRotateWithOffset:(CGPoint)offset{
    mRotateOffset = offset;
    
    if (mMode == MANNIU_DRAW_MODE_RECTANGLE)
        return ;
    
    if (mPinch) return ;
    
    if (mMode == MANNIU_DRAW_MODE_SPHERE_CIRCLE){
        if (mOrigin){
            return ;
        }else{
            GLfloat angle = mAngleH + (mRotateOffset.x * 0.25);
            
            if (mTranslateZ >= 1.16){
                ksMatrixRotate(&mModelViewMatrix, (offset.x * 0.25), 0, 1.0, 0);
                mAngleH += (offset.x * 0.25);
            }else{
//                if (angle >= 200.f || angle <= -200.f){
//                    mRotateOffset.x = 0;
//                }else{
                    ksMatrixRotate(&mModelViewMatrix, (offset.x * 0.25), 0, 1.0, 0);
                    mAngleH += (offset.x * 0.25);
//                }
            }
            
            angle = mAngleV + (offset.y * 0.25);
            
            
            ksMatrixTranslate(&mModelViewMatrix, 0, 0, 1.0);
            ksMatrixRotate(&mModelViewMatrix, (offset.y * 0.25), 1.0, 0, 0);
            ksMatrixTranslate(&mModelViewMatrix, 0, 0, -1.0);
            mAngleV += (offset.y * 0.25);
        }
    }
}

-(void)wheelEvent:(GLfloat)angle{
    if (angle > 0 && ANGLE < 170 && ANGLE > 17)
        ANGLE -= ANGLE / 20.0f;
    else if(angle < 0 && ANGLE > 3){
        ANGLE += ANGLE / 15.0f;
    }
    
    if(ANGLE < 80){
        mTranslateZ = 0;
    }
    else
        mTranslateZ = (80.0f - ANGLE) / 50.0f;
    
    ksPerspective(&mProjectionMatrix, ANGLE, 1.4, 0.1f, 100.0f);
}

-(void)onScale:(CGFloat)scale atPosition:(CGPoint)point{

    if (mMode == MANNIU_DRAW_MODE_SPHERE_CIRCLE){
        if (mOrigin){
        
            if (scale < 1.0){
                mTranslateZ += -scale*0.02;
                
                ksMatrixLoadIdentity(&mModelViewMatrix);
                
                ksMatrixTranslate(&mModelViewMatrix, 0, 0, mTranslateZ);
                
                
            }else{
                mOrigin = NO;
                
                mTranslateZ = -0.01f;
                
                ksMatrixLoadIdentity(&mModelViewMatrix);
                
                ksMatrixTranslate(&mModelViewMatrix, 0, 0, mTranslateZ);
            }
            
        }else{
            if (scale < 1.0){
                [self wheelEvent:-80];
                if (ANGLE >= 80){
                    ANGLE = 80;
                    
                    mOrigin = YES;
                    mTranslateZ = -1.2;
                    mAngleH = 0;
                    mAngleV = 0;
                }
                
                
            }else if (scale > 1.0){
                [self wheelEvent:80];
            }
            
//            if (scale < 1.0){
//                mTranslateZ += -scale*0.02;
//                
//                ksMatrixLoadIdentity(&mModelViewMatrix);
//                ksMatrixTranslate(&mModelViewMatrix, 0, 0, -scale*0.02);
//                ksMatrixRotate(&mModelViewMatrix, mAngleH, 0, 1.0, 0);
//                ksMatrixRotate(&mModelViewMatrix, mAngleV, 1.0, 0, 0);
//                
//                if (mTranslateZ < -0.01){
//                    mOrigin = YES;
//                    mTranslateZ = -1.2;
//                    mAngleH = 0;
//                    mAngleV = 0;
//                }
//                
//                
//            }else if (scale > 1.0){
//                if (mTranslateZ + scale*0.02 <= 0.85){
//                    mTranslateZ += scale*0.02;
//                    
//                    ksMatrixLoadIdentity(&mModelViewMatrix);
//                    
//                    ksMatrixTranslate(&mModelViewMatrix, 0, 0, mTranslateZ);
//                }
//            }
        }
    }else if (mMode == MANNIU_DRAW_MODE_RECTANGLE){
        
        NSLog(@"+++++++++++++++++++++==================== %lf\n", scale);
        
        
        if (scale < 1.0){
            mModeRectangleScale += -scale*0.08;
            
            mModeRectangleScale = mModeRectangleScale < 0.6 ? 0.6 : mModeRectangleScale;
            
            ksMatrixLoadIdentity(&mModelViewMatrix);
            ksMatrixScale(&mModelViewMatrix, mModeRectangleScale, mModeRectangleScale, 1.0);
            
            ksMatrixTranslate(&mModelViewMatrix, mModeRectangleTransX / 200, mModeRectangleTransY / 200, mTranslateZ);
        }
        else{
            mModeRectangleScale += scale*0.02;
            
            mModeRectangleScale = mModeRectangleScale > 4.0 ? 4.0 : mModeRectangleScale;
            
            ksMatrixLoadIdentity(&mModelViewMatrix);
            ksMatrixScale(&mModelViewMatrix, mModeRectangleScale, mModeRectangleScale, 1.0);
            
            ksMatrixTranslate(&mModelViewMatrix, mModeRectangleTransX / 200, mModeRectangleTransY / 200, mTranslateZ);
        }
    }
    

//    
//    
//    
//    
//    ksMatrixTranslate(&mModelViewMatrix, 0, 0, 1.2);
//    ksMatrixRotate(&mModelViewMatrix, mAngleH, 0, 1.0, 0);
//    ksMatrixTranslate(&mModelViewMatrix, 0, 0, -1.2);
}

-(void)onScale{
    if (mScaleType == ZOOM_NONE)
        return ;
    
    if (mMode == MANNIU_DRAW_MODE_RECTANGLE)
        return ;
    
    if (mScaleType == SCALE_ANIMATION_TYPE::ZOOM_IN){
        if (mTranslateZ*1.1 > 2.0){
            mTranslateZ = 2.0;
            mScaleType = ZOOM_NONE;
            return ;
        }
        
        [self onScale:1.03 atPosition:CGPointMake(0, 0)];
        
    }else if (mScaleType == ZOOM_OUT){
        if (mTranslateZ*0.9 < 0.8){
            mTranslateZ = 0.8;
            mScaleType = ZOOM_NONE;
            return ;
        }
        
        [self onScale:0.97 atPosition:CGPointMake(0, 0)];
    }
}

-(void)onTapped{
    if (mScaleType != ZOOM_NONE)
        return ;
    
    if (mMode == MANNIU_DRAW_MODE_RECTANGLE)
        return ;
    
    if (mTranslateZ >= 2.0)
        mScaleType = ZOOM_OUT;
    else if (mTranslateZ <= 0.8)
        mScaleType = ZOOM_IN;
    else
        mScaleType = ZOOM_IN;
}

-(void)onTranslate:(CGPoint)point{
    if (mMode == MANNIU_DRAW_MODE_RECTANGLE){
        if (mPinch) return ;
        
        
        if (mModeRectangleScale > 1.0){
            mModeRectangleTransX += point.x;
            mModeRectangleTransY -= point.y;
            
            
            
            ksMatrixLoadIdentity(&mModelViewMatrix);
            ksMatrixScale(&mModelViewMatrix, mModeRectangleScale, mModeRectangleScale, 1.0);
            
            ksMatrixTranslate(&mModelViewMatrix, mModeRectangleTransX / 200, mModeRectangleTransY / 200, mTranslateZ);
        }
    }
}

-(int)setVideoWidth:(int)width height:(int)height{
    
//    if (m_videoH != 0)
//        return 0;
    
    if((m_videoW == width) && (m_videoH == height) && m_pByYuv420Data)
        return 0;
    
    
    m_videoW = width;
    m_videoH = height;
    
    
  //  [mLock lock];
    
    GW_DELETE_ARRAY(m_pByYuv420Data);
    //GW_DELETE_ARRAY(mpExpendYuv420Data);
    int nLength = width * height * 3 / 2;
    m_pByYuv420Data = new unsigned char[nLength + 1];
    
    mLargeEdge = fmax(width, height);
    nLength = mLargeEdge * mLargeEdge * 3 / 2;
  //  mpExpendYuv420Data = new unsigned char[nLength + 1];
    
  //  [mLock unlock];
    
//    [self generateBlackTextureWithWidth:width height:height];
    
    return 0;
}

// 生成正方形黑色纹理
-(void)generateBlackTextureWithWidth:(int)width height:(int)height{
    if (mBlackTexYId != 0)
        return ;
    
    
    const int BLACK_SCALE = fmax(width, height);
    unsigned char *pbyY = new unsigned char[BLACK_SCALE * BLACK_SCALE];
    unsigned char *pbyBR = new unsigned char[BLACK_SCALE * BLACK_SCALE / 4];
    unsigned char *pbyT = pbyBR;
    for (int i = BLACK_SCALE*BLACK_SCALE/4; i > 0; i--){
        *pbyT = 64;
        pbyT ++;
    }
    memset(pbyY, 0, BLACK_SCALE * BLACK_SCALE);
    
    glGenTextures(1, &mBlackTexYId);
    glBindTexture(GL_TEXTURE_2D, mBlackTexYId);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, BLACK_SCALE, BLACK_SCALE, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, pbyY);
    
    glGenTextures(1, &mBlackTexCbId);
    glBindTexture(GL_TEXTURE_2D, mBlackTexCbId);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, BLACK_SCALE/2, BLACK_SCALE/2, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, pbyBR);
    
    glGenTextures(1, &mBlackTexCrId);
    glBindTexture(GL_TEXTURE_2D, mBlackTexCrId);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, BLACK_SCALE/2, BLACK_SCALE/2, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, pbyBR);
}
// 渲染YUV数据
-(int)renderYUV420pDataY:(const void *)y U:(const void *)u V:(const void *)v width:(int)width height:(int)height{

    
    memcpy(m_pByYuv420Data, y, width * height);
    memcpy(m_pByYuv420Data + width * height, u, width * height * 1/4);
    memcpy(m_pByYuv420Data + width * height * 5 / 4, v, width * height * 1/4);
    
    
//    {
//        GLsizei nLittleEdge = fmin(m_videoH, m_videoW);
//        
//        //////////////////////////////////////////////////////
//        for (int i = 0; i < 2 * m_videoW; i++){
//            m_pByYuv420Data[i] = 0;
//            m_pByYuv420Data[m_videoW * (m_videoH - 2) + i] = 0;
//        }
//        
//        for (int i = 0; i < 2 * m_videoH / 4; i++){
//            m_pByYuv420Data[i + (nLittleEdge * mLargeEdge)] = 128;
//        }
//        for (int i = 0; i < 2 * m_videoH / 4; i++){
//            m_pByYuv420Data[i + (nLittleEdge * mLargeEdge) + (nLittleEdge * mLargeEdge / 4) - 2 * (m_videoH / 4)] = 128;
//        }
//        
//        for (int i = 0; i < 2 * m_videoH / 4; i++){
//            m_pByYuv420Data[i + (nLittleEdge * mLargeEdge) + (nLittleEdge * mLargeEdge / 4)] = 128;
//        }
//        for (int i = 0; i < 2 * m_videoH / 4; i++){
//            m_pByYuv420Data[i + (nLittleEdge * mLargeEdge) + (nLittleEdge * mLargeEdge / 2) - 2 * (m_videoH / 4)] = 128;
//        }
//    }
    
    [m_pDisplayLink setPaused:NO];
    
    return 0;
}
// 渲染YUV数据
-(int)renderYUV420pData:(void *)pYuv420pData length:(int)nLength{
    
    NSAssert(nLength == m_videoH * m_videoW * 3 / 2, @"ERROR: length not match.\n");
    
    if(m_pByYuv420Data == NULL)
        return 0;
    
    memcpy(m_pByYuv420Data, pYuv420pData, nLength);
    
    //[self expendYuv420pData:pYuv420pData length:nLength];
    
    
    {
        GLsizei nLittleEdge = fmin(m_videoH, m_videoW);
        
        //////////////////////////////////////////////////////
        for (int i = 0; i < 2 * m_videoW; i++){
            m_pByYuv420Data[i] = 0;
            m_pByYuv420Data[m_videoW * (m_videoH - 2) + i] = 0;
        }
        
        for (int i = 0; i < 2 * m_videoH / 4; i++){
            m_pByYuv420Data[i + (nLittleEdge * mLargeEdge)] = 128;
        }
        for (int i = 0; i < 2 * m_videoH / 4; i++){
            m_pByYuv420Data[i + (nLittleEdge * mLargeEdge) + (nLittleEdge * mLargeEdge / 4) - 2 * (m_videoH / 4)] = 128;
        }
        
        for (int i = 0; i < 2 * m_videoH / 4; i++){
            m_pByYuv420Data[i + (nLittleEdge * mLargeEdge) + (nLittleEdge * mLargeEdge / 4)] = 128;
        }
        for (int i = 0; i < 2 * m_videoH / 4; i++){
            m_pByYuv420Data[i + (nLittleEdge * mLargeEdge) + (nLittleEdge * mLargeEdge / 2) - 2 * (m_videoH / 4)] = 128;
        }
    }
    
    [m_pDisplayLink setPaused:NO];
    
    return 0;
}

//-(void)expendYuv420pData:(void *)pYuv420pData length:(int)nLength{
//    
//    for (int i = mLargeEdge * mLargeEdge - 1; i >= 0; i--){
//        mpExpendYuv420Data[i] = 0;
//    }
//    
//    for (int i = mLargeEdge * mLargeEdge; i < mLargeEdge * mLargeEdge * 3 / 2; i++){
//        mpExpendYuv420Data[i] = 128;
//    }
//    
//    GLsizei nLittleEdge = fmin(m_videoH, m_videoW);
//    memcpy(mpExpendYuv420Data + (mLargeEdge - nLittleEdge) / 2 * mLargeEdge, pYuv420pData, mLargeEdge * nLittleEdge);
//    
//    
//    
//    memcpy(mpExpendYuv420Data + (mLargeEdge * mLargeEdge) + (((mLargeEdge * mLargeEdge) / 4 - (mLargeEdge * nLittleEdge) / 4) / 2) , (unsigned char *)pYuv420pData + nLittleEdge * mLargeEdge, nLittleEdge * mLargeEdge / 4);
//    
//    memcpy(mpExpendYuv420Data + (mLargeEdge * mLargeEdge + mLargeEdge * mLargeEdge / 4) + (((mLargeEdge * mLargeEdge) / 4 - (mLargeEdge * nLittleEdge) / 4) / 2),
//           (unsigned char *)pYuv420pData + nLittleEdge * mLargeEdge + nLittleEdge * mLargeEdge / 4, nLittleEdge * mLargeEdge / 4);
//    
//    
//
//    
//    
//    
//    return ;
//}

const GLchar *shader_vsh = (const GLchar*)
"uniform mat4 projection;"
"uniform mat4 modelView;"
//"uniform vec4 u_clipPlane;"
"attribute vec4 position;"
"attribute vec2 texCoord;"
"varying vec2 texCoordVarying;"
//"varying float v_clipDist;"
"void main(void)"
"{"
"    lowp mat4 projection_;"
"    projection_ = mat4(1.94855726,         0,              0,              0,"
"                       0,                  1.7320509,      0,              0,"
"                       0,                  0,              -1.10526311,    -1.0,"
"                       0,                  0,              -2.10526323,    0);"
"    lowp mat4 modelView_;"
"    modelView_  = mat4(1,                  0,              0,              0,"
"                       0,                  1,              0,              0,"
"                       0,                  0,              1,              0,"
"                       0,                  0,              -1.5,           1);"
//"    v_clipDist = dot(position.xyz, u_clipPlane.xyz) + u_clipPlane.w;"
"    gl_Position = projection * modelView * position;"
"    texCoordVarying = texCoord;"
"}";

const GLchar *shader_fsh = (const GLchar*)
"varying highp vec2 texCoordVarying;"
"uniform sampler2D SamplerY;"
"uniform sampler2D SamplerU;"
"uniform sampler2D SamplerV;"
//"varying highp float v_clipDist;"
"void main()"
"{"
//"    if (v_clipDist < 0.0)"
//"        discard;"
"    mediump vec3 yuv;"
"    lowp vec3 rgb;"
"    yuv.x = texture2D(SamplerY, texCoordVarying).r;"
"    yuv.y = texture2D(SamplerU, texCoordVarying).r - 0.5;"
"    yuv.z = texture2D(SamplerV, texCoordVarying).r - 0.5;"
"    rgb = mat3(1,       1,         1,"
"               0,       -0.39465,  2.03211,"
"               1.13983, -0.58060,  0) * yuv;"
"    gl_FragColor = vec4(rgb, 1);"
"}";

//const GLchar *shader_fsh = (const GLchar*)"precision mediump float;"
//"void main()"
//"{"
//"    gl_FragColor = vec4(0.0, 0.0, 1.0, 1.0);"
//"}";

//const GLchar *shader_vsh = (const GLchar*)"attribute vec4 position;"
//"attribute vec2 texCoord;"
//"varying vec2 texCoordVarying;"
//"void main()"
//"{"
//"    gl_Position = position;"
//"    texCoordVarying = texCoord;"
//"}";

-(BOOL)loadShaders{
    BOOL bExitCode    = NO;
    GLuint vertShader = 0;
    GLuint fragShader = 0;
    
    // Create the shader program.
    self.program = glCreateProgram();
    
    GW_LOG_PROCESS_ERROR([self compileShaderString:&vertShader type:GL_VERTEX_SHADER shaderString:shader_vsh],   "ERROR: Failed to compile vertex shader!\n");
    GW_LOG_PROCESS_ERROR([self compileShaderString:&fragShader type:GL_FRAGMENT_SHADER shaderString:shader_fsh], "ERROR: Failed to compile fragment shader!\n");
    
    // Attach vertex shader to program.
    glAttachShader(self.program, vertShader);
    
    // Attach fragment shader to program.
    glAttachShader(self.program, fragShader);
    
    // Bind attribute locations. This needs to be done prior to linking.
    glBindAttribLocation(self.program, ATTRIB_VERTEX,   "position");
    glBindAttribLocation(self.program, ATTRIB_TEXCOORD, "texCoord");
    
    // Link the program.
    if (![self linkProgram:self.program]) {
        NSLog(@"Failed to link program: %d", self.program);
        
        if (vertShader) {
            glDeleteShader(vertShader);
            vertShader = 0;
        }
        if (fragShader) {
            glDeleteShader(fragShader);
            fragShader = 0;
        }
        if (self.program) {
            glDeleteProgram(self.program);
            self.program = 0;
        }
        
        return NO;
    }
    
    // Get uniform locations.
    uniforms[UNIFORM_Y] = glGetUniformLocation(self.program, "SamplerY");
    uniforms[UNIFORM_U] = glGetUniformLocation(self.program, "SamplerU");
    uniforms[UNIFORM_V] = glGetUniformLocation(self.program, "SamplerV");
    
    uniforms[UNIFORM_MODELVIEW] = glGetUniformLocation(self.program, "modelView");
    uniforms[UNIFORM_PROJECTION] = glGetUniformLocation(self.program, "projection");
    
    uniforms[UNIFORM_CLIP_PLANE] = glGetUniformLocation(self.program, "u_clipPlane");
    
    
    
    
    uniforms[UNIFORM_ROTATION_ANGLE] = glGetUniformLocation(self.program, "preferredRotation");
    uniforms[UNIFORM_COLOR_CONVERSION_MATRIX] = glGetUniformLocation(self.program, "colorConversionMatrix");
    
    // Release vertex and fragment shaders.
    if (vertShader) {
        glDetachShader(self.program, vertShader);
        glDeleteShader(vertShader);
    }
    if (fragShader) {
        glDetachShader(self.program, fragShader);
        glDeleteShader(fragShader);
    }
    bExitCode = YES;
Exit0:
    
    return bExitCode;
}

-(BOOL)compileShaderString:(GLuint *)shader type:(GLenum)type shaderString:(const GLchar *)shaderString{
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &shaderString, NULL);
    glCompileShader(*shader);
    
#if defined(DEBUG)
    GLint logLength;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    
    GLint status = 0;
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO;
    }
    
    return YES;
}

-(BOOL)compileShader:(GLuint *)shader type:(GLenum)type URL:(NSURL *)URL{
    NSError *error;
    NSString *sourceString = [[NSString alloc] initWithContentsOfURL:URL encoding:NSUTF8StringEncoding error:&error];
    if (sourceString == nil) {
        NSLog(@"Failed to load vertex shader: %@", [error localizedDescription]);
        return NO;
    }
    
    const GLchar *source = (GLchar *)[sourceString UTF8String];
    
    return [self compileShaderString:shader type:type shaderString:source];
}

-(BOOL)linkProgram:(GLuint)prog{
    GLint status;
    glLinkProgram(prog);
    
#if defined(DEBUG)
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program link log:\n%s", log);
        free(log);
    }
#endif
    
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

-(BOOL)validateProgram:(GLuint)prog{
    GLint logLength, status;
    
    glValidateProgram(prog);
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program validate log:\n%s", log);
        free(log);
    }
    
    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

-(void)cleanUpTextures{
}

@end
