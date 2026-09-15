//
//  RTKACEQRoutine.h
//  RTKAudioConnctSDK
//
//  Created by jerome_gu on 2020/3/26.
//  Copyright (c) 2020, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <Foundation/Foundation.h>
#ifdef ATAudioConnectSDK
#import <ATAudioConnectSDK/RTKACRoutine.h>
#import <ATAudioConnectSDK/RTKACType.h>
#import <ATAudioConnectSDK/RTKACBasicRoutine.h>
#import <ATAudioConnectSDK/RTKACAudioRoutine.h>
#import <ATAudioConnectSDK/RTKACEQSetting.h>
#import <ATAudioConnectSDK/RTKACEQSettingPlaceholder.h>
#import <ATAudioConnectSDK/RTKMacros.h>
#import <ATAudioConnectSDK/RTKBBproType.h>
#import <ATAudioConnectSDK/RTKBBproEQSetting.h>
#import <ATAudioConnectSDK/RTKBBproEQSettingPlaceholder.h>
#elif defined(RTKWaveLiteSDK)
#import <RTKWaveLiteSDK/RTKACRoutine.h>
#import <RTKWaveLiteSDK/RTKACType.h>
#import <RTKWaveLiteSDK/RTKACBasicRoutine.h>
#import <RTKWaveLiteSDK/RTKACAudioRoutine.h>
#import <RTKWaveLiteSDK/RTKACEQSetting.h>
#import <RTKWaveLiteSDK/RTKACEQSettingPlaceholder.h>
#import <RTKWaveLiteSDK/RTKMacros.h>
#import <RTKWaveLiteSDK/RTKBBproType.h>
#import <RTKWaveLiteSDK/RTKBBproEQSetting.h>
#import <RTKWaveLiteSDK/RTKBBproEQSettingPlaceholder.h>
#else
#import <RTKAudioConnectSDK/RTKACRoutine.h>
#import <RTKAudioConnectSDK/RTKACBasicRoutine.h>
#import <RTKAudioConnectSDK/RTKACAudioRoutine.h>
#import <RTKAudioConnectSDK/RTKACType.h>
#import <RTKAudioConnectSDK/RTKACEQSetting.h>
#import <RTKAudioConnectSDK/RTKACEQSettingPlaceholder.h>
#import <RTKAudioConnectSDK/RTKMacros.h>
#import <RTKAudioConnectSDK/RTKBBproType.h>
#import <RTKAudioConnectSDK/RTKBBproEQSetting.h>
#import <RTKAudioConnectSDK/RTKBBproEQSettingPlaceholder.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@class RTKACEQRoutine;

/// Methods an ``RTKACEQRoutine`` calls to report EQ related events on its delegate.
@protocol RTKACEQRoutineStateReporting <NSObject>
@optional

/// Tells the delegate that remote device request to change EQ index.
///
/// - Parameter routine: The routine that did request change EQ index.
/// - Parameter index: The new index requested to change to.
/// - Parameter mode: The mode which EQ index is in.
///
/// When this method is called, action should be start to make the real EQ index changing. SDK will perform actual index changing process automatically, so delegate can leave it out.
- (void)ACEQRoutine:(RTKACEQRoutine *)routine didRequestChangeEQIndexTo:(NSUInteger)index ofEQMode:(RTKACEQMode)mode;

- (void)BBproEQRoutine:(RTKACEQRoutine *)routine didRequestChangeEQIndexTo:(NSUInteger)index ofEQMode:(RTKBBproEQMode)mode RTK_REDIRECT(ACEQRoutine:didRequestChangeEQIndexTo:ofEQMode:);


/// Tells the delegate that remote device did change EQ index.
///
/// - Parameter routine: The routine that report EQ index change.
/// - Parameter index: The EQ index current used.
- (void)ACEQRoutine:(RTKACEQRoutine *)routine didReceiveLegacyEQIndexChangeTo:(NSUInteger)index;

- (void)BBproEQRoutine:(RTKACEQRoutine *)routine didReceiveLegacyEQIndexChangeTo:(NSUInteger)index RTK_REDIRECT(ACEQRoutine:didReceiveLegacyEQIndexChangeTo:);

/// Tells the delegate that a EQ index of a specified mode did change of a RTKACEQRoutine instance.
///
/// - Parameter routine: The routine that report eq index change.
/// - Parameter index: The eq index which is updated to.
/// - Parameter mode: The EQ mode peripheral is using.
- (void)ACEQRoutine:(RTKACEQRoutine *)routine didReceiveEQIndexChange:(NSUInteger)index ofEQMode:(RTKACEQMode)mode;

