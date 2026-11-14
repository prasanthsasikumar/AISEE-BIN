package com.flowsxr.aiseebin.nus

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
import java.io.File
import java.util.concurrent.Executors

/** NUS Computing Tour. No glasses, so none of the Realtek start-up AISEE-BIN does: only the usage log. */
class NusApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // First, so `app.launch` is the session's seq 0.
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
