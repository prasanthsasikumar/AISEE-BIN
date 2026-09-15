//
//  RTKBBproError.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2019/1/23.
//  Copyright (c) 2019, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <Foundation/Foundation.h>
#ifdef ATAudioConnectSDK
#import <ATAudioConnectSDK/RTKACError.h>
#import <ATAudioConnectSDK/RTKMacros.h>
#elif defined(RTKWaveLiteSDK)
#import <RTKWaveLiteSDK/RTKACError.h>
#import <RTKWaveLiteSDK/RTKMacros.h>
#else
#import <RTKAudioConnectSDK/RTKACError.h>
#import <RTKAudioConnectSDK/RTKMacros.h>
#endif

extern NSErrorDomain const RTKBBproErrorDomain RTK_REDIRECT(RTKACErrorDomain);

typedef RTKACErrorCode RTKBBproErrorCode RTK_REDIRECT(RTKACErrorCode);

// MARK: - 1. Mapped Errors
// =================================================================

// --- Device Response Errors (Values 1-8) ---

static const RTKACErrorCode RTKBBproErrorCMDDisallow RTK_REDIRECT(RTKACErrorDeviceRespondsCMDDisallow)
    = RTKACErrorDeviceRespondsCMDDisallow;

static const RTKACErrorCode RTKBBproErrorCMDUnknown RTK_REDIRECT(RTKACErrorDeviceRespondsCMDUnknown)
    = RTKACErrorDeviceRespondsCMDUnknown;

static const RTKACErrorCode RTKBBproErrorCMDParameterError RTK_REDIRECT(RTKACErrorDeviceRespondsCMDParameterError)
    = RTKACErrorDeviceRespondsCMDParameterError;

static const RTKACErrorCode RTKBBproErrorCMDSOCBusy RTK_REDIRECT(RTKACErrorDeviceRespondsCMDBusy)
    = RTKACErrorDeviceRespondsCMDBusy;

static const RTKACErrorCode RTKBBproErrorCMDProcessFail RTK_REDIRECT(RTKACErrorDeviceRespondsCMDProcessFail)
    = RTKACErrorDeviceRespondsCMDProcessFail;

static const RTKACErrorCode RTKBBproErrorCMDOneWireExtend RTK_REDIRECT(RTKACErrorDeviceRespondsCMDOneWireExtend)
    = RTKACErrorDeviceRespondsCMDOneWireExtend;

static const RTKACErrorCode RTKBBproErrorCMDVersionIncompatible RTK_REDIRECT(RTKACErrorDeviceRespondsCMDVersionIncompatible)
    = RTKACErrorDeviceRespondsCMDVersionIncompatible;

static const RTKACErrorCode RTKBBproErrorCMDOthers RTK_REDIRECT(RTKACErrorDeviceRespondsCMDOtherError)
    = RTKACErrorDeviceRespondsCMDOtherError;

static const RTKACErrorCode RTKBBproErrorDeviceRespondsCMDDisallow RTK_REDIRECT(RTKACErrorDeviceRespondsCMDDisallow)
    = RTKACErrorDeviceRespondsCMDDisallow;

static const RTKACErrorCode RTKBBproErrorDeviceRespondsCMDUnknown RTK_REDIRECT(RTKACErrorDeviceRespondsCMDUnknown)
    = RTKACErrorDeviceRespondsCMDUnknown;

static const RTKACErrorCode RTKBBproErrorDeviceRespondsCMDParameterError RTK_REDIRECT(RTKACErrorDeviceRespondsCMDParameterError)
    = RTKACErrorDeviceRespondsCMDParameterError;

static const RTKACErrorCode RTKBBproErrorDeviceRespondsBusy RTK_REDIRECT(RTKACErrorDeviceRespondsCMDBusy)
    = RTKACErrorDeviceRespondsCMDBusy;

static const RTKACErrorCode RTKBBproErrorDeviceRespondsOtherError RTK_REDIRECT(RTKACErrorDeviceRespondsCMDOtherError)
    = RTKACErrorDeviceRespondsCMDOtherError;


// --- Local & Service Errors ---

static const RTKACErrorCode RTKBBproErrorParameterInvalid RTK_REDIRECT(RTKACErrorInvalidParameter)
    = RTKACErrorInvalidParameter; // 9

static const RTKACErrorCode RTKBBproError_unkownReason RTK_REDIRECT(RTKACErrorUnknown)
    = RTKACErrorUnknown; // 17

