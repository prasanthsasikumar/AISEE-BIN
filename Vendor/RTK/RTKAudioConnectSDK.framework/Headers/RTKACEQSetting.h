//
//  RTKACEQSetting.h
//  RTKAudioConnectSDK
//
//  Created by irene_wang on 2026/1/14.
//  Copyright (c) 2026, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef float RTKEQFrequency;
typedef float RTKEQGain;
typedef float RTKEQQFactor;

/// The possible Sample Rate related to audio signal
typedef NS_ENUM(NSUInteger, RTKEQSampleRate) {
    RTKEQSampleRate_8K,  ///< 8k hz
    RTKEQSampleRate_16K, ///< 16k hz
    RTKEQSampleRate_32K, ///< 32k hz
    RTKEQSampleRate_44K1,    ///< 44.1k hz
    RTKEQSampleRate_48K,     ///< 48k hz
    RTKEQSampleRate_88K2,    ///< 88.2k hz
    RTKEQSampleRate_96K,     ///< 96k hz
    RTKEQSampleRate_192K,    ///< 192k hz
    RTKEQSampleRate_unknown = 0xFF, ///< sample rate is not known
};


/// The possbile Filter type for EQ effect
typedef NS_ENUM(NSUInteger, RTKEQFilter) {
    RTKEQFilter_PEAK,
    RTKEQFilter_ShelvingLP,
    RTKEQFilter_ShelvingHP,
    RTKEQFilter_LowPass,
    RTKEQFilter_HighPass,
    RTKEQFilter_PEAKCOOKBOOK,
    RTKEQFilter_BandPass,
    RTKEQFilter_BandReject,
    RTKEQFilter_AllPass,
    RTKEQFilter_AllEQ,
};


/// An `RTKACEQSetting` object describe parameters of a EQ entry used or to be used on a remote device.
///
/// An `RTKACEQoSetting` is created with zero parameters, which means that all attribute (i.e globalGain, stage frequency gains,stage Q) value is 0. To represet eq settings of a device, the eq para data should be retrieved and pass to -updateSettingWithParameterData:ofSampleRate:. When set eq effect of a remote device, send data returned by -parameterDataOfSampleRate: to a device.
@interface RTKACEQSetting : NSObject <NSSecureCoding, NSCopying> {
    @protected
    NSString *_name;
}


/// Create and return a new `RTKACEQSetting` object which is preset with Flat effect.
+ (instancetype)FlatEQSetting;

/// Create and return a new `RTKACEQSetting` object which is preset with Acoustic effect.
+ (instancetype)AcousticEQSetting;

/// Create and return a new `RTKACEQSetting` object which is preset with Bass Booster effect.
+ (instancetype)BassBoosterEQSetting;

///* Create and return a new `RTKACEQSetting` object which is preset with Bass Reducer effect.
+ (instancetype)BassReducerEQSetting;

/// Create and return a new `RTKACEQSetting` object which is preset with Classical effect.
+ (instancetype)ClassicalEQSetting;

/// Create and return a new `RTKACEQSetting` object which is preset with Hip Hop effect.
+ (instancetype)HipHopEQSetting;

/// Create and return a new `RTKACEQSetting` object which is preset with Jazz effect.
+ (instancetype)JazzEQSetting;

/// Create and return a new `RTKACEQSetting` object which is preset with Rock effect.
+ (instancetype)RockEQSetting;

// MARK: -

/// Return a human-readable name of this `RTKACEQSetting` object.
@property (readonly, nullable) NSString *name;
//@property (readonly) NSString *localizedName;

/// Return an `RTKACEQSetting` instance with the specified name.
///
/// The returned `RTKACEQSetting` instance have a stageCount equal to 10.  Frequency list is set to a default list value, all stage filter is peak, and all Qs are set to 2 and all gains are set to 0.
- (instancetype)initWithName:(nullable NSString *)name;

/// Return an `RTKACEQSetting` instance with the specified name and stage gain list.
///
/// The returned `RTKACEQSetting` instance have a stageCount set to item count of passed in gainNumbers.  Frequency list is set to a default list value, all stage filter is peak, and all Qs are set to 2, each stage gain is set to item value of gainNumbers list.
- (instancetype)initWithName:(NSString *)name gainNumbers:(NSArray <NSNumber*> *)gainNumbers;


/// Return this object's stage count or set to a new value.
///
/// When set, the new value should not large than 10. Setting a new value will reset stage frequency list, gain list, Q list to default value.
@property (nonatomic) NSUInteger stageCount;


/// Return this object's global gain value or set to a new value.
@property (nonatomic) double globalGain;


/// Return frequency value of a stage specified by index.
///
/// - Parameter idx: The index of the stage to return frequency. Should not exceed stageCount.
- (RTKEQFrequency)frequencyAtIndex:(NSUInteger)idx;


/// Set a new frequency value of a stage specified by index.
///
/// - Parameter idx: The index of the stage to set frequency. Should not exceed stageCount.
- (void)setFrequency:(RTKEQFrequency)freq atIndex:(NSUInteger)idx;


/// Return gain value of a stage specified by index.
///
/// - Parameter idx: The index of the stage to return gain. Should not exceed stageCount.
- (RTKEQGain)gainAtIndex:(NSUInteger)idx;


/// Set a new gain value of a stage specified by index.
///
/// - Parameter idx: The index of the stage to set gain. Should not exceed stageCount.
- (void)setGain:(RTKEQGain)gain atIndex:(NSUInteger)idx;


