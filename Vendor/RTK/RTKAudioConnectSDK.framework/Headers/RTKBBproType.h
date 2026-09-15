//
//  RTKBBproType.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2020/3/13.
//  Copyright (c) 2020, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#ifndef RTKBBproType_h
#define RTKBBproType_h

#import <Foundation/Foundation.h>
#ifdef ATAudioConnectSDK
#import <ATAudioConnectSDK/RTKACType.h>
#import <ATAudioConnectSDK/RTKMacros.h>
#elif defined(RTKWaveLiteSDK)
#import <RTKWaveLiteSDK/RTKACType.h>
#import <RTKWaveLiteSDK/RTKMacros.h>
#else
#import <RTKAudioConnectSDK/RTKACType.h>
#import <RTKAudioConnectSDK/RTKMacros.h>
#endif

typedef uint16_t RTKBBproEntityID RTK_REDIRECT(RTKACEntityID);

extern const uint8_t RTKBBproBatteryLevelInvalid RTK_REDIRECT(RTKACBatteryLevelInvalid);

typedef uint8_t RTKBBproBatteryLevel RTK_REDIRECT(RTKACBatteryLevel);

extern const uint8_t RTKBBproVolumeLevelInvalid RTK_REDIRECT(RTKACVolumeLevelInvalid);

typedef uint8_t RTKBBproVolumeLevel RTK_REDIRECT(RTKACVolumeLevel);

// MARK: - Language

typedef NSString* RTKBBproLanguageType RTK_REDIRECT(RTKACLanguageType);

extern RTKBBproLanguageType const RTKBBproLanguageDefault RTK_REDIRECT(RTKACLanguageDefault);

extern RTKBBproLanguageType const RTKBBproLanguageEnglish RTK_REDIRECT(RTKACLanguageEnglish);

extern RTKBBproLanguageType const RTKBBproLanguageChinese RTK_REDIRECT(RTKACLanguageChinese);

extern RTKBBproLanguageType const RTKBBproLanguageFrench RTK_REDIRECT(RTKACLanguageFrench);

extern RTKBBproLanguageType const RTKBBproLanguagePortuguese RTK_REDIRECT(RTKACLanguagePortuguese);

extern RTKBBproLanguageType const RTKBBproLanguageUnknown RTK_REDIRECT(RTKACLanguageUnknown);


// MARK: - Chip Type

typedef NS_ENUM(NSUInteger, RTKBBproChip) {
    RTKBBproChip_unknown    RTK_REDIRECT(RTKACChip_unknown) = RTKACChip_unknown,
    RTKBBproChip_BBPro      RTK_REDIRECT(RTKACChip_87x3B)   = RTKACChip_87x3B,
    RTKBBproChip_BBPro2     RTK_REDIRECT(RTKACChip_87x3C)   = RTKACChip_87x3C,
    RTKBBproChip_BBLite     RTK_REDIRECT(RTKACChip_8773B)   = RTKACChip_8773B,
    RTKBBproChip_BBpro3     RTK_REDIRECT(RTKACChip_87x3D)   = RTKACChip_87x3D,
    RTKBBproChip_BB2        RTK_REDIRECT(RTKACChip_87x3E)   = RTKACChip_87x3E,
    RTKBBproChip_BB2Plus    RTK_REDIRECT(RTKACChip_87x3EP)  = RTKACChip_87x3EP,
    
    RTKBBproChip_8763B      RTK_REDIRECT(RTKACChip_87x3B)   = RTKACChip_87x3B,
    RTKBBproChip_8763C      RTK_REDIRECT(RTKACChip_87x3C)   = RTKACChip_87x3C,
    RTKBBproChip_8773B      RTK_REDIRECT(RTKACChip_8773B)   = RTKACChip_8773B,
    RTKBBproChip_8763D      RTK_REDIRECT(RTKACChip_87x3D)   = RTKACChip_87x3D,
    RTKBBproChip_8763E      RTK_REDIRECT(RTKACChip_87x3E)   = RTKACChip_87x3E,
    RTKBBproChip_8773E      RTK_REDIRECT(RTKACChip_87x3EP)  = RTKACChip_87x3EP,
} RTK_REDIRECT(RTKACChip);

// MARK: - Capabilities

