//
//  RTKACRHARoutine.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2022/7/14.
//  Copyright (c) 2022, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//
#ifdef ATAudioConnectSDK
#import <ATAudioConnectSDK/RTKACRoutine.h>
#import <ATAudioConnectSDK/RTKACType.h>
#import <ATAudioConnectSDK/RTKHATypes.h>
#import <ATAudioConnectSDK/RTKACBasicRoutine.h>
#import <ATAudioConnectSDK/RTKMacros.h>
#import <ATAudioConnectSDK/RTKBBproType.h>
#elif defined(RTKWaveLiteSDK)
#import <RTKWaveLiteSDK/RTKACRoutine.h>
#import <RTKWaveLiteSDK/RTKACType.h>
#import <RTKWaveLiteSDK/RTKHATypes.h>
#import <RTKWaveLiteSDK/RTKACBasicRoutine.h>
#import <RTKWaveLiteSDK/RTKMacros.h>
#import <RTKWaveLiteSDK/RTKBBproType.h>
#else
#import <RTKAudioConnectSDK/RTKACRoutine.h>
#import <RTKAudioConnectSDK/RTKACType.h>
#import <RTKAudioConnectSDK/RTKHATypes.h>
#import <RTKAudioConnectSDK/RTKACBasicRoutine.h>
#import <RTKAudioConnectSDK/RTKMacros.h>
#import <RTKAudioConnectSDK/RTKBBproType.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@class RTKACRHARoutine;
@class RTKHAWdrc2Param;

@protocol RTKACRHARoutineStateReporting <NSObject>
@optional

/// Called by an ``RTKACRHARoutine`` on its delegate to report pure tone playing status.
- (void)ACHARoutine:(RTKACRHARoutine *)routine didReceivePureTonePlayingStatus:(BOOL)isInterrupted;

- (void)BBproHARoutine:(RTKACRHARoutine *)routine didReceivePureTonePlayingStatus:(BOOL)isInterrupted RTK_REDIRECT(ACHARoutine:didReceivePureTonePlayingStatus:);

/// Report real ear measurement results.
///
///  - Parameter success: Measure whether it is successful.
///  - Parameter bud: Measured ear.
///  - Parameter data: Detailed data of the measurement results. If the measurement fails or there is no data, it is nil.
- (void)ACHARoutine:(RTKACRHARoutine *)routine didReceiveRealEarMeasurementReportWithSuccess:(BOOL)success bud:(RTKACHAEar)bud resultData:(nullable NSData *)data;
@end


/// An object you use to perform communication related to Hearing Aid feature with connected devices.
@interface RTKACRHARoutine : RTKACRoutine

/// An ``RTKACRHARoutineStateReporting`` conformined object that receives events.
@property (nonatomic, weak) id <RTKACRHARoutineStateReporting> delegate;

/// The basic routine this Audio routine depends.
@property RTKACBasicRoutine *basicRoutine;


#pragma mark - Program
/// Get HA program count of the connected device.
- (void)getProgramCountWithCompletionHandler:(nullable void (^)(BOOL success, NSError * _Nullable error, NSUInteger count))handler;

/// Get the program index used currently.
- (void)getCurrentProgramWithCompletionHandler:(nullable void (^)(BOOL success, NSError * _Nullable error, NSUInteger idx))handler;

/// Switch to use a program identified with index.
- (void)setCurrentProgram:(NSUInteger)programIdx withCompletionHandler:(nullable RTKLECompletionBlock)handler;

/// Request to reset the program settings currently used in the connected device.
- (void)resetCurrentProgramWithCompletionHandler:(nullable RTKLECompletionBlock)handler;

/// Get all program names.
- (void)getAllProgramNamesWithCompletionHandler:(nullable void (^)(BOOL success, NSError * _Nullable error, NSArray <NSString*> *names))handler;

/// Get program name of a specified program
- (void)getNameOfProgram:(NSUInteger)programIndex withCompletionHandler:(nullable void (^)(BOOL success, NSError * _Nullable error, NSString *name))handler;

/// Set a new name of a specified program.
- (void)setName:(NSString *)name ofProgram:(NSUInteger)programIdx withCompletionHandler:(nullable RTKLECompletionBlock)handler;

#pragma mark - Program Configuration Information
/// Load HA configuration information of the current program.
- (void)loadConfigurationWithCompletionHandler:(nullable RTKLECompletionBlock)handler;

/// Load HA configuration information of the specified program.
- (void)loadConfigurationOfProgram:(NSUInteger)programIdx withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, NSArray <NSNumber*> *leftAPTGainLevels, NSArray <NSNumber*> *rightAPTGainLevels, BOOL NREnabled, NSUInteger NRLevel, BOOL SEEnabled, NSUInteger SELevel, BOOL beamformingEnabled, BOOL WNREnabled, BOOL INREnabled, NSUInteger INRIntensity, NSUInteger INRSensitivity,  RTKHADRCState outputDRCState, RTKHABeamformingMode BeamformingMode, NSUInteger BeamformingWidth, RTKHABeamformingSuppression BeamformingSuppression, BOOL OwnVoiceProcessEnabled, NSUInteger OwnVoiceProcessSuppression, BOOL OwnVoiceProcessSuppressionUseDb))handler;

#pragma mark - Volume & Balance
/// Get the APT Volume state of the specified program.
- (void)getAPTVolumeOfProgram:(NSUInteger)programIdx withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, HAVolumeLevel LVolume, HAVolumeLevel RVolume, HABalanceType balance))handler;

/// Get the APT Volume state of the current program.
- (void)getAPTVolumeWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, HAVolumeLevel LVolume, HAVolumeLevel RVolume, HABalanceType balance))handler;

/// Get the APT volume synchronization status.
- (void)getAPTVolumeAdjustmentSynchronizationStatusWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, BOOL ajustSynchronously))handler;

