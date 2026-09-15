//
//  RTKACBasicRoutine.h
//  RTKAudioConnectSDK
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
#import <ATAudioConnectSDK/RTKMacros.h>
#import <ATAudioConnectSDK/RTKBBproType.h>
#elif defined(RTKWaveLiteSDK)
#import <RTKWaveLiteSDK/RTKACRoutine.h>
#import <RTKWaveLiteSDK/RTKACType.h>
#import <RTKWaveLiteSDK/RTKMacros.h>
#import <RTKWaveLiteSDK/RTKBBproType.h>
#else
#import <RTKAudioConnectSDK/RTKACRoutine.h>
#import <RTKAudioConnectSDK/RTKACType.h>
#import <RTKAudioConnectSDK/RTKMacros.h>
#import <RTKAudioConnectSDK/RTKBBproType.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@class RTKACBasicRoutine;

/// Methods called by an ``RTKACBasicRoutine`` on its delegate to report events.
@protocol RTKACBasicStateUpdateReporting <NSObject>
@optional

/// Tells the delegate that remote device did change current used language.
///
/// - Parameter routine: The peripheral that did change the eq index.
/// - Parameter lang: The new language.
- (void)ACBasicRoutine:(RTKACBasicRoutine *)routine didReceiveLanguageChangeTo:(RTKACLanguageType)lang;

- (void)BBproBasicRoutine:(RTKACBasicRoutine *)routine didReceiveLanguageChangeTo:(RTKBBproLanguageType)lang RTK_REDIRECT(ACBasicRoutine:didReceiveLanguageChangeTo:);

/// Tells the delegate that remote device did change current battery.
///
/// - Parameter routine: The peripheral that did change battery level.
/// - Parameter primaryLvl: Battery level of primary bud. `RTKACBatteryLevelInvalid` means this value is not valid.
/// - Parameter secondaryLvl: Battery level of secondary bud. `RTKACBatteryLevelInvalid` means this value is not valid.
/// - Parameter cradleLvl: Battery charge level of crade if exist. `RTKACBatteryLevelInvalid` means this value is not valid.
- (void)ACBasicRoutine:(RTKACBasicRoutine *)routine
didReceiveUpdateOfPrimaryBatteryLevel:(RTKACBatteryLevel)primaryLvl
  secondaryBatteryLevel:(RTKACBatteryLevel)secondaryLvl
     cradleBatteryLevel:(RTKACBatteryLevel)cradleLvl;

- (void)BBproBasicRoutine:(RTKACBasicRoutine *)routine
didReceiveUpdateOfPrimaryBatteryLevel:(RTKBBproBatteryLevel)primaryLvl
  secondaryBatteryLevel:(RTKBBproBatteryLevel)secondaryLvl
     cradleBatteryLevel:(RTKBBproBatteryLevel)cradleLvl RTK_REDIRECT(ACBasicRoutine:didReceiveUpdateOfPrimaryBatteryLevel:secondaryBatteryLevel:cradleBatteryLevel:);


/// Tells the delegate that remote device did change current RWS state.
///
/// - Parameter routine: The peripheral that did update RWS state.
/// - Parameter isOn: Whether RWS is on.
- (void)ACBasicRoutine:(RTKACBasicRoutine *)routine didReceiveChangeOfRWSState:(BOOL)isOn;

- (void)BBproBasicRoutine:(RTKACBasicRoutine *)routine didReceiveChangeOfRWSState:(BOOL)isOn RTK_REDIRECT(ACBasicRoutine:didReceiveChangeOfRWSState:);

/// Tells the delegate that remote device did change current RWS channel.
///
/// - Parameter routine: The peripheral that did change channel.
/// - Parameter direction: The new direction.
- (void)ACBasicRoutine:(RTKACBasicRoutine *)routine didReceiveChangeOfRWSChannel:(RTKACChannelDirection)direction;