typedef NS_ENUM(NSUInteger, RTKBBproCapabilityType) {
    RTKBBproCapabilityType_LENameAccess                         RTK_REDIRECT(RTKACCapabilityType_LENameAccess)          = RTKACCapabilityType_LENameAccess,
    RTKBBproCapabilityType_BREDRNameAccess                      RTK_REDIRECT(RTKACCapabilityType_BREDRNameAccess)       = RTKACCapabilityType_BREDRNameAccess,
    RTKBBproCapabilityType_LanguageAccess                       RTK_REDIRECT(RTKACCapabilityType_LanguageAccess)        = RTKACCapabilityType_LanguageAccess,
    RTKBBproCapabilityType_BatteryLevelAccess                   RTK_REDIRECT(RTKACCapabilityType_BatteryLevelAccess)    = RTKACCapabilityType_BatteryLevelAccess,
    RTKBBproCapabilityType_OTA                                  RTK_REDIRECT(RTKACCapabilityType_OTA)                   = RTKACCapabilityType_OTA,
    RTKBBproCapabilityType_ChannelSwitch                        RTK_REDIRECT(RTKACCapabilityType_ChannelSwitch)         = RTKACCapabilityType_ChannelSwitch,
    RTKBBproCapabilityType_TTS                                  RTK_REDIRECT(RTKACCapabilityType_TTS)                   = RTKACCapabilityType_TTS,
    RTKBBproCapabilityType_RWS                                  RTK_REDIRECT(RTKACCapabilityType_RWS)                   = RTKACCapabilityType_RWS,
    RTKBBproCapabilityType_APT                                  RTK_REDIRECT(RTKACCapabilityType_APT)                   = RTKACCapabilityType_APT,
    RTKBBproCapabilityType_EQ                                   RTK_REDIRECT(RTKACCapabilityType_EQ)                    = RTKACCapabilityType_EQ,
    RTKBBproCapabilityType_VAD                                  RTK_REDIRECT(RTKACCapabilityType_VAD)                   = RTKACCapabilityType_VAD,
    RTKBBproCapabilityType_ANC                                  RTK_REDIRECT(RTKACCapabilityType_ANC)                   = RTKACCapabilityType_ANC,
    RTKBBproCapabilityType_LLAPT                                RTK_REDIRECT(RTKACCapabilityType_LLAPT)                 = RTKACCapabilityType_LLAPT,
    RTKBBproCapabilityType_ListeningModeCycle                   RTK_REDIRECT(RTKACCapabilityType_ListeningModeCycle)    = RTKACCapabilityType_ListeningModeCycle,
    RTKBBproCapabilityType_LLAPTBrightness                      RTK_REDIRECT(RTKACCapabilityType_LLAPTBrightness)       = RTKACCapabilityType_LLAPTBrightness,
    RTKBBproCapabilityType_ANCEQ                                RTK_REDIRECT(RTKACCapabilityType_ANCEQ)                 = RTKACCapabilityType_ANCEQ,
    RTKBBproCapabilityType_APTEQ                                RTK_REDIRECT(RTKACCapabilityType_APTEQ)                 = RTKACCapabilityType_APTEQ,
    RTKBBproCapabilityType_ringtoneVPAjustment                  RTK_REDIRECT(RTKACCapabilityType_ringtoneVPAjustment)   = RTKACCapabilityType_ringtoneVPAjustment,
    RTKBBproCapabilityType_singleAPTAdjustment                  RTK_REDIRECT(RTKACCapabilityType_singleAPTAdjustment)   = RTKACCapabilityType_singleAPTAdjustment,
    RTKBBproCapabilityType_MultiLink                            RTK_REDIRECT(RTKACCapabilityType_MultiLink)             = RTKACCapabilityType_MultiLink,
    RTKBBproCapabilityType_Durian                               RTK_REDIRECT(RTKACCapabilityType_Durian)                = RTKACCapabilityType_Durian,
    RTKBBproCapabilityType_APTNR                                RTK_REDIRECT(RTKACCapabilityType_APTNR)                 = RTKACCapabilityType_APTNR,
    RTKBBproCapabilityType_LLAPTScenario                        RTK_REDIRECT(RTKACCapabilityType_LLAPTScenario)         = RTKACCapabilityType_LLAPTScenario,
    RTKBBproCapabilityType_EarDetection                         RTK_REDIRECT(RTKACCapabilityType_EarDetection)          = RTKACCapabilityType_EarDetection,
    RTKBBproCapabilityType_APTPowerOnDelayTime                  RTK_REDIRECT(RTKACCapabilityType_APTPowerOnDelayTime)   = RTKACCapabilityType_APTPowerOnDelayTime,
    RTKBBproCapabilityType_ANCEQConfigure                       RTK_REDIRECT(RTKACCapabilityType_ANCEQConfigure)        = RTKACCapabilityType_ANCEQConfigure,
    RTKBBproCapabilityType_GetBudInfo                           RTK_REDIRECT(RTKACCapabilityType_GetBudInfo)            = RTKACCapabilityType_GetBudInfo,
    RTKBBproCapabilityType_ListeningModereport                  RTK_REDIRECT(RTKACCapabilityType_ListeningModereport)   = RTKACCapabilityType_ListeningModereport,
    RTKBBproCapabilityType_APTVolumeRWSSync                     RTK_REDIRECT(RTKACCapabilityType_APTVolumeRWSSync)      = RTKACCapabilityType_APTVolumeRWSSync,
    RTKBBproCapabilityType_ResetKeyMapping                      RTK_REDIRECT(RTKACCapabilityType_ResetKeyMapping)       = RTKACCapabilityType_ResetKeyMapping,
    RTKBBproCapabilityType_ANCS                                 RTK_REDIRECT(RTKACCapabilityType_ANCS)                  = RTKACCapabilityType_ANCS,
    RTKBBproCapabilityType_Vibration                            RTK_REDIRECT(RTKACCapabilityType_Vibration)             = RTKACCapabilityType_Vibration,
    RTKBBproCapabilityType_MFB                                  RTK_REDIRECT(RTKACCapabilityType_MFB)                   = RTKACCapabilityType_MFB,
    RTKBBproCapabilityType_GamingMode                           RTK_REDIRECT(RTKACCapabilityType_GamingMode)            = RTKACCapabilityType_GamingMode,
    RTKBBproCapabilityType_GamingModeEQ                         RTK_REDIRECT(RTKACCapabilityType_GamingModeEQ)          = RTKACCapabilityType_GamingModeEQ,
    RTKBBproCapabilityType_KeyMapping                           RTK_REDIRECT(RTKACCapabilityType_KeyMapping)            = RTKACCapabilityType_KeyMapping,
    RTKBBproCapabilityType_HearingAid                           RTK_REDIRECT(RTKACCapabilityType_HearingAid)            = RTKACCapabilityType_HearingAid,
    RTKBBproCapabilityType_LocalPlayback                        RTK_REDIRECT(RTKACCapabilityType_LocalPlayback)         = RTKACCapabilityType_LocalPlayback,
    RTKBBproCapabilityType_ANCScenarioGroupSetting              RTK_REDIRECT(RTKACCapabilityType_ANCScenarioGroupSetting)       = RTKACCapabilityType_ANCScenarioGroupSetting,
    RTKBBproCapabilityType_RWSKeyRemap                          RTK_REDIRECT(RTKACCapabilityType_RWSKeyRemap)           = RTKACCapabilityType_RWSKeyRemap,
    RTKBBproCapabilityType_EQPersistence                        RTK_REDIRECT(RTKACCapabilityType_EQPersistence)         = RTKACCapabilityType_EQPersistence,
    RTKBBproCapabilityType_ResetKeyMapByBud                     RTK_REDIRECT(RTKACCapabilityType_ResetKeyMapByBud)      = RTKACCapabilityType_ResetKeyMapByBud,
    RTKBBproCapabilityType_DataCaptureV2                        RTK_REDIRECT(RTKACCapabilityType_DataCaptureV2)         = RTKACCapabilityType_DataCaptureV2,
    RTKBBproCapabilityType_ListeningModeForANCAPT               RTK_REDIRECT(RTKACCapabilityType_ListeningModeForANCAPT)        = RTKACCapabilityType_ListeningModeForANCAPT,
    RTKBBproCapabilityType_SpecialANCScenario                   RTK_REDIRECT(RTKACCapabilityType_SpecialANCScenario)    = RTKACCapabilityType_SpecialANCScenario,
    RTKBBproCapabilityType_DSP3BinScenario                      RTK_REDIRECT(RTKACCapabilityType_DSP3BinScenario)       = RTKACCapabilityType_DSP3BinScenario,
    RTKBBproCapabilityType_VoiceEQ                              RTK_REDIRECT(RTKACCapabilityType_VoiceEQ)               = RTKACCapabilityType_VoiceEQ,
    RTKBBproCapabilityType_ANCApplyBurn                         RTK_REDIRECT(RTKACCapabilityType_ANCApplyBurn)          = RTKACCapabilityType_ANCApplyBurn,
    RTKBBproCapabilityType_EQAdjustSeparately                   RTK_REDIRECT(RTKACCapabilityType_EQAdjustSeparately)    = RTKACCapabilityType_EQAdjustSeparately,
    RTKBBproCapabilityType_EQCompensation                       RTK_REDIRECT(RTKACCapabilityType_EQCompensation)        = RTKACCapabilityType_EQCompensation,
    RTKBBproCapabilityType_MCULog                               RTK_REDIRECT(RTKACCapabilityType_MCULog)                = RTKACCapabilityType_MCULog,
    RTKBBproCapabilityType_DisableNormalAPTVolume               RTK_REDIRECT(RTKACCapabilityType_DisableNormalAPTVolume)        = RTKACCapabilityType_DisableNormalAPTVolume,
    RTKBBproCapabilityType_DisableLLAPTVolume                   RTK_REDIRECT(RTKACCapabilityType_DisableLLAPTVolume)    = RTKACCapabilityType_DisableLLAPTVolume,
    RTKBBproCapabilityType_MICVoiceEQ                           RTK_REDIRECT(RTKACCapabilityType_MICVoiceEQ)            = RTKACCapabilityType_MICVoiceEQ,
    RTKBBproCapabilityType_ListeningModeCycle_CustomMode        RTK_REDIRECT(RTKACCapabilityType_ListeningModeCycle_CustomMode) = RTKACCapabilityType_ListeningModeCycle_CustomMode,
    
    RTKBBproCapabilityType_ChargingCase                         RTK_REDIRECT(RTKACCapabilityType_ChargingCase)          = RTKACCapabilityType_ChargingCase,
    RTKBBproCapabilityType_ChargingCaseWallpaperUpdate          RTK_REDIRECT(RTKACCapabilityType_ChargingCaseWallpaperUpdate)   = RTKACCapabilityType_ChargingCaseWallpaperUpdate,
    
    RTKBBproCapabilityType_SingleModeIndependentVolumeAdjust    RTK_REDIRECT(RTKACCapabilityType_SingleModeIndependentVolumeAdjust) = RTKACCapabilityType_SingleModeIndependentVolumeAdjust,
} RTK_REDIRECT(RTKACCapabilityType);


