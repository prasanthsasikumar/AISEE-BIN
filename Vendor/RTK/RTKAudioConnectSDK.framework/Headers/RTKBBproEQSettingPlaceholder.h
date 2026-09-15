//
//  RTKBBproEQSettingPlaceholder.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2019/7/8.
//  Copyright (c) 2019, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#ifdef ATAudioConnectSDK
#import <ATAudioConnectSDK/RTKACEQSettingPlaceholder.h>
#import <ATAudioConnectSDK/RTKBBproEQSetting.h>
#import <ATAudioConnectSDK/RTKMacros.h>
#elif defined(RTKWaveLiteSDK)
#import <RTKWaveLiteSDK/RTKACEQSettingPlaceholder.h>
#import <RTKWaveLiteSDK/RTKBBproEQSetting.h>
#import <RTKWaveLiteSDK/RTKMacros.h>
#else
#import <RTKAudioConnectSDK/RTKACEQSettingPlaceholder.h>
#import <RTKAudioConnectSDK/RTKBBproEQSetting.h>
#import <RTKAudioConnectSDK/RTKMacros.h>
#endif

NS_ASSUME_NONNULL_BEGIN

RTK_REDIRECT(RTKACEQSettingPlaceholder)
@interface RTKBBproEQSettingPlaceholder: RTKACEQSettingPlaceholder

@end


@interface RTKACEQSettingPlaceholder (Deprecated)

@property (nonatomic, readonly) BOOL determined RTK_REDIRECT(resolved);

- (void)setInitialParameterData:(NSData *)parameterData RTK_REDIRECT(setInitialParameterData:ofSampleRate:);


@property (nonatomic, readonly) RTKBBproSampleRate realizationSampleRate RTK_REDIRECT(activeSampleRate);

- (void)setInitialParameterData:(NSData *)parameterData
             ofSampleRateLegacy:(RTKBBproSampleRate)sampleRate
    RTK_REDIRECT('setInitialParameterData:ofSampleRate:' with 'RTKEQSampleRate')
    NS_SWIFT_NAME(setInitialParameterData(_:ofSampleRate:));

- (BOOL)isEqualToSettingLegacy:(RTKBBproEQSettingPlaceholder *)setting
    RTK_REDIRECT('isEqualToSetting:' with 'RTKACEQSettingPlaceholder')
    NS_SWIFT_NAME(isEqualToSetting(_:));

@end




NS_ASSUME_NONNULL_END
