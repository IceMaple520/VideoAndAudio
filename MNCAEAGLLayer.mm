

/*
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 
 This CAEAGLLayer subclass demonstrates how to draw a CVPixelBufferRef using OpenGLES and display the timecode associated with that pixel buffer in the top right corner.
 
 */

#import <OpenGLES/EAGL.h>
#import <mach/mach_time.h>
#import <UIKit/UIScreen.h>
//#import <OpenGLES/ES2/gl.h>
//#import <OpenGLES/ES2/glext.h>
#import <OpenGLES/ES3/glext.h>
#import <AVFoundation/AVUtilities.h>
#import <AVFoundation/AVFoundation.h>

#import "MNPublic.h"
#import "MNCAEAGLLayer.h"

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


float Image_H = 980.0f;             // 图像高度（pixels）
float Image_W = 1792.0f;            // 图像宽度（pixels）
float HC = 595.4288;                // 畸变中心的H方向坐标，左上角为原点（pixels）
float WC = 897.8561f;               // 畸变中心的W方向坐标，左上角为原点（pixels）
double a0 = 566.3531;               // 多项式0次项系数
double a2 = -7.9609e-4;             // 多项式2次项系数
double a3 = 5.7513e-7;              // 多项式3次项系数
double a4 = -6.879e-10;             // 多项式4次项系数
double W_div = Image_W / 72.0f;     // 纹理坐标与图像像素坐标转换系数
double H_div = Image_H / 72.0f;     // 纹理坐标与图像像素坐标转换系数


// Color Conversion Constants (YUV to RGB) including adjustment from 16-235/16-240 (video range)

// BT.601, which is the standard for SDTV.
static const GLfloat kColorConversion601[] = {
    1.164,  1.164, 1.164,
    0.0, -0.392, 2.017,
    1.596, -0.813, 0.0,
};

// BT.709, which is the standard for HDTV.
static const GLfloat kColorConversion709[] = {
    1.164,  1.164, 1.164,
    0.0, -0.213, 2.112,
    1.793, -0.533, 0.0,
};

@interface MNCAEAGLLayer(){
    EAGLContext *mContext;
    
    GLuint mTextureY;
    GLuint mTextureU;
    GLuint mTextureV;
    
    GLuint depthRenderbuffer;
    GLuint mMSAAFramebuffer;
    GLuint mMSAARenderbuffer;
    GLuint mMSAADepthRenderbuffer;
    GLint mBackingWidth;
    GLint mBackingHeight;
    
    GLuint mFrameBufferHandle; //创建一个帧缓冲区对象
    GLuint mColorBufferHandle;
    
    GLfloat mAngle;
    MN_DRAW_MODE mDrawMode;
    
    NSMutableArray *mPixelBufferFrames;
    
    const GLfloat *mPreferredConversion;
    
    CVOpenGLESTextureRef mLumaTexture;
    CVOpenGLESTextureRef mChromaTexture;
    CVOpenGLESTextureCacheRef mVideoTextureCache;
}
@property GLuint program;
@property (strong, nonatomic) NSThread *mDisplayThread;

@end


@implementation MNCAEAGLLayer

-(instancetype)initWithFrame:(CGRect)frame drawMode:(MN_DRAW_MODE)mode{
    
    self = [super init];
    if (self) {
        CGFloat scale = [[UIScreen mainScreen] scale];
        self.contentsScale = scale;
        self.opaque = TRUE;
        self.drawableProperties = @{kEAGLDrawablePropertyRetainedBacking:[NSNumber numberWithBool:YES]};
        
        [self setFrame:frame];
        
        // cost 150ms-200ms
        //初始化上下文
        {
            mContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
            MN_PROCESS_ERROR(mContext != nil);
        }
        
        self.mMode = mode;
        // cost 70ms
        {
            [self setupGL:mode];
            
            [self initalizeGL];
        }
        
        self.mDisplayThread = [[NSThread alloc] initWithTarget:self selector:@selector(displayThread) object:nil];
        
        [self.mDisplayThread start];
        
        mYuv420Data = NULL;
        
        mVideoW = 0;
        mVideoH = 0;
        
        mBlackTexYId  = 0;
        mBlackTexCrId = 0;
        mBlackTexCbId = 0;
        
        mOrigin = YES;
        
        mModeRectangleScale = 1.0;
        
        mModeRectangleTransX = 0.0;
        mModeRectangleTransY = 0.0;
        
        ANGLE = 80;
        
        mPaused = YES;
        
        mYuvDataLock = [NSLock new];
        mGLCommandCommitLock = [NSLock new];
        mPixelBufferFrames = [NSMutableArray new];
    }
    
Exit0:
    
    return self;
}

-(void)displayThread{
    mDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(draw)];
    [mDisplayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    
    // 默认每秒60帧，frameInterval=2，表示每隔一帧运行一次，每秒运行30次
    [mDisplayLink setFrameInterval:2];
    [mDisplayLink setPaused:YES];
    
    [[NSRunLoop currentRunLoop] run];
}