- (void)BBproBasicRoutine:(RTKACBasicRoutine *)routine didReceiveChangeOfRWSChannel:(RTKBBproChannelDirection)direction RTK_REDIRECT(ACBasicRoutine:didReceiveChangeOfRWSChannel:);
@end



RTK_REDIRECT(RTKACBasicStateUpdateReporting)
@protocol RTKBBproBasicStateUpdateReporting <RTKACBasicStateUpdateReporting>

@end


/// An concrete `RTKACRoutine` class that provides functionality to access basic state of an *Audio Connect* device.
@interface RTKACBasicRoutine : RTKACRoutine

/// The delegate object that receives events.
@property (nonatomic, weak) id <RTKACBasicStateUpdateReporting> delegate;

/// Return the command version supported by the SDK.
@property (nonatomic, readonly, nullable) NSNumber *SDKCMDVersion;


/// Return the EQ version supported by the SDK.
@property (nonatomic, readonly, nullable) NSNumber *SDKEQVersion;


/// Return the command version info of this device represented.
///
/// The command version value is of unsigned integer type with 2 byte length, which mean calling -[NSNumber unsignedIntValue] to retrieve the value. The Least Significant Byte refer to minor version, and the Most Significant Byte refer to major version. i.e 0x0102 value represent a version of "1.2".
///
/// You use this value to call methods selectively. Some methods is available to some versions.
@property (nonatomic, readonly, nullable) NSNumber *cmdVersionNumber;


/// Return the EQ related command version info of this device represented.
///
/// The command version value is of 16-bit unsigned integer type, which mean calling -[NSNumber unsignedIntValue] to retrieve the value. The Least Significant Byte refer to minor version, and the Most Significant Byte refer to major version. i.e 0x0102 value represent a version of "1.2".
///
/// You use this value to call methods selectively. Some methods is available to some versions.
@property (nonatomic, readonly, nullable) NSNumber *EQVersionNumber;


/// Get the command version and EQ version of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update cmdVersionNumber and EQVersionNumber properties when succeed.
- (void)getVersionInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, uint16_t cmdVer, uint16_t eqVer))handler;


/// Get the Chip and Package information of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
- (void)fetchPackageInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKACChip chip, NSUInteger packageID))completion;


/// Return a boolean value that indicates if the capability information did determined.
///
/// - Returns `YES` if the information did retrieved from peripheral. return `NO` if the message didn't receive or peripheral does not support report this information.
@property (readonly) BOOL capabilitySettled;

/// Return a boolean value that indicates if the HA capability information did determined.
///
/// - Returns `YES` if the information did retrieved from peripheral. return `NO` if the message didn't receive or peripheral does not support report this information.
@property (readonly) BOOL haCapabilitySettled;

/// Return a boolean value that indicates whether the specified feature is available.
///
/// - Returns `YES` if the specified feature is supported. return `NO` if the message didn't receive or peripheral does not support report this information.
- (BOOL)isAvailableFor:(RTKACCapabilityType)capability;


/// Get the feature realted information of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `capabilitySettled` properties when succeed.
- (void)getCapabilityWithCompletionHandler:(nullable RTKLECompletionBlock)handler;

/// Get the HA feature information of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `haCapabilitySettled` properties when succeed.
- (void)getHAFeatureWithCompletionHandler:(nullable RTKLECompletionBlock)handler;

#pragma mark - Product ID

/// Get product information of the connected peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `companyID` and `modelID` when succeed.
- (void)fetchProductInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKACEntityID modelId, RTKACEntityID companyId))handler;

#pragma mark - Device Name

/// Get the LE name of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `LEName` property when succeed.
- (void)getLENameWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, NSString *name))handler;


/// Set a new LE name of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `LEName` property when succeed.
- (void)setLEName:(NSString *)name withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Get the BREDR name of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `BREDRName` property when succeed.
- (void)getBREDRNameWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, NSString *name))handler;


/// Set a new BREDR name of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `BREDRName` property when succeed.
- (void)setBREDRName:(NSString *)name withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


