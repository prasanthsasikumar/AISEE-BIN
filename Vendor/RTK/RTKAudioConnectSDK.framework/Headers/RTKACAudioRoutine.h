//
//  RTKACAudioRoutine.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2020/9/14.
//  Copyright (c) 2020, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <Foundation/Foundation.h>

#ifdef ATAudioConnectSDK
#import <ATAudioConnectSDK/RTKACRoutine.h>
#import <ATAudioConnectSDK/RTKACBasicRoutine.h>
#import <ATAudioConnectSDK/RTKACType.h>
#import <ATAudioConnectSDK/RTKACFilterInfo.h>
#import <ATAudioConnectSDK/RTKMacros.h>
#import <ATAudioConnectSDK/RTKBBproType.h>
#elif defined(RTKWaveLiteSDK)
#import <RTKWaveLiteSDK/RTKACRoutine.h>
#import <RTKWaveLiteSDK/RTKACBasicRoutine.h>
#import <RTKWaveLiteSDK/RTKACType.h>
#import <RTKWaveLiteSDK/RTKACFilterInfo.h>
#import <RTKWaveLiteSDK/RTKMacros.h>
#import <RTKWaveLiteSDK/RTKBBproType.h>
#else
#import <RTKAudioConnectSDK/RTKACRoutine.h>
#import <RTKAudioConnectSDK/RTKACBasicRoutine.h>
#import <RTKAudioConnectSDK/RTKACType.h>
#import <RTKAudioConnectSDK/RTKACFilterInfo.h>
#import <RTKAudioConnectSDK/RTKMacros.h>
#import <RTKAudioConnectSDK/RTKBBproType.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@class RTKACAudioRoutine;

/// Methods that an ``RTKACAudioRoutine`` calls on its delegate to report state update events.
@protocol RTKACAudioRoutineStateReporting <NSObject>


/// Tells the delegate that remote device did change current APT(Audio Pass Through) state.
///
/// - Parameter routine: The routine object which reports this event.
/// - Parameter isOn: Whether the APT feature is on.
- (void)ACAudioRoutine:(RTKACAudioRoutine *)routine didReceiveChangeOfAPTState:(BOOL)isOn;

- (void)BBproAudioRoutine:(RTKACAudioRoutine *)routine didReceiveChangeOfAPTState:(BOOL)isOn RTK_REDIRECT(ACAudioRoutine:didReceiveChangeOfAPTState:);


/// Tells the delegate that remote device did change current ANC state.
///
/// - Parameter routine: The routine object which report this event.
/// - Parameter isOn: Whether the ANC feature is on.
- (void)ACAudioRoutine:(RTKACAudioRoutine *)routine didReceiveChangeOfANCState:(BOOL)isOn;

- (void)BBproAudioRoutine:(RTKACAudioRoutine *)routine didReceiveChangeOfANCState:(BOOL)isOn RTK_REDIRECT(ACAudioRoutine:didReceiveChangeOfANCState:);

/// Tells the delegate that remote device did update ANC state.
///
/// - Parameter routine: The routine object which reports this event.
/// - Parameter isOn: Whether the ANC is on.
/// - Parameter modes: All ANC modes supported by this device.
/// - Parameter idx: The mode index current used.
- (void)ACAudioRoutine:(RTKACAudioRoutine *)routine
didReceiveUpdateOfANCState:(BOOL)isOn
                 ANCModes:(NSArray<NSNumber*>*)modes
      currentANCModeIndex:(NSUInteger)idx;

- (void)BBproAudioRoutine:(RTKACAudioRoutine *)routine
didReceiveUpdateOfANCState:(BOOL)isOn
                 ANCModes:(NSArray<NSNumber*>*)modes
      currentANCModeIndex:(NSUInteger)idx RTK_REDIRECT(ACAudioRoutine:didReceiveUpdateOfANCState:ANCModes:currentANCModeIndex:);

/// Tells the delegate that remote device did change low latency state.
///
/// - Parameter routine: The routine object which reports this event.
/// - Parameter enabled: Whether *Low Latency* is on.
/// - Parameter value: The low latency value.
/// - Parameter lvl: The low latency level.
- (void)ACAudioRoutine:(RTKACAudioRoutine *)routine
didReceiveUpdateOfLowLatencyEnabled:(BOOL)enabled
          lowLatencyValue:(NSUInteger)value
          lowLatencyLevel:(NSUInteger)lvl;

- (void)BBproAudioRoutine:(RTKACAudioRoutine *)routine
didReceiveUpdateOfLowLatencyEnabled:(BOOL)enabled
          lowLatencyValue:(NSUInteger)value
          lowLatencyLevel:(NSUInteger)lvl RTK_REDIRECT(ACAudioRoutine:didReceiveUpdateOfLowLatencyEnabled:lowLatencyValue:lowLatencyLevel:);

/**
 * Tells the delegate that RTKACEQRoutine received the captured data.
 *
 * @param routine The routine that report data info.
 * @param receivedPck The number of packets actually received.
 * @param totalPck The number of packets that should be received.
 * @param captureData Raw data received.
 * @param probeData The data parsed from captureData.
 * @param sbcData The data parsed from probeData.
 * @param pcmData The data parsed from sbcData.
 */
