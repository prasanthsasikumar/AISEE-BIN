//
//  RTKACType.h
//  RTKAudioConnectSDK
//
//  Created by irene_wang on 2026/1/16.
//  Copyright (c) 2026, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <Foundation/Foundation.h>

#ifndef RTKACType_h
#define RTKACType_h

typedef uint16_t RTKACEntityID;

/// A constant value describes battery level is not valid.
extern const uint8_t RTKACBatteryLevelInvalid;

/// A unsigned integer value represents battery charge level of one device.
///
/// The value ranges from `0` to `100`.
typedef uint8_t RTKACBatteryLevel;


/// A constant value describes volume level is not valid.
extern const uint8_t RTKACVolumeLevelInvalid;

/// Values that represents volume level. Ranges from `0` to `100`.
typedef uint8_t RTKACVolumeLevel;

// MARK: - Language

/// The languages that the remote device used for Voice Prompt.
typedef NSString* RTKACLanguageType;

/// Represent for a language of remote device which set as default.
extern RTKACLanguageType const RTKACLanguageDefault;

/// Represent for English language
extern RTKACLanguageType const RTKACLanguageEnglish;

/// Represent for Chinese language
extern RTKACLanguageType const RTKACLanguageChinese;

/// Represent for French language
extern RTKACLanguageType const RTKACLanguageFrench;

/// Represent for Portuguese language
extern RTKACLanguageType const RTKACLanguagePortuguese;

/// The language is not determined.
/// May be determined after some operation.
extern RTKACLanguageType const RTKACLanguageUnknown;

// MARK: - Chip Type

/// The chip type (SOC platform) of a remote device.
typedef NS_ENUM(NSUInteger, RTKACChip) {
    RTKACChip_unknown     = 0,
    
    RTKACChip_87x3B       = 1,
    RTKACChip_87x3C       = 2,
    RTKACChip_8773B       = 3,
    RTKACChip_87x3D       = 4,
    RTKACChip_87x3E       = 5,
    RTKACChip_87x3EP      = 6,
};

// MARK: - Capabilities