- (void)BBproEQRoutine:(RTKACEQRoutine *)routine didReceiveEQIndexChange:(NSUInteger)index ofEQMode:(RTKBBproEQMode)mode RTK_REDIRECT(ACEQRoutine:didReceiveEQIndexChange:ofEQMode:);

/// Tells the delegate that a APT EQ index did change of a RTKACEQRoutine instance.
///
/// - Parameter routine: The routine that report APT eq index change.
/// - Parameter index: The eq index which is updated to.
- (void)ACEQRoutine:(RTKACEQRoutine *)routine didReceiveAPTEQIndexChange:(NSUInteger)index;

- (void)BBproEQRoutine:(RTKACEQRoutine *)routine didReceiveAPTEQIndexChange:(NSUInteger)index RTK_REDIRECT(ACEQRoutine:didReceiveAPTEQIndexChange:);

/// Tells the delegate that remote device request to synchronize EQ parameters.
///
/// - Parameter routine: The routine that report eq index change.
/// - Parameter index: The eq index which is updated to.
/// - Parameter mode: The EQ mode peripheral is using.
- (void)ACEQRoutine:(RTKACEQRoutine *)routine didRequestSynchronizeEQofIndex:(NSUInteger)index andMode:(RTKACEQMode)mode;

- (void)BBproEQRoutine:(RTKACEQRoutine *)routine didRequestSynchronizeEQofIndex:(NSUInteger)index andMode:(RTKBBproEQMode)mode RTK_REDIRECT(ACEQRoutine:didRequestSynchronizeEQofIndex:andMode:);

@end


/// An concrete routine which provides functionality to access EQ feature.
@interface RTKACEQRoutine : RTKACRoutine

/// The basic routine this routine uses.
@property RTKACBasicRoutine *basicRoutine;

/// The audio routine this routine uses.
@property RTKACAudioRoutine *audioRoutine;

/// The delegate object that receives events.
@property (nonatomic, weak) id <RTKACEQRoutineStateReporting> delegate;

#pragma mark - EQ General Info

/// Get the count of EQ setting entrys of all modes. (Deprecate in EQ 2.0)
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully. When succeed, a count of the specified EQ mode and type is received .
- (void)getEQEntryCountOfMode:(RTKACEQMode)mode
                         type:(RTKACSWEQType)type
        withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, NSUInteger count))handler;

/// Get the index of EQ setting entry current used of the specified mode. (Deprecate in EQ 2.0)
///
/// - Parameter mode: The specified EQ mode.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
- (void)getCurrentEQIndexOfMode:(RTKACEQMode)mode
          withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, NSUInteger idx))handler;

/// Get EQ info(count, index mapping, sampleRate) of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update the  ``numberOfSavedSPKEQ``, ``numberOfSavedMICEQ``, ``normalEQIndexArray``, ``gamingEQIndexArray``, ``ancEQIndexArray``, ``spkeqSettings``, ``currentNormalEQIndex``, ``currentGamingEQIndex``, ``currentANCEQIndex``, ``currentSampleRate``, ``supportedSampleRate``, ``currentSPKEQMode``, ``currentMICEQMode``, ``apteqSettings``, ``apteqSettingsOfLeft`` or ``apteqSettingsOfRight`` when succeed.
- (void)getEQInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;

#pragma mark - Switch EQ Index

/// Set the index of EQ setting entry current used of the specified mode.
///
/// - Parameter idx: The specified EQ index.
/// - Parameter mode: The specified EQ mode.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
- (void)setCurrentEQIndex:(NSUInteger)idx
                   ofMode:(RTKACEQMode)mode
    withCompletionHandler:(nullable RTKLECompletionBlock)handler;


#pragma mark - SPK EQ Parameters

/// Get the parameter data of a EQ setting entry specified by index of the specified mode. (Deprecate in EQ2.0)
///
/// - Parameter idx: The specified EQ index.
/// - Parameter mode: The specified EQ mode.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully. When succeed, a paraData is received along with sample rate.
- (void)getEQParameterOfIndex:(NSUInteger)idx
                       forMode:(RTKACEQMode)mode
                   withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKEQSampleRate sampleRate, NSData *_Nullable paraData))handler;