// MARK: - Bud Info

typedef NS_ENUM(uint8_t, RTKBBproPeripheralBudType) {
    RTKBBproPeripheralBudType_Default   RTK_REDIRECT(RTKACBudSide_Unknown)  = RTKACBudSide_Unknown,
    RTKBBproPeripheralBudType_Left      RTK_REDIRECT(RTKACBudSide_L)        = RTKACBudSide_L,
    RTKBBproPeripheralBudType_Right     RTK_REDIRECT(RTKACBudSide_R)        = RTKACBudSide_R,
} RTK_REDIRECT(RTKACBudSide);

typedef enum : NSInteger {
    RTKBBproBudSide_Unknown     RTK_REDIRECT(RTKACBudSide_Unknown)  = RTKACBudSide_Unknown,
    RTKBBproBudSide_L           RTK_REDIRECT(RTKACBudSide_L)        = RTKACBudSide_L,
    RTKBBproBudSide_R           RTK_REDIRECT(RTKACBudSide_R)        = RTKACBudSide_R,
} RTKBBproBudSide RTK_REDIRECT(RTKACBudSide);

typedef enum : UInt8 {
    RTKBBproChannelDirection_Unknown            RTK_REDIRECT(RTKACChannelDirection_Unknown)         = RTKACChannelDirection_Unknown,
    RTKBBproChannelDirection_PrimaryToLeft      RTK_REDIRECT(RTKACChannelDirection_PrimaryToLeft)   = RTKACChannelDirection_PrimaryToLeft,
    RTKBBproChannelDirection_PrimaryToRight     RTK_REDIRECT(RTKACChannelDirection_PrimaryToRight)  = RTKACChannelDirection_PrimaryToRight,
    RTKBBproChannelDirection_Mix                RTK_REDIRECT(RTKACChannelDirection_Mix)             = RTKACChannelDirection_Mix,
} RTKBBproChannelDirection RTK_REDIRECT(RTKACChannelDirection);