/// Constants that describe features a device may support.
typedef NS_ENUM(NSUInteger, RTKACCapabilityType) {
    RTKACCapabilityType_LENameAccess,        ///< Indicates that access(read and write) LE name of a device is supported.
    RTKACCapabilityType_BREDRNameAccess,     ///< Indicates that access(read and write) BREDR name of a device is supported.
    RTKACCapabilityType_LanguageAccess,      ///< Indicates that access(read and write) language of a device is supported.
    RTKACCapabilityType_BatteryLevelAccess,  ///< Indicates that get battery level of a device is supported.
    RTKACCapabilityType_OTA,                 ///< Indicates that device is able to be upgrade.
    RTKACCapabilityType_ChannelSwitch,

    RTKACCapabilityType_TTS,                 ///< Indicates that Voice Speak for income caller is supported.
    RTKACCapabilityType_RWS,                 ///< Indicates that device is a RWS speakers.
    RTKACCapabilityType_APT,                 ///< Indicates that Audio Pass Through(APT) feature is supported.
    RTKACCapabilityType_EQ,                  ///< Indicates that equalizer feature is supported.
    RTKACCapabilityType_VAD,                 ///< Indicates that VAD feature is supported.
    RTKACCapabilityType_ANC,                 ///< Indicates that ANC feature supported.
    RTKACCapabilityType_LLAPT,               ///< Indicates that LLAPT feature supported.
    RTKACCapabilityType_ListeningModeCycle,  ///< Indicates that switching between multiple listening modes is supported.
    RTKACCapabilityType_LLAPTBrightness,     ///< Indicates that LLAPT Brightness feature is supported.
    RTKACCapabilityType_ANCEQ,               ///< Indicates that ANC equalizer is supported.
    RTKACCapabilityType_APTEQ,               ///< Indicates that APT equalizer is supported.
    RTKACCapabilityType_ringtoneVPAjustment, ///< Indicates that Ringtone Voice Prompt adjusting is supported.
    RTKACCapabilityType_singleAPTAdjustment, ///< Indicates that Ringtone Voice Prompt adjusting for a single bud is supported.
    RTKACCapabilityType_MultiLink,           ///< Indicates that Multi-Link feature is supported.
    RTKACCapabilityType_Durian,              ///< Indicates that device is a Durian complied.
    RTKACCapabilityType_APTNR,               ///< Indicates that APT Noice Reduction is supported.
    RTKACCapabilityType_LLAPTScenario,       ///< Indicates that LLAPT scenario selection is supported.
    RTKACCapabilityType_EarDetection,        ///< Indicates that In Ear Detection is supported.
    RTKACCapabilityType_APTPowerOnDelayTime, ///< Indicates that Delaying APT when power on is supported.
    RTKACCapabilityType_ANCEQConfigure,
    RTKACCapabilityType_GetBudInfo,
    RTKACCapabilityType_ListeningModereport,
    RTKACCapabilityType_APTVolumeRWSSync,

    RTKACCapabilityType_ResetKeyMapping,
    RTKACCapabilityType_ANCS,                ///< Indicates that ANCS is supported.
    RTKACCapabilityType_Vibration,           ///< Indicates that Vibration function is supported.
    RTKACCapabilityType_MFB,                 ///< Indicates that MFB is supported.
    RTKACCapabilityType_GamingMode,          ///< Indicates that Gaming mode is supported.
    RTKACCapabilityType_GamingModeEQ,        ///< Indicates that Equlizer for Gaming mode is supported.
    RTKACCapabilityType_KeyMapping,          ///< Indicates that Customizing MMI Key is supported.
    RTKACCapabilityType_HearingAid,          ///< Indicates that Hearing Aid is supported.
    RTKACCapabilityType_LocalPlayback,       ///< Indicates that Local Playback is supported.
    RTKACCapabilityType_ANCScenarioGroupSetting,
    RTKACCapabilityType_RWSKeyRemap,
    RTKACCapabilityType_EQPersistence,
    RTKACCapabilityType_ResetKeyMapByBud,
    RTKACCapabilityType_DataCaptureV2,
    RTKACCapabilityType_ListeningModeForANCAPT,
    RTKACCapabilityType_SpecialANCScenario,
    RTKACCapabilityType_DSP3BinScenario,
    RTKACCapabilityType_VoiceEQ,
    RTKACCapabilityType_ANCApplyBurn,
    RTKACCapabilityType_EQAdjustSeparately,
    RTKACCapabilityType_EQCompensation,
    RTKACCapabilityType_MCULog,
    RTKACCapabilityType_DisableNormalAPTVolume,
    RTKACCapabilityType_DisableLLAPTVolume,
    RTKACCapabilityType_MICVoiceEQ,
    RTKACCapabilityType_ListeningModeCycle_CustomMode,
    
    RTKACCapabilityType_ChargingCase,
    RTKACCapabilityType_ChargingCaseWallpaperUpdate,
    
    RTKACCapabilityType_SingleModeIndependentVolumeAdjust,
    
    RTKACCapabilityType_WDRCParamsPerHA,
    RTKACCapabilityType_RealEarMeasurement,
    RTKACCapabilityType_ContinuousTone,
};

// MARK: - Bud Info

typedef NS_ENUM(uint8_t, RTKBudType) {
    RTKBudType_SingleOrStereo,
    RTKBudType_RWS,
};

/// The bud side of a device.
typedef NS_ENUM(uint8_t, RTKACBudSide) {
    RTKACBudSide_Unknown,        ///< The bud side is unknown currently.
    RTKACBudSide_L,              ///< The bud is on left side.
    RTKACBudSide_R,              ///< The bud is on right side.
};


/// Constants that describe the stereo channel direction.
typedef NS_ENUM(UInt8, RTKACChannelDirection) {
    RTKACChannelDirection_Unknown,
    RTKACChannelDirection_PrimaryToLeft,    ///<  Left channel flow to Primary bud.
    RTKACChannelDirection_PrimaryToRight,   ///< Right channel flow to Primary bud.
    RTKACChannelDirection_Mix,              ///< Channels are mixed to both bud.
};

typedef NS_ENUM(UInt8, RTKACLRChannel) {
    RTKACLRChannel_LeftToLeft   = 0x12,
    RTKACLRChannel_LeftToRight  = 0x21,
    RTKACLRChannel_Mix          = 0x33,
    RTKACLRChannel_Invalid      = 0xFF,
};

/// A constant that describle a device role.
typedef NS_ENUM(UInt8, RTKACBudRole) {
    RTKACBudRole_Single,             ///< The device is a single device (only in a device pair)
    RTKACBudRole_Primary,            ///< The device is primary bud.
    RTKACBudRole_Secondary,          ///< The device is secondary bud.
    RTKACBudRole_Unknown = 0xFF      ///< The device role is not known currently.
};

// MARK: - MMI