#pragma mark - Language

/// Get the current using language and supported languages of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `currentLanguage` and `supportedLanguages` properties when succeed.
- (void)getLanguageInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, NSSet <RTKACLanguageType>* supportedLangs, RTKACLanguageType currentLang))handler;

/// Set the current language of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `currentLanguage` property when succeed.
- (void)setCurrentLanguage:(RTKACLanguageType)lang withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


#pragma mark - BudInfo

/// Get bud info of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `budType`,  `primaryBudSide`, `LRChannel`, `singleOrLeftBattery`, `rightBattery`, `RWSState` and `caseBattery` (if support) when succeed. If the peripheral support this cmd, then call this method to get battery instead of ``RTKACBasicRoutine/getBatteryLevelWithCompletionHandler:``.
-(void)getBudInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


/// Get the default role information of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `defaultBudRole` property when succeed. Prefer using `getBudInfoWithCompletionHandler:` if it is available.
- (void)getDefaultBudRoleInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKACBudRole role))handler;


/// Get the bud side information of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `budSide` property when succeed. Prefer using `getBudInfoWithCompletionHandler:` if it is available.
- (void)getBudSideInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError *_Nullable err, RTKACBudSide side))handler;

#pragma mark - Battery

/// Get the current battery level of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `primaryBatteryLevel` and `secondaryBatteryLevel` and `cradleBatteryLevel` properties when succeed. Prefer using `getBudInfoWithCompletionHandler:` if it is available.
- (void)getBatteryInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKACBatteryLevel primary, RTKACBatteryLevel secondary, RTKACBatteryLevel cradle))handler;


/// Convert primary/secondary battery to left/right battery of this peripheral. (If `getBudInfoWithCompletionHandler:` is available, ignore this method)
///
/// - Parameter primary: The battery level of primary bud.
/// - Parameter secondary: The battery level of secondary bud.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `leftBatteryLevel`, `rightBatteryLevel` and `singleBatteryLevel` properties when succeed. (RWSState property should be ready before calling this method)
- (void)convertBatteryToLeftRightFromPrimary:(RTKACBatteryLevel)primary andSecondary:(RTKACBatteryLevel)secondary withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;

#pragma mark - RWS

/// Get the default channel information of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `defaultRWSChannelDirection` property when succeed. Prefer using `getBudInfoWithCompletionHandler:` if it is available.
- (void)getDefaultRWSChannelDirectionInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError *_Nullable error, RTKACChannelDirection direction))handler;


/// Get the RWS on-off state of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `RWSState` property when succeed. Prefer using `getBudInfoWithCompletionHandler:` if it is available.
- (void)getRWSStateWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, BOOL state))handler;


/// Get the RWS channel flow state of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `RWSChannel` property when succeed. Prefer using `getBudInfoWithCompletionHandler:` if it is available.
- (void)getRWSChannelInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKACChannelDirection channel))handler;


/// Switch the RWS channel state of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `RWSChannel` property when succeed.
- (void)switchRWSChannelWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


#pragma mark - Volume level

/// Get the VP & Ringtone volume state of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `LVPRingtoneVolumeLevel`, `RVPRingtoneVolumeLevel`, `minLVPRingtoneVolumeLevel`, `maxLVPRingtoneVolumeLevel`, `minRVPRingtoneVolumeLevel` and `maxRVPRingtoneVolumeLevel` properties when succeed.
- (void)getVPRingtoneVolumeInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKACVolumeLevel minLevelL, RTKACVolumeLevel maxLevelL, RTKACVolumeLevel curLevelL, RTKACVolumeLevel minLevelR, RTKACVolumeLevel maxLevelR, RTKACVolumeLevel curLevelR))handler;


