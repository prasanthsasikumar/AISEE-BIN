//
//  RTKACEQRoutine+Deprecated.h
//  RTKAudioConnectSDK
//
//  Created by irene_wang on 2026/1/26.
//  Copyright (c) 2026, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//
#import <Foundation/Foundation.h>
#ifdef ATAudioConnectSDK
#import <ATAudioConnectSDK/RTKBBproType.h>
#import <ATAudioConnectSDK/RTKBBproEQSetting.h>
#import <ATAudioConnectSDK/RTKBBproEQSettingPlaceholder.h>
#import <ATAudioConnectSDK/RTKACEQRoutine.h>
#import <ATAudioConnectSDK/RTKMacros.h>
#elif defined(RTKWaveLiteSDK)
#import <RTKWaveLiteSDK/RTKBBproType.h>
#import <RTKWaveLiteSDK/RTKBBproEQSetting.h>
#import <RTKWaveLiteSDK/RTKBBproEQSettingPlaceholder.h>
#import <RTKWaveLiteSDK/RTKACEQRoutine.h>
#import <RTKWaveLiteSDK/RTKMacros.h>
#else
#import <RTKAudioConnectSDK/RTKBBproType.h>
#import <RTKAudioConnectSDK/RTKBBproEQSetting.h>
#import <RTKAudioConnectSDK/RTKBBproEQSettingPlaceholder.h>
#import <RTKAudioConnectSDK/RTKACEQRoutine.h>
#import <RTKAudioConnectSDK/RTKMacros.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@interface RTKACEQRoutine (Deprecated)

#pragma mark - EQ General Info

- (void)getEQEntryCountOfModeLegacy:(RTKBBproEQMode)mode
                               type:(RTKBBproSWEQType)type
              withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, NSUInteger count))handler
RTK_REDIRECT('getEQEntryCountOfMode:type:withCompletionHandler:' with 'RTKACEQMode' 'RTKACSWEQType')
NS_SWIFT_NAME(getEQEntryCount(ofMode:type:withCompletionHandler:));

- (void)getCurrentEQIndexOfModeLegacy:(RTKBBproEQMode)mode
                withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, NSUInteger idx))handler
RTK_REDIRECT('getCurrentEQIndexOfMode:withCompletionHandler:' with 'RTKACEQMode')
NS_SWIFT_NAME(getCurrentEQIndex(ofMode:withCompletionHandler:));



#pragma mark - Switch EQ Index

- (void)setCurrentEQIndexLegacy:(NSUInteger)idx
                         ofMode:(RTKBBproEQMode)mode
          withCompletionHandler:(nullable RTKLECompletionBlock)handler
RTK_REDIRECT('setCurrentEQIndex:ofMode:withCompletionHandler:' with 'RTKACEQMode')
NS_SWIFT_NAME(setCurrentEQIndex(_:ofMode:withCompletionHandler:));


#pragma mark - SPK EQ Parameters

- (void)getEQParameterOfIndex:(NSUInteger)idx
                       ofMode:(RTKBBproEQMode)mode
                   withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKBBproSampleRate sampleRate, NSData *_Nullable paraData))handler RTK_REDIRECT(getEQParameterOfIndex:forMode:withCompletionHandler:);

- (void)setEQParameterOfIndexLegacy:(NSUInteger)idx
                             ofMode:(RTKBBproEQMode)mode
                           withData:(NSData *)data
                       ofSampleRate:(RTKBBproSampleRate)sampleRate
              withCompletionHandler:(nullable RTKLECompletionBlock)handler
RTK_REDIRECT('setEQParameterOfIndex:ofMode:withData:ofSampleRate:withCompletionHandler:' with 'RTKACEQMode' 'RTKEQSampleRate')
NS_SWIFT_NAME(setEQParameter(ofIndex:mode:data:sampleRate:withCompletionHandler:));


- (void)getEQParameterAtIndexLegacy:(NSUInteger)idx
                             ofMode:(RTKBBproEQMode)mode
                 toResolveEQSetting:(RTKBBproEQSetting *)setting
              withCompletionHandler:(nullable RTKLECompletionBlock)handler
RTK_REDIRECT('getEQParameterAtIndex:ofMode:toResolveEQSetting:withCompletionHandler:' with 'RTKACEQMode')
NS_SWIFT_NAME(getEQParameter(atIndex:mode:resolving:withCompletionHandler:));


- (void)setEQParameterAtIndexLegacy:(NSUInteger)idx
                             ofMode:(RTKBBproEQMode)mode
                       ofSampleRate:(RTKBBproSampleRate)sampleRate
                        withSetting:(RTKBBproEQSetting *)setting
              withCompletionHandler:(nullable RTKLECompletionBlock)handler
