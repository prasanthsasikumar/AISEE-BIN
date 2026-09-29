package com.flowsxr.aiseebin

import android.app.Application
import com.realsil.sdk.audioconnect.smartwear.SmartWearModelProxy
import com.realsil.sdk.bbpro.BeeProParams
import com.realsil.sdk.bbpro.MultiPeripheralConnectionManager
import com.realsil.sdk.bbpro.core.transportlayer.TransportLayer
import com.realsil.sdk.core.RtkConfigure
import com.realsil.sdk.core.RtkCore
import com.realsil.sdk.core.logger.ZLogger

/** Realtek SDK start-up, as the vendor's SmartWearApplication does it (minus OTA and demo UI). */
class AiseeApp : Application() {
    override fun onCreate() {
        super.onCreate()
        RtkCore.initialize(
            this,
            RtkConfigure.Builder()
                .debugEnabled(BuildConfig.DEBUG)
                .printLog(true)
                .globalLogLevel(ZLogger.INFO)
                .logTag("SmartWear")
                .devModeEnabled(false)
                .build(),
        )
        val mainProcess = android.os.Build.VERSION.SDK_INT < 28 || getProcessName() == packageName
        if (mainProcess) {
            MultiPeripheralConnectionManager.getInstance(this).initialize(
                BeeProParams.Builder()
                    .syncDataWhenConnected(true)
                    .connectA2dp(true)
                    .listenHfp(true)
                    .build(),
            )
            SmartWearModelProxy.initialize(this)
        }
        // Vendor note: transport debug logging slows image and voice transfer.
        TransportLayer.TDBG = false
    }
}