typedef enum : UInt8 {
    RTKBBproLRChannel_LeftToLeft        RTK_REDIRECT(RTKACLRChannel_LeftToLeft)     = RTKACLRChannel_LeftToLeft,
    RTKBBproLRChannel_LeftToRight       RTK_REDIRECT(RTKACLRChannel_LeftToRight)    = RTKACLRChannel_LeftToRight,
    RTKBBproLRChannel_Mix               RTK_REDIRECT(RTKACLRChannel_Mix)            = RTKACLRChannel_Mix,
    RTKBBproLRChannel_invalid           RTK_REDIRECT(RTKACLRChannel_Invalid)        = RTKACLRChannel_Invalid,
} RTKBBproLRChannel RTK_REDIRECT(RTKACLRChannel);

typedef enum : UInt8 {
    RTKBBproBudRole_Single          RTK_REDIRECT(RTKACBudRole_Single)       = RTKACBudRole_Single,
    RTKBBproBudRole_Primary         RTK_REDIRECT(RTKACBudRole_Primary)      = RTKACBudRole_Primary,
    RTKBBproBudRole_Secondary       RTK_REDIRECT(RTKACBudRole_Secondary)    = RTKACBudRole_Secondary,
    RTKBBproBudRole_Unknown         RTK_REDIRECT(RTKACBudRole_Unknown)      = RTKACBudRole_Unknown,
} RTKBBproBudRole RTK_REDIRECT(RTKACBudRole);