- (void)ACAudioRoutine:(RTKACAudioRoutine *)routine didReceivePCKNum:(NSUInteger)receivedPck totalPckNum:(NSUInteger)totalPck withCaptureData:(NSData*)captureData probeData:(NSData *)probeData sbcData:(NSData*)sbcData pcmData:(NSData*)pcmData;

- (void)BBproAudioRoutine:(RTKACAudioRoutine *)routine didReceivePCKNum:(NSUInteger)receivedPck totalPckNum:(NSUInteger)totalPck withCaptureData:(NSData*)captureData probeData:(NSData *)probeData sbcData:(NSData*)sbcData pcmData:(NSData*)pcmData RTK_REDIRECT(ACAudioRoutine:didReceivePCKNum:totalPckNum:withCaptureData:probeData:sbcData:pcmData:);

@end


/// An object that access Audio related state of a corresponding *Audio Connect *device.
///
/// You don't create an `RTKACAudioRoutine` yourself. ``RTKACConnectionUponGATT`` and ``RTKACConnectionUponiAP`` conform to ``RTKACRoutineContainer``, providing the Audio routine you can use.
@interface RTKACAudioRoutine : RTKACRoutine

/// An object that receives Audio state related events.
@property (weak) id <RTKACAudioRoutineStateReporting> delegate;

/// The basic routine this Audio routine depends.
@property RTKACBasicRoutine *basicRoutine;

#pragma mark - Listening mode cycle

/// Get the Listening mode cycle of the corresponding device.
///
/// - Parameter handler: A block to be called when the task complete successfullly or unsuccessfully.
///
/// Will update `listeningSwitchCycle` property if succeed.
- (void)getListeningModeSwitchCycleInfoWithCompletionHandler:(nullable void (^)(BOOL success, NSError *_Nullable error, RTKACListeningModeSwitchCycle cycle))handler;


/// Set the Listening mode cycle of the corresponding device.
///
/// - Parameter cycle: The circular pattern.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `listeningSwitchCycle` property if succeed.
- (void)setListeningSwitchCycle:(RTKACListeningModeSwitchCycle)cycle withCompletionHandler:(nullable RTKLECompletionBlock)handler;


#pragma mark - Listening mode report

/// Set listening mode of the corresponding device.
///
/// - Parameter type: The listening mode.
/// - Parameter index: The scenario index in the current listening mode. If there is no scenario in this mode, the index should be 0.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `ANCEnabled`, `APTState`, `LLAPTEnabled`, `currentANCModeIndex`, `currentANCAPTModeIndex` and `currentLLAPTScenarioIndex` if succeed.
-(void)setListeningStateofType:(RTKACListeningModeType)type andIndex:(uint8_t)index withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Get listening mode of the corresponding device.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `ANCEnabled`, `APTState`, `LLAPTEnabled`, `currentANCModeIndex`, `currentANCAPTModeIndex` and `currentLLAPTScenarioIndex` if succeed.
-(void)getListeningStateStatusWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


#pragma mark - APT

/// Get the APT on-off state of the corresponding device.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `APTState` property if succeed.
- (void)getAPTStateWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, BOOL state))handler;


/// Switch the APT on-off state of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `APTState` property if succeed.
- (void)switchAPTStateWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


#pragma mark - APT Power On Delay Time

/// Get the delay time of APT after the peripheral is powered on.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `APTDelayTime` property when succeed.
-(void)getAPTPowerOnDelayTimeWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, uint8_t delayTime))handler;


/// Set the delay time of APT after the peripheral is powered on.
///
/// - Parameter delayTime: The value ranges from 0 to 31. Unit: second
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `APTDelayTime` property when succeed.
-(void)setAPTPowerOnDelayTime:(uint8_t)delayTime withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


#pragma mark - LLAPT

/// Get the LLAPT state  and scenario info of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `LLAPTEnabled`, `currentLLAPTScenarioIndex` and `LLAPTScenarios` properties when succeed.
- (void)getLLAPTStateWithCompletionHandler:(nullable void (^)(BOOL success, NSError *_Nullable error, BOOL enabled, NSUInteger currentScenarioIndex, NSArray<NSNumber*> *scenarios))handler;


/// Set the LLAPT state of this peripheral.
///
/// - Parameter enabled: A boolean value indicates LLAPT on or off.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `LLAPTEnabled` property when succeed.
- (void)setLLAPTEnable:(BOOL)enabled withCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Set the current LLAPT scenario index of this peripheral.
///
/// - Parameter index: The current LLAPT scenario index.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `currentLLAPTScenarioIndex` property when succeed.
- (void)setCurrentLLAPTScenarioIndex:(NSUInteger)index withCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Set  LLAPT state and scenario index of this peripheral.
///
/// - Parameter enabled: A boolean value indicates LLAPT on or off.
/// - Parameter index: The current LLAPT scenario index.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `LLAPTEnabled` and `currentLLAPTScenarioIndex` properties when succeed.
- (void)setEnable:(BOOL)enabled ofLLAPTScenarioIndex:(NSUInteger)index withCompletionHandler:(nullable RTKLECompletionBlock)handler;


#pragma mark - ANC