/// Set the APT volume synchronization status.
- (void)setAPTVolumeAdjustmentSynchronization:(BOOL)synchronously withCompletionHandler:(nullable RTKLECompletionBlock)handler;

/// Set the HA volume and balance of the connnected device.
- (void)setConfigurationWithBalance:(HABalanceType)balance
                    volumeOfLeftBud:(HAVolumeLevel)LVolume
                   volumeOfRightBud:(HAVolumeLevel)RVolume
                  completionHandler:(nullable RTKLECompletionBlock)handler;

/// Get the APT Volume Mute state of the connected device.
- (void)getAPTVolumeMuteStatusWithCompletionHandler:(nullable void (^)(BOOL success, NSError * _Nullable error, RTKHAAPTVolumeMuteState leftBud, RTKHAAPTVolumeMuteState rightBud))handler;

/// Set the APT Volume Mute state of the connected device.
- (void)setAPTVolumeMute:(BOOL)isMuted ofBud:(RTKACBudSide)bud withCompletionHandler:(nullable RTKLECompletionBlock)handler;

#pragma mark - EQ
/// Set the HA EQ configuration of the connnected device.
- (void)setConfigurationWithGainLevelsOfLeftBud:(HAGainLevel*)lGainLevels
                           gainLevelsOfRightBud:(HAGainLevel*)rGainLevels
                              completionHandler:(nullable RTKLECompletionBlock)handler;

#pragma mark - Noice Reduction
/// Set NR (Noice Reduction) state of the connected device.
///
/// - Parameter level: The aggressiveness level of NR ranges from 0 to 4.
- (void)setNoiceReductionEnable:(BOOL)enabled
                           mode:(RTKHANRMode)mode
                  aggresiveness:(NSUInteger)level
          withCompletionHandler:(nullable RTKLECompletionBlock)handler;

/// Set NR (Noise Reduction) state of the connected device. This method is applicable when ``RTKACRHARoutine/NRVersion`` is 1.
///
/// - Parameter enabled: A boolean value to enable (YES) or disable (NO) the Noise Reduction feature.
/// - Parameter mode: Use the ``RTKACRHARoutine/NRMode`` value returned by device.
/// - Parameter level: The aggressiveness level of NR ranges from 0 to 4.
/// - Parameter stereoMode: The value should be one of the ``RTKHANRStereoMode`` enumerations.
/// - Parameter model: The value should be one of the ``RTKHANRModel`` enumerations.
- (void)setNoiseReductionEnable:(BOOL)enabled
                           mode:(RTKHANRMode)mode
                  aggressiveness:(NSUInteger)level
                   NRStereoMode:(RTKHANRStereoMode)stereoMode
                        NRModel:(RTKHANRModel)model
          withCompletionHandler:(RTKLECompletionBlock)handler;

#pragma mark - FeedBack Cancellation
/// Set FBC state of the connected device.
- (void)setFBCEnable:(BOOL)enabled withCompletionHandler:(nullable RTKLECompletionBlock)handler;

#pragma mark - Speech Enhancement
/// Set speech enhancement state of the connected device.
///
/// - Parameter level: The aggressiveness level of SE ranges from 0 to 3.
- (void)setOVPEnable:(BOOL)enabled aggresiveness:(NSUInteger)level withCompletionHandler:(nullable RTKLECompletionBlock)handler;

#pragma mark - Beamforming
/// Set Beamforming state of the connected device.
- (void)setBeamformingEnable:(BOOL)enabled withCompletionHandler:(nullable RTKLECompletionBlock)handler;

#pragma mark - Wind Noice Reduction
/// Set the Wind Noice Reduction enable state of the connected device.
- (void)setWNREnable:(BOOL)enabled withCompletionHandler:(nullable RTKLECompletionBlock)handler;

#pragma mark - Impulse Noice Reduction
/// Set the Impulse Noice Reduction enable state of the connected device.
///
/// - Parameter intensity: The intensity of INR ranges from 0 to 4.
/// - Parameter sensitivity: The sensitivity of INR ranges from 0 to 4.
- (void)setINREnable:(BOOL)enabled
           intensity:(NSUInteger)intensity
         sensitivity:(NSUInteger)sensitivity
withCompletionHandler:(nullable RTKLECompletionBlock)handler;

#pragma mark - HA algorithm
/// Set if HA algorithm should be used.
- (void)setHABypassed:(BOOL)yesOrNo withCompletionHandler:(nullable RTKLECompletionBlock)handler;

#pragma mark - Hearing Compensation v1
/// Apply compensation to HA based on the hearing loss information.
///
/// - Parameter thresholds: A list of hearing loss of one of the user's ear at different frequency.
/// - Parameter offset: The decibel offset. (-15)
/// - Parameter handler: A block to be invoked when this task completes.
- (void)applyCompensationForHearingLoss:(NSSet <RTKACHAPitchThreshold*>*)thresholds
                              gainOffet:(RTKACHADecibel)offset
                      completionHandler:(nullable RTKLECompletionBlock)handler;

/// Remove compensation to HA based on the hearing loss information.
///
/// - Parameter thresholds: A list of hearing loss of one of the user's ear at different frequency.
/// - Parameter handler: A block to be invoked when this task completes.
- (void)removeCompensationForHearingLoss:(NSSet <RTKACHAPitchThreshold*>*)thresholds
                       completionHandler:(nullable RTKLECompletionBlock)handler;

/// Whether the compensation regarding to Hearing loss is applied.
@property (readonly, getter=isCompensatedForHearingLoss) BOOL compensatedForHearingLoss;

/// Returns a boolean value which indicates whether the left ear bud is compensated.
@property (readonly, getter=isLeftEarCompensated) BOOL leftEarCompensated;