// MARK: - MMI

typedef RTKACMMIAction RTKBBproPeripheralMMI RTK_REDIRECT(RTKACMMIAction);

typedef NS_ENUM(uint8_t, RTKBBproPeripheralMMIStatus) {
    RTKBBproPeripheralMMIStatus_Idle    RTK_REDIRECT(RTKACMMIStatus_Idle)    = RTKACMMIStatus_Idle,
    RTKBBproPeripheralMMIStatus_InCall  RTK_REDIRECT(RTKACMMIStatus_InCall)  = RTKACMMIStatus_InCall,
} RTK_REDIRECT(RTKACMMIStatus);

typedef NS_ENUM(uint8_t, RTKBBproPeripheralMMIClickType) {
    RTKBBproPeripheralMMIClickType_None              RTK_REDIRECT(RTKACMMIClickType_None)           = RTKACMMIClickType_None,
    RTKBBproPeripheralMMIClickType_Single            RTK_REDIRECT(RTKACMMIClickType_Single)         = RTKACMMIClickType_Single,
    RTKBBproPeripheralMMIClickType_Multi2            RTK_REDIRECT(RTKACMMIClickType_Multi2)         = RTKACMMIClickType_Multi2,
    RTKBBproPeripheralMMIClickType_Multi3            RTK_REDIRECT(RTKACMMIClickType_Multi3)         = RTKACMMIClickType_Multi3,
    RTKBBproPeripheralMMIClickType_LongPress         RTK_REDIRECT(RTKACMMIClickType_LongPress)      = RTKACMMIClickType_LongPress,
    RTKBBproPeripheralMMIClickType_UtralLongPress     RTK_REDIRECT(RTKACMMIClickType_UltraLongPress) = RTKACMMIClickType_UltraLongPress,
} RTK_REDIRECT(RTKACMMIClickType);

typedef NS_ENUM(uint8_t, RTKBBproMMIBudSide) {
    RTKBBproMMIBudSide_stereo       RTK_REDIRECT(RTKACMMIBudSide_stereo)    = RTKACMMIBudSide_stereo,
    RTKBBproMMIBudSide_left         RTK_REDIRECT(RTKACMMIBudSide_left)      = RTKACMMIBudSide_left,
    RTKBBproMMIBudSide_right        RTK_REDIRECT(RTKACMMIBudSide_right)     = RTKACMMIBudSide_right,
    RTKBBproMMIBudSide_both         RTK_REDIRECT(RTKACMMIBudSide_both)      = RTKACMMIBudSide_both,
} RTK_REDIRECT(RTKACMMIBudSide);

typedef RTKACMMIMapping RTKBBproMMIMapping RTK_REDIRECT(RTKACMMIMapping);

// MARK: - Audio

typedef enum : NSUInteger {
    RTKBBproListeningModeSwitchCycle_0      RTK_REDIRECT(RTKACListeningModeSwitchCycle_0)   = RTKACListeningModeSwitchCycle_0,
    RTKBBproListeningModeSwitchCycle_1      RTK_REDIRECT(RTKACListeningModeSwitchCycle_1)   = RTKACListeningModeSwitchCycle_1,
    RTKBBproListeningModeSwitchCycle_2      RTK_REDIRECT(RTKACListeningModeSwitchCycle_2)   = RTKACListeningModeSwitchCycle_2,
    RTKBBproListeningModeSwitchCycle_3      RTK_REDIRECT(RTKACListeningModeSwitchCycle_3)   = RTKACListeningModeSwitchCycle_3,
    RTKBBproListeningModeSwitchCycle_4      RTK_REDIRECT(RTKACListeningModeSwitchCycle_4)   = RTKACListeningModeSwitchCycle_4,
    RTKBBproListeningModeSwitchCycle_5      RTK_REDIRECT(RTKACListeningModeSwitchCycle_5)   = RTKACListeningModeSwitchCycle_5,
} RTKBBproListeningModeSwitchCycle RTK_REDIRECT(RTKACListeningModeSwitchCycle);

