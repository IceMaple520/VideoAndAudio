//
//  H264HwDecoder.m
//  MobileLogic
//
//  Created by ZB on 2018/1/2.
//  Copyright © 2018年 lancelet. All rights reserved.
//

#import "H264HwDecoder.h"
#import "sys/utsname.h"
@interface H264HwDecoder()
{
    uint8_t *_sps;
    unsigned long _spsSize;
    uint8_t *_pps;
    size_t _ppsSize;
    VTDecompressionSessionRef _deocderSession;
    CMVideoFormatDescriptionRef _decoderFormatDescription;
    CVImageBufferRef _imageBuffer;
    int _width;
    int _hight;
    int _did;
    int _channel;
    int _framesize;
}
@end
@implementation H264HwDecoder
-(id)init
{
    self = [super init];
    if (self) {
        self.m_lock = [[NSLock alloc] init];
    }
    return self;
}


//解码回调函数
static void didDecompress( void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef pixelBuffer, CMTime presentationTimeStamp, CMTime presentationDuration ){
    HW_PARAM *outputParam = (HW_PARAM *)sourceFrameRefCon;
//    CVPixelBufferRetain(pixelBuffer);
    H264HwDecoder *decoder = (__bridge H264HwDecoder *)decompressionOutputRefCon;
    if (decoder.delegate!=nil)
    {
        [decoder.delegate displayDecodedFrame:pixelBuffer withParam:outputParam];
    }
}

-(BOOL)decodeWithData:(NSData *)h264Data width:(int)width hight:(int)hight param:(HW_PARAM *)param
{
    [_m_lock lock];
    int net = [self decodeNalu:(uint8_t *)[h264Data bytes] withSize:(uint32_t)h264Data.length width:width hight:hight param:param];
    [_m_lock unlock];
    return net;
}

- (void)displayDecodedFrame:(CVImageBufferRef )imageBuffer
{
    _imageBuffer = imageBuffer;
}

-(void)uninit
{
    [_m_lock lock];
    [self releaseBuffer];
    if (_sps) {
        free(_sps);
        _sps = NULL;
    }
    if (_pps) {
        free(_pps);
        _pps = NULL;
    }
    [_m_lock unlock];
}

-(BOOL)isUsedHwDecoder
{
    NSString *phoneModel = [self getDeviceName];
    NSLog(@"phoneModel:%@",phoneModel);
    if (iOS8 && ![phoneModel isEqualToString:@"iPhone 4s"] && ![phoneModel isEqualToString:@"iPhone 5"] && ![phoneModel isEqualToString:@"iPhone 5c"]) {
        return YES;
    }
    return NO;
}

-(void)releaseBuffer
{
    if (_imageBuffer) {
        CVPixelBufferRelease(_imageBuffer);
        _imageBuffer = nil;
    }
    if (_deocderSession)
    {
        VTDecompressionSessionInvalidate(_deocderSession);
        CFRelease(_deocderSession);
        _deocderSession = nil;
    }
    if (_decoderFormatDescription) {
        CFRelease(_decoderFormatDescription);
        _decoderFormatDescription = nil;
    }
}

-(void)dealloc
{
    [self releaseBuffer];
}