-(void)setupParamsWithWidth:(int)nWidth height:(int)nHeight{
    if ((nWidth == 980 && nHeight == 1792) || (nWidth == 1920 && nHeight == 1080)){
        Image_H = 980.0f;               // 图像高度（pixels）
        Image_W = 1792.0f;              // 图像宽度（pixels）
        HC = 595.4288;                  // 畸变中心的H方向坐标，左上角为原点（pixels）
        WC = 897.8561f;                 // 畸变中心的W方向坐标，左上角为原点（pixels）
        a0 = 566.3531;                  // 多项式0次项系数
        a2 = -7.9609e-4;                // 多项式2次项系数
        a3 = 5.7513e-7;                 // 多项式3次项系数
        a4 = -6.879e-10;                // 多项式4次项系数
        W_div = Image_W / 72.0f;        // 纹理坐标与图像像素坐标转换系数
        H_div = Image_H / 72.0f;        // 纹理坐标与图像像素坐标转换系数
    }else if (nWidth == 1280 && nHeight == 720){
        Image_H = 980.0f;               // 图像高度（pixels）
        Image_W = 1792.0f;              // 图像宽度（pixels）
        HC = 595.4288;                  // 畸变中心的H方向坐标，左上角为原点（pixels）
        WC = 897.8561f;                 // 畸变中心的W方向坐标，左上角为原点（pixels）
        a0 = 566.3531;                  // 多项式0次项系数
        a2 = -7.9609e-4;                // 多项式2次项系数
        a3 = 5.7513e-7;                 // 多项式3次项系数
        a4 = -6.879e-10;                // 多项式4次项系数
        W_div = Image_W / 72.0f;        // 纹理坐标与图像像素坐标转换系数
        H_div = Image_H / 72.0f;        // 纹理坐标与图像像素坐标转换系数
    }else if (nWidth == 704 && nHeight == 576){
        Image_H = 980.0f;               // 图像高度（pixels）
        Image_W = 1792.0f;              // 图像宽度（pixels）
        HC = 595.4288;                  // 畸变中心的H方向坐标，左上角为原点（pixels）
        WC = 897.8561f;                 // 畸变中心的W方向坐标，左上角为原点（pixels）
        a0 = 566.3531;                  // 多项式0次项系数
        a2 = -7.9609e-4;                // 多项式2次项系数
        a3 = 5.7513e-7;                 // 多项式3次项系数
        a4 = -6.879e-10;                // 多项式4次项系数
        W_div = Image_W / 72.0f;        // 纹理坐标与图像像素坐标转换系数
        H_div = Image_H / 72.0f;        // 纹理坐标与图像像素坐标转换系数
    }
}

-(void)initalizeGL{
    for (int rad = 0; rad < MAX_RAD_NUM; rad++)                                     // 径向量
    {
        // 径向由内到外
        for (int rotate = 0; rotate < MAX_ROTATE_NUM; rotate++)                     // 旋转量
        {
            float theta = float(rotate)*(360.f / MAX_ROTATE_NUM)*3.141592654f*2.0f/360.0f;    // 弧度值
            float r_pixel = float(rad+1)*0.96*Image_W/(2 * MAX_RAD_NUM);          // 注意：rad+1。径向值，像素为单位，Image_W后期调试可以更改其值，改变的是纹理区域的范围
            
            /*****************构建球面向量*****************/
            float X_pixel = r_pixel*sin(theta);                         // X方向值，像素为单位   // 围绕坐标轴顺时针转动
            float Y_pixel = r_pixel*cos(theta);                         // Y方向值，像素为单位
            float Z_pixel = a0+a2*r_pixel*r_pixel+a3*r_pixel*r_pixel*r_pixel+a4*r_pixel*r_pixel*r_pixel*r_pixel;  // Z方向值，像素为单位
            float R_pixel = sqrt(X_pixel*X_pixel+Y_pixel*Y_pixel+Z_pixel*Z_pixel);    // 三维向量的模
            float X_sphere = X_pixel/R_pixel;                           // 归一化
            float Y_sphere = Y_pixel/R_pixel;                           // 归一化
            float Z_sphere = Z_pixel/R_pixel;                           // 归一化
            
            /*****************根据畸变中心就对应上述球面顶点的纹理坐标*****************/
            float x_texture = (WC+X_pixel)/Image_W;                     // 纹理坐标（0,1），原点在左下角
            float y_texture = (HC-Y_pixel)/Image_H;                     // 方向纹理坐标（0,1），原点在左下角
            m_points[rad][rotate][0] = X_sphere;                        // 三维数组存储三维向量
            m_points[rad][rotate][1] = Y_sphere;
            m_points[rad][rotate][2] = -Z_sphere;
            
            texture[rad][rotate][0] = x_texture;                        // 三维数组存储与此相对应的纹理坐标
            texture[rad][rotate][1] = y_texture;
        }
    }
}