/// The possible action when a MMI event triggered.
///
/// The enumerated constants may not be exhaustive.
typedef NS_ENUM(uint8_t, RTKACMMIAction) {
    AU_MMI_NULL                                                 =   0x00,
    AU_MMI_ADD_REMOVE_SCO                                       =   0x01,
    AU_MMI_FORCE_END_OUTGOING_CALL                              =   0x02,  ///< end call without check sco status
    AU_MMI_ANSWER_CALL                                          =   0x03, ///< answer incoming call
    AU_MMI_REJECT_CALL                                          =   0x04,   ///< reject incoming call
    AU_MMI_END_ACTIVE_CALL                                      =   0x05, ///< add sco if sco doesn't exist, otherwise end call
    AU_MMI_DEV_MIC_MUTE_TOGGLE                                  =   0x06,  ///< mute mic if mic is ON, otherwise unmute mic
    AU_MMI_DEV_MIC_MUTE                                         =   0x07, ///< mute mic
    AU_MMI_DEV_MIC_UNMUTE                                       =   0x08, ///< unmute mic
    AU_MMI_INITIATE_VOICE_DIAL                                  =   0x09,
    AU_MMI_CANCEL_VOICE_DIAL                                    =   0x0A,
    AU_MMI_LAST_NUMBER_REDIAL                                   =   0x0B, ///< dail last number
    AU_MMI_SWITCH_TO_SECOND_CALL                                =   0x0C, ///< hold the active call  and active the hold call
    AU_MMI_TRANSFER_TO_PHONE                                    =   0x0D, ///< when call active, add sco if sco doesn't exist, otherwise remove sco
    AU_MMI_QUERY_CURRENT_CALL_LIST                              =   0x0E, ///< query call list
    AU_MMI_JOIN_TWO_CALLS                                       =   0x0F, ///< 3 way call
    AU_MMI_RELEASE_HELD_OR_WAITING_CALL                         =   0x10,
    AU_MMI_RELEASE_ACTIVE_CALL_ACCEPT_HELD_OR_WAITING_CALL      =   0x11,
    AU_MMI_CONNECT_HF_LINK                                      =   0x12,
    AU_MMI_DISCONNECT_HF_LINK                                   =   0x13,
    AU_MMI_UPDATE_INDICATOR                                     =   0x14,
    MMI_DEV_MIC_VOL_UP                                          =   0x15, ///< mic volume up
    MMI_DEV_MIC_VOL_DOWN                                        =   0x16,    ///< mic volume down
    AU_MMI_HF_VENDOR_CMD_1                                      =   0x20,
    AU_MMI_HF_VENDOR_CMD_2                                      =   0x21,
    
    MMI_TAKE_LIFE_PHOTO                                         =   0x25,
    MMI_START_RECORDING_VIDEO                                   =   0x26,
    MMI_STOP_RECORDING_VIDEO                                    =   0x27,
    
    MMI_START_RECORDING_AUDIO                                   =   0x2C,
    MMI_STOP_RECORDING_AUDIO                                    =   0x2D,
    
    AU_MMI_DEV_SPK_VOL_UP                                       =   0x30,
    AU_MMI_DEV_SPK_VOL_DOWN                                     =   0x31,
    AU_MMI_AV_PLAY_PAUSE                                        =   0x32,
    AU_MMI_AV_STOP                                              =   0x33,
    AU_MMI_AV_FWD                                               =   0x34,
    AU_MMI_AV_BWD                                               =   0x35,
    AU_MMI_AV_FASTFORWARD                                       =   0x36,
    AU_MMI_AV_REWIND                                            =   0x37,
    AU_MMI_AV_EQ_MODE_UP                                        =   0x38,
    AU_MMI_AV_EQ_MODE_DOWN                                      =   0x39,
    AU_MMI_DISCONNECT_AV_LINK                                   =   0x3A,
    AU_MMI_AV_FASTFORWARD_RELEASE                               =   0x3B,
    AU_MMI_AV_REWIND_RELEASE                                    =   0x3C,
    AU_MMI_DEV_SPK_MUTE                                         =   0x3D,
    AU_MMI_DEV_SPK_UNMUTE                                       =   0X3E,
    AU_MMI_DISC_LINK_AND_ENTER_PAIRING_MODE                     =   0x50,
    AU_MMI_DEV_ENTER_PAIRING_MODE                               =   0x51,
    AU_MMI_DEV_EXIT_PAIRING_MODE                                =   0x52,
    AU_MMI_DEV_LINK_LAST_DEVICE                                 =   0x53,
    AU_MMI_DEV_POWER_ON_BUTTON_PRESS                            =   0x54,
    AU_MMI_DEV_POWER_ON_BUTTON_RELEASE                          =   0x55,
    AU_MMI_DEV_POWER_OFF_BUTTON_PRESS                           =   0x56,
    AU_MMI_DEV_POWER_OFF_BUTTON_RELEASE                         =   0x57,
    AU_MMI_DEV_FACTORY_RESET_TO_DEFAULT                         =   0x58,
    AU_MMI_DEV_DISCONNECT_ALL_LINK                              =   0x59,
    AU_MMI_DEV_FACTORY_RESET_BY_SPP                             =   0x5A,
    AU_MMI_DEV_RWS_FACTORY_BY_SPP                               =   0x5B,
    AU_MMI_ENTER_DUT_FROM_SPP                                   =   0x5C,
    AU_MMI_FORCE_ROLE_SWAP                                      =   0x5D,
    AU_MMI_AUDIO_EQ_NEXT                                        =   0x60,
    AU_MMI_AUDIO_EQ_PREVIOUS                                    =   0x61,
    AU_MMI_NFC_DETECT                                           =   0x62,
    AU_MMI_AUDIO_EFFECT_NEXT                                    =   0x63,
    AU_MMI_AUDIO_EFFECT_PREVIOUS                                =   0x64,
    AU_MMI_AUDIO_PASS_THROUGH                                   =   0x65,
    AU_MMI_SWITCH_NEXT_VOICE_PROMPT_LANGUAGE                    =   0x66,
    AU_MMI_OUTPUT_INDICATION_1                                  =   0x67,
    AU_MMI_OUTPUT_INDICATION_2                                  =   0x68,
    AU_MMI_OUTPUT_INDICATION_3                                  =   0x69,
    AU_MMI_MIC_SWITCH                                           =   0x6A,
    AU_MMI_AUDIO_EQ_SWITCH                                      =   0x6B,
    AU_MMI_FORCE_ENTER_PAIR_MODE                                =   0x6C,
    AU_MMI_LED2_SWITCH                                          =   0x6D,
//    AU_MMI_FORCE_ROLE_SWAP                            =   0x6E,
    AU_MMI_APT_EQ_SWITCH_1                                      =   0x6E,
    AU_MMI_RESET_TO_UNINITIAL_STATE_BY_SPP                      =   0x6F,
//    AU_MMI_RWS_PAIRING_MODE                           =   0x70,
    AU_MMI_TAKE_PICTURE                                         =   0x70,
    AU_MMI_RWS_LINKBACK                                         =   0x71,
    AU_MMI_RWS_CANCEL_PAIRING                                   =   0x72,
    AU_MMI_RWS_DISCONNECT                                       =   0x73,
    AU_MMI_RWS_SWITCH_CHANNEL                                   =   0x74,
    AU_MMI_RWS_BUNDLE_PAIRING                                   =   0x75,
    AU_MMI_RWS_RESET_TO_DEFAULT                                 =   0x76,
    AU_MMI_RWS_POWER_OFF                                        =   0x77,
    AU_MMI_RWS_TO_SPK1_EXIT_SNIFF                               =   0x78,
    AU_MMI_RWS_SYNC_RINGTONE                                    =   0x79,
    AU_MMI_ENTER_PAIRING_MODE_LONG_PRESS                        =   0x7A,
    AU_MMI_RWS_SAVE_CFG                                         =   0x7B,
    AU_MMI_RWS_LOAD_CFG                                         =   0x7C,
    AU_MMI_RWS_SYNC_LK_PRI                                      =   0x7D,
    AU_MMI_RWS_SYNC_LK_SEC                                      =   0x7E,
    AU_MMI_RWS_ENGAGED_COUNT                                    =   0x7F,
    AU_MMI_GAMING_MODE_SWITCH                                   =   0x80,
//    AU_MMI_PRI_REQUEST_SPK2_BAT_LEVEL_CHECK           =   0x81,
    AU_MMI_AUDIO_ANC_ON                                         =   0x81,
//    AU_MMI_RWS_ANS_SPEAKER_MUTE                       =   0x82,
    AU_MMI_AUDIO_APT_ON                                         =   0x82,
    AU_MMI_AUDIO_ANC_APT_ALL_OFF                                =   0x83,
    AU_MMI_AUDIO_PASS_THROUGH_NR_SWITCH                         =   0x84,
    AU_MMI_AUDIO_PASS_THROUGH_VOL_UP                            =   0x85,
    AU_MMI_AUDIO_PASS_THROUGH_VOL_DOWN                          =   0x86,
    AU_MMI_TOGGLE_FIND_ME_FEATURE                               =   0x87,
    AU_MMI_AUDIO_VAD_OPEN                                       =   0x87,
    AU_MMI_AUDIO_VAD_CLOSE                                      =   0x88,
    AU_MMI_AUDIO_DUAL_EFFECT_SWITCH                             =   0x89,
    AU_MMI_RBA_CSB_MASTER_PROCESS                               =   0x90,
//    AU_MMI_RBA_CSB_SLAVE_PROCESS                      =   0x91,
    AU_MMI_APT_EQ_SWITCH_2                                      =   0x91,
    AU_MMI_AUDIO_APT_VOL_UP                                     =   0x92,
    AU_MMI_AUDIO_APT_VOL_DOWN                                   =   0x93,
    AU_MMI_AUDIO_APT_VOICE_FOCUS                                =   0x94,
    MMI_AUDIO_APT_DISALLOW_SYNC_VOLUME_TOGGLE                   =   0x95,
    AU_MMI_OTA_OVER_BLE_START                                   =   0xA0,
    AU_MMI_DUT_TEST_MODE                                        =   0xA1,
    AU_MMI_MS_TEAMS_BUTTON                                      =   0xA9,
    AU_MMI_ALEXA_WAKEWORD                                       =   0xB0,
    AU_MMI_XIAOAI_WAKEWORD                                      =   0xB2,
    AU_MMI_SD_PLAYBACK_SWITCH                                   =   0xC0,
    AU_MMI_SD_PLAYPACK_PAUSE                                    =   0xC1,
    AU_MMI_SD_PLAYBACK_FWD                                      =   0xC2,
    AU_MMI_SD_PLAYBACK_BWD                                      =   0xC3,
    AU_MMI_SD_PLAYBACK_FWD_PLAYLIST                             =   0xC4,
    AU_MMI_SD_PLAYBACK_BWD_PLAYLIST                             =   0xC5,
    AU_MMI_ANC_ON_OFF                                           =   0xD0,
    AU_MMI_LISTENING_MODE_CYCLE                                 =   0xD1,
    AU_MMI_ANC_CYCLE                                            =   0xD2,
    AU_MMI_LIGHT_SENSOR_ON_OFF                                  =   0xD3,
    AU_MMI_AIRPLANE_MODE                                        =   0xD4,
    AU_MMI_START_ROLESWAP                                       =   0xF0,
    AU_MMI_ENTER_SINGLE_MODE                                    =   0xF1,
    AU_MMI_AV_PAUSE                                             =   0xF8,
    AU_MMI_AV_RESUME                                            =   0xF9,
};