/// Send the parameter data to a EQ setting entry specified by index of the specified mode.(Deprecate in EQ2.0)
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
- (void)setEQParameterOfIndex:(NSUInteger)idx
                       ofMode:(RTKACEQMode)mode
                     withData:(NSData *)data
                 ofSampleRate:(RTKEQSampleRate)sampleRate
            withCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Get the parameter data of a EQ setting entry specified by index of the specified mode and use the parameter data to make the RTKACEQSetting object full-fledged. (Deprecate in EQ2.0)
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
- (void)getEQParameterAtIndex:(NSUInteger)idx
                       ofMode:(RTKACEQMode)mode
           toResolveEQSetting:(RTKACEQSetting *)setting
            withCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Set a EQ setting entry specified by index of the specified mode with a RTKACEQSetting object. (Deprecate in EQ2.0)
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
- (void)setEQParameterAtIndex:(NSUInteger)idx
                       ofMode:(RTKACEQMode)mode
                 ofSampleRate:(RTKEQSampleRate)sampleRate
                  withSetting:(RTKACEQSetting *)setting
            withCompletionHandler:(nullable RTKLECompletionBlock)handler;

// MARK: - EQ (SPEC 2.0)

/// Reset the specified EQ to the factory setting.
///
/// - Parameter type: The specified EQ type.
/// - Parameter mode: The specified EQ mode.
/// - Parameter index: The specified EQ mode index.
/// - Parameter side: The specified bud side.
/// - Parameter setting: The current EQ setting.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update the ``spkeqSettings``, ``apteqSettings``, ``apteqSettingsOfLeft`` or ``apteqSettingsOfRight`` when succeed.
- (void)resetEQSetting:(RTKACEQSetting *)setting
                ofType:(RTKACSWEQType)type
                 mode:(RTKACEQMode)mode
                index:(uint8_t)index
                  side:(RTKACEQBudSide)side
withCompletionHandler:(nullable void(^)(BOOL success, NSError * _Nullable error, RTKEQSampleRate sampleRate, NSData * _Nullable paraData))handler;


/// Set the specified EQ parameters.
///
/// - Parameter applyOrSave: Specifies whether the current EQ setting takes effect immediately or needs to be saved on the device.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update the ``spkeqSettings``, ``apteqSettings``, ``apteqSettingsOfLeft`` or ``apteqSettingsOfRight`` when succeed.
- (void)setEQParameterAtIndex:(NSUInteger)idx
                       ofType:(RTKACSWEQType)type
                       mode:(RTKACEQMode)mode
                 sampleRate:(RTKEQSampleRate)sampleRate
                  withSetting:(RTKACEQSetting *)setting
                       forBud:(RTKACEQBudSide)bud
                  applyOrSave:(RTKApplyOrSaveEQ)applyOrSave
        withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Set the specified EQ parameters with compensation supported.
///
/// - Parameter UISetting: The setting without compensation.
/// - Parameter finalSetting: The setting after compensation.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update the ``spkeqSettings``, ``apteqSettings``, ``apteqSettingsOfLeft`` or ``apteqSettingsOfRight`` when succeed.
- (void)setEQParameterAtIndex:(NSUInteger)idx
                       ofType:(RTKACSWEQType)type
                         mode:(RTKACEQMode)mode
                   sampleRate:(RTKEQSampleRate)sampleRate
                withUISetting:(nonnull RTKACEQSetting *)UISetting
        andCompensatedSetting:(nullable RTKACEQSetting *)finalSetting
                       forBud:(RTKACEQBudSide)bud
                  applyOrSave:(RTKApplyOrSaveEQ)applyOrSave
        withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Get the specified EQ parameters.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update the ``spkeqSettings``, ``apteqSettings``, ``apteqSettingsOfLeft`` or ``apteqSettingsOfRight`` when succeed.
- (void)getEQParameterAtIndex:(NSUInteger)idx
                       ofType:(RTKACSWEQType)type
                         mode:(RTKACEQMode)mode
                          bud:(RTKACEQBudSide)bud
           toResolveEQSetting:(RTKACEQSetting *)setting
        withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;

// MARK: - EQ (SPEC 3.0)

/// Set the specified EQ parameters.
///
/// - Parameter finalSetting: The EQ setting calculated by combining `UISetting` and `compensationSetting`.
/// - Parameter UISetting: The EQ setting without compensation.
/// - Parameter compensationSetting: The EQ setting that need to be compensated to `UISetting`.
/// - Parameter action: Specifies whether the current EQ setting takes effect immediately or needs to be saved on the device.
- (void)setEQParametersWithFinalSetting:(nonnull RTKACEQSetting *)finalSetting
                              UISetting:(nonnull RTKACEQSetting *)UISetting
                    compensationSetting:(nullable RTKACEQSetting *)compensationSetting
                                ofIndex:(NSUInteger)idx
                                    bud:(RTKACEQBudSide)bud
                                   type:(RTKACSWEQType)type
                                   mode:(RTKACEQMode)mode
                                 action:(RTKApplyOrSaveEQ)applyOrSave
                  withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Get the specified EQ parameters.
