//
//  RTKContactsAccess.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2019/1/18.
//  Copyright (c) 2019, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Methods you can use to request Contacts authorization and search the name of a contact.
///
/// Include `NSContactsUsageDescription` in app Info.plist file, or your app could crash if you use these methods.
@interface RTKContactsAccess : NSObject

/// Request Contacts access authorization.
+ (void)requestAuthorizationIfPossible;


/// Search the name of a contact which matches a provided number.
///
/// - Parameter number: The number to match.
/// - Parameter handler: The block to be called when a contact is found.
/// - Returns `YES` if a matching contact is found, or `NO` if not.
///
/// `NSContactsUsageDescription` should be included in your app Info.plist, or your app crashes if you call this method. If the user doesn't grand your app to access Contacts data, the searching fails always.
+ (BOOL)searchContactNameMatchCallerNumber:(NSString *)number foundHandler:(void(^)(NSString *_Nullable))handler;

@end

NS_ASSUME_NONNULL_END