-(BOOL)initH265DecoderWithWidth:(int)width hight:(int)hight param:(HW_PARAM *)param{
    if(_deocderSession && _width == width && _hight == hight && _did == param->did && _channel == param->channel) {
        return YES;
    }
    
    _width = width;
    _hight = hight;
    _did = param->did;
    _channel = param->channel;
    [self releaseBuffer];
    const uint8_t* const parameterSetPointers[2] = { _sps, _pps };
    const size_t parameterSetSizes[2] = { _spsSize, _ppsSize };
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                          2, //param count
                                                                          parameterSetPointers,
                                                                          parameterSetSizes,
                                                                          4, //nal start code size
                                                                          &_decoderFormatDescription);
    if(status == noErr) {
        NSDictionary* destinationPixelBufferAttributes = @{
                                                           (id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8Planar],
                                                           //硬解必须是 kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                                                           //                                                           或者是kCVPixelFormatType_420YpCbCr8Planar
                                                           //因为iOS是  nv12  其他是nv21
                                                           (id)kCVPixelBufferWidthKey : [NSNumber numberWithInt:width],
                                                           (id)kCVPixelBufferHeightKey : [NSNumber numberWithInt:hight],
                                                           //这里款高和编码反的
                                                           (id)kCVPixelBufferOpenGLCompatibilityKey : [NSNumber numberWithBool:YES]
                                                           };
        
        
        VTDecompressionOutputCallbackRecord callBackRecord;
        callBackRecord.decompressionOutputCallback = didDecompress;
        callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
        status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                              _decoderFormatDescription,
                                              NULL,
                                              (__bridge CFDictionaryRef)destinationPixelBufferAttributes,
                                              &callBackRecord,
                                              &_deocderSession);
        VTSessionSetProperty(_deocderSession, kVTDecompressionPropertyKey_ThreadCount, (__bridge CFTypeRef)[NSNumber numberWithInt:1]);
        VTSessionSetProperty(_deocderSession, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
    } else {
        NSLog(@"IOS8VT: reset decoder session failed status=%d", (int)status);
    }
    
    return YES;
}

-(BOOL)initH264DecoderWithWidth:(int)width hight:(int)hight param:(HW_PARAM *)param{
    if(_deocderSession && _width == width && _hight == hight && _did == param->did && _channel == param->channel) {
        return YES;
    }
   
    _width = width;
    _hight = hight;
    _did = param->did;
    _channel = param->channel;
    [self releaseBuffer];
    const uint8_t* const parameterSetPointers[2] = { _sps, _pps };
    const size_t parameterSetSizes[2] = { _spsSize, _ppsSize };
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                          2, //param count
                                                                          parameterSetPointers,
                                                                          parameterSetSizes,
                                                                          4, //nal start code size
                                                                          &_decoderFormatDescription);
    
    if(status == noErr) {
        NSDictionary* destinationPixelBufferAttributes = @{
                                                           (id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8Planar],
                                                           //硬解必须是 kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                                                           //                                                           或者是kCVPixelFormatType_420YpCbCr8Planar
                                                           //因为iOS是  nv12  其他是nv21
                                                           (id)kCVPixelBufferWidthKey : [NSNumber numberWithInt:width],
                                                           (id)kCVPixelBufferHeightKey : [NSNumber numberWithInt:hight],
                                                           //这里款高和编码反的
                                                           (id)kCVPixelBufferOpenGLCompatibilityKey : [NSNumber numberWithBool:YES]
                                                           };
        
        
        VTDecompressionOutputCallbackRecord callBackRecord;
        callBackRecord.decompressionOutputCallback = didDecompress;
        callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
        status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                              _decoderFormatDescription,
                                              NULL,
                                              (__bridge CFDictionaryRef)destinationPixelBufferAttributes,
                                              &callBackRecord,
                                              &_deocderSession);
        VTSessionSetProperty(_deocderSession, kVTDecompressionPropertyKey_ThreadCount, (__bridge CFTypeRef)[NSNumber numberWithInt:1]);
        VTSessionSetProperty(_deocderSession, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
    } else {
        NSLog(@"IOS8VT: reset decoder session failed status=%d", (int)status);
    }
    
    return YES;
}