typedef NS_ENUM(uint8_t, RTKBBproListeningModeType) {
    RTKBBproListeningModeType_AllOFF            RTK_REDIRECT(RTKACListeningModeType_AllOFF)     = RTKACListeningModeType_AllOFF,
    RTKBBproListeningModeType_NormalAPT         RTK_REDIRECT(RTKACListeningModeType_NormalAPT)  = RTKACListeningModeType_NormalAPT,
    RTKBBproListeningModeType_ANC               RTK_REDIRECT(RTKACListeningModeType_ANC)        = RTKACListeningModeType_ANC,
    RTKBBproListeningModeType_LLAPT             RTK_REDIRECT(RTKACListeningModeType_LLAPT)      = RTKACListeningModeType_LLAPT,
    RTKBBproListeningModeType_ANCAPT            RTK_REDIRECT(RTKACListeningModeType_ANCAPT)     = RTKACListeningModeType_ANCAPT,
} RTK_REDIRECT(RTKACListeningModeType);

typedef NS_ENUM(uint8_t, RTKBBproAPTType) {
    RTKBBproAPTType_NormalAPT   RTK_REDIRECT(RTKACAPTType_NormalAPT)    = RTKACAPTType_NormalAPT,
    RTKBBproAPTType_LLAPT       RTK_REDIRECT(RTKACAPTType_LLAPT)        = RTKACAPTType_LLAPT,
} RTK_REDIRECT(RTKACAPTType);

typedef enum : uint8_t {
    RTKBBproANCScenario_none        RTK_REDIRECT(RTKACANCScenario_none)         = RTKACANCScenario_none,
    RTKBBproANCScenario_high        RTK_REDIRECT(RTKACANCScenario_high)         = RTKACANCScenario_high,
    RTKBBproANCScenario_low         RTK_REDIRECT(RTKACANCScenario_low)          = RTKACANCScenario_low,
    RTKBBproANCScenario_family      RTK_REDIRECT(RTKACANCScenario_family)       = RTKACANCScenario_family,
    RTKBBproANCScenario_library     RTK_REDIRECT(RTKACANCScenario_library)      = RTKACANCScenario_library,
    RTKBBproANCScenario_airplane    RTK_REDIRECT(RTKACANCScenario_airplane)     = RTKACANCScenario_airplane,
    RTKBBproANCScenario_subway      RTK_REDIRECT(RTKACANCScenario_subway)       = RTKACANCScenario_subway,
    RTKBBproANCScenario_outdoor     RTK_REDIRECT(RTKACANCScenario_outdoor)      = RTKACANCScenario_outdoor,
    RTKBBproANCScenario_running     RTK_REDIRECT(RTKACANCScenario_running)      = RTKACANCScenario_running,
    RTKBBproANCScenario_linein      RTK_REDIRECT(RTKACANCScenario_linein)       = RTKACANCScenario_linein,
    
    RTKBBproANCScenario_customer0   RTK_REDIRECT(RTKACANCScenario_customer0)    = RTKACANCScenario_customer0,
    RTKBBproANCScenario_customer1   RTK_REDIRECT(RTKACANCScenario_customer1)    = RTKACANCScenario_customer1,
    RTKBBproANCScenario_customer2   RTK_REDIRECT(RTKACANCScenario_customer2)    = RTKACANCScenario_customer2,
    RTKBBproANCScenario_customer3   RTK_REDIRECT(RTKACANCScenario_customer3)    = RTKACANCScenario_customer3,
    RTKBBproANCScenario_customer4   RTK_REDIRECT(RTKACANCScenario_customer4)    = RTKACANCScenario_customer4,
    RTKBBproANCScenario_customer5   RTK_REDIRECT(RTKACANCScenario_customer5)    = RTKACANCScenario_customer5,
    RTKBBproANCScenario_customer6   RTK_REDIRECT(RTKACANCScenario_customer6)    = RTKACANCScenario_customer6,
    RTKBBproANCScenario_customer7   RTK_REDIRECT(RTKACANCScenario_customer7)    = RTKACANCScenario_customer7,
    
    RTKBBproANCScenario_MP1         RTK_REDIRECT(RTKACANCScenario_MP1)          = RTKACANCScenario_MP1,
    RTKBBproANCScenario_MP2         RTK_REDIRECT(RTKACANCScenario_MP2)          = RTKACANCScenario_MP2,
    
    RTKBBproANCScenario_unknown     RTK_REDIRECT(RTKACANCScenario_unknown)      = RTKACANCScenario_unknown,
    RTKBBproANCScenario_unselected  RTK_REDIRECT(RTKACANCScenario_unselected)   = RTKACANCScenario_unselected,
} RTKBBproANCScenario RTK_REDIRECT(RTKACANCScenario);