static const RTKACErrorCode RTKBBproErrorNotSupport RTK_REDIRECT(RTKACErrorServiceNotSupported)
    = RTKACErrorServiceNotSupported; // 20

static const RTKACErrorCode RTKBBproErrorGATTServiceConformance RTK_REDIRECT(RTKACErrorGATTServiceMissing)
    = RTKACErrorGATTServiceMissing; // 21

static const RTKACErrorCode RTKBBproErrorOperationAlreadyStarted RTK_REDIRECT(RTKACErrorOperationAlreadyStarted)
    = RTKACErrorOperationAlreadyStarted; // 22

static const RTKACErrorCode RTKBBproErrorDeviceNotSupport RTK_REDIRECT(RTKACErrorEQSpecNotSupported)
    = RTKACErrorEQSpecNotSupported; // 23

static const RTKACErrorCode RTKBBproErrorNotARequest RTK_REDIRECT(RTKACErrorNotARequest)
    = RTKACErrorNotARequest; // 24

static const RTKACErrorCode RTKBBproErrorDeviceRespondsOperationFail RTK_REDIRECT(RTKACErrorDeviceOperationFailed)
    = RTKACErrorDeviceOperationFailed; // 25

static const RTKACErrorCode RTKBBproErrorDeviceUpdateVPRingtoneVolumeFail RTK_REDIRECT(RTKACErrorDeviceRingtoneVolumeUpdateFailed)
    = RTKACErrorDeviceRingtoneVolumeUpdateFailed; // 26

static const RTKACErrorCode RTKBBproErrorCRCCheckFail RTK_REDIRECT(RTKACErrorDeviceCRCCheckFailed)
    = RTKACErrorDeviceCRCCheckFailed; // 27

// --- Data Capture Errors ---

static const RTKACErrorCode RTKBBproErrorDeviceNotSupportDataCapture RTK_REDIRECT(RTKACErrorDataCaptureNotSupported)
    = RTKACErrorDataCaptureNotSupported; // 28

static const RTKACErrorCode RTKBBproErrorDeviceLoadDataCaptureScenarioFail RTK_REDIRECT(RTKACErrorDataCaptureLoadScenarioFailed)
    = RTKACErrorDataCaptureLoadScenarioFailed; // 29

static const RTKACErrorCode RTKBBproErrorDeviceExitDataCaptureFail RTK_REDIRECT(RTKACErrorDataCaptureExitFailed)
    = RTKACErrorDataCaptureExitFailed; // 30

static const RTKACErrorCode RTKBBproErrorTransportNotAvailable RTK_REDIRECT(RTKACErrorTransportNotAvailable)
    = RTKACErrorTransportNotAvailable; // 31


// MARK: - 2. Removed / Legacy Errors

// =================================================================

static const RTKACErrorCode RTKBBproErrorSOCNotSupport DEPRECATED_MSG_ATTRIBUTE("This error is removed in new SDK.")
    = (RTKACErrorCode)10;

static const RTKACErrorCode RTKBBproErrorTTSInstantiation DEPRECATED_MSG_ATTRIBUTE("TTS feature is removed in new SDK.")
    = (RTKACErrorCode)11;

static const RTKACErrorCode RTKBBproErrorMessageSendFail DEPRECATED_MSG_ATTRIBUTE("This error is removed in new SDK.")
    = (RTKACErrorCode)12;

static const RTKACErrorCode RTKBBproErrorTTSSynthesizeFail DEPRECATED_MSG_ATTRIBUTE("TTS feature is removed in new SDK.")
    = (RTKACErrorCode)13;

static const RTKACErrorCode RTKBBproErrorEQParameterWaitTimeout DEPRECATED_MSG_ATTRIBUTE("This error is removed in new SDK.")
    = (RTKACErrorCode)14;

static const RTKACErrorCode RTKBBproErrorPreviousNotFinished DEPRECATED_MSG_ATTRIBUTE("This error is removed in new SDK.")
    = (RTKACErrorCode)15;

static const RTKACErrorCode RTKBBproError_prepareFailed DEPRECATED_MSG_ATTRIBUTE("This error is removed in new SDK.")
    = (RTKACErrorCode)16;

static const RTKACErrorCode RTKBBproErrorDeviceOperateFail DEPRECATED_MSG_ATTRIBUTE("This error is removed in new SDK.")
    = (RTKACErrorCode)18;

static const RTKACErrorCode RTKBBproError_deviceReportFailure DEPRECATED_MSG_ATTRIBUTE("This error is removed in new SDK.")
    = (RTKACErrorCode)19;

