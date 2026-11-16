package com.nfclinkcard.nlctoolkit

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.reactivex.exceptions.UndeliverableException
import io.reactivex.plugins.RxJavaPlugins
import com.polidea.rxandroidble2.exceptions.BleException

import android.os.Bundle

class MainActivity: FlutterActivity() {
    private var phoneNfc: PhoneNfcManager? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        RxJavaPlugins.setErrorHandler { throwable ->
            if (throwable is UndeliverableException && throwable.cause is BleException) {
                return@setErrorHandler // ignore BleExceptions since we do not have subscriber
            } else {
                throw throwable
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val manager = PhoneNfcManager(this)
        phoneNfc = manager
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PhoneNfcManager.CHANNEL
        ).setMethodCallHandler(manager)
    }

    override fun onDestroy() {
        phoneNfc?.dispose()
        phoneNfc = null
        super.onDestroy()
    }
}