typedef NS_ENUM(uint8_t, RTKBBproAPTVolumeType) {
    RTKBBproAPTVolumeType_Main  RTK_REDIRECT(RTKACAPTVolumeType_Main)   = RTKACAPTVolumeType_Main,
    RTKBBproAPTVolumeType_Sub   RTK_REDIRECT(RTKACAPTVolumeType_Sub)    = RTKACAPTVolumeType_Sub,
} RTK_REDIRECT(RTKACAPTVolumeType);

typedef NS_ENUM(uint8_t, RTKBBproAPTBrightnessType) {
    RTKBBproAPTBrightnessType_Main  RTK_REDIRECT(RTKACAPTBrightnessType_Main)   = RTKACAPTBrightnessType_Main,
    RTKBBproAPTBrightnessType_Sub   RTK_REDIRECT(RTKACAPTBrightnessType_Sub)    = RTKACAPTBrightnessType_Sub,
} RTK_REDIRECT(RTKACAPTBrightnessType);


// MARK: - EQ

typedef NS_ENUM(uint8_t, RTKBBproSWEQType) {
    RTKBBproSPK_SW_EQ   RTK_REDIRECT(RTKACSPK_SW_EQ)    = RTKACSPK_SW_EQ,
    RTKBBproMIC_SW_EQ   RTK_REDIRECT(RTKACMIC_SW_EQ)    = RTKACMIC_SW_EQ,
} RTK_REDIRECT(RTKACSWEQType);

typedef NS_ENUM(uint8_t, RTKBBproEQMode) {
    RTKBBproEQMode_apt          RTK_REDIRECT(RTKACEQMode_apt)           = RTKACEQMode_apt,
    RTKBBproEQMode_normal       RTK_REDIRECT(RTKACEQMode_normal)        = RTKACEQMode_normal,
    RTKBBproEQMode_MICVoice     RTK_REDIRECT(RTKACEQMode_MICVoice)      = RTKACEQMode_MICVoice,
    RTKBBproEQMode_gaming       RTK_REDIRECT(RTKACEQMode_gaming)        = RTKACEQMode_gaming,
    RTKBBproEQMode_record       RTK_REDIRECT(RTKACEQMode_record)        = RTKACEQMode_record,
    RTKBBproEQMode_anc          RTK_REDIRECT(RTKACEQMode_anc)           = RTKACEQMode_anc,
    RTKBBproEQMode_linein       RTK_REDIRECT(RTKACEQMode_linein)        = RTKACEQMode_linein,
    RTKBBproEQMode_AudioVoice   RTK_REDIRECT(RTKACEQMode_AudioVoice)    = RTKACEQMode_AudioVoice,
    RTKBBproEQMode_unknown      RTK_REDIRECT(RTKACEQMode_unknown)       = RTKACEQMode_unknown,
} RTK_REDIRECT(RTKACEQMode);

typedef NS_ENUM(uint8_t, RTKBBproEQBudType) {
    RTKBBproEQLeftBud   RTK_REDIRECT(RTKACEQBudSide_Left)   = RTKACEQBudSide_Left,
    RTKBBproEQRightBud  RTK_REDIRECT(RTKACEQBudSide_Right)  = RTKACEQBudSide_Right,
    RTKBBproEQBothBud   RTK_REDIRECT(RTKACEQBudSide_Both)   = RTKACEQBudSide_Both,
} RTK_REDIRECT(RTKACEQBudSide);

