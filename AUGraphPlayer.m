//
//  AUGraphPlayer.m
//  VSSMobile
//
//  Created by lancelet on 2017/7/26.
//  Copyright © 2017年 Fun. All rights reserved.
//

#import "AUGraphPlayer.h"
#import <AVFoundation/AVAudioSession.h>
#import <AudioToolbox/AUGraph.h>

@interface AUGraphPlayer (){

    AUGraph     m_auGraph;
    AudioUnit   m_auRemoteUnit;
    
    char*        m_pPlayerBuffer;
    unsigned int m_nPlayerBufLen;
    unsigned int m_nPlayerDataLen;
    NSLock*      m_lockPlayer;
    
    int         m_nSample;
    
}

@end


OSStatus InputCallback(void *inRefCon,
                       AudioUnitRenderActionFlags *ioActionFlags,
                       const AudioTimeStamp *inTimeStamp,
                       UInt32 inBusNumber,
                       UInt32 inNumberFrames,
                       AudioBufferList *ioData)
{
    AudioBuffer buffer = ioData->mBuffers[0];
    
    AUGraphPlayer* player = (__bridge AUGraphPlayer*)inRefCon;
    [player onInputCallback:buffer.mData len:buffer.mDataByteSize];
    
    return noErr;
}

@implementation AUGraphPlayer

-(void) initPlayer:(int)sample
{
    m_nSample = sample;
    
    m_lockPlayer = [[NSLock alloc] init];
    m_nPlayerBufLen = m_nSample * 2 * 2;       //保存2秒
    m_pPlayerBuffer = (char*)malloc(m_nPlayerBufLen);
    m_nPlayerDataLen = 0;
    
    AVAudioSession *session = [AVAudioSession sharedInstance];
//    [session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error:nil];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
//    [session setMode:AVAudioSessionModeVoiceChat error:nil];
//    [session setCategory:AVAudioSessionCategoryPlayAndRecord mode:AVAudioSessionModeVoiceChat options:AVAudioSessionCategoryOptionDefaultToSpeaker error:nil];
//    [session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error:nil];
    //[session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
    [session setActive:YES error:nil];
    
    [self createAUGraph];
    [self setupRemoteIOUnit];
    [self startAUGraph];
    
    //必须在最后设置才有效
    if ([self hasHeadset]) {
        [session overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];
    } else {
        [session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
    }
    
}

-(void) uninitPlayer
{
    AUGraphStop(m_auGraph);
    AUGraphUninitialize(m_auGraph);
    
    AUGraphClose(m_auGraph);
    DisposeAUGraph(m_auGraph);
    
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategorySoloAmbient error:nil];
    [session setActive:YES error:nil];
    
    free(m_pPlayerBuffer);
}

-(void) sendData:(const void*)data len:(int)len
{
    [m_lockPlayer lock];
    if ((m_nPlayerDataLen + len) > m_nPlayerBufLen)
    {
        [m_lockPlayer unlock];
        return;
    }
    memcpy(m_pPlayerBuffer + m_nPlayerDataLen, data, len);
    m_nPlayerDataLen += len;
    [m_lockPlayer unlock];
}

-(void)onInputCallback:(void*)data len:(int)len
{
    [m_lockPlayer lock];
    if (m_nPlayerDataLen >= len)
    {
        memcpy(data, m_pPlayerBuffer, len);
        memmove(m_pPlayerBuffer, m_pPlayerBuffer + len, m_nPlayerDataLen - len);
        m_nPlayerDataLen -= len;
    }
    else
    {
        memset(data, 0, len);
    }
    [m_lockPlayer unlock];
}

-(void)setupRemoteIOUnit{
    
    OSStatus status = 0;
    //Open input of the bus 1(input mic)
    UInt32 enableFlag = 1;
    status = AudioUnitSetProperty(m_auRemoteUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input,
                                  1,
                                  &enableFlag,
                                  sizeof(enableFlag));
    
    AudioStreamBasicDescription streamFormat;
    streamFormat.mFormatID = kAudioFormatLinearPCM;
    streamFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    streamFormat.mSampleRate = m_nSample;
    streamFormat.mFramesPerPacket = 1;
    streamFormat.mBytesPerFrame = 2;
    streamFormat.mBytesPerPacket = 2;
    streamFormat.mBitsPerChannel = 16;
    streamFormat.mChannelsPerFrame = 1;
    status = AudioUnitSetProperty(m_auRemoteUnit,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Input,
                         0,
                         &streamFormat,
                         sizeof(streamFormat));
    
    UInt32 echoCancellation = 0;
    status = AudioUnitSetProperty(m_auRemoteUnit,
                         kAUVoiceIOProperty_BypassVoiceProcessing,
                         kAudioUnitScope_Global,
                         0,
                         &echoCancellation,
                         sizeof(echoCancellation));
    
    AURenderCallbackStruct input;
    input.inputProc = InputCallback;
    input.inputProcRefCon = (__bridge void*)self;
    status = AudioUnitSetProperty(m_auRemoteUnit,
                         kAudioUnitProperty_SetRenderCallback,
                         kAudioUnitScope_Global,
                         0,//input mic
                         &input,
                         sizeof(input));
    
    status = 0;
}

-(void)createAUGraph{
    OSStatus status = 0;
    
    //Create graph
    status = NewAUGraph(&m_auGraph);
    
    //Create nodes and add to the graph
    //Set up a RemoteIO for synchronously playback
    AudioComponentDescription inputcd = {0};
    inputcd.componentType = kAudioUnitType_Output;
    //inputcd.componentSubType = kAudioUnitSubType_RemoteIO;
    //we can access the system's echo cancellation by using kAudioUnitSubType_VoiceProcessingIO subtype
    inputcd.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    inputcd.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    AUNode remoteIONode;
    //Add node to the graph
    status = AUGraphAddNode(m_auGraph, &inputcd, &remoteIONode);
    
    //Open the graph
    status = AUGraphOpen(m_auGraph);
    
    //Get reference to the node
    status = AUGraphNodeInfo(m_auGraph, remoteIONode, &inputcd, &m_auRemoteUnit);
    
    //
    status = 0;
}

-(void)startAUGraph
{
    AUGraphInitialize(m_auGraph);
    AUGraphUpdate(m_auGraph, nil);
    AUGraphStart(m_auGraph);
}

- (BOOL)hasHeadset {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    AVAudioSessionRouteDescription *currentRoute = [audioSession currentRoute];
    
    for (AVAudioSessionPortDescription *output in currentRoute.outputs) {
        if ([[output portType] isEqualToString:AVAudioSessionPortHeadphones]) {
            return YES;
        }
    }
    return NO;
}

@end