RTK_REDIRECT('setEQParameterAtIndex:ofMode:ofSampleRate:withSetting:withCompletionHandler:' with 'RTKACEQMode' 'RTKEQSampleRate')
NS_SWIFT_NAME(setEQParameter(atIndex:mode:sampleRate:setting:withCompletionHandler:));


// MARK: - EQ (SPEC 2.0)

- (void)resetEQOfType:(RTKBBproSWEQType)type
                 mode:(RTKBBproEQMode)mode
                index:(uint8_t)index
              andSide:(RTKEQBudSide)side
   toResolveEQSetting:(RTKBBproEQSetting *)setting
withCompletionHandler:(nullable void(^)(BOOL success, NSError * _Nullable error, RTKBBproSampleRate sampleRate, NSData * _Nullable paraData))handler RTK_REDIRECT(resetEQSetting:ofType:mode:index:side:withCompletionHandler:);

- (void)setEQParameterAtIndexLegacy:(NSUInteger)idx
                             ofType:(RTKBBproSWEQType)type
                               mode:(RTKBBproEQMode)mode
                         sampleRate:(RTKBBproSampleRate)sampleRate
                        withSetting:(RTKBBproEQSetting *)setting
                             forBud:(RTKEQBudSide)bud
                        applyOrSave:(RTKApplyOrSaveEQ)applyOrSave
              withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler
RTK_REDIRECT('setEQParameterAtIndex:ofType:mode:sampleRate:withSetting:forBud:applyOrSave:withCompletionHandler:' with 'RTKACSWEQType' 'RTKACEQMode' 'RTKEQSampleRate' 'RTKACEQBudSide')
NS_SWIFT_NAME(setEQParameter(atIndex:type:mode:sampleRate:setting:bud:applyOrSave:withCompletionHandler:));


- (void)setEQParameterAtIndexLegacy:(NSUInteger)idx
                             ofType:(RTKBBproSWEQType)type
                               mode:(RTKBBproEQMode)mode
                         sampleRate:(RTKBBproSampleRate)sampleRate
                      withUISetting:(nonnull RTKBBproEQSetting *)UISetting
              andCompensatedSetting:(nullable RTKBBproEQSetting *)finalSetting
                             forBud:(RTKEQBudSide)bud
                        applyOrSave:(RTKApplyOrSaveEQ)applyOrSave
              withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler
RTK_REDIRECT('setEQParameterAtIndex:ofType:mode:sampleRate:withUISetting:andCompensatedSetting:forBud:applyOrSave:withCompletionHandler:' with 'RTKACSWEQType' 'RTKACEQMode' 'RTKEQSampleRate' 'RTKACEQBudSide')
NS_SWIFT_NAME(setEQParameter(atIndex:type:mode:sampleRate:uiSetting:compensatedSetting:bud:applyOrSave:withCompletionHandler:));


- (void)getEQParameterAtIndexLegacy:(NSUInteger)idx
                             ofType:(RTKBBproSWEQType)type
                               mode:(RTKBBproEQMode)mode
                                bud:(RTKEQBudSide)bud
                 toResolveEQSetting:(RTKBBproEQSetting *)setting
              withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler
RTK_REDIRECT('getEQParameterAtIndex:ofType:mode:bud:toResolveEQSetting:withCompletionHandler:' with 'RTKACSWEQType' 'RTKACEQMode' 'RTKACEQBudSide')
NS_SWIFT_NAME(getEQParameter(atIndex:type:mode:bud:resolving:withCompletionHandler:));


#pragma mark - EQ (SPEC 3.0)

- (void)setEQParametersWithFinalSettingLegacy:(nonnull RTKBBproEQSetting *)finalSetting
                                    UISetting:(nonnull RTKBBproEQSetting *)UISetting
                          compensationSetting:(nullable RTKBBproEQSetting *)compensationSetting
                                      ofIndex:(NSUInteger)idx
                                          bud:(RTKEQBudSide)bud
                                         type:(RTKBBproSWEQType)type
                                         mode:(RTKBBproEQMode)mode
                                       action:(RTKApplyOrSaveEQ)applyOrSave
                        withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler
RTK_REDIRECT('setEQParametersWithFinalSetting:UISetting:compensationSetting:ofIndex:bud:type:mode:action:withCompletionHandler:' with 'RTKACEQBudSide' 'RTKACSWEQType' 'RTKACEQMode')
NS_SWIFT_NAME(setEQParameters(finalSetting:uiSetting:compensationSetting:index:bud:type:mode:action:withCompletionHandler:));