- (void)getEQParameterAtIndex:(NSUInteger)idx
                        ofBud:(RTKACEQBudSide)bud
                         type:(RTKACSWEQType)type
                         mode:(RTKACEQMode)mode
         toResolveUIEQSetting:(RTKACEQSetting *)UISetting
        compensationEQSetting:(nullable RTKACEQSetting *)compensationSetting
        withCompletionHandler:(nullable void (^)(BOOL, NSError * _Nullable, NSData * _Nullable paraData))handler;


/// Reset the specified EQ to the factory setting.
- (void)resetEQOfType:(RTKACSWEQType)type
                 mode:(RTKACEQMode)mode
                index:(uint8_t)index
                  bud:(RTKACEQBudSide)bud
 toResolveUIEQSetting:(RTKACEQSetting *)UISetting
compensationEQSetting:(nullable RTKACEQSetting *)compensationSetting
withCompletionHandler:(nullable void (^)(BOOL success, NSError * _Nullable error, NSData * _Nullable paraData))handler;


// MARK: - EQ (SPEC 3.2)

/// Queries the EQ format configuration from the connected device.
///
/// This method retrieves the supported EQ format versions for specific sample rates.
/// Once the query succeeds, the `eqFormatTable` property is updated, and the ordered values are returned in the block.
///
/// - Parameter handler: The completion block executed when the task finishes.
///   - success: `YES` if the query command was sent and a valid reply was received.
///   - error: An `NSError` object describing the failure, or `nil` if successful.
///   - formatArray: An ordered array of `NSNumber` objects (values of `RTKEQFormatVersion`).
///     The array indices correspond to the following sample rates:
///     - **Index 0**: 44.1 kHz
///     - **Index 1**: 48 kHz
///     - **Index 2**: 96 kHz
///     - **Index 3**: 192 kHz
- (void)queryEQFormatWithCompletionHandler:(nullable void (^)(BOOL success, NSError * _Nullable error, NSArray<NSNumber *> * _Nullable formatArray))handler;


#pragma mark - APT EQ

/// Get current APT EQ index of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update  ``apteqIndex``  when succeed.
- (void)getCurrentAPTEQIndexWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, NSUInteger APTEQIndex))handler;


/// Set current APT EQ index of this peripheral.
///
/// - Parameter index: The specified APT EQ index.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update ``apteqIndex`` when succeed.
- (void)setCurrentAPTEQIndex:(NSUInteger)index withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Get the specified APT EQ parameters of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update the specified APTEQSettings when succeed. (Deprecate in EQ2.0)
- (void)getEQParameterOfIndex:(NSUInteger)index type:(RTKACSWEQType)type inMode:(RTKACEQMode)mode withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKEQSampleRate sampleRate, NSData *_Nullable paraData))handler;


/// Set the specified APT EQ parameters of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update the specified APTEQSettings(left/right) when succeed. (Deprecate in EQ2.0)
- (void)setEQParameterOfIndex:(NSUInteger)index
                      andType:(RTKACSWEQType)type
                       inMode:(RTKACEQMode)mode
                     withData:(NSData *)data
                 ofSampleRate:(RTKEQSampleRate)sampleRate
                       forBud:(RTKACEQBudSide)bud
            withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Get the specified APT EQ parameters of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update the specified APTEQSettings when succeed. (Deprecate in EQ2.0)
- (void)getEQParameterAtIndex:(NSUInteger)idx ofType:(RTKACSWEQType)type inMode:(RTKACEQMode)mode toResolveEQSettings:(NSArray <RTKACEQSetting*> *)settings withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Set the specified APT EQ parameters of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update the specified APTEQSettings(left/right) when succeed. (Deprecate in EQ2.0)
- (void)setEQParameterAtIndex:(NSUInteger)idx
                       ofType:(RTKACSWEQType)type
                       inMode:(RTKACEQMode)mode
                 ofSampleRate:(RTKEQSampleRate)sampleRate
                  withSetting:(RTKACEQSetting *)setting
                       forBud:(RTKACEQBudSide)bud
            withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