/// Returns a boolean value which indicates whether the right ear bud is compensated.
@property (readonly, getter=isRightEarCompensated) BOOL rightEarCompensated;

/// Whether the left ear is compensated basing the preset hearing loss severity selected.
@property (readonly, getter=isLeftEarCompensatedByPresetSeverity) BOOL leftEarCompensatedByPresetSeverity;

/// The selected hearing loss severity for left ear.
@property (readonly) RTKHAHearingLossSeverity leftEarHearingSeverity;

/// Whether the right ear is compensated basing the preset hearing loss severity selected.
@property (readonly, getter=isRightEarCompensatedByPresetSeverity) BOOL rightEarCompensatedByPresetSeverity;

/// The selected hearing loss severity for right ear.
@property (readonly) RTKHAHearingLossSeverity rightEarHearingSeverity;

#pragma mark - Preset Index
/// Get the current preset hearing loss severity indexes of the left and right buds.
///
/// - Parameter presetMode: The current preset mode.
/// - Parameter handler: A completion handler block to be invoked once the task completes.
- (void)getHAPresetIndexInMode:(RTKHAPresetMode)presetMode
         withCompletionHandler:(nullable void (^)(BOOL success, NSError * _Nullable error, RTKHAPresetMode mode, RTKHAHearingLossSeverity LIndex, RTKHAHearingLossSeverity RIndex))handler;

/// Preset the current hearing loss severity indexes for the left and right buds respectively.
///
/// When you apply hearing loss compensation, the method ``RTKACRHARoutine/applyCompensationForLeftEar:rightEar:withOut0dbFsTodbSPL:in0dbFsTodbSPL:lossThreshold:mode:completionHandler:`` automatically invokes this API to set the appropriate severity levels. To remove hearing compensation, you can call this method with `LIndex` or `RIndex` set to `RTKHAHearingLossSeverity_NotConfigured`.
/// - Parameters:
///   - LIndex: The hearing loss severity for the left bud.
///   - RIndex: The hearing loss severity for the right bud.
///   - presetMode: The preset mode in which these severity levels will be applied.
///   - handler: A completion handler block to be invoked once the task completes. This block contains:
///       - `success`:  A boolean indicating whether the command was successful.
///       - `error`:  An optional error object containing details if the operation failed.
///       - `mode`:  The mode in which the severities were applied.
///       - `status`:  A boolean indicating the current status of the preset operation.
- (void)setHAPresetIndexL:(RTKHAHearingLossSeverity)LIndex
                   andIndexR:(RTKHAHearingLossSeverity)RIndex
                   inMode:(RTKHAPresetMode)presetMode
             withCompletionHandler:(nullable void (^)(BOOL success, NSError * _Nullable error, RTKHAPresetMode mode, BOOL status))handler;

#pragma mark - Hearing Compensation v2
/// Apply compensation with noise gating based on the hearing loss information.
///
/// - Parameters:
///   - leftSeverity: The severity of hearing loss for the left ear.
///   - rightSeverity: The severity of hearing loss for the right ear.
///   - outValue: The output reference level in dB SPL that corresponds to 0 dB FS. This parameter is effective in `RTKHAPresetMode_A2DP` and `RTKHAPresetMode_SCO` modes, and can be  `nil` in `RTKHAPresetMode_RHA` mode. It should be within the range of 86 to 126.
///   - inValue: The input reference level in dB SPL that corresponds to 0 dB FS, similar to `outValue`.
///   - thresholds: The user's hearing loss thresholds across different frequencies.  It can be `nil` if both `leftSeverity` and `rightSeverity` are not `RTKHAHearingLossSeverity_HearingCompensation`.
///   - mode: The preset mode that determines how the compensation is applied.
///   - enabled: Whether noise gating is enabled.
///   - noiseFrequencies: Frequencies for noise gating (Hz). Can be nil if enabled=NO.
///   - noiseThresholds: Threshold levels for noise gating (dB). Can be nil if enabled=NO.
///   - noiseRatios: Compression ratios for noise gating. Can be nil if enabled=NO.
///   - handler: A block that is called upon completion of the compensation process. This block may contain results of the operation or an error if one occurred.
///
/// - Important: You must call ``RTKACBasicRoutine/getPackageInfoWithCompletionHandler:``  and ensure it has completed successfully before invoking this method. Otherwise, compensation processing may fail due to missing context.
- (void)applyCompensationForLeftEar:(RTKHAHearingLossSeverity)leftSeverity
                           rightEar:(RTKHAHearingLossSeverity)rightSeverity
                withOut0dbFsTodbSPL:(nullable NSNumber *)outValue
                     in0dbFsTodbSPL:(nullable NSNumber *)inValue
                      lossThreshold:(nullable NSSet<RTKACHAPitchThreshold *> *)thresholds
                               mode:(RTKHAPresetMode)mode
                  noiseGatingEnable:(BOOL)enabled
             noiseGatingFrequencies:(nullable NSArray *)noiseFrequencies
              noiseGatingThresholds:(nullable NSArray *)noiseThresholds
                  noiseGatingRatios:(nullable NSArray *)noiseRatios
                  completionHandler:(nullable RTKLECompletionBlock)handler;