/// Set the VP & Ringtone volume level of this peripheral.
///
/// - Parameter levelL: The VP & Ringtone volume of left bud.
/// - Parameter levelR: The VP & Ringtone volume of right bud.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `LVPRingtoneVolumeLevel`, `RVPRingtoneVolumeLevel` properties when succeed.
- (void)setVPRingtoneVolumeLevelOfL:(RTKACVolumeLevel)levelL R:(RTKACVolumeLevel)levelR withCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Set VP & Ringtone volume level and sync info of this peripheral.
///
/// - Parameter levelL: The VP & Ringtone volume of left bud.
/// - Parameter levelR: The VP & Ringtone volume of right bud.
/// - Parameter sync: A boolean value indicates whether left volume and right volume are consistent.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `LVPRingtoneVolumeLevel`, `RVPRingtoneVolumeLevel` and `syncVPRingtoneVolume` properties when succeed.
- (void)setVPRingtoneVolumeLevelOfL:(RTKACVolumeLevel)levelL R:(RTKACVolumeLevel)levelR Sync:(uint8_t)sync withCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Get the global volume level of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `volumeLevel` and `maxVolumeLevel` properties when succeed.
- (void)getVolumeInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKACVolumeLevel volumeLevel, RTKACVolumeLevel maxLevel))handler;


/// Set the global volume level of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `volumeLevel` property when succeed.
- (void)setVolumeLevelTo:(RTKACVolumeLevel)level withCompletionHandler:(nullable RTKLECompletionBlock)handler;


#pragma mark - Legacy profile connection
- (void)connectProfile:(RTKACLegacyProfile)profile withCompletionHandler:(nullable RTKLECompletionBlock)handler;

- (void)cancelProfileConnection:(RTKACLegacyProfile)profile withCompletionHandler:(nullable RTKLECompletionBlock)handler;


#pragma mark - Multi-link

/// Get the connection count of this peripheral which support multilink.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// A Multi-link supported device may estabilish connection with multiple devices.
- (void)getAppConnectionCountWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, NSUInteger count))handler;

#pragma mark - In ear detection

/// Get the In Ear Detection status of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `inEarDetectionStatus` when succeed.
- (void)getInEarDetectionStatusWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, BOOL isOn))handler;


/// Switch the In Ear Detection status of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update `inEarDetectionStatus` when succeed.
- (void)switchInEarDetectionStatusWithCompletionHandler:(RTKLECompletionBlock)handler;


/// Inform the device of the application state.
///
/// - Parameter isInForeground: Whether the app is running in the foreground.
/// - Parameter handler: The block to be called once the task completes.
- (void)informOfAppState:(BOOL)isInForeground withCompletionHandler:(nullable RTKLECompletionBlock)handler;

#pragma mark - Play Status

/// Get the current music playing status.
///
/// - Parameter handler: The block to be called when the task completes.
- (void)getCurrentPlayStatusWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKPlayStatus status))handler;


#pragma mark - Find me

/// Get the find me status of remote peripheral.
///
/// Will update `leftBudFindmeEnabled` and `rightBudFindmeEnabled` when succeed.
- (void)getFindmeStatusWithCompletionHandler:(RTKLECompletionBlock)handler;


/// Set find me status on each bud.
///
/// - Parameter isOn: 0x00 disable 0x01enable.
/// - Parameter isRightBud: 0x00 left bud 0x01right bud.
///
/// Will update `leftBudFindmeEnabled` or `rightBudFindmeEnabled` when succeed.
- (void)setFindmeStatus:(BOOL)isOn ofRightBud:(BOOL)isRightBud withCompletionHandler:(RTKLECompletionBlock)handler;


#pragma mark - Charging Case

/// Ask the connected device for the charging case which the device is connected with.
///
/// This method should be called only if the device supports charginge case.
- (void)getChargingCaseAddressWithCompletionHandler:(void(^)(BOOL success, NSError *_Nullable error, BDAddressType addr))handler;

/// Request the charging case to advertise or stop advertising
///
/// - Parameter shouldAdvertise: Whether the advertising should be started or stopped.
///
/// This method should be called only if the device supports charginge case.
- (void)requestChargingCaseToAdvertise:(BOOL)shouldAdvertise
                 withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler;