#pragma mark - Legacy EQ setting

/// Get EQ Setting index of peripheral
///
/// - Parameter handler: This block is called upon completion. If the action take effect then success is YES and error is nil, and parameter currentIndex is the the EQ Setting Index current used in Peripheral, supportedIndexes is a bit field which indicate supported Indexes. Otherwise success is NO with an error.
- (void)getLegacyCurrentEQIndexWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKACEQIndex currentIndex, RTKACEQIndex supportedIndexes))handler;


/// Set current used EQ Setting of peripheral
///
/// - Parameter index: A bitmask whose EQ Setting to use bit set 1.
- (void)setLegacyCurrentEQIndexTo:(RTKACEQIndex)index withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Get DSP version information of Peripheral.
///
/// - Parameter handler: Called upon completion. If success, info is a dictionary containning DSP Info element (a example next), else a error is provided. info Dictionary example:  @{@"Scenario": @(0x00), @"SF": @(0x03), @"ROM": @(0x01010101), @"RAM": @(0x01010101), @"Patch": @(0x01010101), @"SDK": @(0x01010101)}
///
/// Deprecated by more recent device.
- (void)getDSPInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, NSDictionary <NSString*,NSNumber*>*_Nullable info))handler;


/// Set DSP EQ effect parameter.
///
/// - Parameter paramterData: EQ raw data to send to DSP. The data should be return by call -[RTKACEQSetting parameterDataOfSampleRate:] method.
/// - Parameter handler: This block is called upon completion. If the action take effect then success is YES and error is nil. Otherwise success is NO with an error.
///
/// This method set equalizer of 44.1kHz sample rate audio. Deprecated by more recent device.
- (void)setDSPEQ:(NSData *)paramterData withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Set DSP EQ effect parameter.
///
/// - Parameter paramterData: EQ raw data to send to DSP. The data should be return by call -[RTKACEQSetting parameterDataOfSampleRate:] method.
/// - Parameter sampleRate: The sample rate to which this EQ affect.
/// - Parameter handler: This block is called upon completion. If the action take effect then success is YES and error is nil. Otherwise success is NO with an error.
///
/// Deprecated by more recent device.
- (void)setDSPEQData:(NSData *)paramterData ofSampleRate:(RTKEQSampleRate)sampleRate withCompletionHandler:(nullable void(^)(BOOL, NSError*_Nullable))handler;


/// Clear DSP equalizer effect.
///
/// - Parameter handler: This block is called upon completion. If the action take effect then success is YES and error is nil. Otherwise success is NO with an error.
///
/// Deprecated by more recent device.
- (void)clearDSPEQWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;

@end



@interface RTKACEQRoutine (Cache)

#pragma mark - Legacy EQ

/// Return cached current EQ index used for a legacy SOC implementation.
///
/// Affected by ``RTKACEQRoutine/getLegacyCurrentEQIndexStateWithCompletionHandler:`` and ``RTKACEQRoutine/setLegacyCurrentEQIndexTo:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *legacyCurrentEQIndex;


/// Return cached supported EQ indexes used for a legacy SOC implementation.
///
/// Affected by ``RTKACEQRoutine/getLegacyCurrentEQIndexStateWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *legacySupportedEQIndexes;


/// Return an ``RTKACEQSetting`` instance which currently used of a legacy implementation.
@property (readonly, nullable) RTKACEQSetting *activeLegacyEQ;

#pragma mark - EQ spec < 2.0

/// Return a list of ``RTKACEQSetting`` objects which representing EQ settings in remote device runing normal mode.
///
/// Affected by ``RTKACEQRoutine/getEQEntryCountOfMode:type:withCompletionHandler:`` with ``RTKACEQMode/RTKACEQMode_normal``. The returned ``RTKACEQSetting`` object may not be fully determine the parameter. Call ``RTKACEQRoutine/getEQParameterAtIndex:ofMode:toResolveEQSetting:withCompletionHandler:`` to make it full-fledged. (Deprecate in EQ2.0)
@property (readonly, nullable) NSArray <RTKACEQSetting*> *normalModeEQs;


/// Return an ``RTKACEQSetting`` instance which currently used for normal mode.
///
/// Affected by ``RTKACEQRoutine/getCurrentEQIndexOfMode:withCompletionHandler:`` and ``RTKACEQRoutine/setCurrentEQIndex:ofMode:withCompletionHandler:`` with  ``RTKACEQMode/RTKACEQMode_normal`` . (Deprecate in EQ2.0)
@property (readonly, nullable) RTKACEQSetting *activeNormalEQ;