/// Get the specify ANC(ANC+ normal APT) state and scenario info of this peripheral. (basicRoutine isAvaliableFor:RTKACCapabilityType_SpecialANCScenario)
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `ANCEnabled`, `APTState`, `currentANCAPTModeIndex` and `ANCAPTModes` properties when succeed.
- (void)querySpecifyANCStateWithCompletionHandler:(nullable void (^)(BOOL success, NSError *_Nullable error, BOOL enabled, NSUInteger currentModeIndex, NSArray<NSNumber*> * modes))handler;


/// Get the ANC state and scenario info of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `ANCEnabled`, `currentANCModeIndex` and `ANCModes` properties when succeed.
- (void)getANCStateWithCompletionHandler:(nullable void (^)(BOOL success, NSError *_Nullable error, BOOL enabled, NSUInteger currentModeIndex, NSArray<NSNumber*> * modes))handler;


/// Set the ANC state of this peripheral.
///
/// - Parameter enabled: A boolean value indicates ANC on or off.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `ANCEnabled` property when succeed.
- (void)setANCEnable:(BOOL)enabled withCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Set the ANC scenario index of this peripheral.
///
/// - Parameter index: The current ANC scenario index.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `currentANCModeIndex` property when succeed.
- (void)setCurrentANCModeIndex:(NSUInteger)index withCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Set the ANC state and scenario index of this peripheral.
///
/// - Parameter enabled: A boolean value indicates ANC on or off.
/// - Parameter index: The current ANC scenario index.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `ANCEnabled` and `currentANCModeIndex` properties when succeed.
- (void)setEnable:(BOOL)enabled ofANCModeIndex:(NSUInteger)index withCompletionHandler:(nullable RTKLECompletionBlock)handler;


#pragma mark - APT NR

/// Return whether the APT Noice Reduction is on of this peripheral last cached.(deprecated)
///
/// Scalar value is of `BOOL` type.
@property (nonatomic, readonly, nullable) NSNumber *APTNRStatus;


/// Get the APT NR on-off state of this peripheral. (deprecated)
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `APTNRStatus` property when succeed.
- (void)getAPTNRStatusWithCompletionHandler:(void(^)(BOOL success, NSError*_Nullable error))handler;


/// Switch the APT NR on-off state of this peripheral. (deprecated)
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `APTNRStatus` property when succeed.
- (void)switchAPTNROnOffWithCompletion:(RTKLECompletionBlock)handler;


/// Set the APT NR state of this peripheral.
///
/// - Parameter onOrOff: A boolean value indicates APT NR on or off.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `APTNRState` property when succeed.
-(void)setAPTNRState:(uint8_t)onOrOff withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Get the APT NR on-off state of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `APTNRState` property when succeed.
-(void)getAPTNRStateWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, uint8_t state))handler;


#pragma mark - APT Gain (deprecated)

/// Return the APT Noice Reduction gain level of this peripheral last cached.
///
/// Scalar value is of unsigned integer type.
@property (nonatomic, readonly, nullable) NSNumber *APTGainLevel;


/// Return the maximum APT Noice Reduction gain level of this peripheral last cached.
///
/// Scalar value is of unsigned integer type. This property is not KVO applicable.
@property (nonatomic, readonly, nullable) NSNumber *maximumAPTGainLevel;


/// Get the APT Gain level of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `APTGainLevel`, `maximumAPTGainLevel` property when succeed.
- (void)getAPTGainLevelWithCompletionHandler:(void(^)(BOOL success, NSError*_Nullable error, NSUInteger gain, NSUInteger maxGain))handler;


/// Set the APT Gain level of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `APTGainLevel` property when succeed.
- (void)setAPTGainLevel:(NSUInteger)level withCompletionHandler:(RTKLECompletionBlock)handler;


/// Set the APT Gain level by increase of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `APTGainLevel` property when succeed.
- (void)increaseAPTGainLevelWithCompletionHandler:(RTKLECompletionBlock)handler;


/// Set the APT Gain level by decrease of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `APTGainLevel` property when succeed.
- (void)decreaseAPTGainLevelWithCompletionHandler:(RTKLECompletionBlock)handler;


#pragma mark - APT Volume

/// Get the APT Volume info of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `maxMainAPTVolumeLevel`, `maxSubAPTVolumeLevel`, `leftMainAPTVolumeLevel`, `leftSubAPTVolumeLevel`, `rightMainAPTVolumeLevel`, `rightSubAPTVolumeLevel` and `syncAPTVolume` (if support) properties when succeed.
- (void)getAPTVolumeInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, uint8_t maxMainLevel, uint16_t maxSubLevel, uint8_t leftMainLevel, uint16_t leftSubLevel, uint8_t rightMainLevel, uint8_t rightSubLevel))handler;


/// Set current APT Volume level of this peripheral.
///
/// - Parameter volumeType: The APT volume type (Main or Sub).
/// - Parameter leftVolume: The APT volume of left bud.
/// - Parameter rightVolume: The APT voume of right bud.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `leftMainAPTVolumeLevel`, `leftSubAPTVolumeLevel`, `rightMainAPTVolumeLevel` and `rightSubAPTVolumeLevel` properties when succeed.
- (void)setAPTVolumeLevelofType:(RTKACAPTVolumeType)volumeType withLeftVolume:(uint16_t)leftVolume andRightVolume:(uint16_t)rightVolume withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Get the APT Volume level of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `leftMainAPTVolumeLevel`, `leftSubAPTVolumeLevel`, `rightMainAPTVolumeLevel` and `rightSubAPTVolumeLevel` properties when succeed.
- (void)getAPTVolumeStatusWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, uint8_t leftMainLevel, uint16_t leftSubLevel, uint8_t rightMainLevel, uint8_t rightSubLevel))handler;


