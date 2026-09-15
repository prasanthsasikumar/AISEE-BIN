//
//  RTKHATypes.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2023/2/24.
//  Copyright (c) 2023, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#ifndef RTKHATypes_h
#define RTKHATypes_h

/// A relative value which represents a volume level.
///
/// Having range of 0..100.
typedef uint8_t HAVolumeLevel;

/// A relative value represents a EQ gain level.
///
/// Having a range of 0...100.
typedef uint8_t HAGainLevel;

/// A relative value represents a  balance level.
///
/// Having range of 0..100.
typedef uint8_t HABalanceType;

/// Type used to represent a gain, specified in DB.
///
/// Havign a range of -20...30.
typedef double HAVolumeGain;

/// Type used to represent a gain, specified in DB.
///
/// Havign a range of -20...60.
typedef double HAEQGain;

/// Represent an audio frequency in Hz.
///
/// Havign a range of 0...12000.
typedef double HAFrequency;

typedef double RTKACHADecibel;

typedef NS_ENUM(NSInteger, RTKACHAEar) {
    RTKACHAEar_left,
    RTKACHAEar_right,
};

@interface RTKACHAPitchThreshold : NSObject
@property (readonly) RTKACHAEar ear;
@property (readonly) HAFrequency freq;
@property (readonly) RTKACHADecibel db;

- (instancetype)initWithEar:(RTKACHAEar)ear frequency:(HAFrequency)freq threshold:(RTKACHADecibel)db;
@end

/// Contants that represent Hearing Aid Noice Reduction mode.
typedef NS_ENUM(uint8_t, RTKHANRMode) {
    RTKHANR_lowLatency      =   0x00,   ///< Low latency
    RTKHANR_neural          =   0x02,   ///< Neural
    RTKHANR_highLatency     =   0x03,   ///< High Latency
};

typedef NS_ENUM(uint8_t, RTKHANRStereoMode) {
    RTKHANRStereoMode_RWS       =   0x00,
    RTKHANRStereoMode_Stereo    =   0x01,
    RTKHANRStereoMode_Auto      =   0x02,
};

typedef NS_ENUM(uint8_t, RTKHANRModel) {
    RTKHANRModel_LowPower           =   0x00,
    RTKHANRModel_HighPerformance    =   0x01,
};

typedef struct {
    int8_t volMaxGain;
    int8_t volMinGain;
    uint8_t balanceGain;
    uint8_t eqChCount;
    uint16_t eqChFreqs[32];
    int8_t eqChMaxGains[32];
    int8_t eqChMinGains[32];
} RTKHAGainConfiguration;

/// Constants that indicates current volume mute state.
typedef NS_ENUM(uint8_t, RTKHAAPTVolumeMuteState) {
    RTKHAAPTVolumeMuteState_unmute      =   0x00,
    RTKHAAPTVolumeMuteState_mute,
    RTKHAAPTVolumeMuteState_invalid,
};

typedef NS_ENUM(uint8_t, RTKHAApplyBud) {
    RTKHAApplyBud_left      =   0x00,
    RTKHAApplyBud_right,
    RTKHAApplyBud_both,
};

typedef struct {
    uint8_t threshold;       ///< Range from 0 to 148
    float slope;             ///< Range from 0.0 to 1.0
    uint16_t attackTime;    ///< Range within {10, 20, 50, 100, 150, 200, 250, 500, 700, 1000} ms
    uint16_t releaseTime;
} RTKHAdbSPLDRCState;

typedef struct {
    uint setCount;
    uint attackTime;    ///< Range within {0, 3, 5, 10, 20, 50, 100, 150, 200, 250, 500, 700, 1000}
    uint releaseTime;
    struct {
        int threshold;  ///< Range from -150 to 0
        float slope;    ///< Range from 0 to 1
    } set0;
    struct {
        int threshold;
        float slope;
    } set1;
} RTKHADRCState;

typedef NS_ENUM(uint8_t, RTKHABeamformingMode) {
    RTKHABeamformingMode_Omni      =   0x00,
    RTKHABeamformingMode_Fixed,
    RTKHABeamformingMode_Adaptive,
};

typedef NS_ENUM(uint8_t, RTKHABeamformingSuppression) {
    RTKHABeamformingSuppression_Off      =   0x00,
    RTKHABeamformingSuppression_Medium,
    RTKHABeamformingSuppression_High,
};

/// The hearing loss severity categories.
typedef NS_ENUM(NSInteger, RTKHAHearingLossSeverity) {
    RTKHAHearingLossSeverity_normal      =   0x00,
    RTKHAHearingLossSeverity_minimal,
    RTKHAHearingLossSeverity_mild,
    RTKHAHearingLossSeverity_moderate,
    RTKHAHearingLossSeverity_severe,
    
    RTKHAHearingLossSeverity_NotConfigured          =   0xFD,   ///< Don't allow set to this value when you set preset index. Use it to remove the preset effect of the specified bud.
    RTKHAHearingLossSeverity_HearingCompensation    =   0xFE,   ///< Special Flag. For hearing compensation
    RTKHAHearingLossSeverity_Invalid                =   0xFF,   ///< Special Flag. If set to this value, the preset param on this bud will be ignored 
};

typedef NS_ENUM(uint8_t, RTKHAEnvironment) {
    RTKHAEnvironment_Quite    =   0x00,
    RTKHAEnvironment_Traffic,
    RTKHAEnvironment_Transportation,
    RTKHAEnvironment_ChatCrowd,
    RTKHAEnvironment_Music,
    RTKHAEnvironment_Others,
};

typedef NS_ENUM(NSInteger, RTKHAPresetMode) {
    RTKHAPresetMode_A2DP         =   0x00,
    RTKHAPresetMode_SCO          =   0x01,
    RTKHAPresetMode_RHA          =   0x02,
};

typedef struct {
    uint8_t  playing_type;     ///< range: 0~5, default: 0
    uint8_t  playing_time;     ///< range: 3~10, default:3
    int8_t   playing_gain;     ///< range: -50~50, default:0
    int8_t   debug_gain;        ///< range: -20~20, default:0
    uint16_t start_frequency;  ///< range: 750~12000, default:750
    uint16_t end_frequency;    ///< range: 750~12000, default:12000
    uint8_t  max_delta_gain;   ///< range: 0~100, default:0
    int8_t   min_delta_gain;   ///< range: -100~0, default:-100
    uint8_t  smooth_len;       ///< range: 0~5, default:1
    uint8_t  margin;            ///< range: 0~100, default:5
    uint8_t  debug_value1;     ///< range: 0~255, default:192
    uint8_t  debug_value2;     ///< range: 0~255, default:192
} RTKHARealEarMeasurementParams;

#endif /* RTKHATypes_h */
