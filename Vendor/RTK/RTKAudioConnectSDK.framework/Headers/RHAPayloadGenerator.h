//
//  RHAPayloadGenerator.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2023/2/22.
//  Copyright (c) 2023, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <Foundation/Foundation.h>
#ifdef ATAudioConnectSDK
#import <ATAudioConnectSDK/RTKHATypes.h>
#import <ATAudioConnectSDK/RTKACEQSetting.h>
#import <ATAudioConnectSDK/RTKHATypes.h>
#elif defined(RTKWaveLiteSDK)
#import <RTKWaveLiteSDK/RTKHATypes.h>
#import <RTKWaveLiteSDK/RTKACEQSetting.h>
#import <RTKWaveLiteSDK/RTKHATypes.h>
#else
#import <RTKAudioConnectSDK/RTKHATypes.h>
#import <RTKAudioConnectSDK/RTKBBproEQSetting.h>
#import <RTKAudioConnectSDK/RTKACEQSetting.h>
#import <RTKAudioConnectSDK/RTKHATypes.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@class RTKHAWdrc2Param;

@interface RTKAPTState: NSObject

@property (readonly) HABalanceType balance;

/// Returns the number object that indicates solved APT volume of left bud.
@property (readonly) HAVolumeLevel leftBudAPTVolume;

/// Returns the number object that indicates solved APT volume of right bud.
@property (readonly) HAVolumeLevel rightBudAPTVolume;

/// Returns the number object that indicates solved APT gain levels of left bud.
@property (readonly) NSArray <NSNumber*> *leftAPTGainLevels;

/// Returns the number object that indicates solved APT gain levels of right bud.
@property (readonly) NSArray <NSNumber*> *rightAPTGainLevels;


/// Returns the number object that indicates solved NR enable status.
@property (readonly) BOOL NREnabled;

/// Returns the number object that indicates solved NR level status.
@property (readonly) NSUInteger NRLevel;

/// Returns the number object that indicates solved NR mode status.
@property (readonly) NSUInteger NRMode;

@property (readonly) NSUInteger NRVersion;

@property (readonly) NSUInteger NRStereoMode;

@property (readonly) NSUInteger NRModel;

/// Returns the number object that indicates solved OVP enable status.
@property (readonly) BOOL OVPEnabled;

/// Returns the number object that indicates solved OVP level status.
@property (readonly) NSUInteger OVPLevel;

/// Returns the number object that indicates solved Beamforming enable status.
@property (readonly) BOOL beamformingEnabled;

/// Returns the number object that indicates solved dehowling enable status.
@property (readonly) BOOL dehowlingEnabled;

/// Returns the number object that indicates solved dehowling level status.
@property (readonly) NSUInteger dehowlingLevel;

/// Returns the number object that indicates solved WNR enable status.
@property (readonly) BOOL WNREnabled;

/// Returns the number object that indicates solved INR enable status.
@property (readonly) BOOL INREnabled;

/// Returns the number object that indicates solved INR level status.
@property (readonly) NSUInteger INRIntensity;

/// Returns the number object that indicates solved INR level status.
@property (readonly) NSUInteger INRSensitivity;

/// Returns a boolean value that indicates if Real Natural Sound(RNS) is enabled.
@property (readonly) BOOL RNSEnabled;

/// Returns the dbSPL output DRC state.
@property (readonly) RTKHAdbSPLDRCState dbSPLOutputDRC;

/// Returns the output DRC state.
@property (readonly) RTKHADRCState outputDRC;

/// Returns the object that indicates the beamforming mode.
@property (readonly) RTKHABeamformingMode BeamformingMode;

/// Returns the object that indicates the beamforming width.
@property (readonly) NSUInteger BeamformingWidth;

/// Returns the object that indicates the beamforming suppression.
@property (readonly) RTKHABeamformingSuppression BeamformingSuppression;

/// Returns the object that indicates the own voice process status.
@property (readonly) BOOL OwnVoiceProcessEnabled;

/// Returns the object that indicates the own voice process suppression.
@property (readonly) NSUInteger OwnVoiceProcessSuppression;

@property (readonly) BOOL OwnVoiceProcessSuppressionUseDb;

@end

