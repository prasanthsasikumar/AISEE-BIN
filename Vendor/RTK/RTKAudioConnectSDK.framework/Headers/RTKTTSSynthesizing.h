//
//  RTKTTSSynthesizing.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2019/1/17.
//  Copyright (c) 2019, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Contants that identify the language a TTS engine will synthesize.
typedef NS_ENUM(NSUInteger, RTKTTSLanguage) {
    RTKTTSLanguageUnknown,  ///< The language is unknown.
    RTKTTSLanguageEnglish,  ///< English
    RTKTTSLanguageChinese,  ///< Chinese
};

/// Constants that identify the sample rate of the TTS audio.
typedef NS_ENUM(NSUInteger, RTKAudioSampleRate) {
    RTKAudioSampleRate_Default  =   0,      ///< Default sample rate
    RTKAudioSampleRate_8K       =   1,      ///< 8k hz
    RTKAudioSampleRate_16K      =   0,      ///< 16K hz
};


/// Methods that an object conforms to provide TTS synthesizing service.
///
/// ``RTKACTTSRoutine`` uses these methods to request service of an `RTKTTSSynthesizing` object.
@protocol RTKTTSSynthesizing <NSObject>

/// Synthesize the speech voice of the provided sentence.
///
/// - Parameter text: The sententce to synthesize speech.
/// - Parameter handler: The block be invoked to tells the sythesizing result.
///
/// - Returns a possitive value which identifies the sentence or  `-1` if synthesizing fails.
- (NSInteger)synthesizeSentence:(NSString *)text withCompletionHandler:(void(^)(BOOL success, NSError *_Nullable error, NSData *_Nullable pcmSpeechData))handler;

/// Cancel an on-going sythesizing task.
///
/// - Parameter sentenceToken: A token value which is returned by  `synthesizeSentence:withCompletionHandler`.
- (void)cancelSynthesizing:(NSInteger)sentenceToken;

@end

NS_ASSUME_NONNULL_END