/// Apply compensation with noise gating using user-specified WDRC parameter files.
///
/// This method is designed for scenarios where the hearing loss severity is less than `RTKHAHearingLossSeverity_NotConfigured`, and the user wishes to apply custom WDRC parameters from a file instead of relying on the default parameters. If a file path for an ear is provided as `nil`, the default WDRC parameters for the corresponding severity level will be used for that ear.
///
/// - Parameters:
///   - LFilePath: The local file path to the WDRC parameter file for the left ear. If `nil`, the default parameters corresponding to the `leftSeverity` will be used.
///   - leftSeverity: The severity of hearing loss for the left ear.
///   - RFilePath: The local file path to the WDRC parameter file for the right ear. If `nil`, the default parameters corresponding to the `rightSeverity` will be used.
///   - rightSeverity: The severity of hearing loss for the right ear. 
///   - outValue: The output reference level in dB SPL that corresponds to 0 dB FS. This parameter is effective in `RTKHAPresetMode_A2DP` and `RTKHAPresetMode_SCO` modes, and can be  `nil` in `RTKHAPresetMode_RHA` mode. It should be within the range of 86 to 126.
///   - inValue: The input reference level in dB SPL that corresponds to 0 dB FS, similar to `outValue`.
///   - thresholds: The user's hearing loss thresholds across different frequencies.  It can be `nil` if a custom WDRC file (`LFilePath` or `RFilePath`) is provided for the corresponding ear, or if both `leftSeverity` and `rightSeverity` are not `RTKHAHearingLossSeverity_HearingCompensation`.
///   - mode: The preset mode that determines how the compensation is applied.
///   - enabled: Whether noise gating is enabled.
///   - noiseFrequencies: Frequencies for noise gating (Hz). Can be nil if enabled=NO.
///   - noiseThresholds: Threshold levels for noise gating (dB). Can be nil if enabled=NO.
///   - noiseRatios: Compression ratios for noise gating. Can be nil if enabled=NO.
///   - handler: A block that is called upon completion of the compensation process. This block may contain results of the operation or an error if one occurred.
///
/// - Important: You must call ``RTKACBasicRoutine/getPackageInfoWithCompletionHandler:``  and ensure it has completed successfully before invoking this method. Otherwise, compensation processing may fail due to missing context.
- (void)applyCompensationWithLeftWDRCParamFile:(nullable NSString *)LFilePath
                                    forLeftEar:(RTKHAHearingLossSeverity)leftSeverity
                            rightWDRCParamFile:(nullable NSString *)RFilePath
                                   forRightEar:(RTKHAHearingLossSeverity)rightSeverity
                           withOut0dbFsTodbSPL:(nullable NSNumber *)outValue
                                in0dbFsTodbSPL:(nullable NSNumber *)inValue
                                 lossThreshold:(nullable NSSet<RTKACHAPitchThreshold *> *)thresholds
                                          mode:(RTKHAPresetMode)mode
                             noiseGatingEnable:(BOOL)enabled
                        noiseGatingFrequencies:(nullable NSArray *)noiseFrequencies
                         noiseGatingThresholds:(nullable NSArray *)noiseThresholds
                             noiseGatingRatios:(nullable NSArray *)noiseRatios
                             completionHandler:(nullable RTKLECompletionBlock)handler;


/// Apply compensation based on the hearing loss information.
///
/// - Parameters:
///   - leftSeverity: The severity of hearing loss for the left ear.
///   - rightSeverity: The severity of hearing loss for the right ear.
///   - outValue: The output reference level in dB SPL that corresponds to 0 dB FS. This parameter is effective in `RTKHAPresetMode_A2DP` and `RTKHAPresetMode_SCO` modes, and can be  `nil` in `RTKHAPresetMode_RHA` mode. It should be within the range of 86 to 126.
///   - inValue: The input reference level in dB SPL that corresponds to 0 dB FS, similar to `outValue`.
///   - thresholds: The user's hearing loss thresholds across different frequencies.  It can be `nil` if both `leftSeverity` and `rightSeverity` are not `RTKHAHearingLossSeverity_HearingCompensation`.
///   - mode: The preset mode that determines how the compensation is applied.
///   - handler: A block that is called upon completion of the compensation process. This block may contain results of the operation or an error if one occurred.
///
/// - Important: You must call ``RTKACBasicRoutine/getPackageInfoWithCompletionHandler:``  and ensure it has completed successfully before invoking this method. Otherwise, compensation processing may fail due to missing context.
- (void)applyCompensationForLeftEar:(RTKHAHearingLossSeverity)leftSeverity
                           rightEar:(RTKHAHearingLossSeverity)rightSeverity
                withOut0dbFsTodbSPL:(nullable NSNumber *)outValue
                     in0dbFsTodbSPL:(nullable NSNumber *)inValue
                      lossThreshold:(nullable NSSet <RTKACHAPitchThreshold *> *)thresholds
                               mode:(RTKHAPresetMode)mode
                  completionHandler:(nullable RTKLECompletionBlock)handler;

/// Returns the hearing loss compensation severity for a specified mode and bud.
///
/// - Parameters:
///   - mode: The preset mode for which the severity is being queried.
///   - bud: The bud  for which compensation severity is being determined.
- (RTKHAHearingLossSeverity)severityForMode:(RTKHAPresetMode)mode bud:(RTKHAApplyBud)bud;


#pragma mark - Preset Index (Support applying to HA scenarios)
/// Get the preset hearing loss severity indexes for a specific scenario.
///
/// This method allows querying the hearing compensation levels for a particular usage scenario (e.g., HA scenario 0, 1, 2.....).
///
/// - Parameters:
///   - presetMode: The preset mode.
///   - index: The index of the scenario to be queried. Only valid in `RTKHAPresetMode_RHA` mode. Otherwise, set it to 0.
///   - handler: A completion handler block to be invoked once the task completes. The block returns the severity indexes (`LIndex`, `RIndex`) for the specified scenario.
- (void)getHAPresetIndexV2InMode:(RTKHAPresetMode)presetMode scenario:(uint8_t)index withCompletionHandler:(nullable void (^)(BOOL, NSError * _Nullable, RTKHAPresetMode mode, RTKHAHearingLossSeverity LIndex, RTKHAHearingLossSeverity RIndex))handler;