- (void)getEQParameterAtIndexLegacy:(NSUInteger)idx
                              ofBud:(RTKEQBudSide)bud
                               type:(RTKBBproSWEQType)type
                               mode:(RTKBBproEQMode)mode
               toResolveUIEQSetting:(RTKBBproEQSetting *)UISetting
              compensationEQSetting:(nullable RTKBBproEQSetting *)compensationSetting
              withCompletionHandler:(void (^)(BOOL, NSError * _Nullable, NSData * _Nullable paraData))handler
RTK_REDIRECT('getEQParameterAtIndex:ofBud:type:mode:toResolveUIEQSetting:compensationEQSetting:withCompletionHandler:' with 'RTKACEQBudSide' 'RTKACSWEQType' 'RTKACEQMode')
NS_SWIFT_NAME(getEQParameter(atIndex:bud:type:mode:resolvingUI:resolvingCompensation:withCompletionHandler:));


- (void)resetEQOfTypeLegacy:(RTKBBproSWEQType)type
                       mode:(RTKBBproEQMode)mode
                      index:(uint8_t)index
                        bud:(RTKEQBudSide)bud
       toResolveUIEQSetting:(RTKBBproEQSetting *)UISetting
      compensationEQSetting:(nullable RTKBBproEQSetting *)compensationSetting
      withCompletionHandler:(void (^)(BOOL success, NSError * _Nullable error, NSData * _Nullable paraData))handler
RTK_REDIRECT('resetEQOfType:mode:index:bud:toResolveUIEQSetting:compensationEQSetting:withCompletionHandler:' with 'RTKACSWEQType' 'RTKACEQMode' 'RTKACEQBudSide')
NS_SWIFT_NAME(resetEQ(type:mode:index:bud:resolvingUI:resolvingCompensation:withCompletionHandler:));


#pragma mark - APT EQ

- (void)getEQParameterOfIndex:(NSUInteger)index andType:(RTKBBproSWEQType)type inMode:(RTKBBproEQMode)mode withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKBBproSampleRate sampleRate, NSData *_Nullable paraData))handler RTK_REDIRECT(getEQParameterOfIndex:type:inMode:withCompletionHandler:);

- (void)setEQParameterOfIndexLegacy:(NSUInteger)index
                            andType:(RTKBBproSWEQType)type
                             inMode:(RTKBBproEQMode)mode
                           withData:(NSData *)data
                       ofSampleRate:(RTKBBproSampleRate)sampleRate
                             forBud:(RTKEQBudSide)bud
              withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler
RTK_REDIRECT('setEQParameterOfIndex:andType:inMode:withData:ofSampleRate:forBud:withCompletionHandler:' with 'RTKACSWEQType' 'RTKACEQMode' 'RTKEQSampleRate' 'RTKACEQBudSide')
NS_SWIFT_NAME(setEQParameter(ofIndex:type:mode:data:sampleRate:bud:withCompletionHandler:));


- (void)getEQParameterAtIndexLegacy:(NSUInteger)idx
                             ofType:(RTKBBproSWEQType)type
                             inMode:(RTKBBproEQMode)mode
              toResolveEQSettings:(NSArray <RTKBBproEQSetting*> *)settings
              withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler
RTK_REDIRECT('getEQParameterAtIndex:ofType:inMode:toResolveEQSettings:withCompletionHandler:' with 'RTKACSWEQType' 'RTKACEQMode')
NS_SWIFT_NAME(getEQParameter(atIndex:type:mode:resolvingSettings:withCompletionHandler:));


- (void)setEQParameterAtIndexLegacy:(NSUInteger)idx
                             ofType:(RTKBBproSWEQType)type
                             inMode:(RTKBBproEQMode)mode
                       ofSampleRate:(RTKBBproSampleRate)sampleRate
                        withSetting:(RTKBBproEQSetting *)setting
                             forBud:(RTKEQBudSide)bud
              withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler
RTK_REDIRECT('setEQParameterAtIndex:ofType:inMode:ofSampleRate:withSetting:forBud:withCompletionHandler:' with 'RTKACSWEQType' 'RTKACEQMode' 'RTKEQSampleRate' 'RTKACEQBudSide')
NS_SWIFT_NAME(setEQParameter(atIndex:type:mode:sampleRate:setting:bud:withCompletionHandler:));


#pragma mark - Legacy EQ setting

- (void)getLegacyCurrentEQIndexStateWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKBBproEQIndex currentIndex, RTKBBproEQIndex supportedIndexes))handler RTK_REDIRECT(getLegacyCurrentEQIndexWithCompletionHandler:);