#pragma mark - HFP Dial

/// Instruct the device to make a dial with the provided phone number.
///
/// - Parameter number: The phone number text. Should be a valid number. And should be no more than 25 byte in length after being encoding using Ascii.
/// - Parameter handler: The closure to be called when the instruction is successfully received by the device or fail sending.
///
/// You should ensure the validity of  the phone number.
- (void)dialWithNumber:(NSString *)number
 withCompletionHandler:(nullable RTKLECompletionBlock)handler;

@end


@interface RTKACBasicRoutine (Cache)

/// The company ID of the peripheral
///
/// Affected by ``RTKACBasicRoutine/getProductInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *companyId;


/// The model ID of the peripheral
///
/// Affected by ``RTKACBasicRoutine/getProductInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *modelId;

@property (nonatomic, readonly, nullable) NSNumber *chip;

@property (nonatomic, readonly, nullable) NSNumber *package;


/// Return the cached LE name of device.
///
/// In contrast to `CBPeripheral`.name, this name is retrieved by message exchange through GATT Service, though they are often same. Affected by ``RTKACBasicRoutine/getLENameWithCompletionHandler:`` and ``RTKACBasicRoutine/setLEName:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSString *LEName;


/// Return the cached BREDR name of this device used for BREDR controller.
///
/// Affected by ``RTKACBasicRoutine/getBREDRNameWithCompletionHandler:`` and ``RTKACBasicRoutine/setBREDRName:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSString *BREDRName;


/// Return the language this peripheral used currently for Voice prompt.
///
/// Affected by ``RTKACBasicRoutine/getLanguageWithCompletionHandler:`` and ``RTKACBasicRoutine/setCurrentLanguage:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) RTKACLanguageType currentLanguage;


/// Return a list of languages this peripheral support for Voice prompt.
///
/// Affected by ``RTKACBasicRoutine/getLanguageWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSSet <RTKACLanguageType> *supportedLanguages;

/// Return the battery level of the primary role this device last cached.
///
/// Scalar value is of `RTKACBatteryLevelInvalid` type. Affected by  ``RTKACBasicRoutine/getBatteryLevelWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *primaryBatteryLevel;

/// Return the battery level of the secondary role this device last cached.
///
/// Scalar value is of `RTKACBatteryLevelInvalid` type. Affected by ``RTKACBasicRoutine/getBatteryLevelWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *secondaryBatteryLevel;

/// Return the battery level of the cradle this device last cached.
///
/// Scalar value is of `RTKACBatteryLevelInvalid` type. Affected by ``RTKACBasicRoutine/getBatteryLevelWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *cradleBatteryLevel;


/// Return the battery level of the left role this device last cached.
///
/// Scalar value is of `RTKACBatteryLevelInvalid` type. Affected by ``RTKACBasicRoutine/convertBatteryToLeftRightFromPrimary:andSecondary:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *leftBatteryLevel;


/// Return the battery level of the right role this device last cached.
///
/// Scalar value is of `RTKACBatteryLevelInvalid` type. Affected by ``RTKACBasicRoutine/convertBatteryToLeftRightFromPrimary:andSecondary:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *rightBatteryLevel;


/// Return the battery level of the single bud this device last cached.
///
/// Scalar value is of `RTKACBatteryLevelInvalid` type. Affected by ``RTKACBasicRoutine/convertBatteryToLeftRightFromPrimary:andSecondary:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *singleBatteryLevel;


/// Return the VP Ringtone volume level of the left bud this device last cached.
///
/// Scalar value is of `RTKACVolumeLevel` type. Affected by ``RTKACBasicRoutine/getVPRingtoneVolumeStateWithCompletionHandler:``, ``RTKACBasicRoutine/setVPRingtoneVolumeLevelOfL:R:withCompletionHandler:`` and ``RTKACBasicRoutine/setVPRingtoneVolumeLevelOfL:R:Sync:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *LVPRingtoneVolumeLevel;