/// Set the hearing loss severity indexes for one or more specific scenarios.
///
/// This method enhances the preset functionality by allowing you to apply severity levels to multiple scenarios simultaneously. This multi-scenario capability is exclusively available for the `RTKHAPresetMode_RHA` mode. To remove hearing compensation from specific scenarios, call this method with the target scenario indexes and set `LIndex` or `RIndex` to `RTKHAHearingLossSeverity_NotConfigured`.
///
/// - Parameters:
///   - LIndex: The hearing loss severity for the left bud.
///   - RIndex: The hearing loss severity for the right bud.
///   - presetMode: The preset mode in which these severity levels will be applied.
///   - scenarios: An array of `NSNumber` objects, each representing a scenario index. The specified `LIndex` and `RIndex` will be applied to all scenarios listed in this array. It can be `nil` in `RTKHAPresetMode_A2DP` and `RTKHAPresetMode_SCO` modes.
///   - handler: A completion handler block to be invoked once the task completes. This block contains:
///       - `success`: A boolean indicating whether the command was successful.
///       - `error`: An optional error object containing details if the operation failed.
///       - `mode`: The mode in which the severities were applied.
///       - `status`: A boolean indicating the current status of the preset operation.
- (void)setHAPresetIndexV2L:(RTKHAHearingLossSeverity)LIndex
                andIndexR:(RTKHAHearingLossSeverity)RIndex
                   inMode:(RTKHAPresetMode)presetMode
                scenarios:(nullable NSArray<NSNumber *> *)scenarios
      withCompletionHandler:(nullable void (^)(BOOL success, NSError * _Nullable error, RTKHAPresetMode mode, BOOL status))handler;

#pragma mark - Hearing Compensation (Support applying to HA scenarios)
/// Apply compensation with noise gating to one or more specific scenarios using user-specified WDRC parameter files.
///
/// This method extends the compensation functionality by allowing a single set of parameters (WDRC files, severity levels, noise gating settings, etc.) to be applied to multiple usage scenarios simultaneously. If a file path for an ear is provided as `nil`, the default WDRC parameters for the corresponding severity level will be used for that ear.
///
/// - Parameters:
///   - LFilePath: The local file path to the WDRC parameter file for the left ear. If `nil`, the default parameters corresponding to the `leftSeverity` will be used.
///   - leftSeverity: The severity of hearing loss for the left ear.
///   - RFilePath: The local file path to the WDRC parameter file for the right ear. If `nil`, the default parameters corresponding to the `rightSeverity` will be used.
///   - rightSeverity: The severity of hearing loss for the right ear.
///   - outValue: The output reference level in dB SPL that corresponds to 0 dB FS. This parameter is effective in `RTKHAPresetMode_A2DP` and `RTKHAPresetMode_SCO` modes, and can be `nil` in `RTKHAPresetMode_RHA` mode. It should be within the range of 86 to 126.
///   - inValue: The input reference level in dB SPL that corresponds to 0 dB FS, similar to `outValue`.
///   - thresholds: The user's hearing loss thresholds across different frequencies. It can be `nil` if a custom WDRC file (`LFilePath` or `RFilePath`) is provided for the corresponding ear, or if both `leftSeverity` and `rightSeverity` are not `RTKHAHearingLossSeverity_HearingCompensation`.
///   - mode: The preset mode that determines how the compensation is applied.
///   - scenarios: An array of `NSNumber` objects, each representing a scenario index. The specified compensation settings will be applied to all scenarios listed in this array. It can be `nil` in `RTKHAPresetMode_A2DP` and `RTKHAPresetMode_SCO` modes.
///   - enabled: Whether noise gating is enabled.
///   - noiseFrequencies: Frequencies for noise gating (Hz). Can be `nil` if `enabled` is `NO`.
///   - noiseThresholds: Threshold levels for noise gating (dB). Can be `nil` if `enabled` is `NO`.
///   - noiseRatios: Compression ratios for noise gating. Can be `nil` if `enabled` is `NO`.
///   - handler: A block that is called upon completion of the compensation process. This block may contain results of the operation or an error if one occurred.
///
/// - Important: You must call ``RTKACBasicRoutine/getPackageInfoWithCompletionHandler:`` and ensure it has completed successfully before invoking this method. Otherwise, compensation processing may fail due to missing context.
- (void)applyCompensationWithLeftWDRCParamFile:(nullable NSString *)LFilePath
                                    forLeftEar:(RTKHAHearingLossSeverity)leftSeverity
                            rightWDRCParamFile:(nullable NSString *)RFilePath
                                   forRightEar:(RTKHAHearingLossSeverity)rightSeverity
                           withOut0dbFsTodbSPL:(nullable NSNumber *)outValue
                                in0dbFsTodbSPL:(nullable NSNumber *)inValue
                                 lossThreshold:(nullable NSSet<RTKACHAPitchThreshold *> *)thresholds
                                        forMode:(RTKHAPresetMode)mode
                                     inScenarios:(nullable NSArray<NSNumber *> *)scenarios
                             noiseGatingEnable:(BOOL)enabled
                        noiseGatingFrequencies:(nullable NSArray *)noiseFrequencies
                         noiseGatingThresholds:(nullable NSArray *)noiseThresholds
                             noiseGatingRatios:(nullable NSArray *)noiseRatios
                             completionHandler:(nullable RTKLECompletionBlock)handler;


