//
//  RTKBBproEQSetting.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2019/2/25.
//  Copyright (c) 2019, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <Foundation/Foundation.h>

#ifdef ATAudioConnectSDK
#import <ATAudioConnectSDK/RTKACEQSetting.h>
#import <ATAudioConnectSDK/RTKMacros.h>
#elif defined(RTKWaveLiteSDK)
#import <RTKWaveLiteSDK/RTKACEQSetting.h>
#import <RTKWaveLiteSDK/RTKMacros.h>
#else
#import <RTKAudioConnectSDK/RTKACEQSetting.h>
#import <RTKAudioConnectSDK/RTKMacros.h>
#endif

NS_ASSUME_NONNULL_BEGIN

/// The possible Sample Rate related to audio signal
typedef NS_ENUM(NSUInteger, RTKBBproSampleRate) {
    RTKBBproSampleRate_8K       RTK_REDIRECT(RTKEQSampleRate_8K)        = RTKEQSampleRate_8K,
    RTKBBproSampleRate_16K      RTK_REDIRECT(RTKEQSampleRate_16K)       = RTKEQSampleRate_16K,
    RTKBBproSampleRate_32K      RTK_REDIRECT(RTKEQSampleRate_32K)       = RTKEQSampleRate_32K,
    RTKBBproSampleRate_44K1     RTK_REDIRECT(RTKEQSampleRate_44K1)      = RTKEQSampleRate_44K1,
    RTKBBproSampleRate_48K      RTK_REDIRECT(RTKEQSampleRate_48K)       = RTKEQSampleRate_48K,
    RTKBBproSampleRate_88K2     RTK_REDIRECT(RTKEQSampleRate_88K2)      = RTKEQSampleRate_88K2,
    RTKBBproSampleRate_96K      RTK_REDIRECT(RTKEQSampleRate_96K)       = RTKEQSampleRate_96K,
    RTKBBproSampleRate_192K     RTK_REDIRECT(RTKEQSampleRate_192K)      = RTKEQSampleRate_192K,
    RTKBBproSampleRate_unknown  RTK_REDIRECT(RTKEQSampleRate_unknown)   = RTKEQSampleRate_unknown,
} RTK_REDIRECT(RTKEQSampleRate);


/// The possbile Filter type for EQ effect
typedef NS_ENUM(NSUInteger, RTKBBproEQFilter) {
    RTKBBproEQFilter_PEAK           RTK_REDIRECT(RTKEQFilter_PEAK)          = RTKEQFilter_PEAK,
    RTKBBproEQFilter_ShelvingLP     RTK_REDIRECT(RTKEQFilter_ShelvingLP)    = RTKEQFilter_ShelvingLP,
    RTKBBproEQFilter_ShelvingHP     RTK_REDIRECT(RTKEQFilter_ShelvingHP)    = RTKEQFilter_ShelvingHP,
    RTKBBproEQFilter_LowPass        RTK_REDIRECT(RTKEQFilter_LowPass)       = RTKEQFilter_LowPass,
    RTKBBproEQFilter_HighPass       RTK_REDIRECT(RTKEQFilter_HighPass)      = RTKEQFilter_HighPass,
    RTKBBproEQFilter_PEAKCOOKBOOK   RTK_REDIRECT(RTKEQFilter_PEAKCOOKBOOK)  = RTKEQFilter_PEAKCOOKBOOK,
    RTKBBproEQFilter_BandPass       RTK_REDIRECT(RTKEQFilter_BandPass)      = RTKEQFilter_BandPass,
    RTKBBproEQFilter_BandReject     RTK_REDIRECT(RTKEQFilter_BandReject)    = RTKEQFilter_BandReject,
    RTKBBproEQFilter_AllPass        RTK_REDIRECT(RTKEQFilter_AllPass)       = RTKEQFilter_AllPass,
    RTKBBproEQFilter_AllEQ          RTK_REDIRECT(RTKEQFilter_AllEQ)         = RTKEQFilter_AllEQ,
} RTK_REDIRECT(RTKEQFilter);


/// An `RTKBBproEQSetting` object describe parameters of a EQ entry used or to be used on a remote RTKBBproPeripheral device.
///
/// An `RTKBBproSetting` is created with zero parameters, which means that all attribute (i.e globalGain, stage frequency gains,stage Q) value is 0. To represet eq settings of a device, the eq para data should be retrieved and pass to -updateSettingWithParameterData:ofSampleRate:. When set eq effect of a remote device, send data returned by -parameterDataOfSampleRate: to a device.
RTK_REDIRECT(RTKACEQSetting)
@interface RTKBBproEQSetting: RTKACEQSetting