/// Return the VP Ringtone volume level of the right bud this device last cached.
///
/// Scalar value is of ``RTKACVolumeLevel`` type. Affected by ``RTKACBasicRoutine/getVPRingtoneVolumeStateWithCompletionHandler:``, ``RTKACBasicRoutine/setVPRingtoneVolumeLevelOfL:R:withCompletionHandler:`` and ``RTKACBasicRoutine/setVPRingtoneVolumeLevelOfL:R:Sync:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *RVPRingtoneVolumeLevel;


/// Return the VP Ringtone minimum volume level of the left bud this device last cached.
///
/// Scalar value is of ``RTKACVolumeLevel`` type. Affected by ``RTKACBasicRoutine/getVPRingtoneVolumeStateWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *minLVPRingtoneVolumeLevel;


/// Return the VP Ringtone maximum volume level of the left bud this device last cached.
///
/// Scalar value is of ``RTKACVolumeLevel`` type. Affected by ``RTKACBasicRoutine/getVPRingtoneVolumeStateWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *maxLVPRingtoneVolumeLevel;


/// Return the VP Ringtone minimum volume level of the right bud this device last cached.
///
/// Scalar value is of ``RTKACVolumeLevel`` type. Affected by ``RTKACBasicRoutine/getVPRingtoneVolumeStateWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *minRVPRingtoneVolumeLevel;


/// Return the VP Ringtone maximum volume level of the right bud this device last cached.
///
/// Scalar value is of `RTKACVolumeLevel` type. Affected by ``RTKACBasicRoutine/getVPRingtoneVolumeStateWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *maxRVPRingtoneVolumeLevel;


/// Return whether the left and right VP Ringtone level are in sync.
///
/// Scalar value is of `BOOL` type. Affected by ``RTKACBasicRoutine/getVPRingtoneVolumeStateWithCompletionHandler:`` and ``RTKACBasicRoutine/setVPRingtoneVolumeLevelOfL:R:Sync:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *syncVPRingtoneVolume;


/// Return the current global volume level.
///
/// Scalar value is of ``RTKACVolumeLevel`` type. Affected by ``RTKACBasicRoutine/getVolumeLevelWithCompletionHandler:`` and ``RTKACBasicRoutine/setVolumeLevelTo:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *volumeLevel;


/// Return the maximum volume level.
///
/// Scalar value is of ``RTKACVolumeLevel`` type. Affected by ``RTKACBasicRoutine/getVolumeLevelWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *maxVolumeLevel;


/// Return the RWS on-off state of the this device last cached.
///
/// Scalar value is of `BOOL` type. Affected by ``RTKACBasicRoutine/getRWSStateWithCompletionHandler:`` and device active notification.
@property (nonatomic, nullable, readonly) NSNumber *RWSState;


/// Return the RWS channel state of the this device last cached.
///
/// Scalar value is of ``RTKACChannelDirection`` type. Affected by ``RTKACBasicRoutine/getRWSChannelWithCompletionHandler:`` and device active notification.
@property (nonatomic, readonly, nullable) NSNumber *RWSChannel;


/// Return the default role last cached of this device.
///
/// Scalar value is of ``RTKACBudRole`` type. Affected by ``RTKACBasicRoutine/getDefaultBudRoleWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *defaultBudRole;


///Return the bud side last cached of this device.
///
/// Scalar value is of ``RTKACBudSide`` type. Affected by ``RTKACBasicRoutine/getBudSideWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *budSide;


/// Return the default channel last cached of this device.
///
/// Scalar value is of ``RTKACChannelDirection`` type. Affected by ``RTKACBasicRoutine/getDefaultRWSChannelDirectionWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *defaultRWSChannelDirection;


/// Return the budType of this peripheral last cached. 0x00 Single, 0x01 RWS
///
/// Scalar value is of ``RTKBudType`` type. Affected by ``RTKACBasicRoutine/getBudInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *budType;


