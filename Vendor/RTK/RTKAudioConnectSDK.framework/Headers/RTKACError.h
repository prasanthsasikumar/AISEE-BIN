//
//  RTKACError.h
//  RTKAudioConnectSDK
//
//  Created by irene_wang on 2026/1/16.
//  Copyright (c) 2026, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <Foundation/Foundation.h>

extern NSErrorDomain const RTKACErrorDomain;

typedef enum : NSUInteger {
    // MARK: - ack errors
    RTKACErrorDeviceRespondsCMDDisallow                 = 1,
    RTKACErrorDeviceRespondsCMDUnknown                  = 2,
    RTKACErrorDeviceRespondsCMDParameterError           = 3,
    RTKACErrorDeviceRespondsCMDBusy                     = 4,
    RTKACErrorDeviceRespondsCMDProcessFail              = 5,
    RTKACErrorDeviceRespondsCMDOneWireExtend            = 6,
    RTKACErrorDeviceRespondsCMDVersionIncompatible      = 7,
    RTKACErrorDeviceRespondsCMDOtherError               = 8,

    // MARK: - SDK Local Errors
    RTKACErrorInvalidParameter                          = 9,

    RTKACErrorUnknown                                   = 17,
    
    RTKACErrorServiceNotSupported                       = 20,
    RTKACErrorGATTServiceMissing                        = 21,
    RTKACErrorOperationAlreadyStarted                   = 22,
    RTKACErrorEQSpecNotSupported                        = 23,
    RTKACErrorNotARequest                               = 24,
    
    RTKACErrorDeviceOperationFailed                     = 25,
    RTKACErrorDeviceRingtoneVolumeUpdateFailed          = 26,
    RTKACErrorDeviceCRCCheckFailed                      = 27,
    
    // MARK: - Data Capture Errors
    RTKACErrorDataCaptureNotSupported                   = 28,
    RTKACErrorDataCaptureLoadScenarioFailed             = 29,
    RTKACErrorDataCaptureExitFailed                     = 30,
    
    // MARK: -
    RTKACErrorTransportNotAvailable                     = 31,
    RTKACErrorInvalidParameters                         = 32,
    RTKACErrorLibAlgorithmFailed                        = 33,
} RTKACErrorCode;
