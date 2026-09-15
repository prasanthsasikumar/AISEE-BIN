//
//  RTKACEQSettingPlaceholder.h
//  RTKAudioConnectSDK
//
//  Created by irene_wang on 2026/1/15.
//  Copyright (c) 2026, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#ifdef ATAudioConnectSDK
#import <ATAudioConnectSDK/RTKACEQSetting.h>
#elif defined(RTKWaveLiteSDK)
#import <RTKWaveLiteSDK/RTKACEQSetting.h>
#else
#import <RTKAudioConnectSDK/RTKACEQSetting.h>
#endif

NS_ASSUME_NONNULL_BEGIN

/// A object that provides more infomation related to load state.
@interface RTKACEQSettingPlaceholder : RTKACEQSetting

@property (nonatomic, readonly) NSUInteger index;

- (instancetype)initWithIndex:(NSUInteger)idx;

/// Set a new human-readable name of this object.
@property (nullable) NSString *name;

/// Return a boolean value that indicate whether parameters is updated by device data.
@property (nonatomic, readonly) BOOL resolved;

/// Return a boolean value indicate whether parameters did modified after the initial retrieve.
@property (nonatomic, readonly) BOOL modified;

/// Parse the parameterData and update this instance's setting parameters.
- (void)setInitialParameterData:(NSData *)parameterData ofSampleRate:(RTKEQSampleRate)sampleRate;

/// Return the sample rate of which when parse the parameter data.
///
/// - Returns `RTKEQSampleRate_unknown` if this object has not parse a paramter data.
@property (nonatomic, readonly) RTKEQSampleRate activeSampleRate;

/// Return a boolean value that indicate whether parameters could be saved by device.
@property (nonatomic) BOOL canBeSaved;

/// Whether the compensation based on hearing loss has applied
@property BOOL hearingLossCompensationApplied;

/// Compares only the gain values of all EQ bands against another setting object.
///
/// This method serves a specific purpose related to the `modified` property's behavior. When a gain value is adjusted, the `modified` property is typically set to `YES`. However, it is possible for a user to make several changes and subsequently revert the gains back to their original state. In such a scenario, the setting is effectively no longer modified.
- (BOOL)isEqualToSetting:(RTKACEQSettingPlaceholder *)setting;

@end

NS_ASSUME_NONNULL_END