/// Return a list of  ``RTKACEQSetting`` objects which representing EQ settings in remote device excuting gaming mode.
///
/// Affected by ``RTKACEQRoutine/getEQEntryCountOfMode:type:withCompletionHandler:`` with ``RTKACEQMode/RTKACEQMode_gaming`` . The returned ``RTKACEQSetting`` object may not be fully determine the parameter. Call ``RTKACEQRoutine/getEQParameterAtIndex:ofMode:toResolveEQSetting:withCompletionHandler:`` to make it full-fledged. (Deprecate in EQ2.0)
@property (readonly, nullable) NSArray <RTKACEQSetting*> *gamingModeEQs;


/// Return the current ``RTKACEQSetting`` used of the remote device in gaming mode.
///
/// Affected by ``RTKACEQRoutine/getCurrentEQIndexOfMode:withCompletionHandler:`` and ``RTKACEQRoutine/setCurrentEQIndex:ofMode:withCompletionHandler:`` with  ``RTKACEQMode/RTKACEQMode_gaming`` . (Deprecate in EQ2.0)
@property (readonly, nullable) RTKACEQSetting *activeGamingEQ;


/// Return a list of ``RTKACEQSetting`` objects which representing EQ settings in remote device runing ANC mode.
///
/// Affected by ``RTKACEQRoutine/getEQEntryCountOfMode:type:withCompletionHandler:`` with ``RTKACEQMode/RTKACEQMode_anc`` . The returned ``RTKACEQSetting`` object may not be fully determine the parameter. Call ``RTKACEQRoutine/getEQParameterAtIndex:ofMode:toResolveEQSetting:withCompletionHandler:`` to make it full-fledged. (Deprecate in EQ2.0)
@property (readonly, nullable) NSArray <RTKACEQSetting*> *ANCModeEQs;


/// Return an ``RTKACEQSetting`` instance which currently used for ANC mode.
///
/// Affected by ``RTKACEQRoutine/getCurrentEQIndexOfMode:withCompletionHandler:`` and ``RTKACEQRoutine/setCurrentEQIndex:ofMode:withCompletionHandler:``  with ``RTKACEQMode/RTKACEQMode_anc`` . (Deprecate in EQ2.0)
@property (readonly, nullable) RTKACEQSetting *activeANCEQ;

#pragma mark - APT EQ

/// Return the count of APT EQ entry of this peripheral last cached.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACEQRoutine/getEQEntryCountOfMode:type:withCompletionHandler:`` or ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *APTEQCount;


/// Return the index of APT EQ entry current used.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACEQRoutine/getCurrentAPTEQIndexWithCompletionHandler:``,  ``RTKACEQRoutine/setCurrentAPTEQIndex:withCompletionHandler:`` and ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *APTEQIndex;


/// Return a list of ``RTKACEQSetting`` objects which representing EQ settings of left bud in remote device runing APT mode.
///
/// Affected by ``RTKACEQRoutine/getEQEntryCountOfMode:type:withCompletionHandler:`` or ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``. The returned `RTKACEQSetting` object may not be fully determine the parameter. Call ``RTKACEQRoutine/getEQParameterAtIndex:ofType:inMode:toResolveEQSettings:withCompletionHandler:`` or ``RTKACEQRoutine/getEQParameterAtIndex:ofType:mode:bud:toResolveEQSetting:withCompletionHandler:`` or to make it full-fledged.
@property (readonly, nullable) NSArray <RTKACEQSetting*> *leftAPTEQs;


/// Return a list of ``RTKACEQSetting`` objects which representing EQ settings of right bud in remote device runing APT mode.
///
/// Affected by ``RTKACEQRoutine/getEQEntryCountOfMode:type:withCompletionHandler:`` or ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``. The returned ``RTKACEQSetting`` object may not be fully determine the parameter. Call ``RTKACEQRoutine/getEQParameterAtIndex:ofType:inMode:toResolveEQSettings:withCompletionHandler:`` or ``RTKACEQRoutine/getEQParameterAtIndex:ofType:mode:bud:toResolveEQSetting:withCompletionHandler:`` to make it full-fledged.
@property (readonly, nullable) NSArray <RTKACEQSetting*> *rightAPTEQs;