-(HW_PARAM *)decode:(uint8_t *)frame withSize:(uint32_t)frameSize param:(HW_PARAM *)param
{
    HW_PARAM * outputPixelBuffer = param;
    
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status  = CMBlockBufferCreateWithMemoryBlock(NULL,
                                                          (void *)frame,
                                                          frameSize,
                                                          kCFAllocatorNull,
                                                          NULL,
                                                          0,
                                                          frameSize,
                                                          FALSE,
                                                          &blockBuffer);
    if(status == kCMBlockBufferNoErr) {
        CMSampleBufferRef sampleBuffer = NULL;
        const size_t sampleSizeArray[] = {frameSize};
        status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                           blockBuffer,
                                           _decoderFormatDescription ,
                                           1, 0, NULL, 1, sampleSizeArray,
                                           &sampleBuffer);
        if (status == kCMBlockBufferNoErr && sampleBuffer) {
            VTDecodeFrameFlags flags = 0;
            VTDecodeInfoFlags flagOut = 0;
            OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(_deocderSession,
                                                                      sampleBuffer,
                                                                      flags,
                                                                      outputPixelBuffer,
                                                                      &flagOut);
            
            if(decodeStatus == kVTInvalidSessionErr) {
                NSLog(@"IOS8VT: Invalid session, reset decoder session");
            } else if(decodeStatus == kVTVideoDecoderBadDataErr) {
                NSLog(@"IOS8VT: decode failed status=%d(Bad data)", (int)decodeStatus);
            } else if(decodeStatus != noErr) {
                NSLog(@"IOS8VT: decode failed status=%d", (int)decodeStatus);
            }
            CFRelease(sampleBuffer);
        }
        CFRelease(blockBuffer);
    }
    
    return outputPixelBuffer;
}
static const uint8_t *avc_find_startcode_internal(const uint8_t *p, const uint8_t *end)
{
    const uint8_t *a = p + 4 - ((intptr_t)p & 3);
    
    for (end -= 3; p < a && p < end; p++) {
        if (p[0] == 0 && p[1] == 0 && p[2] == 1)
            return p;
    }
    
    for (end -= 3; p < end; p += 4) {
        uint32_t x = *(const uint32_t*)p;
        //      if ((x - 0x01000100) & (~x) & 0x80008000) // little endian
        //      if ((x - 0x00010001) & (~x) & 0x00800080) // big endian
        if ((x - 0x01010101) & (~x) & 0x80808080) { // generic
            if (p[1] == 0) {
                if (p[0] == 0 && p[2] == 1)
                    return p;
                if (p[2] == 0 && p[3] == 1)
                    return p+1;
            }
            if (p[3] == 0) {
                if (p[2] == 0 && p[4] == 1)
                    return p+2;
                if (p[4] == 0 && p[5] == 1)
                    return p+3;
            }
        }
    }
    
    for (end += 3; p < end; p++) {
        if (p[0] == 0 && p[1] == 0 && p[2] == 1)
            return p;
    }
    
    return end + 3;
}
const uint8_t *avc_find_startcode(const uint8_t *p, const uint8_t *end)
{
    const uint8_t *out= avc_find_startcode_internal(p, end);
    if(p<out && out<end && !out[-1]) out--;
    return out;
}