-(void)paintGL{
    for (int rad = 0; rad < MAX_RAD_NUM; rad++)                         // 径向量
    {
        // Y平面循环
        for (int rotate = 0; rotate < MAX_ROTATE_NUM; rotate++)         // 旋转量
        {
            if (rad == 0)
            {
                if(rotate == MAX_ROTATE_NUM - 1)
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
                if(rotate == MAX_ROTATE_NUM - 1)
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

- (void)cleanUpTextures
{
    if (mLumaTexture) {
        CFRelease(mLumaTexture);
        mLumaTexture = NULL;
    }
    
    if (mChromaTexture) {
        CFRelease(mChromaTexture);
        mChromaTexture = NULL;
    }
    
    // Periodic texture cache flush every frame
    CVOpenGLESTextureCacheFlush(mVideoTextureCache, 0);
}

-(void)draw{
    // NSLog(@"绘制\n");
    if(self.isPaused)return;
    
    if (nil == self.mDisplayThread){
        [mDisplayLink setPaused:YES];
        [mDisplayLink invalidate];
        mDisplayLink = nil;
        
        [NSThread exit];
    }
    
    if (NULL == mYuv420Data) return ;
    
    [mGLCommandCommitLock lock];
    CVPixelBufferRef pixelBuffer = NULL;
    
    [self onScale];
    [self modeSphereCircleAdjustAngle];
    [self modeRectangleAdjustTrans];
    
    if (!mOnTouched){
        if (self.mMode == MN_DRAW_MODE_SPHERE_CIRCLE){
            if (mOrigin){
                if (fabs(mTranslateZ - -1.2) > 0.000001){
                    mTranslateZ = -1.2;
                }
            }
        }else if (self.mMode == MN_DRAW_MODE_RECTANGLE){
            if (mModeRectangleScale < 1.0){
                mModeRectangleTransX = 0;
                mModeRectangleTransY = 0;
                
                [self onScale:1.01 atPosition:CGPointMake(0, 0)];
            }
        }
    }
    
    MN_PROCESS_ERROR(YES == [EAGLContext setCurrentContext:mContext]);
    
    mPreferredConversion = kColorConversion709;
    
    @synchronized (mPixelBufferFrames) {
        if ([mPixelBufferFrames count] > 0){
            pixelBuffer = (__bridge CVPixelBufferRef)[mPixelBufferFrames objectAtIndex:0];
        }
    }
    
    if (NULL != pixelBuffer){
        // NSLog(@"pixelBuffer = %p", pixelBuffer);
        
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        
        int frameWidth = (int)CVPixelBufferGetWidth(pixelBuffer);
        int frameHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
        
        [self cleanUpTextures];
        
        CFTypeRef colorAttachments = CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, NULL);
        
        if (colorAttachments == kCVImageBufferYCbCrMatrix_ITU_R_601_4) {
            mPreferredConversion = kColorConversion601;
        }else{
            mPreferredConversion = kColorConversion709;
        }
        
        glActiveTexture(GL_TEXTURE0);
        CVReturn err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                    mVideoTextureCache,
                                                                    pixelBuffer,
                                                                    NULL,
                                                                    GL_TEXTURE_2D,
                                                                    GL_RED,
                                                                    frameWidth,
                                                                    frameHeight,
                                                                    GL_RED,
                                                                    GL_UNSIGNED_BYTE,
                                                                    0,
                                                                    &mLumaTexture);
        if (err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        
        glBindTexture(CVOpenGLESTextureGetTarget(mLumaTexture), CVOpenGLESTextureGetName(mLumaTexture));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        // UV-plane.
        glActiveTexture(GL_TEXTURE1);
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           mVideoTextureCache,
                                                           pixelBuffer,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_RG,
                                                           frameWidth / 2,
                                                           frameHeight / 2,
                                                           GL_RG,
                                                           GL_UNSIGNED_BYTE,
                                                           1,
                                                           &mChromaTexture);
        if (err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        
        glBindTexture(CVOpenGLESTextureGetTarget(mChromaTexture), CVOpenGLESTextureGetName(mChromaTexture));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        
        @synchronized (mPixelBufferFrames) {
            if ([mPixelBufferFrames count] > 1){
                pixelBuffer = (__bridge CVPixelBufferRef)[mPixelBufferFrames objectAtIndex:0];
                [mPixelBufferFrames removeObjectAtIndex:0];
                CFRelease((CFTypeRef)pixelBuffer);
                
                pixelBuffer = NULL;
            }
        }
    }
    
    glViewport(0, 0, mBackingWidth, mBackingHeight);
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
    
    
    glUniformMatrix3fv(uniforms[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, mPreferredConversion);
    
    if (self.mMode == MN_DRAW_MODE_RECTANGLE)            // 平面矩形
    {
        
        glVertexAttribPointer(ATTRIB_VERTEX, 3, GL_FLOAT, 0, 0, rectCoords);
        glEnableVertexAttribArray(ATTRIB_VERTEX);
        
        glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, texCoords);
        glEnableVertexAttribArray(ATTRIB_TEXCOORD);
        
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    }
    else if (self.mMode == MN_DRAW_MODE_SPHERE_CIRCLE)   // 圆形映射到球面
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
    
    [mContext presentRenderbuffer:GL_RENDERBUFFER];
    
    glFlush();
    
    [mGLCommandCommitLock unlock];
    
Exit0:
    return ;
}

//-(void)draw{
//    if (nil == self.mDisplayThread){
//        [mDisplayLink setPaused:YES];
//        [mDisplayLink invalidate];
//        mDisplayLink = nil;
//
//        [NSThread exit];
//    }
//
//    if (NULL == mYuv420Data) return ;
//
//    [self onScale];
//    [self modeSphereCircleAdjustAngle];
//    [self modeRectangleAdjustTrans];
//
//    if (!mOnTouched){
//        if (mMode == MN_DRAW_MODE_SPHERE_CIRCLE){
//            if (mOrigin){
//                if (fabs(mTranslateZ - -1.2) > 0.000001){
//                    mTranslateZ = -1.2;
//                }
//            }
//        }else if (mMode == MN_DRAW_MODE_RECTANGLE){
//            if (mModeRectangleScale < 1.0){
//                mModeRectangleTransX = 0;
//                mModeRectangleTransY = 0;
//
//                [self onScale:1.01 atPosition:CGPointMake(0, 0)];
//            }
//        }
//    }
//
//    MN_PROCESS_ERROR(YES == [EAGLContext setCurrentContext:mContext]);
//
//    [mGLCommandCommitLock lock];
//
//    [mYuvDataLock lock];
//
//    glActiveTexture(GL_TEXTURE0);
//    glBindTexture(GL_TEXTURE_2D, mTextureY);
//    glTexImage2D(GL_TEXTURE_2D, 0, GL_RED_EXT, mVideoW, mVideoH, 0, GL_RED_EXT, GL_UNSIGNED_BYTE, mYuv420Data);
//
//    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
//    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
//    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
//    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
//
//    glActiveTexture(GL_TEXTURE1);
//    glBindTexture(GL_TEXTURE_2D, mTextureU);
//    glTexImage2D(GL_TEXTURE_2D, 0, GL_RED_EXT, mVideoW / 2, mVideoH / 2, 0, GL_RED_EXT, GL_UNSIGNED_BYTE, (char *)mYuv420Data + mVideoW * mVideoH);
//
//    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
//    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
//    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
//    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
//
//    glActiveTexture(GL_TEXTURE2);
//    glBindTexture(GL_TEXTURE_2D, mTextureV);
//    glTexImage2D(GL_TEXTURE_2D, 0, GL_RED_EXT, mVideoW / 2, mVideoH / 2, 0, GL_RED_EXT, GL_UNSIGNED_BYTE, (char *)mYuv420Data + mVideoW * mVideoH * 5 / 4);
//
//    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
//    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
//    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
//    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
//
//    [mYuvDataLock unlock];
//
//
//    glViewport(0, 0, mBackingWidth, mBackingHeight);
//    glClearColor(0.0, 0.0, 0.0, 1.0);
//
//    // 方向横屏
//    static const GLfloat rectCoords[] = {
//        -1, -1, 0.0,
//        1, -1, 0.0,
//        -1, 1, 0.0,
//        1, 1, 0.0,
//    };
//
//    static const GLfloat texCoords[] = {
//        0.0f, 1.0f,
//        1.0f, 1.0f,
//        0.0f,  0.0f,
//        1.0f,  0.0f,
//    };
//
//    glClear(GL_COLOR_BUFFER_BIT);
//    glUseProgram(self.program);
//
//
//    glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEW], 1, GL_FALSE, (GLfloat*)&mModelViewMatrix.m[0][0]);
//
//    glUniform1i(uniforms[UNIFORM_Y], 0);
//    glUniform1i(uniforms[UNIFORM_U], 1);
//    glUniform1i(uniforms[UNIFORM_V], 2);
//
//
//    if (mMode == MN_DRAW_MODE_RECTANGLE)            // 平面矩形
//    {
//        glVertexAttribPointer(ATTRIB_VERTEX, 3, GL_FLOAT, 0, 0, rectCoords);
//        glEnableVertexAttribArray(ATTRIB_VERTEX);
//
//        glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, texCoords);
//        glEnableVertexAttribArray(ATTRIB_TEXCOORD);
//
//        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
//    }
//    else if (mMode == MN_DRAW_MODE_SPHERE_CIRCLE)   // 圆形映射到球面
//    {
//        if (mOrigin){
//
//            ksMatrixLoadIdentity(&mModelViewMatrix);
//            ksMatrixTranslate(&mModelViewMatrix, 0, 0, mTranslateZ);
//
//            ksMatrixLoadIdentity(&mProjectionMatrix);
//            ksPerspective(&mProjectionMatrix, 80.0, 1.0, 0.1f, 80.0f);
//            glUniformMatrix4fv(uniforms[UNIFORM_PROJECTION], 1, GL_FALSE, (GLfloat*)&mProjectionMatrix.m[0][0]);
//
//            glVertexAttribPointer(ATTRIB_VERTEX, 3, GL_FLOAT, 0, 0, rectCoords);
//            glEnableVertexAttribArray(ATTRIB_VERTEX);
//
//            glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, texCoords);
//            glEnableVertexAttribArray(ATTRIB_TEXCOORD);
//
//            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
//        }else{
//            ksMatrixLoadIdentity(&mProjectionMatrix);
//            ksPerspective(&mProjectionMatrix, ANGLE, 1.40, 0.1f, 80.0f);     // TODO: 1.4??
//            glUniformMatrix4fv(uniforms[UNIFORM_PROJECTION], 1, GL_FALSE, (GLfloat*)&mProjectionMatrix.m[0][0]);
//
//            ksMatrixLoadIdentity(&mModelViewMatrix);
//            ksMatrixTranslate(&mModelViewMatrix, 0, 0, mTranslateZ);
//            ksMatrixRotate(&mModelViewMatrix, mAngleV, 1, 0, 0);
//            ksMatrixRotate(&mModelViewMatrix, mAngleH, 0, 1, 0);
//
//            glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEW], 1, GL_FALSE, (GLfloat*)&mModelViewMatrix.m[0][0]);
//
//            [self paintGL];
//        }
//    }
//
////    if (mPaused)
////        return ;
//
//    [mContext presentRenderbuffer:GL_RENDERBUFFER];
//
//    glFlush();
//
//    [mGLCommandCommitLock unlock];
//
//Exit0:
//    return ;
//}

-(void)onTouchBegin{
    mOnTouched = YES;
    mRotateOffset = CGPointMake(0, 0);
}

-(void)onTouchEnd{
    mOnTouched = NO;
}

-(void)uninit{
    // 保证mPixelBufferFrames清除时，不进draw函数操作CVPixelBufferRef
    [mGLCommandCommitLock lock];
    
    @synchronized (mPixelBufferFrames) {
        while ([mPixelBufferFrames count] > 0){
            CVPixelBufferRef pixelBuffer = (__bridge CVPixelBufferRef)[mPixelBufferFrames objectAtIndex:0];
            [mPixelBufferFrames removeObjectAtIndex:0];
            CFRelease((CFTypeRef)pixelBuffer);
        }
    }
    
    [mGLCommandCommitLock unlock];
    
    self.mDisplayThread = nil;
    
    if (!mContext || ![EAGLContext setCurrentContext:mContext]) {
        return;
    }
    
    [self cleanUpTextures];
    
    if (self.program) {
        glDeleteProgram(self.program);
        self.program = 0;
    }
    if(mContext) {
        mContext = nil;
    }
    
    [mYuvDataLock lock];
    
    MN_DELETE_ARRAY(mYuv420Data);
    MN_DELETE_ARRAY(mpExpendYuv420Data);
    
    [mYuvDataLock unlock];
}

-(void)setupBuffers{
     glEnable(GL_DEPTH_TEST); //启用深度缓冲测试 它只会再那个像素前方没有其他像素遮挡时，才会绘画这个像素。
    
    glEnableVertexAttribArray(ATTRIB_VERTEX);  // glEnableVertexAttribArray 允许顶点着色器读取GPU（服务器端）数据。
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
    
    glEnableVertexAttribArray(ATTRIB_TEXCOORD); //激活ATTRIB_TEXCOORD顶点数组
    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
    
    glGenFramebuffers(1, &mFrameBufferHandle);                   //创建一个帧染缓冲区对象
    glBindFramebuffer(GL_FRAMEBUFFER, mFrameBufferHandle);       //将该帧染缓冲区对象绑定到管线上
    
    glGenRenderbuffers(1, &mColorBufferHandle);
    glBindRenderbuffer(GL_RENDERBUFFER, mColorBufferHandle);  //将创建的渲染缓冲区绑定到帧缓冲区上，并使用颜色填充
    
  //  glResolveMultisampleFramebufferAPPLE();

    [mContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:self]; // 为 color renderbuffer 分配存储空间
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &mBackingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &mBackingHeight);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, mColorBufferHandle);

    
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
    }
}