/// The calling status of the device when a MMI is triggered.
typedef NS_ENUM(uint8_t, RTKACMMIStatus) {
    RTKACMMIStatus_Idle,       ///< The device is idle.
    RTKACMMIStatus_InCall,     ///< The device is in call.
};

/// A constant that describes which motion to trigger a MMI action .
typedef NS_ENUM(uint8_t, RTKACMMIClickType) {
    RTKACMMIClickType_None,
    RTKACMMIClickType_Single = 0x01,       ///< Single click.
    RTKACMMIClickType_Multi2,              ///< Double click.
    RTKACMMIClickType_Multi3,              ///< Triple click.
    RTKACMMIClickType_LongPress,           ///< A long press.
    RTKACMMIClickType_UltraLongPress,      ///< A ultra long press.
};

typedef NS_ENUM(uint8_t, RTKACMMIBudSide) {
    RTKACMMIBudSide_stereo   = 0x00,
    RTKACMMIBudSide_left     = 0x01,
    RTKACMMIBudSide_right    = 0x02,
    RTKACMMIBudSide_both     = 0x03,
} ;

/// A structure that describes condition and motion for trigger a MMI action.
typedef struct {
    RTKACBudSide bud;                 ///< Which bud is used to trigger this MMI.
    RTKACMMIStatus status;           ///< Whether bud is in calling for trigger this MMI.
    RTKACMMIClickType click;         ///< Which motion for trigger this MMI.
    RTKACMMIAction MMI;              ///< The action triggered.
} RTKACMMIMapping;