- (void)applyCompensationWithLeftWDRC2Param:(nullable RTKHAWdrc2Param *)LParam
                                    forLeftEar:(RTKHAHearingLossSeverity)leftSeverity
                            rightWDRC2Param:(nullable RTKHAWdrc2Param *)RParam
                                   forRightEar:(RTKHAHearingLossSeverity)rightSeverity
                           withOut0dbFsTodbSPL:(nullable NSNumber *)outValue
                                in0dbFsTodbSPL:(nullable NSNumber *)inValue
                                 lossThreshold:(nullable NSSet<RTKACHAPitchThreshold *> *)thresholds
                                        forMode:(RTKHAPresetMode)mode
                                     inScenarios:(nullable NSArray<NSNumber *> *)scenarios
                             noiseGatingEnable:(BOOL)enabled
                        noiseGatingFrequencies:(nullable NSArray *)noiseFrequencies
                         noiseGatingThresholds:(nullable NSArray *)noiseThresholds
                             noiseGatingRatios:(nullable NSArray *)noiseRatios
                             completionHandler:(nullable RTKLECompletionBlock)handler;


/// Returns the hearing loss compensation severity for a specified mode, scenario, and bud.
///
/// This method allows querying the severity level for a specific usage scenario within a given mode.
///
/// - Parameters:
///   - mode: The preset mode for which the severity is being queried.
///   - scenario: The index of the scenario to be queried. If the `mode` is not `RTKHAPresetMode_RHA`, set it to 0.
///   - bud: The bud for which compensation severity is being determined.
- (RTKHAHearingLossSeverity)severityForMode:(RTKHAPresetMode)mode
                                   scenario:(NSUInteger)scenario
                                        bud:(RTKHAApplyBud)bud;

#pragma mark - dbSPL Output DRC
/// Update the dbSPL output DRC parameter of the connected device.
///
/// - Parameter state: A structure containing updated state information.
/// - Parameter handler: The handler to be called once this task completes.
- (void)setdbSPLOutputDRC:(RTKHAdbSPLDRCState)state withCompletionHandler:(nullable RTKLECompletionBlock)handler;

#pragma mark - Output DRC
/// Update the output DRC parameter of the connected device.
///
/// - Parameter state: A structure containing updated state information.
/// - Parameter handler: The handler to be called once this task completes.
- (void)setOutputDRC:(RTKHADRCState)state withCompletionHandler:(nullable RTKLECompletionBlock)handler;

#pragma mark - RealFocus 2.0 Settings
/// Update the adaptive beamforming settings of the connected device.
///
/// - Parameter mode: see ``RTKHABeamformingMode``
/// - Parameter width: 0(wide) ~ 7(narrow)
/// - Parameter suppression: see ``RTKHABeamformingSuppression``
/// - Parameter handler: The handler to be called once this task completes.
- (void)setBeamformingMode:(RTKHABeamformingMode)mode width:(uint8_t)width andSuppression:(RTKHABeamformingSuppression)suppression withCompletionHandler:(nullable RTKLECompletionBlock)handler;

#pragma mark - Own Voice Reduction
/// Update the own voice processing settings of the connected device.
///
/// - Parameter suppression: If  ``RTKACRHARoutine/OwnVoiceProcessSuppressionUseDb`` is  YES,  the valid range is 0 ~ 50 (representing 0 ~ -50db), else the range is 0(low) ~ 7(high) ;
/// - Parameter handler: The handler to be called once this task completes.
- (void)setOwnVoiceProcessEnabled:(BOOL)enabled andSupprssion:(uint8_t)suppression withCompletionHandler:(nullable RTKLECompletionBlock)handler;

#pragma mark - OVP Training
/// Request device to start Own Voice Process Training.
- (void)startOVPTrainingWithCompletionHandler:(nullable RTKLECompletionBlock)handler;

/// Request device to stop Own Voice Process Training.
- (void)stopOVPTrainingWithCompletionHandler:(nullable RTKLECompletionBlock)handler;

#pragma mark - Hearing Test Related
/// Get a list of dBSPL references of the specified ear bud.
///
/// Once request is completed successfully, the freqReferences dictionary has keys that represents frequency integer and values that represents dbspl value.
- (void)getAudioOutputDBSPLReferencesOfBud:(RTKACBudSide)bud withCompletionHandler:(nullable void (^)(BOOL success, NSError * _Nullable error, NSDictionary <NSNumber*, NSNumber*> *_Nullable freqReferences))handler;

/// Get the measured dbFS about the recent outputed audio.
- (void)getAudioOutputDBFSOfBud:(RTKACBudSide)bud withCompletionHandler:(nullable void (^)(BOOL success, NSError * _Nullable error, NSInteger db))handler;

/// Request device to create a player instance for playing pure tone.
///
/// - Parameter bud: A specific ear bud.
/// - Parameter handler: A completion handler block to be invoked once the task completes.
- (void)createPureTonePlayerIn:(RTKHAApplyBud)bud withCompletionHandler:(nullable RTKLECompletionBlock)handler;

/// Request device to destroy a created player instance for playing pure tone.
///
/// - Parameter bud: A specific ear bud.
/// - Parameter handler: A completion handler block to be invoked once the task completes.
- (void)destroyPureTonePlayerIn:(RTKHAApplyBud)bud withCompletionHandler:(nullable RTKLECompletionBlock)handler;

/// Request device to start playing pure tone.
///
/// - Parameter bud: A specific ear bud.
/// - Parameter handler: A completion handler block to be invoked once the task completes.
- (void)startPureTonePlayerIn:(RTKHAApplyBud)bud withCompletionHandler:(nullable RTKLECompletionBlock)handler;

/// Request device to stop playing pure tone.
///
/// - Parameter bud: A specific ear bud.
/// - Parameter handler: A completion handler block to be invoked once the task completes.
- (void)stopPureTonePlayerIn:(RTKHAApplyBud)bud withCompletionHandler:(nullable RTKLECompletionBlock)handler;