/// Return a list of ``RTKACEQSetting`` objects which representing EQ settings of the both buds in remote device runing APT mode.
///
/// Affected by ``RTKACEQRoutine/getEQEntryCountOfMode:type:withCompletionHandler:`` or ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``. The returned ``RTKACEQSetting`` object may not be fully determine the parameter. Call ``RTKACEQRoutine/getEQParameterAtIndex:ofType:inMode:toResolveEQSettings:withCompletionHandler:`` or ``RTKACEQRoutine/getEQParameterAtIndex:ofType:mode:bud:toResolveEQSetting:withCompletionHandler:`` to make it full-fledged.
@property (readonly, nullable) NSArray <RTKACEQSetting*> *APTEQs;


#pragma mark - EQ >= 2.0

/// Return the number of the SPKEQ which could be saved in SOC.
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *numberOfSavedSPKEQ;


/// Return the number of the MICEQ which could be saved in SOC.
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *numberOfSavedMICEQ;


/// Return an index array representing the position of normal EQ in SPKEQSettings.
///
 /// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSArray<NSNumber *> *normalEQIndexArray;


/// Return an index array representing the position of gaming EQ in SPKEQSettings.
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSArray<NSNumber *> *gamingEQIndexArray;


/// Return an index array representing the position of anc EQ in SPKEQSettings.
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSArray<NSNumber *> *ancEQIndexArray;


/// Return a list of ``RTKACEQSetting`` objects which representing SPKEQ settings in remote device.
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``. The returned ``RTKACEQSetting`` object may not be fully determine the parameter. Call ``RTKACEQRoutine/getEQParameterAtIndex:ofType:mode:bud:toResolveEQSetting:withCompletionHandler:`` to make it full-fledged.
@property (readonly, nullable) NSArray <RTKACEQSetting*> *SPKEQs;

/// Return a list of ``RTKACEQSettingPlaceholder`` objects which representing compensation SPK EQ settings in remote device.
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``. The returned ``RTKACEQSettingPlaceholder`` object may not be fully determine the parameter. Call ``RTKACEQRoutine/getEQParameterAtIndex:ofBud:type:mode:toResolveUIEQSetting:compensationEQSetting:withCompletionHandler:`` to make it full-fledged.
@property (readonly, nullable) NSArray <RTKACEQSettingPlaceholder*> *compensationEQs;

/// Return a list of ``RTKACEQSettingPlaceholder`` objects which representing SPKEQ settings of left bud. (Peripheral supports ``RTKACCapabilityType/RTKACCapabilityType_EQAdjustSeparately``)
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``. The returned ``RTKACEQSettingPlaceholder`` object may not be fully determine the parameter. Call ``RTKACEQRoutine/getEQParameterAtIndex:ofType:mode:bud:toResolveEQSetting:withCompletionHandler:`` to make it full-fledged.
@property (readonly, nullable) NSArray <RTKACEQSettingPlaceholder*> *leftSPKEQs;

/// Return a list of ``RTKACEQSettingPlaceholder`` objects which representing compensation SPK EQ settings of left bud. (Peripheral supports RTKACCapabilityType_EQAdjustSeparately)
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``. The returned ``RTKACEQSettingPlaceholder`` object may not be fully determine the parameter. Call ``RTKACEQRoutine/getEQParameterAtIndex:ofBud:type:mode:toResolveUIEQSetting:compensationEQSetting:withCompletionHandler:`` to make it full-fledged.
@property (readonly, nullable) NSArray <RTKACEQSettingPlaceholder*> *leftCompensationEQs;

/// Return a list of ``RTKACEQSettingPlaceholder`` objects which representing SPKEQ settings of right bud. (Peripheral supports RTKACCapabilityType_EQAdjustSeparately)
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``. The returned ``RTKACEQSettingPlaceholder`` object may not be fully determine the parameter. Call ``RTKACEQRoutine/getEQParameterAtIndex:ofType:mode:bud:toResolveEQSetting:withCompletionHandler:`` to make it full-fledged.
@property (readonly, nullable) NSArray <RTKACEQSettingPlaceholder*> *rightSPKEQs;

/// Return a list of ``RTKACEQSettingPlaceholder`` objects which representing compensation SPK EQ settings of right bud. (Peripheral supports RTKACCapabilityType_EQAdjustSeparately)
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``. The returned ``RTKACEQSettingPlaceholder`` object may not be fully determine the parameter. Call ``RTKACEQRoutine/getEQParameterAtIndex:ofBud:type:mode:toResolveUIEQSetting:compensationEQSetting:withCompletionHandler:`` to make it full-fledged.
@property (readonly, nullable) NSArray <RTKACEQSettingPlaceholder*> *rightCompensationEQs;

