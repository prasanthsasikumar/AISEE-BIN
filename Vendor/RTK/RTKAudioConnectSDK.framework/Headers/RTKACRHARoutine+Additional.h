//
//  RTKACRHARoutine+Additional.h
//  RTKAudioConnectSDK
//
//  Created by irene_wang on 2025/4/2.
//  Copyright (c) 2025, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#ifndef RTKACRHARoutine_Additional_h
#define RTKACRHARoutine_Additional_h

@interface RTKACRHARoutine(Additional)

#pragma mark - Real Natural Sound
/// Set the Real Natural Sound enable state of the connected device.
- (void)setRNSEnable:(BOOL)enabled withCompletionHandler:(nullable RTKLECompletionBlock)handler;

/// Returns a number object that indicates solved WNR enable status.
@property (nullable, readonly) NSNumber *RNSEnabled;

@end

#endif /* RTKACRHARoutine_Additional_h */