-(BOOL) decodeNalu:(uint8_t *)frame withSize:(uint32_t)frameSize width:(int)width hight:(int)hight param:(HW_PARAM *)param
{
    //    NSLog(@">>>>>>>>>>开始解码");
    if (frame == NULL || frameSize == 0)
        return NO;
    
    uint8_t *_buf_out; // 原始接收的重组数据包

    _buf_out = (uint8_t*)malloc(frameSize + 128);    
    int size = frameSize;
    const uint8_t *p = frame;
    const uint8_t *end = p + size;
    const uint8_t *nal_start, *nal_end;
    int nal_len, nalu_type;
    
    size = 0;
    nal_start = avc_find_startcode(p, end);
    while (![[NSThread currentThread] isCancelled]) {
        while (![[NSThread currentThread] isCancelled] && nal_start < end && !*(nal_start++));
        if (nal_start == end)
            break;
        
        nal_end = avc_find_startcode(nal_start, end);
        nal_len = (int)(nal_end - nal_start);
        
        nalu_type = nal_start[0] & 0x1f;
        if (nalu_type == 0x07) {
            if (_sps == NULL || _width != width || _hight != hight || _did != param->did || _channel != param->channel) {
                _spsSize = nal_len;
                _sps = (uint8_t*)malloc(_spsSize);
                memcpy(_sps, nal_start, _spsSize);
            }
        }
        else if (nalu_type == 0x08) {
            if (_pps == NULL || _width != width || _hight != hight || _did!= param->did || _channel != param->channel) {
                _ppsSize = nal_len;
                _pps = (uint8_t*)malloc(_ppsSize);
                memcpy(_pps, nal_start, _ppsSize);
            }
        }
        else {
            _buf_out[size + 0] = (uint8_t)(nal_len >> 24);
            _buf_out[size + 1] = (uint8_t)(nal_len >> 16);
            _buf_out[size + 2] = (uint8_t)(nal_len >> 8 );
            _buf_out[size + 3] = (uint8_t)(nal_len);
            
            memcpy(_buf_out + 4 + size, nal_start, nal_len);
            size += 4 + nal_len;
        }
        
        nal_start = nal_end;
    }
    
    if ([self initH264DecoderWithWidth:width hight:hight param:param]) {
        [self decode:_buf_out withSize:size param:param];
    }
    
    free(_buf_out);
    
    return size > 0 ? YES : NO;

    
    
    
//    int nalu_type = (frame[4] & 0x1F);
//    CVPixelBufferRef pixelBuffer = NULL;
//    uint32_t nalSize = (uint32_t)(frameSize - 4);
//    uint8_t *pNalSize = (uint8_t*)(&nalSize);
//    frame[0] = *(pNalSize + 3);
//    frame[1] = *(pNalSize + 2);
//    frame[2] = *(pNalSize + 1);
//    frame[3] = *(pNalSize);
//    //传输的时候。关键帧不能丢数据 否则绿屏   B/P可以丢  这样会卡顿
//    switch (nalu_type)
//    {
//        case 0x05:
//            //           NSLog(@"nalu_type:%d Nal type is IDR frame",nalu_type);  //关键帧
//            if([self initH264DecoderWithWidth:width hight:hight])
//            {
//                pixelBuffer = [self decode:frame withSize:frameSize];
//            }
//            break;
//        case 0x07:
//            //           NSLog(@"nalu_type:%d Nal type is SPS",nalu_type);   //sps
//            _spsSize = frameSize - 4;
//            _sps = malloc(_spsSize);
//            memcpy(_sps, &frame[4], _spsSize);
//            break;
//        case 0x08:
//        {
//            //            NSLog(@"nalu_type:%d Nal type is PPS",nalu_type);   //pps
//            _ppsSize = frameSize - 4;
//            _pps = malloc(_ppsSize);
//            memcpy(_pps, &frame[4], _ppsSize);
//            break;
//        }
//        default:
//        {
//            //            NSLog(@"Nal type is B/P frame");//其他帧
//            if([self initH264DecoderWithWidth:width hight:hight])
//            {
//                pixelBuffer = [self decode:frame withSize:frameSize];
//            }
//            break;
//        }
//    }
}