/// Request device to update the pure tone parameters.(Pulse)
///
/// - Parameters:
///     - freq: The frequency of the pure tone.
///     - db: The intensity in dBFS of the pure tone.
///     - bud: A specific ear bud.
///     - duration: The interval for playing the pure tone.
///     - handler: A completion handler block to be invoked once the task completes.
- (void)updatePureToneFrequency:(NSUInteger)freq intensity:(NSInteger)db ofPureTonePlayerIn:(RTKHAApplyBud)bud for:(NSTimeInterval)duration withCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Request device to update the pure tone parameters. (Continuous)
///
/// - Parameters:
///     - freq: The frequency of the pure tone.
///     - db: The intensity in dBFS of the pure tone.
///     - bud: A specific ear bud.
///     - timeout: If the device does not receive the next request within this time, it will not play the next pure tone.
///     - duration: The duration for playing the pure tone.
///     - handler: A completion handler block to be invoked once the task completes.
- (void)updatePureToneFrequency:(NSUInteger)freq
                      intensity:(NSInteger)db
             ofPureTonePlayerIn:(RTKHAApplyBud)bud
                        timeout:(NSTimeInterval)timeout
                       duration:(NSTimeInterval)duration
              withCompletionHandler:(nullable RTKLECompletionBlock)handler;

#pragma mark - Environment Classification
/// Request device to start/stop scenario classification.
- (void)enableClassify:(BOOL)enabled withCompletionHandler:(nullable RTKLECompletionBlock)handler;


#pragma mark - Real Ear Measurement
/// Starts the Real Ear Measurement process on a specific earbud.
///
/// This method puts the target earbud into a special mode, preparing it for configuration and measurement. You must call this before setting parameters or performing the measurement.
///
/// - Parameters:
///   - bud: The target earbud (`RTKACHAEar_left` or `RTKACHAEar_right`) to enter REM mode.
///   - handler: A block that is called when the operation completes. It receives a `BOOL` indicating success and an `NSError` object if the operation failed.
- (void)startRealEarMeasurementForBud:(RTKACHAEar)bud withCompletionHandler:(nullable RTKLECompletionBlock)handler;

/// Configures the Real Ear Measurement parameters for a specific earbud.
///
/// After entering REM mode, use this method to send the desired measurement settings to the earbud.
/// This method should be called after successfully entering REM mode via ``startRealEarMeasurementForBud:withCompletionHandler:``.
///
/// - Parameters:
///  - params: A `RTKHARealEarMeasurementParams` struct containing the configuration for the measurement.
///  - bud: The target earbud (`RTKACHAEar_left` or `RTKACHAEar_right`) to configure.
///  - handler: A block that is called upon completion. The block receives a `BOOL` for success, and an `NSError` object on failure.
- (void)configureRealEarMeasurementWithParams:(RTKHARealEarMeasurementParams)params forBud:(RTKACHAEar)bud withCompletionHandler:(nullable RTKLECompletionBlock)handler;

/// Resets the Real Ear Measurement parameters on the both earbuds to their factory defaults.
///
/// This action reverts any custom configurations set by
/// ``configureRealEarMeasurementWithParams:forBud:withCompletionHandler:``.
///
///- Parameters:
///    - handler: A block that is called when the operation completes. It receives a `BOOL` indicating success and an `NSError` object if the operation failed.
- (void)resetRealEarMeasurementParamsWithCompletionHandler:(nullable RTKLECompletionBlock)handler;

/// Calculates the output dBSPL and applies a specified debug gain.
///
/// - Parameter speakerResponse: A dictionary containing the speaker's frequency response data. The dictionary should use frequency (Hz) as the key (`NSNumber`) and response (dB) as the value (`NSNumber`).
/// - Parameter gain: A signed 8-bit integer value representing the debug gain to be added.
/// - Parameter error: An `out` parameter. If an error occurs, this pointer is populated with an `NSError`
///                  object describing the failure.
/// - Returns: The final calculated output level in dBSPL (including the debug gain), or `NAN` (Not a Number) if the calculation fails.
- (double)calculateOutputdBSPLWithSpeakerResponse:(NSDictionary<NSNumber *, NSNumber *> *)speakerResponse andDebugGain:(int8_t)gain error:(NSError * _Nullable * _Nullable)error;

@end


@interface RTKACRHARoutine (Cache)

/// Returns the number object that indicates solved program count.
@property (nullable, readonly) NSNumber *programCount;

/// Returns the number object that indicates solved program names.
@property (nullable, readonly) NSArray <NSString *> *programNames;

/// Returns the number object that indicates solved program index current used .
@property (nullable, readonly) NSNumber *programIndex;

/// Returns the number object that indicates solved name of current used program.
@property (nullable, readonly) NSString *programName;

/// Return a number that indicates if the left ear bud APT is muted.
@property (nullable, readonly) NSNumber *leftBudAPTMuted;

/// Return a number that indicates if the right ear bud APT is muted.
@property (nullable, readonly) NSNumber *rightBudAPTMuted;

/// Returns the number object that indicates solved APT balance.
@property (nullable, readonly) NSNumber *balance;

/// Returns the HA gain configuration.
@property (readonly) RTKHAGainConfiguration configuration;

/// Returns the number object that indicates solved APT volume of left bud.
@property (nullable, readonly) NSNumber *leftBudAPTVolume;

/// Returns the number object that indicates solved APT volume of right bud.
@property (nullable, readonly) NSNumber *rightBudAPTVolume;

/// Returns the number object that indicates whether APT volume adjustment of left bud and right bud occurs synchronously.
@property (nullable, readonly) NSNumber *APTVolumeAdjustmentSynchronously;

/// Returns the number object that indicates solved APT gain levels of left bud.
@property (nullable, readonly) NSArray <NSNumber*> *leftAPTGainLevels;

/// Returns the number object that indicates solved APT gain levels of right bud.
@property (nullable, readonly) NSArray <NSNumber*> *rightAPTGainLevels;

/// Returns the number object that indicates solved NR enable status.
@property (nullable, readonly) NSNumber *NREnabled;

/// Returns the number object that indicates solved NR level status.
@property (nullable, readonly) NSNumber *NRLevel;

