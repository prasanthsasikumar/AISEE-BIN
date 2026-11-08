package com.flowsxr.aiseebin

import android.app.Application
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.flowsxr.aiseebin.usage.SessionHeader
import com.flowsxr.aiseebin.usage.Usage
import com.flowsxr.aiseebin.usage.UsageLog
import com.flowsxr.aiseebin.usage.UsageUploader
import com.flowsxr.aiseebin.usage.current
import com.flowsxr.aiseebin.usage.storedStaff
import com.realsil.sdk.audioconnect.smartwear.SmartWearModelProxy
import com.realsil.sdk.bbpro.BeeProParams
import com.realsil.sdk.bbpro.MultiPeripheralConnectionManager
import com.realsil.sdk.bbpro.core.transportlayer.TransportLayer
import com.realsil.sdk.core.RtkConfigure
import com.realsil.sdk.core.RtkCore
import com.realsil.sdk.core.logger.ZLogger
import java.io.File
import java.util.concurrent.Executors

/** Realtek SDK start-up, as the vendor's SmartWearApplication does it (minus OTA and demo UI). */
class AiseeApp : Application() {
    override fun onCreate() {
        super.onCreate()
        val mainProcess = android.os.Build.VERSION.SDK_INT < 28 || getProcessName() == packageName
        if (mainProcess) startUsageLog()
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

    /** Usage logging starts first so `app.launch` is the session's seq 0. */
    private fun startUsageLog() {
        val executor = Executors.newSingleThreadExecutor { Thread(it, "usage").apply { isDaemon = true } }
        val app = this
        Usage.log = UsageLog(File(filesDir, "usage"), UsageUploader(), System::currentTimeMillis,
            SessionHeader.current(this), executor, staff = { storedStaff(app) })
        Usage.log.onLaunch()
        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) = Usage.log.onForeground()
            override fun onStop(owner: LifecycleOwner) = Usage.log.onBackground()
        })
    }
}