// 获取设备型号然后手动转化为对应名称
- (NSString *)getDeviceName
{
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *deviceString = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    
    if ([deviceString isEqualToString:@"iPhone3,1"])    return @"iPhone 4";
    if ([deviceString isEqualToString:@"iPhone3,2"])    return @"iPhone 4";
    if ([deviceString isEqualToString:@"iPhone3,3"])    return @"iPhone 4";
    if ([deviceString isEqualToString:@"iPhone4,1"])    return @"iPhone 4s";
    if ([deviceString isEqualToString:@"iPhone5,1"])    return @"iPhone 5";
    if ([deviceString isEqualToString:@"iPhone5,2"])    return @"iPhone 5";
    if ([deviceString isEqualToString:@"iPhone5,3"])    return @"iPhone 5c";
    if ([deviceString isEqualToString:@"iPhone5,4"])    return @"iPhone 5c";
    if ([deviceString isEqualToString:@"iPhone6,1"])    return @"iPhone 5s";
    if ([deviceString isEqualToString:@"iPhone6,2"])    return @"iPhone 5s";
    if ([deviceString isEqualToString:@"iPhone7,1"])    return @"iPhone 6 Plus";
    if ([deviceString isEqualToString:@"iPhone7,2"])    return @"iPhone 6";
    if ([deviceString isEqualToString:@"iPhone8,1"])    return @"iPhone 6s";
    if ([deviceString isEqualToString:@"iPhone8,2"])    return @"iPhone 6s Plus";
    if ([deviceString isEqualToString:@"iPhone8,4"])    return @"iPhone SE";
    
    if ([deviceString isEqualToString:@"iPod1,1"])      return @"iPod Touch 1G";
    if ([deviceString isEqualToString:@"iPod2,1"])      return @"iPod Touch 2G";
    if ([deviceString isEqualToString:@"iPod3,1"])      return @"iPod Touch 3G";
    if ([deviceString isEqualToString:@"iPod4,1"])      return @"iPod Touch 4G";
    if ([deviceString isEqualToString:@"iPod5,1"])      return @"iPod Touch (5 Gen)";
    
    if ([deviceString isEqualToString:@"iPad1,1"])      return @"iPad";
    if ([deviceString isEqualToString:@"iPad1,2"])      return @"iPad 3G";
    if ([deviceString isEqualToString:@"iPad2,1"])      return @"iPad 2 (WiFi)";
    if ([deviceString isEqualToString:@"iPad2,2"])      return @"iPad 2";
    if ([deviceString isEqualToString:@"iPad2,3"])      return @"iPad 2 (CDMA)";
    if ([deviceString isEqualToString:@"iPad2,4"])      return @"iPad 2";
    if ([deviceString isEqualToString:@"iPad2,5"])      return @"iPad Mini (WiFi)";
    if ([deviceString isEqualToString:@"iPad2,6"])      return @"iPad Mini";
    if ([deviceString isEqualToString:@"iPad2,7"])      return @"iPad Mini (GSM+CDMA)";
    if ([deviceString isEqualToString:@"iPad3,1"])      return @"iPad 3 (WiFi)";
    if ([deviceString isEqualToString:@"iPad3,2"])      return @"iPad 3 (GSM+CDMA)";
    if ([deviceString isEqualToString:@"iPad3,3"])      return @"iPad 3";
    if ([deviceString isEqualToString:@"iPad3,4"])      return @"iPad 4 (WiFi)";
    if ([deviceString isEqualToString:@"iPad3,5"])      return @"iPad 4";
    if ([deviceString isEqualToString:@"iPad3,6"])      return @"iPad 4 (GSM+CDMA)";
    if ([deviceString isEqualToString:@"iPad4,1"])      return @"iPad Air (WiFi)";
    if ([deviceString isEqualToString:@"iPad4,2"])      return @"iPad Air (Cellular)";
    if ([deviceString isEqualToString:@"iPad4,4"])      return @"iPad Mini 2 (WiFi)";
    if ([deviceString isEqualToString:@"iPad4,5"])      return @"iPad Mini 2 (Cellular)";
    if ([deviceString isEqualToString:@"iPad4,6"])      return @"iPad Mini 2";
    if ([deviceString isEqualToString:@"iPad4,7"])      return @"iPad Mini 3";
    if ([deviceString isEqualToString:@"iPad4,8"])      return @"iPad Mini 3";
    if ([deviceString isEqualToString:@"iPad4,9"])      return @"iPad Mini 3";
    if ([deviceString isEqualToString:@"iPad5,1"])      return @"iPad Mini 4 (WiFi)";
    if ([deviceString isEqualToString:@"iPad5,2"])      return @"iPad Mini 4 (LTE)";
    if ([deviceString isEqualToString:@"iPad5,3"])      return @"iPad Air 2";
    if ([deviceString isEqualToString:@"iPad5,4"])      return @"iPad Air 2";
    if ([deviceString isEqualToString:@"iPad6,3"])      return @"iPad Pro 9.7";
    if ([deviceString isEqualToString:@"iPad6,4"])      return @"iPad Pro 9.7";
    if ([deviceString isEqualToString:@"iPad6,7"])      return @"iPad Pro 12.9";
    if ([deviceString isEqualToString:@"iPad6,8"])      return @"iPad Pro 12.9";
    
    if ([deviceString isEqualToString:@"i386"])         return @"Simulator";
    if ([deviceString isEqualToString:@"x86_64"])       return @"Simulator";
    
    return deviceString;
}

@end