// MARK: - Audio

typedef NS_ENUM(NSUInteger, RTKACListeningModeSwitchCycle) {
    RTKACListeningModeSwitchCycle_0,     ///< All off -> ANC on -> APT on
    RTKACListeningModeSwitchCycle_1,     ///< All off -> APT on -> ANC on
    RTKACListeningModeSwitchCycle_2,     ///< APT on -> ANC on
    RTKACListeningModeSwitchCycle_3,     ///< All off -> ANC on
    RTKACListeningModeSwitchCycle_4,     ///< OFF -> ANC -> APT -> ANC+APT
    RTKACListeningModeSwitchCycle_5,     ///< Custom Mode
};

// 0x00 all off, 0x01 normal APT, 0x02 ANC, 0x03 LLAPT, 0x04 ANC+Normal APT
typedef NS_ENUM(uint8_t, RTKACListeningModeType) {
    RTKACListeningModeType_AllOFF,
    RTKACListeningModeType_NormalAPT,
    RTKACListeningModeType_ANC,
    RTKACListeningModeType_LLAPT,
    RTKACListeningModeType_ANCAPT,
};

typedef NS_ENUM(uint8_t, RTKACAPTType) {
    RTKACAPTType_NormalAPT,
    RTKACAPTType_LLAPT,
};