/// Get the APT Volume Sync state of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `syncAPTVolume` when succeed.
- (void)getAPTVolumeSyncStateWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Switch the APT Volume Sync state of this peripheral.
/// @param handler A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `syncAPTVolume` when succeed.
- (void)switchAPTVolumeSyncStateWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Set current APT Volume level of this peripheral (basicRoutine.cmdVersionNumber is 0x0104/0x0105).
///
/// - Parameter APTVolumeOutLevel: The APT volume of left and right buds.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `APTVolumeOutLevel` when succeed.
-(void)setAPTVolumeOutLevel:(uint8_t)APTVolumeOutLevel withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Get current APT Volume level of this peripheral (basicRoutine.cmdVersionNumber is 0x0104/0x0105).
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `APTVolumeOutLevel` when succeed.
-(void)getAPTVolumeOutLevelWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, uint8_t volumeLevel))handler;


#pragma mark - APT Brightness

/// Get the APT brightness info of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `maxMainBrightnessLevel`, `maxSubBrightnessLevel`, `leftMainBrightnessLevel`, `leftSubBrightnessLevel`, `rightMainBrightnessLevel`,  `rightSubBrightnessLevel`  and `syncAPTBrightness` (if support) properties when succeed.
- (void)getAPTBrightnessInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, uint8_t maxMainLevel, uint16_t maxSubLevel, uint8_t leftMainLevel, uint16_t leftSubLevel, uint8_t rightMainLevel, uint8_t rightSubLevel))handler;


/// Set current APT brightness level of this peripheral.
///
/// - Parameter type: The APT brightness type (Main or Sub).
/// - Parameter leftBrightness: The APT Brightness of left bud.
/// - Parameter rightBrightness: The APT Brightness of right bud.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `leftMainAPTVolumeLevel`, `leftSubAPTVolumeLevel`, `rightMainAPTVolumeLevel` and `rightSubAPTVolumeLevel` properties when succeed.
- (void)setAPTBrightnessLevelofType:(RTKACAPTBrightnessType)type withLeftBrightness:(uint16_t)leftBrightness andRightBrightness:(uint16_t)rightBrightness withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Set current APT brightness level and sync state of this peripheral.
///
/// - Parameter type: The APT brightness type (Main or Sub).
/// - Parameter leftBrightness: The APT Brightness of left bud.
/// - Parameter rightBrightness: The APT Brightness of right bud.
/// - Parameter sync: A boolean value indicates whether left and right brightness level are consistent.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `leftMainAPTVolumeLevel`, `leftSubAPTVolumeLevel`, `rightMainAPTVolumeLevel` and `rightSubAPTVolumeLevel` and `syncAPTBrightness` properties when succeed.
- (void)setAPTBrightnessLevelofType:(RTKACAPTBrightnessType)type withLeftBrightness:(uint16_t)leftBrightness andRightBrightness:(uint16_t)rightBrightness Sync:(uint8_t)sync withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Get current APT brightness level of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `leftMainBrightnessLevel`, `leftSubBrightnessLevel`, `rightMainBrightnessLevel`,  `rightSubBrightnessLevel`  and `syncAPTBrightness` (if support) properties when succeed.
- (void)getAPTBrightnessStatusWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, uint8_t leftMainLevel, uint16_t leftSubLevel, uint8_t rightMainLevel, uint8_t rightSubLevel))handler;


#pragma mark - LLAPT Scenario Group Setting

/// Get LLAPT Scenario info of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `LLAPTGroupsNumber` and `scenarios` when succeed.
-(void)getLLAPTScenarioChooseInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error,NSInteger groupsNumber, NSArray<NSNumber *> *scenarios))handler;


/// Try the effect of the selected scenario.
///
/// - Parameter LEnable: A boolean value indicates the LLAPT state of left bud is on or off.
/// - Parameter LIndex: The LLAPT scenario index of left bud.
/// - Parameter REnable: A boolean value indicates the LLAPT state of right bud is on or off.
/// - Parameter RIndex: The LLAPT scenario index of right bud.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Listening to the effect of current scenario setting and will not affect other properties.
-(void)tryLLAPTScenarioOfLChannelType:(uint8_t)LEnable andLChannelIndex:(uint8_t)LIndex andRChannelType:(uint8_t)REnable andRChannelIndex:(uint8_t)RIndex withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Save and get the result(success or unsuccess) after modifing the group settings of this peripheral.
///
/// - Parameter LScenarioList: The scenario setting of left bud (In binary).
/// - Parameter RScenarioList: The scenario setting of right bud (In binary).
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `LLAPTEnabled`, `currentLLAPTScenarioIndex` and `LLAPTScenarios` properties when succeed.
-(void)getLLAPTScenarioChooseResultofLScenarioList:(uint32_t)LScenarioList andRScenarioList:(uint32_t)RScenarioList withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Get LLAPT scenario result after tring the effect but not saving the modified settings.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `LLAPTEnabled`, `currentLLAPTScenarioIndex` and `LLAPTScenarios` properties when succeed.
-(void)getLLAPTScenarioChooseResultWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;