/// Return the current normal EQ index.
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:`` and ``RTKACEQRoutine/setCurrentEQIndex:ofMode:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *currentNormalEQIndex;


/// Return the current gaming EQ index.
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:`` and  ``RTKACEQRoutine/setCurrentEQIndex:ofMode:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *currentGamingEQIndex;


/// Return the current anc EQ index.
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:`` and  ``RTKACEQRoutine/setCurrentEQIndex:ofMode:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *currentANCEQIndex;


/// The current sample rate of the connected device.
///
/// - **Availability Details**:
///   - **Spec < 3.0**: Valid and active.
///   - **Spec 3.0 - 3.1**:  **Reserved/Ignored**. The value may be ``RTKEQSampleRate/rate_unknown``. Do not rely on it.
///   - **Spec ≥ 3.2**: **Re-enabled**. Valid and active.
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *currentSampleRate;


/// Return a list of the sample rates the peripheral supported.
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSArray<NSNumber *> *supportedSampleRate;


/// Return the current SPKEQ mode (normal, gaming or anc).
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *currentSPKEQMode;


/// Return the current MICEQ mode (apt).
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *currentMICEQMode;


/// Return the voice EQ setting.
///
/// Affected by ``RTKACEQRoutine/getEQEntryCountOfMode:type:withCompletionHandler:`` or ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``.
@property (readonly, nullable) RTKACEQSettingPlaceholder *voiceEQ;

/// Return a  ``RTKACEQSettingPlaceholder`` object which representing the compensation Voice EQ setting in remote device.
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``. The returned ``RTKACEQSettingPlaceholder`` object may not be fully determine the parameter. Call ``RTKACEQRoutine/getEQParameterAtIndex:ofBud:type:mode:toResolveUIEQSetting:compensationEQSetting:withCompletionHandler:`` to make it full-fledged.
@property (readonly, nullable) RTKACEQSettingPlaceholder *voiceCompensationEQ;

/// Return the voice EQ setting of left bud. (Peripheral supports RTKACCapabilityType_EQAdjustSeparately)
///
/// Affected by ``RTKACEQRoutine/getEQEntryCountOfMode:type:withCompletionHandler:``  or ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``.
@property (readonly, nullable) RTKACEQSettingPlaceholder *leftVoiceEQ;

/// Return a ``RTKACEQSettingPlaceholder`` object which representing the compensation Voice EQ setting of left bud. (Peripheral supports RTKACCapabilityType_EQAdjustSeparately)
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``. The returned ``RTKACEQSettingPlaceholder`` object may not be fully determine the parameter. Call ``RTKACEQRoutine/getEQParameterAtIndex:ofBud:type:mode:toResolveUIEQSetting:compensationEQSetting:withCompletionHandler:`` to make it full-fledged.
@property (readonly, nullable) RTKACEQSettingPlaceholder *leftVoiceCompensationEQ;

/// Return the voice EQ setting of right bud. (Peripheral supports RTKACCapabilityType_EQAdjustSeparately)
///
/// Affected by ``RTKACEQRoutine/getEQEntryCountOfMode:type:withCompletionHandler:``  or ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``.
@property (readonly, nullable) RTKACEQSettingPlaceholder *rightVoiceEQ;

/// Return a ``RTKACEQSettingPlaceholder`` object which representing the compensation Voice EQ setting of right bud. (Peripheral supports RTKACCapabilityType_EQAdjustSeparately)
///
/// Affected by ``RTKACEQRoutine/getEQInfoWithCompletionHandler:``. The returned ``RTKACEQSettingPlaceholder`` object may not be fully determine the parameter. Call ``RTKACEQRoutine/getEQParameterAtIndex:ofBud:type:mode:toResolveUIEQSetting:compensationEQSetting:withCompletionHandler:`` to make it full-fledged.
@property (readonly, nullable) RTKACEQSettingPlaceholder *rightVoiceCompensationEQ;

#pragma mark - EQ >= 3.2

/// A dictionary that caches the EQ format version for each sample rate.
///
/// It is updated automatically upon the successful completion of ``RTKACEQRoutine/queryEQFormatWithCompletionHandler:`` .
///
/// - **Key**: `NSNumber` wrapping `RTKEQSampleRate`.
/// - **Value**: `NSNumber` wrapping `RTKEQFormatVersion` .

@property (readonly, nullable) NSDictionary<NSNumber *, NSNumber *> *eqFormatTable;

@end

NS_ASSUME_NONNULL_END
