//
//  RTKACCapturedDataParser.h
//  RTKAudioConnectSDK
//
//  Created by irene_wang on 2023/5/23.
//  Copyright (c) 2023, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <Foundation/Foundation.h>
#import <RTKLEFoundation/RTKLEFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTKACCapturedDataParser : NSObject

//Return PCM data parsed from SBC data
- (NSData*)convertSBCDataToPCMData:(NSData *)sbcData ofChannel:(NSUInteger)channelNum;

@end

NS_ASSUME_NONNULL_END