#pragma mark - ANC Scenario Group Setting

/// Get ANC Scenario info of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `ANCGroupsNumber` and `ANCScenarios` when succeed.
-(void)getANCScenarioChooseInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error,NSInteger groupsNumber, NSArray<NSNumber *> *scenarios))handler;


/// Try the effect of the selected scenario.
///
/// - Parameter LEnable: A boolean value indicates the ANC state of left bud is on or off.
/// - Parameter LIndex: The ANC scenario index of left bud.
/// - Parameter REnable: A boolean value indicates the ANC state of right bud is on or off.
/// - Parameter RIndex: The ANC scenario index of right bud.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Listening to the effect of current scenario setting and will not affect other properties.
-(void)tryANCScenarioOfLChannelType:(uint8_t)LEnable andLChannelIndex:(uint8_t)LIndex andRChannelType:(uint8_t)REnable andRChannelIndex:(uint8_t)RIndex withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Save and get the result(success or unsuccess) after modifing the ANC group settings of this peripheral.
///
/// - Parameter LScenarioList: The scenario setting of left bud (In binary).
/// - Parameter RScenarioList: The scenario setting of right bud (In binary).
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `ANCEnabled`, `currentANCModeIndex` and `ANCModes` properties when succeed.
-(void)getANCScenarioChooseResultofLScenarioList:(uint32_t)LScenarioList andRScenarioList:(uint32_t)RScenarioList withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Get ANC scenario result after tring the effect but not saving the modified settings.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `ANCEnabled`, `currentANCModeIndex` and `ANCModes` properties when succeed.
-(void)getANCScenarioChooseResultWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


#pragma mark - ANC Burn/Apply

/// Get ANC/LLAPT scenario filter information.
///
/// - Parameter channel: Specify the budSide. 0x01: Left channel 0x02:Right channel.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
///  `filterInfo` will be returned in `handler` when succeed.
- (void)getFilterInfoOfChannel:(uint8_t)channel withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKACFilterInfo *filterInfo))handler;

/// Get ANC/LLAPT scenario parameters information.
///
/// - Parameter channel: Specify the budSide. 0x01: Left channel 0x02:Right channel.
/// - Parameter type: Specify the scenario type. 0x00: ANC 0x01:LLAPT
/// - Parameter index: Specify the scenario group index.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// `paraData` will be returned in `handler` when succeed.
- (void)getANCAPTParametersOfChannel:(uint8_t)channel paraType:(uint8_t)type andIndex:(uint8_t)index withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, NSData *paraData))handler;

/// Set ANC/LLAPT scenario parameters information.
///
/// - Parameter data: The scenario parameters data before modifying.
/// - Parameter filterPara: The modified filter parameters. The key represents filterType information(`RTKACFilterType`). The value represents the modified filter parameters( `NSMutableArray` {{b0,b1,b2,a1,a2,shiftType,shiftValue},{b0,b1,b2,a1,a2,shiftType,shiftValue}...}).
/// - Parameter filterInfo: The filter information of the specified channel.
/// - Parameter channel: Specify the budSide. 0x01: Left channel 0x02:Right channel.
/// - Parameter mode: 0x00 burn mode, 0x01 apply mode.
/// - Parameter type: Specify the scenario type. 0x00: ANC 0x01:LLAPT
/// - Parameter groupIndex: Specify the scenario group index.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
- (void)setANCAPTParametersWithInitialData:(NSData *)data newFilterPara:(NSMutableDictionary *)filterPara andFilterInfo:(RTKACFilterInfo*)filterInfo channel:(uint8_t)channel mode:(uint8_t)mode type:(uint8_t)type index:(uint8_t)groupIndex withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;

#ifndef RTKWaveLiteSDK
#pragma mark - Data Capture

/// Enter/Exit DSP Capture Scenario.
///
/// - Parameter enable: 0x00: exit 0x01:enter
/// - Parameter bud: 0x01:left bud 0x02:right bud
- (void)enterOrExitDSPCaptureScenario: (BOOL)enable withBudSide:(uint8_t)bud completionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, uint8_t curStateMask))handler;

/// Start/Stop data capture.
///
/// - Parameter enable: 0x00: stop 0x01:start
/// - Parameter micType: Specify the logic mic type. (FF/FB/Voice)
/// - Parameter probeSource: Specify the probe sources. (The number of sources is less than or equal to 2)
/// - Parameter sbcConfig:  {RTKSBCConfigSamplingFrequency, RTKSBCConfigChannelMode, RTKSBCConfigBlockLength, RTKSBCConfigSubBandNumber, RTKSBCConfigAllocationMethod, bitpool}
- (void)startOrStopCapture:(BOOL)enable withLogicMic:(RTKLogicMicType)micType probeSource:(NSArray *)probeSource andSBCConfig:(NSArray *)sbcConfig completionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;
#endif

#pragma mark - Low latency

/// Switch the gaming mode on-off state of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `gamingModeEnabled` property when succeed.
- (void)switchGamingModeEnableWithCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Get the Low latency state of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `gamingModeEnabled`, `lowLatencyValue`, `lowLatencyLevel` and `maxLowLatencyLevel` properties when succeed.
- (void)getLowLatencyStateWithCompletionHandler:(nullable void(^)(BOOL success, NSError *err, BOOL enabled, NSUInteger value, NSUInteger level, NSUInteger maxLevel))handler;