/// A series predefined ANC scenario.
typedef enum : uint8_t {
    RTKACANCScenario_none       =   0x00,
    RTKACANCScenario_high       =   0x01,
    RTKACANCScenario_low        =   0x02,
    RTKACANCScenario_family     =   0x03,
    RTKACANCScenario_library    =   0x04,
    RTKACANCScenario_airplane   =   0x05,
    RTKACANCScenario_subway     =   0x06,
    RTKACANCScenario_outdoor    =   0x07,
    RTKACANCScenario_running    =   0x08,
    RTKACANCScenario_linein     =   0x09,
    
    RTKACANCScenario_customer0  =   0x80,
    RTKACANCScenario_customer1,
    RTKACANCScenario_customer2,
    RTKACANCScenario_customer3,
    RTKACANCScenario_customer4,
    RTKACANCScenario_customer5,
    RTKACANCScenario_customer6,
    RTKACANCScenario_customer7  =   0x87,
    
    RTKACANCScenario_MP1,
    RTKACANCScenario_MP2,
    
    RTKACANCScenario_unknown    =   0xff,
    RTKACANCScenario_unselected =   0xfe,
} RTKACANCScenario;

/// The volume type when setting APT Volume.
typedef NS_ENUM(uint8_t, RTKACAPTVolumeType) {
    RTKACAPTVolumeType_Main       = 0x00,        ///< Main
    RTKACAPTVolumeType_Sub        = 0x01,        ///< Sub
} ;

typedef NS_ENUM(uint8_t, RTKACAPTBrightnessType) {
    RTKACAPTBrightnessType_Main       = 0x00,        ///< Main
    RTKACAPTBrightnessType_Sub        = 0x01,        ///< Sub
} ;



// MARK: - EQ

typedef NS_ENUM(NSUInteger, RTKEQFormatVersion) {
    RTKEQFormatVersion_V2      = 0x00,
    RTKEQFormatVersion_V1      = 0x01,
    
    RTKEQFormatVersion_Unknown = 0xFF,
};


typedef NS_ENUM(uint8_t, RTKApplyOrSaveEQ) {
    RTKApplyOrSaveEQ_Apply,
    RTKApplyOrSaveEQ_ApplyAndSave,
    RTKApplyOrSaveEQ_Save,
};

typedef NS_ENUM(uint8_t, RTKEQParametersType) {
    RTKEQParametersType_Final,  //apply to dsp
    RTKEQParametersType_UI,     //sync with phone app
    RTKEQParametersType_Compensation,
};


/// A constant that describles which target the equalizer apply to.
typedef NS_ENUM(uint8_t, RTKACSWEQType) {
    RTKACSPK_SW_EQ,      ///< Apply to speakers.
    RTKACMIC_SW_EQ,      ///< Apply to microphone.
};


/// The mode current used by the remote device.
typedef NS_ENUM(uint8_t, RTKACEQMode) {
    RTKACEQMode_normal      = 0x00,         ///< Normal mode. Audio EQ
    RTKACEQMode_gaming      = 0x01,         ///< Gaming mode. Audio EQ
    RTKACEQMode_anc         = 0x02,         ///< ANC mode. Audio EQ
    RTKACEQMode_linein      = 0x03,         ///< Line-in mode. Audio EQ
    RTKACEQMode_AudioVoice  = 0x04,         ///< Voice mode. Audio EQ
    
    RTKACEQMode_apt         = 0x00,         ///<APT mode. MIC EQ
    RTKACEQMode_MICVoice    = 0x01,         ///< Voice mode. MIC EQ
    RTKACEQMode_record      = 0x02,         ///< Record mode. MIC EQ
    
    RTKACEQMode_unknown     = 0xff
};

