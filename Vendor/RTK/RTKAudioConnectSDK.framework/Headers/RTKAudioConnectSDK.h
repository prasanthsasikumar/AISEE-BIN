//
//  RTKAudioConnectSDK.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2019/1/23.
//  Copyright (c) 2019, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <UIKit/UIKit.h>

//! Project version number for RTKAudioConnectSDK.
FOUNDATION_EXPORT double RTKAudioConnectSDKVersionNumber;

//! Project version string for RTKAudioConnectSDK.
FOUNDATION_EXPORT const unsigned char RTKAudioConnectSDKVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <RTKAudioConnectSDK/PublicHeader.h>

#import <RTKAudioConnectSDK/RTKMacros.h>
#import <RTKAudioConnectSDK/RTKACServiceIdentifier.h>
#import <RTKAudioConnectSDK/RTKANCSNotificationEvent.h>
#import <RTKAudioConnectSDK/RTKANCSNotificationAttribute.h>

#import <RTKAudioConnectSDK/RTKACRoutine.h>
#import <RTKAudioConnectSDK/RTKACBasicRoutine.h>
#import <RTKAudioConnectSDK/RTKACAudioRoutine.h>
#import <RTKAudioConnectSDK/RTKACEQRoutine.h>
#import <RTKAudioConnectSDK/RTKACMMIRoutine.h>
#import <RTKAudioConnectSDK/RTKACTTSRoutine.h>
#import <RTKAudioConnectSDK/RTKACRHARoutine.h>
#import <RTKAudioConnectSDK/RTKACRHARoutine+Additional.h>
#import <RTKAudioConnectSDK/RTKHATypes.h>
#import <RTKAudioConnectSDK/RTKHAWdrc2Param.h>

#import <RTKAudioConnectSDK/RTKACConnectionUponGATT.h>
#import <RTKAudioConnectSDK/RTKACConnectionUponiAP.h>
#import <RTKAudioConnectSDK/RTKACMessageTransport.h>
#import <RTKAudioConnectSDK/RTKACRequestTransport.h>

#import <RTKAudioConnectSDK/RTKACConnectionManager.h>

#import <RTKAudioConnectSDK/RTKContactsAccess.h>

#import <RTKAudioConnectSDK/RTKACBeaconMonitor.h>

#import <RTKAudioConnectSDK/RHAPayloadGenerator.h>

#import <RTKAudioConnectSDK/RTKHAUtility.h>

#import <RTKAudioConnectSDK/RTKACFilterInfo.h>
#import <RTKAudioConnectSDK/RTKACCapturedDataParser.h>


#import <RTKAudioConnectSDK/RTKACEQSetting.h>
#import <RTKAudioConnectSDK/RTKACEQSettingPlaceholder.h>
#import <RTKAudioConnectSDK/RTKACError.h>
#import <RTKAudioConnectSDK/RTKACType.h>

// Legacy APIs
// Only for compatibility, not recommend for new usage.
#import <RTKAudioConnectSDK/RTKBBproEQSetting.h>
#import <RTKAudioConnectSDK/RTKBBproEQSettingPlaceholder.h>
#import <RTKAudioConnectSDK/RTKBBproError.h>
#import <RTKAudioConnectSDK/RTKBBproType.h>
#import <RTKAudioConnectSDK/RTKACEQRoutine+Deprecated.h>