/// Set the Low latency level of this peripheral.
///
/// - Parameter level: The low latency level.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update lowLatencyLevel property when succeed.
- (void)setLowLatencyLevel:(NSUInteger)level withCompletionHandler:(nullable RTKLECompletionBlock)handler;


#pragma mark - Switch normal APT and LLAPT

/// Query APT type that is selected currently when both APT types are supported.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
- (void)queryAPTTypeInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError *err, RTKACAPTType APTType))handler;


/// Select to apply one APT type when both APT types are supported.
///
/// - Parameter type: one of the APT type.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
- (void)setAPTType:(RTKACAPTType)type withCompletionHandler:(nullable void(^)(BOOL success, NSError *err, RTKACAPTType APTType))handler;

@end



@interface RTKACAudioRoutine (Cache)

/// Return the listening mode switch cycle last cached of this device.
///
/// Scalar value is of ``RTKACListeningModeSwitchCycle`` type. Affected by ``RTKACAudioRoutine/getListeningModeSwitchCycleStateWithCompletionHandler:`` and ``RTKACAudioRoutine/setListeningSwitchCycle:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *listeningSwitchCycle;

#pragma mark - Audio Pass Through

/// Return the current APT type.
///
/// Scalar value is of ``RTKACAPTType`` type. Affected by ``RTKACAudioRoutine/queryAPTTypeWithCompletionHandler:`` and ``RTKACAudioRoutine/assignAPTType:withCompletionHandler:``.
@property (nonatomic, nullable, readonly) NSNumber *currentAPTType;

/// Return the current listening mode.
///
/// Scalar value is of `RTKACListeningModeType` type.
@property (nonatomic, nullable, readonly) NSNumber *currentListeningMode;

/// Return the APT on-off state of this device last cached.
///
/// Scalar value is of `BOOL` type. Affected by ``RTKACAudioRoutine/getAPTStateWithCompletionHandler:`` and ``RTKACAudioRoutine/switchAPTStateWithCompletionHandler:`` and device active notification.
@property (nonatomic, nullable, readonly) NSNumber *APTState;


/// Return the LLAPT on-off state of this device last cached.
///
/// Scalar value is of `BOOL` type. Affected by ``RTKACAudioRoutine/getLLAPTStateWithCompletionHandler:`` and ``RTKACAudioRoutine/setLLAPTEnable:withCompletionHandler:`` and device active notification.
@property (nonatomic, nullable, readonly) NSNumber *LLAPTEnabled;


/// Return the LLAPT scenario index last cached of this device.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getLLAPTStateWithCompletionHandler:``, ``RTKACAudioRoutine/setCurrentLLAPTScenarioIndex:withCompletionHandler:`` and ``RTKACAudioRoutine/setEnable:ofLLAPTScenarioIndex:withCompletionHandler:``.
@property (nonatomic, nullable) NSNumber *currentLLAPTScenarioIndex;


/// Return a list of LLAPT scenarios last cached of this device.
///
/// For each item, scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getLLAPTStateWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSArray<NSNumber*> *LLAPTScenarios;


/// Return a list indicating whether LLAPT scenario N supports brightness.
///
/// For each item, scalar value is of `BOOL` type. Affected by ``RTKACAudioRoutine/getLLAPTStateWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSArray<NSNumber*> *supportedLLAPTBrightnessIndicator;


/// Return the count of LLAPT scenario groups last cached of this device.
///
/// For each item, scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getLLAPTScenarioChooseInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *LLAPTGroupsNumber;


/// Return a list of LLAPT scenarios last cached of this device (All scenarios, no matter the scenario is enabled or not. The value will not change).
///
/// For each item, scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getLLAPTScenarioChooseInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSArray<NSNumber *> *scenarios;


/// Return whether the APT NR is on of this peripheral last cached.
///
/// Scalar value is of BOOL type. Affected by ``RTKACAudioRoutine/getAPTNRStateWithCompletionHandler:`` and ``RTKACAudioRoutine/setAPTNRState:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *APTNRState;


/// Return the APT Delay Time of this peripheral last cached.
///
/// Scalar value is of unsigned integer type. Unit is second. Affected by ``RTKACAudioRoutine/getAPTPowerOnDelayTimeWithCompletionHandler:``, ``RTKACAudioRoutine/setAPTPowerOnDelayTime:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *APTDelayTime;


/// Return whether the left and right volume are in sync.
///
/// Scalar value is of `BOOL` type. Affected by ``RTKACAudioRoutine/getAPTVolumeSyncStateWithCompletionHandler:`` and ``RTKACAudioRoutine/switchAPTVolumeSyncStateWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *syncAPTVolume;


/// Return the maximum Main APT volume level of this peripheral last cached.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getAPTVolumeInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *maxMainAPTVolumeLevel;


/// Return the maximum Sub APT volume level of this peripheral last cached.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getAPTVolumeInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *maxSubAPTVolumeLevel;


/// Return the current Main APT volume level of the left bud last cached.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getAPTVolumeInfoWithCompletionHandler:``, ``RTKACAudioRoutine/setAPTVolumeLevelofType:withLeftVolume:andRightVolume:withCompletionHandler:`` and ``RTKACAudioRoutine/getAPTVolumeStatusWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *leftMainAPTVolumeLevel;