-(void)setupGL:(MN_DRAW_MODE)mode{
    
    MN_PROCESS_ERROR(mContext != nil);
    MN_PROCESS_ERROR([EAGLContext setCurrentContext:mContext]);
    
    [self setupBuffers];
    [self loadShaders];
    
  //  int LrgSupAni;
  //  glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT, &LrgSupAni);

    glUseProgram(self.program);
    
    ksMatrixLoadIdentity(&mProjectionMatrix);
    
    if (mode == MN_DRAW_MODE_RECTANGLE){
        ksPerspective(&mProjectionMatrix, 80.0, 1.0, 0.1f, 40.0f);
    }else{
        ksPerspective(&mProjectionMatrix, 80.0, 1.40, 0.1f, 40.0f);     // TODO: 1.4??
    }
    glUniformMatrix4fv(uniforms[UNIFORM_PROJECTION], 1, GL_FALSE, (GLfloat*)&mProjectionMatrix.m[0][0]);
    
    
    ksMatrixLoadIdentity(&mModelViewMatrix);
    if (mode == MN_DRAW_MODE_RECTANGLE){
        mTranslateZ = -1.2;
        ksMatrixTranslate(&mModelViewMatrix, 0, 0, mTranslateZ);
    }else{
        mTranslateZ = -1.2;
        
        ksMatrixTranslate(&mModelViewMatrix, 0, 0, mTranslateZ);
    }
    
    glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEW], 1, GL_FALSE, (GLfloat*)&mModelViewMatrix.m[0][0]);
    
    
    glGenTextures(1, &mTextureY);
    glGenTextures(1, &mTextureU);
    glGenTextures(1, &mTextureV);
    
    // Create CVOpenGLESTextureCacheRef for optimal CVPixelBufferRef to GLES texture conversion.
    if (!mVideoTextureCache) {
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, mContext, NULL, &mVideoTextureCache);
        if (err != noErr) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
            return;
        }
    }
    
    
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
    if (MN_DRAW_MODE_SPHERE_CIRCLE){
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

-(BOOL)isPaused{
    return mPaused;
}

-(void)pause{
    mPaused = YES;
    [mDisplayLink setPaused:YES];
    
    // 等待draw函数中GL指令调用完毕
    [mGLCommandCommitLock lock];
    
    glFinish();
    
    [mGLCommandCommitLock unlock];
    
    NSLog(@"-(void)pause");
}

-(void)resume{
    mPaused = NO;
    
    [mDisplayLink setPaused:NO];
}

-(void)onTouchMoved:(CGPoint)offset{
    if (self.mMode == MN_DRAW_MODE_SPHERE_CIRCLE){
        [self onRotateWithOffset:offset];
    }else if (self.mMode == MN_DRAW_MODE_RECTANGLE){
        [self onTranslate:offset];
    }
}

-(void)onRotateWithOffset:(CGPoint)offset{
    mRotateOffset = offset;
    
    if (self.mMode == MN_DRAW_MODE_RECTANGLE)
        return ;
    
    if (mPinch) return ;
    
    if (self.mMode == MN_DRAW_MODE_SPHERE_CIRCLE){
        if (mOrigin){
            return ;
        }else{
            GLfloat angle = mAngleH + (mRotateOffset.x * 0.25);
            
            if (mTranslateZ >= 1.16){
                ksMatrixRotate(&mModelViewMatrix, (offset.x * 0.25), 0, 1.0, 0);
                mAngleH += (offset.x * 0.25);
            }else{
                ksMatrixRotate(&mModelViewMatrix, (offset.x * 0.25), 0, 1.0, 0);
                mAngleH += (offset.x * 0.25);
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
    
    if (self.mMode == MN_DRAW_MODE_SPHERE_CIRCLE){
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
        }
    }else if (self.mMode == MN_DRAW_MODE_RECTANGLE){
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
}

-(void)onScale{
    if (mScaleType == ZOOM_NONE)
        return ;
    
    if (self.mMode == MN_DRAW_MODE_RECTANGLE)
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
    
    if (self.mMode == MN_DRAW_MODE_RECTANGLE)
        return ;
    
    if (mTranslateZ >= 2.0)
        mScaleType = ZOOM_OUT;
    else if (mTranslateZ <= 0.8)
        mScaleType = ZOOM_IN;
    else
        mScaleType = ZOOM_IN;
}

-(void)onTranslate:(CGPoint)point{
    if (self.mMode == MN_DRAW_MODE_RECTANGLE){
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
    if (mVideoW == width && mVideoH == height){
        return 0;
    }else{
        [self setupParamsWithWidth:width height:height];
        [self initalizeGL];
    }
    
    mVideoW = width;
    mVideoH = height;
    
    [mYuvDataLock lock];
    
    MN_DELETE_ARRAY(mYuv420Data);
    MN_DELETE_ARRAY(mpExpendYuv420Data);
    
    int nLength = width * height * 3 / 2;
    mYuv420Data = new unsigned char[nLength + 1];
    NSLog(@"mYuv420Data = %p, len = %d", mYuv420Data, nLength + 1);
    
    
    memset(mYuv420Data, 0, width * height);
    memset(mYuv420Data + width * height, 0x80, width * height / 2);
    
    mLargeEdge = fmax(width, height);
    nLength = mLargeEdge * mLargeEdge * 3 / 2;
    mpExpendYuv420Data = new unsigned char[nLength + 1];
    
    [mYuvDataLock unlock];
    
    // [self generateBlackTextureWithWidth:width height:height];
    
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

-(int)renderYuv420p:(unsigned char *)y u:(unsigned char *)u v:(unsigned char *)v width:(int)nWidth height:(int)nHeight length:(int)nLength{
    if (mYuvDataLock == nil) return -1;
    
    [mYuvDataLock lock];
    if (NULL == mYuv420Data){
        [mYuvDataLock unlock];
        return -1;
    }
    // double begin = CFAbsoluteTimeGetCurrent();
    
    memcpy(mYuv420Data, y, nWidth * nHeight);
    memcpy(mYuv420Data + nWidth * nHeight, u, (mVideoW / 2) * (mVideoH / 2));
    memcpy(mYuv420Data + mVideoW * mVideoH * 5 / 4, v, (mVideoW / 2) * (mVideoH / 2));
    // NSLog(@"解码回调耗时:%lf\n", (CFAbsoluteTimeGetCurrent() - begin) * 1000);
    GLsizei nLittleEdge = fmin(mVideoH, mVideoW);
    
    //////////////////////////////////////////////////////
    for (int i = 0; i < mVideoW; i++){
        mYuv420Data[i] = 0;
        mYuv420Data[mVideoW * (mVideoH - 1) + i] = 0;
    }
    
    for (int i = 0; i < mVideoW / 2; i++){
        mYuv420Data[i + (nLittleEdge * mLargeEdge)] = 128;
        mYuv420Data[i + (nLittleEdge * mLargeEdge) + (mVideoW / 2) * (mVideoH / 2 - 1)] = 128;
        
        mYuv420Data[i + (nLittleEdge * mLargeEdge) + (nLittleEdge * mLargeEdge / 4)] = 128;
        
        mYuv420Data[i + (nLittleEdge * mLargeEdge) + (nLittleEdge * mLargeEdge / 4) + (mVideoW / 2) * (mVideoH / 2 - 1)] = 128;
    }
    [mYuvDataLock unlock];
    
    if ([mDisplayLink isPaused]){
        [mDisplayLink setPaused:NO];
    }
    
    return 0;
}

// 渲染YUV数据
-(int)renderYUV420pData:(void *)pYuv420pData length:(int)nLength{
    
    NSAssert(nLength == mVideoH * mVideoW * 3 / 2, @"ERROR: length not match.\n");
    
    memcpy(mYuv420Data, pYuv420pData, nLength);
    
    // [self expendYuv420pData:pYuv420pData length:nLength];
    
    
    {
        GLsizei nLittleEdge = fmin(mVideoH, mVideoW);
        
        //////////////////////////////////////////////////////
        for (int i = 0; i < mVideoW; i++){
            mYuv420Data[i] = 0;
            mYuv420Data[mVideoW * (mVideoH - 1) + i] = 0;
        }
        
        for (int i = 0; i < mVideoW / 4 * 2; i++){      // 2 line
            mYuv420Data[i + (nLittleEdge * mLargeEdge)] = 128;
            mYuv420Data[i + (nLittleEdge * mLargeEdge) + (mVideoW / 2) * (mVideoH / 2 - 1)] = 128;
            
            mYuv420Data[i + (nLittleEdge * mLargeEdge) + (nLittleEdge * mLargeEdge / 4)] = 128;
            
            mYuv420Data[i + (nLittleEdge * mLargeEdge) + (nLittleEdge * mLargeEdge / 4) + (mVideoW / 2) * (mVideoH / 2 - 1)] = 128;
        }
    }
    
    if (!mPaused){
        [mDisplayLink setPaused:NO];
    }
    
    return 0;
}

-(int)renderYuv420pData:(CVPixelBufferRef)pixelBuffer{
    @synchronized (mPixelBufferFrames) {
        CFRetain((CFTypeRef)pixelBuffer);
        
        [mPixelBufferFrames addObject:(__bridge id)pixelBuffer];
        // NSLog(@"IOYOSADGASJKJKD count = %ld", [mPixelBufferFrames count]);
    }
    
    return 0;
}

-(void)expendYuv420pData:(void *)pYuv420pData length:(int)nLength{
    
    for (int i = mLargeEdge * mLargeEdge - 1; i >= 0; i--){
        mpExpendYuv420Data[i] = 0;
    }
    
    for (int i = mLargeEdge * mLargeEdge; i < mLargeEdge * mLargeEdge * 3 / 2; i++){
        mpExpendYuv420Data[i] = 128;
    }
    
    GLsizei nLittleEdge = fmin(mVideoH, mVideoW);
    memcpy(mpExpendYuv420Data + (mLargeEdge - nLittleEdge) / 2 * mLargeEdge, pYuv420pData, mLargeEdge * nLittleEdge);
    
    
    
    memcpy(mpExpendYuv420Data + (mLargeEdge * mLargeEdge) + (((mLargeEdge * mLargeEdge) / 4 - (mLargeEdge * nLittleEdge) / 4) / 2) , (unsigned char *)pYuv420pData + nLittleEdge * mLargeEdge, nLittleEdge * mLargeEdge / 4);
    
    memcpy(mpExpendYuv420Data + (mLargeEdge * mLargeEdge + mLargeEdge * mLargeEdge / 4) + (((mLargeEdge * mLargeEdge) / 4 - (mLargeEdge * nLittleEdge) / 4) / 2),
           (unsigned char *)pYuv420pData + nLittleEdge * mLargeEdge + nLittleEdge * mLargeEdge / 4, nLittleEdge * mLargeEdge / 4);
    
    return ;
}

-(unsigned char *)getYuv420pData{
    return mYuv420Data;
}
-(CVPixelBufferRef)getCVPixelBufferRef{
    @synchronized (mPixelBufferFrames) {
        if ([mPixelBufferFrames count] > 0){
            return (__bridge_retained CVPixelBufferRef)[mPixelBufferFrames firstObject];
        }
    }
    return NULL;
}

const GLchar *shader_vsh = (const GLchar *)
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

//const GLchar *shader_vsh = (const GLchar*)
//"attribute vec4 position;"
//"attribute vec2 texCoord;"
//"uniform float preferredRotation;"
//"varying vec2 texCoordVarying;"
//"void main()"
//"{"
//"    mat4 rotationMatrix = mat4( cos(preferredRotation), -sin(preferredRotation), 0.0, 0.0,"
//"                               sin(preferredRotation),  cos(preferredRotation), 0.0, 0.0,"
//"                               0.0,					    0.0, 1.0, 0.0,"
//"                               0.0,					    0.0, 0.0, 1.0);"
//"    gl_Position = position * rotationMatrix;"
//"    texCoordVarying = texCoord;"
//"}";

//const GLchar *shader_fsh = (const GLchar*)
//"varying highp vec2 texCoordVarying;"
//"uniform sampler2D SamplerY;"
//"uniform sampler2D SamplerU;"
//"uniform sampler2D SamplerV;"
////"varying highp float v_clipDist;"
//"void main()"
//"{"
////"    if (v_clipDist < 0.0)"
////"        discard;"
//"    mediump vec3 yuv;"
//"    lowp vec3 rgb;"
//"    yuv.x = texture2D(SamplerY, texCoordVarying).r;"
//"    yuv.y = texture2D(SamplerU, texCoordVarying).r - 0.5;"
//"    yuv.z = texture2D(SamplerV, texCoordVarying).r - 0.5;"
//"    rgb = mat3(1,       1,         1,"
//"               0,       -0.39465,  2.03211,"
//"               1.13983, -0.58060,  0) * yuv;"
//"    gl_FragColor = vec4(rgb, 1);"
//"}";


const GLchar *shader_fsh = (const GLchar *)
"varying highp vec2 texCoordVarying;"
"precision mediump float;"
"uniform sampler2D SamplerY;"
"uniform sampler2D SamplerU;"
"uniform mat3 colorConversionMatrix;"
//"varying highp float v_clipDist;"
"void main()"
"{"
"    mediump vec3 yuv;"
"    lowp vec3 rgb;"
"    yuv.x = (texture2D(SamplerY, texCoordVarying).r - (16.0/255.0));"
"    yuv.yz = (texture2D(SamplerU, texCoordVarying).rg - vec2(0.5, 0.5));"
"    rgb = colorConversionMatrix * yuv;"
"    gl_FragColor = vec4(rgb,1);"
"}";


//const GLchar *shader_fsh = (const GLchar*)
//"varying highp vec2 texCoordVarying;"
//"precision mediump float;"
//"uniform sampler2D SamplerY;"
//"uniform sampler2D SamplerU;"//"uniform sampler2D SamplerUV;"
//"uniform mat3 colorConversionMatrix;"
//"void main()"
//"{"
//"    mediump vec3 yuv;"
//"    lowp vec3 rgb;"
//"    // Subtract constants to map the video range start at 0"
//"    yuv.x = (texture2D(SamplerY, texCoordVarying).r - (16.0/255.0));"
//"    yuv.yz = (texture2D(SamplerUV, texCoordVarying).rg - vec2(0.5, 0.5));"
//"    rgb = colorConversionMatrix * yuv;"
//"    gl_FragColor = vec4(rgb,1);"
//"}";



-(BOOL)loadShaders{
    BOOL bExitCode    = NO;
    GLuint vertShader = 0;
    GLuint fragShader = 0;
    
    // Create the shader program.
    self.program = glCreateProgram();
    
    MN_LOG_PROCESS_ERROR([self compileShaderString:&vertShader type:GL_VERTEX_SHADER shaderString:shader_vsh],   "ERROR: Failed to compile vertex shader!\n");
    MN_LOG_PROCESS_ERROR([self compileShaderString:&fragShader type:GL_FRAGMENT_SHADER shaderString:shader_fsh], "ERROR: Failed to compile fragment shader!\n");
    
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

@end