/// An object which saves HA states.
///
/// @discussion This object is needed when an RHAPayloadGenerator calculates the payload.
@interface RHASettingContext : NSObject

/// Initializes using a piece of data which is received from a device.
- (instancetype)initWithToolData:(NSData *)data;

- (instancetype)initWithToolDataSpaceSize:(NSUInteger)size eqStageCount:(NSUInteger)count;

/// Returns the parsed state information.
@property (readonly) RTKAPTState *state;

- (void)updateWithBalance:(HABalanceType)balance
          volumeOfLeftBud:(HAVolumeLevel)LVolume
         volumeOfRightBud:(HAVolumeLevel)RVolume;

- (void)updateWithGainStageCount:(NSUInteger)count
             gainLevelsOfLeftBud:(HAGainLevel*)lGainLevels
            gainLevelsOfRightBud:(HAGainLevel*)rGainLevels;

- (void)updateWithNoiceReductionEnable:(BOOL)enabled
                                  mode:(RTKHANRMode)mode
                         aggresiveness:(HAGainLevel)level;

- (void)updateWithNoiseReductionEnable:(BOOL)enabled
                           mode:(RTKHANRMode)mode
                         aggressiveness:(NSUInteger)level
                          NRStereoMode:(RTKHANRStereoMode)stereoMode
                               NRModel:(RTKHANRModel)model;

- (void)updateWithOVPEnable:(BOOL)enabled aggresiveness:(HAGainLevel)level;


- (void)updateWithWNREnable:(BOOL)enabled;

- (void)updateWithINREnable:(BOOL)enabled intensity:(UInt8)intensity sensitivity:(UInt8)sensitivity;

- (void)updateWithRNSEnable:(BOOL)enabled;

- (void)updateWithdbSPLOutputDRC:(RTKHAdbSPLDRCState)state;

- (void)updateWithOutputDRC:(RTKHADRCState)state;

- (void)updateWithBeamformingMode:(RTKHABeamformingMode)mode width:(UInt8)width andSuppression:(RTKHABeamformingSuppression)suppression;

- (void)updateWithOwnVoiceProcessEnabled:(BOOL)enabled andSuppression:(UInt8)suppression;

- (void)updateWithOwnVoiceProcessEnabled:(BOOL)enabled andDbSuppression:(UInt8)suppression;

// MARK: for Philips

/// Update the Band EQ Gain settings saved in this context.
- (void)updateGainLevelsWithStageCount:(NSUInteger)count
                        ofLeftBud:(HAGainLevel*)lGainLevels
                       ofRightBud:(HAGainLevel*)rGainLevels;

/// Update the Noice Reduction settings saved in this context.
- (void)updateWithNoiceReductionAggresiveness:(HAGainLevel)level;

/// Update the OVP settings saved in this context.
- (void)updateWithOVPAggresiveness:(HAGainLevel)level;

/// Update the Beamforming settings saved in this context.
- (void)updateWithBeamformingEnable:(BOOL)enabled;

@end



@interface RHAPayloadGenerator : NSObject

/// Creates a new RHA Payload Generator object with a HA configuration.
///
/// @param configuration A structure which contains HA related information.
- (instancetype)initWithConfiguration:(RTKHAGainConfiguration)configuration;

/// Creates a new RHA Payload Generator with default configuration.
- (instancetype)init;

@property (readonly) RTKHAGainConfiguration configuration;

- (NSData *)payloadForRealEarMeasurementWithParams:(RTKHARealEarMeasurementParams)params;

- (NSData *)payloadForUpdateBandEQWithBalance:(HABalanceType)balance
                              volumeOfLeftBud:(HAVolumeLevel)LVolume
                             volumeOfRightBud:(HAVolumeLevel)RVolume
                                      context:(RHASettingContext *)context;

- (NSData *)payloadForUpdateBandEQWithBalance:(HABalanceType)balance
                              volumeOfLeftBud:(HAVolumeLevel)LVolume
                          gainLevelsOfLeftBud:(HAGainLevel*)lGainLevels
                             volumeOfRightBud:(HAVolumeLevel)RVolume
                         gainLevelsOfRightBud:(HAGainLevel*)rGainLevels
                                      context:(RHASettingContext *)context;