/// Return the current Sub APT volume level of the left bud last cached.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getAPTVolumeInfoWithCompletionHandler:``, ``RTKACAudioRoutine/setAPTVolumeLevelofType:withLeftVolume:andRightVolume:withCompletionHandler:`` and ``RTKACAudioRoutine/getAPTVolumeStatusWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *leftSubAPTVolumeLevel;


/// Return the current Main APT volume level of the right bud last cached.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getAPTVolumeInfoWithCompletionHandler:``, ``RTKACAudioRoutine/setAPTVolumeLevelofType:withLeftVolume:andRightVolume:withCompletionHandler:`` and ``RTKACAudioRoutine/getAPTVolumeStatusWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *rightMainAPTVolumeLevel;


/// Return the current Sub APT volume level of the right bud last cached.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getAPTVolumeInfoWithCompletionHandler:``, ``RTKACAudioRoutine/setAPTVolumeLevelofType:withLeftVolume:andRightVolume:withCompletionHandler:`` and ``RTKACAudioRoutine/getAPTVolumeStatusWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *rightSubAPTVolumeLevel;


/// Return the current APT Volume level of this peripheral last cached.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getAPTVolumeOutLevelWithCompletionHandler:``, ``RTKACAudioRoutine/setAPTVolumeOutLevel:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *APTVolumeOutLevel;


/// Return the maximum Main APT Brightness level of this peripheral last cached.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getAPTBrightnessInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *maxMainBrightnessLevel;


/// Return the maximum Sub APT Brightness level of this peripheral last cached.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getAPTBrightnessInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *maxSubBrightnessLevel;


/// Return the current Main APT Brightness level of the left bud last cached.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getAPTBrightnessInfoWithCompletionHandler:``, ``RTKACAudioRoutine/setAPTBrightnessLevelofType:withLeftBrightness:andRightBrightness:withCompletionHandler:``, ``RTKACAudioRoutine/getAPTBrightnessInfoWithCompletionHandler:`` and  ``RTKACAudioRoutine/setAPTBrightnessLevelofType:withLeftBrightness:andRightBrightness:Sync:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *leftMainBrightnessLevel;


/// Return the current Sub APT Brightness level of the left bud last cached.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getAPTBrightnessInfoWithCompletionHandler:``, ``RTKACAudioRoutine/setAPTBrightnessLevelofType:withLeftBrightness:andRightBrightness:withCompletionHandler:``, ``RTKACAudioRoutine/getAPTBrightnessInfoWithCompletionHandler:`` and ``RTKACAudioRoutine/setAPTBrightnessLevelofType:withLeftBrightness:andRightBrightness:Sync:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *leftSubBrightnessLevel;


/// Return the current Main APT Brightness level of the right bud last cached.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getAPTBrightnessInfoWithCompletionHandler:``, ``RTKACAudioRoutine/setAPTBrightnessLevelofType:withLeftBrightness:andRightBrightness:withCompletionHandler:``, ``RTKACAudioRoutine/getAPTBrightnessInfoWithCompletionHandler:`` and ``RTKACAudioRoutine/setAPTBrightnessLevelofType:withLeftBrightness:andRightBrightness:Sync:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *rightMainBrightnessLevel;


/// Return the current Sub APT Brightness level of the right bud last cached.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getAPTBrightnessInfoWithCompletionHandler:``, ``RTKACAudioRoutine/setAPTBrightnessLevelofType:withLeftBrightness:andRightBrightness:withCompletionHandler:``, ``RTKACAudioRoutine/getAPTBrightnessInfoWithCompletionHandler:`` and ``RTKACAudioRoutine/setAPTBrightnessLevelofType:withLeftBrightness:andRightBrightness:Sync:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *rightSubBrightnessLevel;


/// Return whether the left and right brightness are in sync.
///
/// Scalar value is of `BOOL` type. Affected by ``RTKACAudioRoutine/getAPTBrightnessInfoWithCompletionHandler:``, ``RTKACAudioRoutine/setAPTBrightnessLevelofType:withLeftBrightness:andRightBrightness:Sync:withCompletionHandler:`` and ``RTKACAudioRoutine/getAPTBrightnessStatusWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *syncAPTBrightness;


@property (nonatomic, readonly, nullable) NSNumber *ANCAPTEnabled;

#pragma mark - ANC mode

/// Return the ANC on-off state last cached of this device.
///
/// Scalar value is of `BOOL` type. Affected by ``RTKACAudioRoutine/getANCStateWithCompletionHandler:`` and ``RTKACAudioRoutine/setANCEnable:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *ANCEnabled;


/// Return the ANC scenario index last cached of this device.
///
/// Scalar value is of ``RTKACANCScenario`` type. Affected by ``RTKACAudioRoutine/getANCStateWithCompletionHandler:`` and ``RTKACAudioRoutine/setCurrentANCModeIndex:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *currentANCModeIndex;


/// Return the ANC+APT scenario index last cached of this device.
///
/// Scalar value is of `RTKACANCScenario` type. Affected by ``RTKACAudioRoutine/querySpecifyANCStateWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *currentANCAPTModeIndex;