/// Return the connected bud of this peripheral last cached.
///
/// Scalar value is of ``RTKACBudSide`` type. Affected by ``RTKACBasicRoutine/getBudInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *primaryBudSide;


/// Return the channel corresponding to left and right of this peripheral last cached.
///
/// Scalar value is of ``RTKACLRChannel`` type. Affected by ``RTKACBasicRoutine/getBudInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *LRChannel;


/// Return the left battery of this peripheral last cached.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACBasicRoutine/getBudInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *singleOrLeftBattery;


/// Return the right battery of this peripheral last cached.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACBasicRoutine/getBudInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *rightBattery;


/// Return the case battery of this peripheral last cached.
///
/// Scalar value is of unsigned integer type. Affected by ``RTKACBasicRoutine/getBudInfoWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *caseBattery;


/// Returns a value indicating if In Ear Dectection is on.
///
/// Scalar value is of `BOOL` type. Affected by ``RTKACBasicRoutine/getInEarDetectionStatusWithCompletionHandler:`` and ``RTKACBasicRoutine/switchInEarDetectionStatusWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *inEarDetectionStatus;


/// Returns a value indicating whether the find me status of left bud is enabled.
///
/// Scalar value is of `BOOL` type. Affected by ``RTKACBasicRoutine/getFindmeStatusWithCompletionHandler:`` and ``RTKACBasicRoutine/setFindmeStatus:ofRightBud:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *leftBudFindmeEnabled;


/// Returns a value indicating whether the find me status of right bud is enabled.
///
/// Scalar value is of `BOOL` type. Affected by ``RTKACBasicRoutine/getFindmeStatusWithCompletionHandler:`` and ``RTKACBasicRoutine/setFindmeStatus:ofRightBud:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *rightBudFindmeEnabled;


@end


@interface RTKACBasicRoutine (Deprecated)


- (void)getPackageInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKBBproChip chip, NSUInteger packageID))handler RTK_REDIRECT(fetchPackageInfoWithCompletionHandler:);

- (void)getProductInfoWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKBBproEntityID modelId, RTKBBproEntityID companyId))handler RTK_REDIRECT(fetchProductInfoWithCompletionHandler:);

#pragma mark - Capability

/// Please migrate to the new API that uses `RTKACCapabilityType`.
/// @see isAvailableFor:
- (BOOL)isAvailableForLegacy:(RTKBBproCapabilityType)capability
RTK_REDIRECT('isAvailableFor:' with 'RTKACCapabilityType')
   NS_SWIFT_NAME(isAvailable(for:));

#pragma mark - Language
- (void)getLanguageWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, NSSet <RTKBBproLanguageType>* supportedLangs, RTKBBproLanguageType currentLang))handler RTK_REDIRECT(getLanguageInfoWithCompletionHandler:);

/// Please migrate to the new API that uses `RTKACLanguageType`.
/// @see setCurrentLanguage:withCompletionHandler:
- (void)setCurrentLanguageLegacy:(RTKBBproLanguageType)lang
           withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler
RTK_REDIRECT('setCurrentLanguage:withCompletionHandler:' with 'RTKACLanguageType')
   NS_SWIFT_NAME(setCurrentLanguage(_:withCompletionHandler:));

#pragma mark - BudInfo

- (void)getDefaultBudRoleWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKBBproBudRole role))handler RTK_REDIRECT(getDefaultBudRoleInfoWithCompletionHandler:);

- (void)getBudSideWithCompletionHandler:(nullable void(^)(BOOL success, NSError *_Nullable err, RTKBBproBudSide side))handler RTK_REDIRECT(getBudSideInfoWithCompletionHandler:);

#pragma mark - Battery

- (void)getBatteryLevelWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKBBproBatteryLevel primary, RTKBBproBatteryLevel secondary, RTKBBproBatteryLevel cradle))handler RTK_REDIRECT(getBatteryInfoWithCompletionHandler:);