typedef NS_ENUM(uint8_t, RTKEQBudSide) {
    RTKEQLeftBud        RTK_REDIRECT(RTKACEQBudSide_Left)   = RTKACEQBudSide_Left,
    RTKEQRightBud       RTK_REDIRECT(RTKACEQBudSide_Right)  = RTKACEQBudSide_Right,
    RTKEQBothBud        RTK_REDIRECT(RTKACEQBudSide_Both)   = RTKACEQBudSide_Both,
} RTK_REDIRECT(RTKACEQBudSide);

typedef enum : uint8_t {
    RTKBBproMeridianSoundEffect_Off     RTK_REDIRECT(RTKACMeridianSoundEffect_Off)      = RTKACMeridianSoundEffect_Off,
    RTKBBproMeridianSoundEffect_Bass    RTK_REDIRECT(RTKACMeridianSoundEffect_Bass)     = RTKACMeridianSoundEffect_Bass,
    RTKBBproMeridianSoundEffect_Flat    RTK_REDIRECT(RTKACMeridianSoundEffect_Flat)     = RTKACMeridianSoundEffect_Flat,
    RTKBBproMeridianSoundEffect_Treble  RTK_REDIRECT(RTKACMeridianSoundEffect_Treble)   = RTKACMeridianSoundEffect_Treble,
} RTKBBproMeridianSoundEffect RTK_REDIRECT(RTKACMeridianSoundEffect);

typedef NS_OPTIONS(uint16_t, RTKBBproEQIndex) {
    RTKBBproEQIndexOff          RTK_REDIRECT(RTKACEQIndexOff)           = RTKACEQIndexOff,
    RTKBBproEQIndexCustomer1    RTK_REDIRECT(RTKACEQIndexCustomer1)     = RTKACEQIndexCustomer1,
    RTKBBproEQIndexCustomer2    RTK_REDIRECT(RTKACEQIndexCustomer2)     = RTKACEQIndexCustomer2,
    RTKBBproEQIndexCustomer3    RTK_REDIRECT(RTKACEQIndexCustomer3)     = RTKACEQIndexCustomer3,
    RTKBBproEQIndexBuiltin1     RTK_REDIRECT(RTKACEQIndexBuiltin1)      = RTKACEQIndexBuiltin1,
    RTKBBproEQIndexBuiltin2     RTK_REDIRECT(RTKACEQIndexBuiltin2)      = RTKACEQIndexBuiltin2,
    RTKBBproEQIndexBuiltin3     RTK_REDIRECT(RTKACEQIndexBuiltin3)      = RTKACEQIndexBuiltin3,
    RTKBBproEQIndexBuiltin4     RTK_REDIRECT(RTKACEQIndexBuiltin4)      = RTKACEQIndexBuiltin4,
    RTKBBproEQIndexBuiltin5     RTK_REDIRECT(RTKACEQIndexBuiltin5)      = RTKACEQIndexBuiltin5,
    RTKBBproEQIndexRealtime     RTK_REDIRECT(RTKACEQIndexRealtime)      = RTKACEQIndexRealtime,
    RTKBBproEQIndexRealtime2    RTK_REDIRECT(RTKACEQIndexRealtime2)     = RTKACEQIndexRealtime2,
} RTK_REDIRECT(RTKACEQIndex);

// MARK: -

typedef NS_OPTIONS(uint8_t, RTKBBproLegacyProfile) {
    RTKBBproLegacyProfile_A2DP      RTK_REDIRECT(RTKACLegacyProfile_A2DP)   = RTKACLegacyProfile_A2DP,
    RTKBBproLegacyProfile_AVRCP     RTK_REDIRECT(RTKACLegacyProfile_AVRCP)  = RTKACLegacyProfile_AVRCP,
    RTKBBproLegacyProfile_HFHS      RTK_REDIRECT(RTKACLegacyProfile_HFHS)   = RTKACLegacyProfile_HFHS,
    RTKBBproLegacyProfile_Vendor    RTK_REDIRECT(RTKACLegacyProfile_Vendor) = RTKACLegacyProfile_Vendor,
    RTKBBproLegacyProfile_SPP       RTK_REDIRECT(RTKACLegacyProfile_SPP)    = RTKACLegacyProfile_SPP,
    RTKBBproLegacyProfile_iAP       RTK_REDIRECT(RTKACLegacyProfile_iAP)    = RTKACLegacyProfile_iAP,
    RTKBBproLegacyProfile_PBAP      RTK_REDIRECT(RTKACLegacyProfile_PBAP)   = RTKACLegacyProfile_PBAP,
} RTK_REDIRECT(RTKACLegacyProfile);

#endif /* RTKBBproType_h */