/// Return a list of ANC modes last cached of this device.
///
/// For each item, scalar value is of ``RTKACANCScenario`` type. Affected by ``RTKACAudioRoutine/getANCStateWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSArray<NSNumber*> *ANCModes;


/// Return a list of ANC+APT modes last cached of this device.
///
/// For each item, scalar value is of ``RTKACANCScenario`` type. Affected by ``RTKACAudioRoutine/querySpecifyANCStateWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSArray<NSNumber*> *ANCAPTModes;


/// Return the count of ANC scenario groups last cached of this device.
///
/// For each item, scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getANCScenarioChooseInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *ANCGroupsNumber;


/// Return a list of ANC scenarios last cached of this device (All scenarios, no matter the scenario is enabled or not. The value will not change.).
///
/// For each item, scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getANCScenarioChooseInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSArray<NSNumber *> *ANCScenarios;


#pragma mark - Low latency

/// Return whether the gaming mode is on of this peripheral last cached.
///
/// Scalar value is of `BOOL` type. Affected by ``RTKACAudioRoutine/getLowLatencyStateWithCompletionHandler:`` and ``RTKACAudioRoutine/switchGamingModeEnableWithCompletionHandler:``.
@property (readonly, nullable) NSNumber *gamingModeEnabled;


/// Return the low lantency value of this peripheral last cached.
///
/// Scalar value is of  unsigned  integer type. Affected by ``RTKACAudioRoutine/getLowLatencyStateWithCompletionHandler:`` and ``RTKACAudioRoutine/setLowLatencyLevel:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *lowLatencyValue;


/// Return the low lantency level of this peripheral last cached.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getLowLatencyStateWithCompletionHandler:`` and ``RTKACAudioRoutine/setLowLatencyLevel:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *lowLatencyLevel;


/// Return the maximum low lantency level of this peripheral last cached.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACAudioRoutine/getLowLatencyStateWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *maxLowLatencyLevel;

@end



@interface RTKACAudioRoutine (Deprecated)

- (void)getListeningModeSwitchCycleStateWithCompletionHandler:(nullable void (^)(BOOL success, NSError *_Nullable error, RTKBBproListeningModeSwitchCycle cycle))handler RTK_REDIRECT(getListeningModeSwitchCycleInfoWithCompletionHandler:);


- (void)queryAPTTypeWithCompletionHandler:(nullable void(^)(BOOL success, NSError *err, RTKBBproAPTType APTType))handler RTK_REDIRECT(queryAPTTypeInfoWithCompletionHandler:);


- (void)assignAPTType:(RTKBBproAPTType)type withCompletionHandler:(nullable void(^)(BOOL success, NSError *err, RTKBBproAPTType APTType))handler RTK_REDIRECT(setAPTType:withCompletionHandler:);

- (void)setListeningSwitchCycleLegacy:(RTKBBproListeningModeSwitchCycle)cycle
                withCompletionHandler:(nullable RTKLECompletionBlock)handler
RTK_REDIRECT('setListeningSwitchCycle:withCompletionHandler:' with 'RTKACListeningModeSwitchCycle')
   NS_SWIFT_NAME(setListeningSwitchCycle(_:withCompletionHandler:));

- (void)setListeningStateofTypeLegacy:(RTKBBproListeningModeType)type
                             andIndex:(uint8_t)index
                withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler
RTK_REDIRECT('setListeningStateofType:andIndex:withCompletionHandler:' with 'RTKACListeningModeType')
   NS_SWIFT_NAME(setListeningState(ofType:index:withCompletionHandler:));

- (void)setAPTVolumeLevelofTypeLegacy:(RTKBBproAPTVolumeType)volumeType
                       withLeftVolume:(uint16_t)leftVolume
                       andRightVolume:(uint16_t)rightVolume
                withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler
RTK_REDIRECT('setAPTVolumeLevelofType:withLeftVolume:andRightVolume:withCompletionHandler:' with 'RTKACAPTVolumeType')
   NS_SWIFT_NAME(setAPTVolumeLevel(ofType:leftVolume:rightVolume:withCompletionHandler:));

- (void)setAPTBrightnessLevelofTypeLegacy:(RTKBBproAPTBrightnessType)type
                       withLeftBrightness:(uint16_t)leftBrightness
                       andRightBrightness:(uint16_t)rightBrightness
                    withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler
RTK_REDIRECT('setAPTBrightnessLevelofType:withLeftBrightness:andRightBrightness:withCompletionHandler:' with 'RTKACAPTBrightnessType')
   NS_SWIFT_NAME(setAPTBrightnessLevel(ofType:leftBrightness:rightBrightness:withCompletionHandler:));

- (void)setAPTBrightnessLevelofTypeLegacy:(RTKBBproAPTBrightnessType)type
                       withLeftBrightness:(uint16_t)leftBrightness
                       andRightBrightness:(uint16_t)rightBrightness
                                     Sync:(uint8_t)sync
                    withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler
RTK_REDIRECT('setAPTBrightnessLevelofType:withLeftBrightness:andRightBrightness:Sync:withCompletionHandler:' with 'RTKACAPTBrightnessType')
   NS_SWIFT_NAME(setAPTBrightnessLevel(ofType:leftBrightness:rightBrightness:sync:withCompletionHandler:));

@end

NS_ASSUME_NONNULL_END