@end

@interface RTKACEQSetting (Deprecated)

// synonymous with -serializedDataAt44P1KFrequency
- (NSData *)serializedData  RTK_REDIRECT(-parameterDataOfSampleRate:);
- (NSData *)serializedDataAt44P1KFrequency  RTK_REDIRECT(-parameterDataOfSampleRate:);
- (NSData *)serializedDataAt48KFrequency    RTK_REDIRECT(-parameterDataOfSampleRate:);
- (NSData *)serializedDataAt96KFrequency    RTK_REDIRECT(-parameterDataOfSampleRate:);


- (void)updateSettingWithParameterData:(NSData *)parameterData  RTK_REDIRECT(-updateSettingWithParameterData:ofSampleRate:);

- (void)updateSettingWithParameterExtraInfoData:(NSData *)data  RTK_REDIRECT(-updateSettingWithParameterExtraInfoData:ofSampleRate:);

- (void)updateSettingWithNewParameterExtraInfoData:(NSData *)data   RTK_REDIRECT(-updateSettingWithNewParameterExtraInfoData:ofSampleRate:);

// MARK: -

- (RTKBBproEQFilter)filterAtIndexLegacy:(NSUInteger)idx
    RTK_REDIRECT('filterAtIndex:' with 'RTKEQFilter')
    NS_SWIFT_NAME(filterAtIndex(_:));

- (void)setFilterLegacy:(RTKBBproEQFilter)filter atIndex:(NSUInteger)idx
    RTK_REDIRECT('setFilter:atIndex:' with 'RTKEQFilter')
    NS_SWIFT_NAME(setFilter(_:atIndex:));

- (NSData *)parameterDataOfSampleRateLegacy:(RTKBBproSampleRate)sampleRate
    RTK_REDIRECT('parameterDataOfSampleRate:' with 'RTKEQSampleRate')
    NS_SWIFT_NAME(parameterDataOfSampleRate(_:));

- (NSData *)parameterDataWithExtraInfoOfSampleRateLegacy:(RTKBBproSampleRate)sampleRate
    RTK_REDIRECT('parameterDataWithExtraInfoOfSampleRate:' with 'RTKEQSampleRate')
    NS_SWIFT_NAME(parameterDataWithExtraInfoOfSampleRate(_:));

- (NSData *)parameterDataWithNewExtraInfoDataAttachedOfSampleRateLegacy:(RTKBBproSampleRate)sampleRate
    RTK_REDIRECT('parameterDataWithNewExtraInfoDataAttachedOfSampleRate:' with 'RTKEQSampleRate')
    NS_SWIFT_NAME(parameterDataWithNewExtraInfoDataAttachedOfSampleRate(_:));

- (NSData *)parameterInfoOfSampleRateLegacy:(RTKBBproSampleRate)sampleRate
    RTK_REDIRECT('parameterInfoOfSampleRate:' with 'RTKEQSampleRate')
    NS_SWIFT_NAME(parameterInfoOfSampleRate(_:));

- (void)updateSettingWithParameterData:(NSData *)parameterData
                    ofSampleRateLegacy:(RTKBBproSampleRate)sampleRate
    RTK_REDIRECT('updateSettingWithParameterData:ofSampleRate:' with 'RTKEQSampleRate')
    NS_SWIFT_NAME(updateSetting(withParameterData:ofSampleRate:));

- (void)updateSettingWithParameterExtraInfoData:(NSData *)data
                             ofSampleRateLegacy:(RTKBBproSampleRate)sampleRate
    RTK_REDIRECT('updateSettingWithParameterExtraInfoData:ofSampleRate:' with 'RTKEQSampleRate')
    NS_SWIFT_NAME(updateSetting(withParameterExtraInfoData:ofSampleRate:));

- (void)updateSettingWithNewParameterExtraInfoData:(NSData *)data
                                ofSampleRateLegacy:(RTKBBproSampleRate)sampleRate
    RTK_REDIRECT('updateSettingWithNewParameterExtraInfoData:ofSampleRate:' with 'RTKEQSampleRate')
    NS_SWIFT_NAME(updateSetting(withNewParameterExtraInfoData:ofSampleRate:));

@end



NS_ASSUME_NONNULL_END