- (void)setLegacyCurrentEQIndexToLegacy:(RTKBBproEQIndex)index withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler
RTK_REDIRECT('setLegacyCurrentEQIndexTo:withCompletionHandler:' with 'RTKACEQIndex')
NS_SWIFT_NAME(setLegacyCurrentEQIndex(to:withCompletionHandler:));


- (void)setDSPEQDataLegacy:(NSData *)paramterData
              ofSampleRate:(RTKBBproSampleRate)sampleRate
     withCompletionHandler:(nullable void(^)(BOOL, NSError*_Nullable))handler
RTK_REDIRECT('setDSPEQData:ofSampleRate:withCompletionHandler:' with 'RTKEQSampleRate')
NS_SWIFT_NAME(setDSPEQData(_:sampleRate:withCompletionHandler:));


#pragma mark - EQ spec < 2.0

@property (readonly, nullable) NSArray <RTKBBproEQSetting*> *normalModeEQSettings RTK_REDIRECT(normalModeEQs);

@property (readonly, nullable) RTKBBproEQSetting *normalModeEQSettingInUse RTK_REDIRECT(activeNormalEQ);

@property (readonly, nullable) NSArray <RTKBBproEQSetting*> *gamingModeEQSettings RTK_REDIRECT(gamingModeEQs);

@property (readonly, nullable) RTKBBproEQSetting *gamingModeEQSettingInUse RTK_REDIRECT(activeGamingEQ);

@property (readonly, nullable) NSArray <RTKBBproEQSetting*> *ANCModeEQSettings RTK_REDIRECT(ANCModeEQs);

@property (readonly, nullable) RTKBBproEQSetting *ANCModeEQSettingInUse RTK_REDIRECT(activeANCEQ);

#pragma mark - EQ >= 2.0

@property (readonly, nullable) NSArray <RTKBBproEQSetting*> *SPKEQSettings RTK_REDIRECT(SPKEQs);

@property (readonly, nullable) NSArray <RTKBBproEQSettingPlaceholder*> *compensationEQSettings RTK_REDIRECT(compensationEQs);

@property (readonly, nullable) NSArray <RTKBBproEQSettingPlaceholder*> *SPKEQSettingsOfLeft RTK_REDIRECT(leftSPKEQs);

@property (readonly, nullable) NSArray <RTKBBproEQSettingPlaceholder*> *compensationEQSettingsOfLeft RTK_REDIRECT(leftCompensationEQs);

@property (readonly, nullable) NSArray <RTKBBproEQSettingPlaceholder*> *SPKEQSettingsOfRight RTK_REDIRECT(rightSPKEQs);

@property (readonly, nullable) NSArray <RTKBBproEQSettingPlaceholder*> *compensationEQSettingsOfRight RTK_REDIRECT(rightCompensationEQs);

@property (readonly, nullable) RTKBBproEQSettingPlaceholder *VoiceEQSetting RTK_REDIRECT(voiceEQ);

@property (readonly, nullable) RTKBBproEQSettingPlaceholder *compensationVoiceEQSetting RTK_REDIRECT(voiceCompensationEQ);

@property (readonly, nullable) RTKBBproEQSettingPlaceholder *VoiceEQSettingOfLeft RTK_REDIRECT(leftVoiceEQ);

@property (readonly, nullable) RTKBBproEQSettingPlaceholder *compensationVoiceEQSettingOfLeft RTK_REDIRECT(leftVoiceCompensationEQ);

@property (readonly, nullable) RTKBBproEQSettingPlaceholder *VoiceEQSettingOfRight RTK_REDIRECT(rightVoiceEQ);

@property (readonly, nullable) RTKBBproEQSettingPlaceholder *compensationVoiceEQSettingOfRight RTK_REDIRECT(rightVoiceCompensationEQ);

#pragma mark - APT EQ

@property (readonly, nullable) NSArray <RTKBBproEQSetting*> *APTEQSettingsOfLeft RTK_REDIRECT(leftAPTEQs);

@property (readonly, nullable) NSArray <RTKBBproEQSetting*> *APTEQSettingsOfRight RTK_REDIRECT(rightAPTEQs);

@property (readonly, nullable) NSArray <RTKBBproEQSetting*> *APTEQSettings RTK_REDIRECT(APTEQs);

#pragma mark - Legacy EQ

@property (readonly, nullable) RTKBBproEQSetting *legacyEQSettingInUse RTK_REDIRECT(activeLegacyEQ);


@end

NS_ASSUME_NONNULL_END