/// Please migrate to the new API that uses `RTKACBatteryLevel`.
/// @see convertBatteryToLeftRightFromPrimary:andSecondary:withCompletionHandler:
- (void)convertBatteryToLeftRightFromPrimaryLegacy:(RTKBBproBatteryLevel)primary
                                      andSecondary:(RTKBBproBatteryLevel)secondary
                             withCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error))handler
RTK_REDIRECT('convertBatteryToLeftRightFromPrimary:andSecondary:withCompletionHandler:' with 'RTKACBatteryLevel')
   NS_SWIFT_NAME(convertBatteryToLeftRight(fromPrimary:andSecondary:withCompletionHandler:));

#pragma mark - RWS

- (void)getDefaultRWSChannelDirectionWithCompletionHandler:(nullable void(^)(BOOL success, NSError *_Nullable error, RTKBBproChannelDirection direction))handler RTK_REDIRECT(getDefaultRWSChannelDirectionInfoWithCompletionHandler:);

- (void)getRWSChannelWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKBBproChannelDirection channel))handler RTK_REDIRECT(getRWSChannelInfoWithCompletionHandler:);

#pragma mark - Volume

- (void)getVPRingtoneVolumeStateWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKBBproVolumeLevel minLevelL, RTKBBproVolumeLevel maxLevelL, RTKBBproVolumeLevel curLevelL, RTKBBproVolumeLevel minLevelR, RTKBBproVolumeLevel maxLevelR, RTKBBproVolumeLevel curLevelR))handler RTK_REDIRECT(getVPRingtoneVolumeInfoWithCompletionHandler:);

- (void)getVolumeLevelWithCompletionHandler:(nullable void(^)(BOOL success, NSError*_Nullable error, RTKBBproVolumeLevel volumeLevel, RTKBBproVolumeLevel maxLevel))handler RTK_REDIRECT(getVolumeInfoWithCompletionHandler:);

/// Please migrate to the new API that uses `RTKACVolumeLevel`.
/// @see setVPRingtoneVolumeLevelOfL:R:withCompletionHandler:
- (void)setVPRingtoneVolumeLevelOfLLegacy:(RTKBBproVolumeLevel)levelL
                                        R:(RTKBBproVolumeLevel)levelR
                    withCompletionHandler:(nullable RTKLECompletionBlock)handler
RTK_REDIRECT('setVPRingtoneVolumeLevelOfL:R:withCompletionHandler:' with 'RTKACVolumeLevel')
   NS_SWIFT_NAME(setVPRingtoneVolumeLevelOfL(_:R:withCompletionHandler:));


/// Please migrate to the new API that uses `RTKACVolumeLevel`.
/// @see setVPRingtoneVolumeLevelOfL:R:Sync:withCompletionHandler:
- (void)setVPRingtoneVolumeLevelOfLLegacy:(RTKBBproVolumeLevel)levelL
                                        R:(RTKBBproVolumeLevel)levelR
                                     Sync:(uint8_t)sync
                    withCompletionHandler:(nullable RTKLECompletionBlock)handler
RTK_REDIRECT('setVPRingtoneVolumeLevelOfL:R:Sync:withCompletionHandler:' with 'RTKACVolumeLevel')
   NS_SWIFT_NAME(setVPRingtoneVolumeLevelOfL(_:R:Sync:withCompletionHandler:));


/// Please migrate to the new API that uses `RTKACVolumeLevel`.
/// @see setVolumeLevelTo:withCompletionHandler:
- (void)setVolumeLevelToLegacy:(RTKBBproVolumeLevel)level
         withCompletionHandler:(nullable RTKLECompletionBlock)handler
RTK_REDIRECT('setVolumeLevelTo:withCompletionHandler:' with 'RTKACVolumeLevel')
   NS_SWIFT_NAME(setVolumeLevel(to:withCompletionHandler:));

@end

NS_ASSUME_NONNULL_END