/// Returns the number object that indicates solved NR mode status.
@property (nullable, readonly) NSNumber *NRMode;

/// Returns the number object that indicates the version information of the current SOC NR feature.
@property (nullable, readonly) NSNumber *NRVersion;

/// Returns the number object indicating the NR stereo mode. The value corresponds to the ``RTKHANRStereoMode`` enum type.
@property (nullable, readonly) NSNumber *NRStereoMode;

/// Returns the number object indicating the NR model. The value corresponds to the ``RTKHANRModel`` enum type.
@property (nullable, readonly) NSNumber *NRModel;

/// Returns the number object that indicates solved FBC enable status.
@property (nullable, readonly) NSNumber *FBCEnabled;

/// Returns the number object that indicates solved OVP enable status.
@property (nullable, readonly) NSNumber *OVPEnabled;

/// Returns the number object that indicates solved OVP level status.
@property (nullable, readonly) NSNumber *OVPLevel;

/// Returns the number object that indicates solved Beamforming enable status.
@property (nullable, readonly) NSNumber *beamformingEnabled;

/// Returns the number object that indicates solved dehowling enable status.
@property (nullable, readonly) NSNumber *dehowlingEnabled;

/// Returns the number object that indicates solved dehowling level status.
@property (nullable, readonly) NSNumber *dehowlingLevel;

/// Returns the number object that indicates solved WNR enable status.
@property (nullable, readonly) NSNumber *WNREnabled;

/// Returns the number object that indicates solved INR enable status.
@property (nullable, readonly) NSNumber *INREnabled;

/// Returns the number object that indicates solved INR intensity status.
@property (nullable, readonly) NSNumber *INRIntensity;

/// Returns the number object that indicates solved INR sensitivity status.
@property (nullable, readonly) NSNumber *INRSensitivity;

/// Returns a NSNumber that indicates if HA Algorithm is bypassed.
@property (nullable, readonly) NSNumber *HABypassed;

/// Returns a `NSValue` object embeding an ``RTKHAdbSPLDRCState`` value.
@property (nullable, readonly) NSValue *dbSPLOutputDRCState;

/// Returns a `NSValue` object embeding an ``RTKHADRCState`` value.
@property (nullable, readonly) NSValue *outputDRCState;

/// Returns the number object that indicates the current beamforming mode.
@property (nullable, readonly) NSNumber *BeamformingMode;

/// Returns the number object that indicates the current beamforming width.
@property (nullable, readonly) NSNumber *BeamformingWidth;

/// Returns the number object that indicates the current beamforming suppression.
@property (nullable, readonly) NSNumber *BeamformingSuppression;

/// Returns the number object that indicates the current own voice process status.
@property (nullable, readonly) NSNumber *OwnVoiceProcessEnabled;

/// Returns the number object that indicates the current own voice process suppression.
@property (nullable, readonly) NSNumber *OwnVoiceProcessSuppression;

/// Returns the number object that indicates whether the current own voice process suppression is using db or level.
@property (nullable, readonly) NSNumber *OwnVoiceProcessSuppressionUseDb;

/// Returns a number object that indicates whether your Own Voice Training failed.
@property (nullable, readonly) NSNumber *OwnVoiceTrainingFailed;

/// Returns a number object that indicates the score(0-127) of the Own Voice Training.
@property (nullable, readonly) NSNumber *OwnVoiceTrainingScore;

/// Returns a number object that indicates the current environment type.
@property (nullable, readonly) NSNumber *currentEnvironment;

/// Returns a number object that indicates the signal input value in   `RTKHAPresetMode_A2DP`.
@property (nullable, readonly) NSNumber *A2DPSigIn;

/// Returns a number object that indicates the signal input value in `RTKHAPresetMode_SCO`.
@property (nullable, readonly) NSNumber *SCOSigIn;

@end


@interface RTKACRHARoutine (Deprecated)

/// Please migrate to the new API that uses `RTKACBudSide`.
/// @see setAPTVolumeMute:ofBud:withCompletionHandler:
- (void)setAPTVolumeMute:(BOOL)isMuted
             ofBudLegacy:(RTKBBproBudSide)bud
   withCompletionHandler:(nullable RTKLECompletionBlock)handler
RTK_REDIRECT('setAPTVolumeMute:ofBud:withCompletionHandler:' with 'RTKACBudSide')
   NS_SWIFT_NAME(setAPTVolumeMute(_:ofBud:withCompletionHandler:));


/// Please use the updated method compatible with `RTKACBudSide`.
/// @see getAudioOutputDBSPLReferencesOfBud:withCompletionHandler:
- (void)getAudioOutputDBSPLReferencesOfBudLegacy:(RTKBBproBudSide)bud
                           withCompletionHandler:(nullable void (^)(BOOL success, NSError * _Nullable error, NSDictionary <NSNumber*, NSNumber*> *_Nullable freqReferences))handler
RTK_REDIRECT('getAudioOutputDBSPLReferencesOfBud:withCompletionHandler:' with 'RTKACBudSide')
   NS_SWIFT_NAME(getAudioOutputDBSPLReferences(ofBud:withCompletionHandler:));


/// Please switch to the new API using the `RTKACBudSide` enum.
/// @see getAudioOutputDBFSOfBud:withCompletionHandler:
- (void)getAudioOutputDBFSOfBudLegacy:(RTKBBproBudSide)bud
                withCompletionHandler:(nullable void (^)(BOOL success, NSError * _Nullable error, NSInteger db))handler
RTK_REDIRECT('getAudioOutputDBFSOfBud:withCompletionHandler:' with 'RTKACBudSide')
   NS_SWIFT_NAME(getAudioOutputDBFS(ofBud:withCompletionHandler:));

@end

NS_ASSUME_NONNULL_END
