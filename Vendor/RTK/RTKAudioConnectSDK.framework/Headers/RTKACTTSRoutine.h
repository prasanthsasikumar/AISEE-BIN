//
//  RTKACTTSRoutine.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2021/10/27.
//  Copyright (c) 2021, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#ifdef ATAudioConnectSDK
#import <ATAudioConnectSDK/RTKACBasicRoutine.h>
#import <ATAUdioConnectSDK/RTKTTSSynthesizing.h>
#elif defined(RTKWaveLiteSDK)
#import <RTKWaveLiteSDK/RTKACBasicRoutine.h>
#import <RTKWaveLiteSDK/RTKTTSSynthesizing.h>
#else
#import <RTKAudioConnectSDK/RTKACBasicRoutine.h>
#import <RTKAUdioConnectSDK/RTKTTSSynthesizing.h>
#endif

NS_ASSUME_NONNULL_BEGIN

/// A conrete routine that provides functionality to access and support In-Call speech.
///
/// See <doc:CallerSpeech> to get more about Caller speech.
@interface RTKACTTSRoutine : RTKACRoutine

/// The basic routine object this routine relies on.
@property RTKACBasicRoutine *basicRoutine;

/// An object that provides TTS synthesizing service.
@property (nullable) id <RTKTTSSynthesizing> TTSSynthesizer;

/// Decalre that TTS is available on this app to the coresponding device.
///
/// - Parameter handler: A block be called when this task completes.
- (void)declareTTSAvailabilityWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;

@end

NS_ASSUME_NONNULL_END