/// Constants that represent which bud side to set the new APT EQ effect.
typedef NS_ENUM(uint8_t, RTKACEQBudSide) {
    RTKACEQBudSide_Left,     ///< Apply to Left bud.
    RTKACEQBudSide_Right,    ///< Apply to Right bud.
    RTKACEQBudSide_Both,     ///< Apply to both buds.
};

/// The mode that device is used for Meridian sound effect.
typedef NS_ENUM(uint8_t, RTKACMeridianSoundEffect) {
    RTKACMeridianSoundEffect_Off,    ///< Meridian Sound Effect is off
    RTKACMeridianSoundEffect_Bass,   ///< Using Bass Meridian Sound Effect
    RTKACMeridianSoundEffect_Flat,   ///< Using Flat Meridian Sound Effect
    RTKACMeridianSoundEffect_Treble, ///< Using Treble Meridian Sound Effect.
};


/// A bitmask value indicate the EQ Setting index.
///
/// When used as current EQ Index only one current Index bit set to 1, when usded as supported EQ Indexes, all supported EQ index set to 1.
typedef NS_OPTIONS(uint16_t, RTKACEQIndex) {
    RTKACEQIndexOff         = 1 << 0,
    RTKACEQIndexCustomer1   = 1 << 1,  ///< Bass Boost
    RTKACEQIndexCustomer2   = 1 << 2,  ///< Normal
    RTKACEQIndexCustomer3   = 1 << 3,  ///< Treble
    RTKACEQIndexBuiltin1    = 1 << 4,
    RTKACEQIndexBuiltin2    = 1 << 5,
    RTKACEQIndexBuiltin3    = 1 << 6,
    RTKACEQIndexBuiltin4    = 1 << 7,
    RTKACEQIndexBuiltin5    = 1 << 8,
    RTKACEQIndexRealtime    = 1 << 9,       ///< The EQ can be adjusted in UI
    RTKACEQIndexRealtime2   = 1 << 10,     ///< The EQ can be adjusted in UI
};

// MARK: - Data Capture

typedef NS_ENUM(uint32_t, RTKSBCConfigSamplingFrequency) {
    RTKSBCConfigSamplingFrequency_16K    =   16000,
    RTKSBCConfigSamplingFrequency_32K    =   32000,
    RTKSBCConfigSamplingFrequency_44K1   =   44100,
    RTKSBCConfigSamplingFrequency_48K    =   48000,
};


typedef NS_ENUM(uint8_t, RTKSBCConfigChannelMode) {
    RTKSBCConfigChannelMode_MONO            =   0x00,
    RTKSBCConfigChannelMode_DUAL            =   0x01,
    RTKSBCConfigChannelMode_STEREO          =   0x02,
    RTKSBCConfigChannelMode_JOINT_STEREO    =   0x03,
};

typedef NS_ENUM(uint8_t, RTKSBCConfigBlockLength) {
    RTKSBCConfigBlockLength_4    =   0x00,
    RTKSBCConfigBlockLength_8    =   0x01,
    RTKSBCConfigBlockLength_12  =   0x02,
    RTKSBCConfigBlockLength_16    =   0x03,
};

typedef NS_ENUM(uint8_t, RTKSBCConfigSubBandNumber) {
    RTKSBCConfigSubBandNumber_4    =   0x00,
    RTKSBCConfigSubBandNumber_8    =   0x01,
};

typedef NS_ENUM(uint8_t, RTKSBCConfigAllocationMethod) {
    RTKSBCConfigAllocationMethod_LOUDNESS   =   0x00,
    RTKSBCConfigAllocationMethod_SNR    =   0x01,
};

typedef NS_ENUM(uint8_t, RTKDSPCaptureType) {
    RTKDSPCaptureType_SAIYAN    =   0x00,
    RTKDSPCaptureType_RAW_DATA  =   0x01,
    RTKDSPCaptureType_ENTER_SCO_MODE    =   0x02,
    RTKDSPCaptureType_SCO_MODE_CTL  =   0x03,
    RTKDSPCaptureType_USER_MIC  =   0x04,
    RTKDSPCaptureType_RAW_DATA_DSP2 =   0x05,
};

