//
//  RTKACFilterInfo.h
//  RTKAudioConnectSDK
//
//  Created by irene_wang on 2023/4/18.
//  Copyright (c) 2023, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <Foundation/Foundation.h>
#import <RTKLEFoundation/RTKLEFoundation.h>

NS_ASSUME_NONNULL_BEGIN

//The possible filter type in ANC/LLAPT filter parameters.
typedef NS_ENUM(NSUInteger, RTKACFilterType) {
    RTKACFilterType_FF_LEFT     = 0,
    RTKACFilterType_FF_RIGHT    = 1,
    RTKACFilterType_FB_LEFT     = 2,
    RTKACFilterType_FB_RIGHT    = 3,
    RTKACFilterType_SZ_LEFT     = 6,
    RTKACFilterType_SZ_RIGHT    = 7,
    RTKACFilterType_APT_LEFT    = 8,
    RTKACFilterType_APT_RIGHT   = 9,
    RTKACFilterType_EQ0_LEFT    = 10,
    RTKACFilterType_EQ0_RIGHT   = 11,
    RTKACFilterType_EQ1_LEFT    = 12,
    RTKACFilterType_EQ1_RIGHT   = 13,
};

@interface RTKACFilterInfo : NSObject

//The spec version of the filter parameters.
@property NSUInteger specVersion;

//The number of the scenario group.
@property NSUInteger groupNum;

//The number of the ANC scenario group.
@property NSUInteger ANCGroupNum;

//The number of the LLAPT scenario group.
@property NSUInteger LLAPTGroupNum;

//The index array of ANC scenarios.
@property NSMutableArray *ANCGroupIndex;

//The index array of LLAPT scenarios.
@property NSMutableArray *LLAPTGroupIndex;

//The filter type information of ANC scenarios. The key is ANC group index. The value is ANC filter type array.
@property NSMutableDictionary *ANCFilterTypeDictionary;

//The filter type information of LLAPT scenarios. The key is LLAPT group index. The value is LLAPT filter type array.
@property NSMutableDictionary *LLAPTFilterTypeDictionary;

//The stage information of ANC scenarios with the specified groupIndex and filterType. The key could be available by -[RTKACFilterInfo getKeyofStageInfoDicMapToTypeDicOf:type:mode:]. The value is stage information array ({stageStartIndex0, stageStartIndex1, stageStartIndex2...}). The count of the array means how many stages could be modified.
@property NSMutableDictionary *ANCFilterStageInfoDictionary;

//The stage information of LLAPT scenarios with the specified groupIndex and filterType. The key could be available by -[RTKACFilterInfo getKeyofStageInfoDicMapToTypeDicOf:type:mode:]. The value is stage information array ({stageStartIndex0, stageStartIndex1, stageStartIndex2...}). The count of the array means how many stages could be modified.
@property NSMutableDictionary *LLAPTFilterStageInfoDictionary;

/**
 * Return the key of ANCFilterStageInfoDictionary/LLAPTFilterStageInfoDictionary.
 * @param index Specify the group index. (The range of the value is in ANCGroupIndex/LLAPTGroupIndex)
 * @param type Specify the filter type. (The range of the value is in ANCFilterTypeDictionary/LLAPTFilterTypeDictionary)
 * @param mode 0x00:ANC 0x01:LLAPT.
 */
- (NSNumber*)getKeyofStageInfoDicMapToTypeDicOf:(NSUInteger)index type:(NSUInteger)type mode:(NSUInteger)mode;

/**
 * Parse the parameterData .
 * @param data The raw para data received from remote device.
 */
- (void)parseFilterData:(NSData *)data;


@end

NS_ASSUME_NONNULL_END