/// Return Q value of a stage specified by index.
///
/// - Parameter idx: The index of the stage to return Q. Should not exceed stageCount.
- (RTKEQQFactor)qAtIndex:(NSUInteger)idx;


/// Set a new Q value of a stage specified by index.
///
/// - Parameter idx: The index of the stage to set Q. Should not exceed stageCount.
- (void)setQ:(RTKEQQFactor)q atIndex:(NSUInteger)idx;


/// Return Filter type of a stage specified by index.
///
/// - Parameter idx: The index of the stage to return type. Should not exceed stageCount.
- (RTKEQFilter)filterAtIndex:(NSUInteger)idx;


/// Set Filter type of a stage specified by index.
///
/// - Parameter idx: The index of the stage to set type. Should not exceed stageCount.
- (void)setFilter:(RTKEQFilter)filter atIndex:(NSUInteger)idx;


/// Reset all setting parameters to default value.
///
/// `StageCount` is reset to 10, `globalGain` is reset to 0, `frequency` list is reset to default list, all gains is reset to 0, Qs are reset to 2, and all stage use PEAK filter.
- (void)reset;

// MARK: -

/// Calculate and return the raw parameter data (EQ data needs to be sent to the dsp) used for send to config remote device.
///
/// - Parameter sampleRate: The sample rate under which calculate data.
- (NSData *)parameterDataOfSampleRate:(RTKEQSampleRate)sampleRate;


/// Calculate and return the extended raw parameter data (EQ data + EQ para info) used for send to config remote device.(EQ 1.0)
///
/// - Parameter sampleRate: Sample rate which the calculated parameter used for.
- (NSData *)parameterDataWithExtraInfoOfSampleRate:(RTKEQSampleRate)sampleRate;


/// Calculate and return the extended raw parameter data (EQ data + EQ para info) used for send to config remote device.(EQ 1.1+)
///
/// - Parameter sampleRate: Sample rate which the calculated parameter used for.
- (NSData *)parameterDataWithNewExtraInfoDataAttachedOfSampleRate:(RTKEQSampleRate)sampleRate;

/// Calculate and return the parameter data (EQ para info) used for send to config remote device.(EQ 1.1+)
///
/// - Parameter sampleRate: Sample rate which the calculated parameter used for.
- (NSData *)parameterInfoOfSampleRate:(RTKEQSampleRate)sampleRate;

// MARK: -

/// Parse the parameterData and update this instance's setting parameters.
///
/// - Parameter parameterData: The raw para data received from remote device.
/// - Parameter sampleRate: The sample rate of the parameterData.
- (void)updateSettingWithParameterData:(NSData *)parameterData ofSampleRate:(RTKEQSampleRate)sampleRate;


/// Parse the parameterData and update this instance's setting parameters.
///
/// - Parameter data: The raw para data received from remote device.
/// - Parameter sampleRate: The sample rate of the parameterData.
- (void)updateSettingWithParameterExtraInfoData:(NSData *)data ofSampleRate:(RTKEQSampleRate)sampleRate;


/// Parse the parameterData and update this instance's setting parameters.
///
/// - Parameter data: The raw para data received from remote device.
/// - Parameter sampleRate: The sample rate of the parameterData.
- (void)updateSettingWithNewParameterExtraInfoData:(NSData *)data ofSampleRate:(RTKEQSampleRate)sampleRate;

// MARK: - EQ 3.0+

/// Serializes the current EQ settings into a raw data packet for transmission.
///
/// This method generates a **V2 format** packet consisting of a V2 Header and V2 Parameters.
/// The data size typically corresponds to ~10 bytes per stage.
///
/// - Returns: The serialized `NSData` object ready to be sent to the remote device.
- (NSData *)composeToEQParametersData;


/// Updates the instance's settings by deserializing the provided raw data.
///
/// This method expects the data to be in the **V2 format** (V2 Header + V2 Parameters).
///
/// - Parameter data: The raw parameter data received from the remote device.
- (void)updateSettingWithEQParametersData:(NSData *)data;


/// Serializes the EQ settings into a backward-compatible (Legacy) data packet.
///
/// This method encapsulates V1 parameters within a V2 structure to support legacy requirements.
/// **Structure:** `[V2 Header] + [V1 Header] + [V1 Parameters]`
/// The data size typically corresponds to ~20 bytes per stage.
///
/// - Parameter sampleRate: The specific sample rate required for the legacy V1 parameter calculation.
/// - Returns: The serialized `NSData` object containing the encapsulated legacy payload.
- (NSData *)composeToLegacyEQParametersDataWithSampleRate:(RTKEQSampleRate)sampleRate;

/// Updates the EQ settings by parsing the provided data, with support for both legacy and V2 formats.
///
/// This method inspects the **Version** field within the V2 Header:
/// 1. If the version indicates a modern V2 format, it internally redirects to `updateSettingWithEQParametersData:`.
/// 2. If the version indicates a legacy format, it parses the nested `[V1 Header] + [V1 Parameters]` structure using the provided sample rate.
///
/// - Parameters:
///   - data: The raw parameter data received from the remote device.
///   - sampleRate: The sample rate used to interpret the legacy V1 parameters (ignored if data is standard V2).
- (void)updateSettingWithLegacyEQParametersData:(NSData *)data andSampleRate:(RTKEQSampleRate)sampleRate;

@end


NS_ASSUME_NONNULL_END