typedef NS_ENUM(uint8_t, RTKCaptureBandWidth) {
    RTKCaptureBandWidth_1M,
    RTKCaptureBandWidth_2M,
    RTKCaptureBandWidth_3M,
};

typedef NS_ENUM(uint8_t, RTKCodecType) {
    RTKCodecType_SBC,
    RTKCodecType_OPUS,
    RTKCodecType_RAW,
    RTKCodecType_SAIYAN,
    RTKCodecType_RAW_PACK,
    RTKCodecType_CODEC_MAX,
};

typedef NS_ENUM(uint8_t, RTKProbeSource) {
    RTKProbeSource_TX_IN_CH0,
    RTKProbeSource_TX_IN_CH1,
    RTKProbeSource_TX_OUT_CH0,
    RTKProbeSource_TX_OUT_CH1,
    RTKProbeSource_RX_IN_TDM4CH0,
    RTKProbeSource_RX_IN_TDM4CH1,
    RTKProbeSource_RX_IN_TDM4CH2,
    RTKProbeSource_RX_IN_TDM4CH3,
    RTKProbeSource_RX_OUT,
    RTKProbeSource_SAIYAN_MP_CH0,
    RTKProbeSource_SAIYAN_MP_CH1,
    RTKProbeSource_SAIYAN_MP_CH2,
    RTKProbeSource_SAIYAN_MP_CH3,
    RTKProbeSource_RX_IN_TDM6CH0,
    RTKProbeSource_RX_IN_TDM6CH1,
    RTKProbeSource_RX_IN_TDM6CH2,
    RTKProbeSource_RX_IN_TDM6CH3,
    RTKProbeSource_RX_IN_TDM6CH4,
    RTKProbeSource_RX_IN_TDM6CH5,
    // DSP2
    RTKProbeSource_DSP2_TX_IN_CH0,
    RTKProbeSource_DSP2_TX_IN_CH1,
    RTKProbeSource_DSP2_TX_OUT_CH0,
    RTKProbeSource_DSP2_TX_OUT_CH1,
    RTKProbeSource_DSP2_RX_IN_TDM4CH0,
    RTKProbeSource_DSP2_RX_IN_TDM4CH1,
    RTKProbeSource_DSP2_RX_IN_TDM4CH2,
    RTKProbeSource_DSP2_RX_IN_TDM4CH3,
    RTKProbeSource_DSP2_RX_OUT,
    RTKProbeSource_DSP2_RX_IN_TDM6CH0,
    RTKProbeSource_DSP2_RX_IN_TDM6CH1,
    RTKProbeSource_DSP2_RX_IN_TDM6CH2,
    RTKProbeSource_DSP2_RX_IN_TDM6CH3,
    RTKProbeSource_DSP2_RX_IN_TDM6CH4,
    RTKProbeSource_DSP2_RX_IN_TDM6CH5,
    
    RTKProbeSource_DEFAULT_MAX,
    RTKProbeSource_VENDOR_START = 100,
    PROBE_SDK_SOURCE_CH0,
    PROBE_SDK_SOURCE_CH1,
    PROBE_SDK_SOURCE_CH2,
    PROBE_SDK_SOURCE_CH3,
    
    RTKProbeSource_INVALID_SOURCE_INDEX = 0xFF, // maximum source index
};

typedef NS_ENUM(uint8_t, RTKLogicMicType) {
    RTKLogicMicType_FF,
    RTKLogicMicType_FB,
    RTKLogicMicType_Voice,
};

// MARK: -

/// A Bluetooth BREDR Profile.
typedef NS_OPTIONS(uint8_t, RTKACLegacyProfile) {
    RTKACLegacyProfile_A2DP   = 1 << 0,         ///< A2DP profile
    RTKACLegacyProfile_AVRCP  = 1 << 1,         ///< AVRCP profile
    RTKACLegacyProfile_HFHS   = 1 << 2,         ///< HFHS profile
    RTKACLegacyProfile_Vendor = 1 << 3,         ///< Vendor profile
    RTKACLegacyProfile_SPP    = 1 << 4,         ///< SPP profile
    RTKACLegacyProfile_iAP    = 1 << 5,         ///< iAP profile
    RTKACLegacyProfile_PBAP   = 1 << 6,         ///< PBAP profile
};

typedef NS_ENUM(uint8_t, RTKPlayStatus) {
    RTKPlayStatus_Stopped,
    RTKPlayStatus_Playing,
    RTKPlayStatus_Paused,
};
#endif /* RTKACType_h */