- (NSData *)payloadForUpdateNoiceReductionWithEnable:(BOOL)enabled
                                                mode:(RTKHANRMode)mode
                                       aggresiveness:(HAGainLevel)level
                                             context:(RHASettingContext *)context;

- (NSData *)payloadForUpdateNoiseReductionWithEnable:(BOOL)enabled
                                                mode:(RTKHANRMode)mode
                                       aggressiveness:(NSUInteger)level
                                        NRStereoMode:(RTKHANRStereoMode)stereoMode
                                             NRModel:(RTKHANRModel)model
                                             context:(RHASettingContext *)context;

- (NSData *)payloadForUpdateFBCWithEnable:(BOOL)enabled
                                  context:(RHASettingContext *)context;

- (NSData *)payloadForUpdateOVPWithEnable:(BOOL)enabled
                            aggresiveness:(HAGainLevel)level
                                  context:(RHASettingContext *)context;

- (NSData *)payloadForUpdateWNRWithEnable:(BOOL)enabled
                                  context:(RHASettingContext *)context;

- (NSData *)payloadForUpdateINRWithEnable:(BOOL)enabled
                                intensity:(NSUInteger)intensity
                              sensitivity:(NSUInteger)sensitivity
                                  context:(RHASettingContext *)context;

- (NSData *)payloadForUpdateRNSWithEnable:(BOOL)enabled
                                  context:(RHASettingContext *)context;

- (NSData *)payloadForUpdateHATestWithEnable:(BOOL)enabled
                                     context:(RHASettingContext *)context;

- (NSData *)payloadForUpdatedbSPLOutputDRCWith:(RTKHAdbSPLDRCState)state
                                  context:(RHASettingContext *)context;

- (NSData *)payloadForUpdateOutputDRCWith:(RTKHADRCState)state
                                  context:(RHASettingContext *)context;

- (NSData *)payloadForUpdateBeamformingMode:(RTKHABeamformingMode)mode
                                      width:(uint8_t)width
                                suppression:(RTKHABeamformingSuppression)suppression
                                    context:(RHASettingContext *)context;

- (NSData *)payloadForUpdateOwnVoiceProcessenabled:(BOOL)enabled
                                       suppression:(uint8_t)suppression
                                           context:(RHASettingContext *)context;

- (NSData *)payloadForUpdateOwnVoiceProcessenabled:(BOOL)enabled
                                       dbSuppression:(uint8_t)suppression
                                           context:(RHASettingContext *)context;

- (NSData *)payloadFor0dbFsTodBSPLWithOutValue:(uint16_t)outValue andInValue:(uint16_t)inValue;

- (NSData *)payloadForEnableWDRC2:(BOOL)enabled;

- (NSData *)payloadForApplyHACompensation:(BOOL)apply
                          withHearingLoss:(NSSet <RTKACHAPitchThreshold*>*)thresholds
                               gainOffset:(RTKACHADecibel)offset;

- (NSData *)payloadForApplyHACompensationForSeverity:(RTKHAHearingLossSeverity)severity;

// NAL-R
- (NSData *)payloadForApplyHACompensation:(BOOL)apply
                          withHearingLoss:(NSSet <RTKACHAPitchThreshold *> *)thresholds
                                  forMode:(RTKHAPresetMode)mode;

- (NSData *)payloadForApplyHACompensationForSeverity:(RTKHAHearingLossSeverity)severity
                                                mode:(RTKHAPresetMode)mode;

// NAL-R + NoiseGating
- (nullable NSData *)payloadForApplyHACompensation:(BOOL)apply
                          withHearingLoss:(NSSet <RTKACHAPitchThreshold *>*)thresholds
                                  forMode:(RTKHAPresetMode)mode
                       noiseGatingEnabled:(BOOL)enabled
                   noiseGatingFrequencies:(nullable NSArray *)noiseGatingFrequencies
                    noiseGatingThresholds:(nullable NSArray *)noiseGatingThresholds
                        noiseGatingRatios:(nullable NSArray *)noiseGatingRatios;

- (nullable NSData *)payloadForApplyHACompensationForSeverity:(RTKHAHearingLossSeverity)severity
                                                mode:(RTKHAPresetMode)mode
                                  noiseGatingEnabled:(BOOL)enabled
                              noiseGatingFrequencies:(nullable NSArray *)noiseGatingFrequencies
                               noiseGatingThresholds:(nullable NSArray *)noiseGatingThresholds
                                   noiseGatingRatios:(nullable NSArray *)noiseGatingRatios;

- (NSData *)payloadForApplyHACompensationWithWDRCParamFile:(NSString *)filePath
                                        noiseGatingEnabled:(BOOL)enabled
                                    noiseGatingFrequencies:(nullable NSArray *)noiseGatingFrequencies
                                     noiseGatingThresholds:(nullable NSArray *)noiseGatingThresholds
                                         noiseGatingRatios:(nullable NSArray *)noiseGatingRatios;

- (NSData *)payloadForApplyHACompensationWithWDRC2Param:(RTKHAWdrc2Param *)param
                                        noiseGatingEnabled:(BOOL)enabled
                                    noiseGatingFrequencies:(nullable NSArray *)noiseGatingFrequencies
                                     noiseGatingThresholds:(nullable NSArray *)noiseGatingThresholds
                                      noiseGatingRatios:(nullable NSArray *)noiseGatingRatios;

// MARK: - for Philips

/// Generates the payload which is be send to remote device to update Band EQ Gain.
///
/// @param lGainLevels An array of gain levels to update the left ear bud.
/// @param rGainLevels An array of gain levels to update the right ear bud.
/// @param context The object that contains state of the connected device.
/// @return The data to be send.
///
/// @discussion This method calculates the payload without send it. You should send it to a device to make it take effect. If the device receives this payload and update its state, you call @c -[RHASettingContext @c updateWitGainLevelsOfLeftBud:gainLevelsOfRightBud:] to tell the context.
- (NSData *)payloadForUpdateBandEQWithLeftBudGainLevels:(HAGainLevel*)lGainLevels
                                     rightBudGainLevels:(HAGainLevel*)rGainLevels
                                                context:(RHASettingContext *)context;

/// Generates the payload which is be send to remote device to update Noice Reduction Aggresiveness.
///
/// @param level The NR level to set.
/// @param context The object that contains state of the connected device.
/// @return The data to be send.
///
/// @discussion This method calculates the payload without send it. You should send it to a device to make it take effect. If the device receives this payload and update its state, you call @c -[RHASettingContext @c updateWithNoiceReductionAggresiveness:] to tell the context.
- (NSData *)payloadForUpdateNoiceReductionWithAggresiveness:(HAGainLevel)level
                                                    context:(RHASettingContext *)context;

/// Generates the payload which is be send to remote device to update OVP Aggresiveness.
///
/// @param level The NR level to set.
/// @param context The object that contains state of the connected device.
/// @return The data to be send.
///
/// @discussion This method calculates the payload without send it. You should send it to a device to make it take effect. If the device receives this payload and update its state, you call @c -[RHASettingContext @c updateWithOVPAggresiveness:] to tell the context.
- (NSData *)payloadForUpdateOVPWithAggresiveness:(HAGainLevel)level
                                         context:(RHASettingContext *)context;

/// Generates the payload which is be send to remote device to enable Beamforming.
///
/// @param enabled Whether to enale beamforming.
/// @param context The object that contains state of the connected device.
/// @return The data to be send.
///
/// @discussion This method calculates the payload without send it. You should send it to a device to make it take effect. If the device receives this payload and update its state, you call @c -[RHASettingContext @c updateWithBeamformingEnable:] to tell the context.
- (NSData *)payloadForUpdateBeamformingWithEnable:(BOOL)enabled
                                          context:(RHASettingContext *)context;

@end


@interface RTKACEQSetting (HearingLossCompensation)

/// Returns the compensated EQ Setting.
- (nullable instancetype)compensatedEQSettingWithPitchThreholds:(NSSet <RTKACHAPitchThreshold*>*)threholds forA2DP:(BOOL)yesOrNo;

/// Returns the EQ Setting that needs to be compensated to the original EQ.
- (nullable instancetype)compensationEQSettingWithPitchThreholds:(NSSet <RTKACHAPitchThreshold*>*)threholds forA2DP:(BOOL)yesOrNo;

@end

NS_ASSUME_NONNULL_END
