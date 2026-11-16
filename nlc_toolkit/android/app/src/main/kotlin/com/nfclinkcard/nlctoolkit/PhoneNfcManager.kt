package com.nfclinkcard.nlctoolkit

import android.app.Activity
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.IsoDep
import android.nfc.tech.MifareClassic
import android.nfc.tech.MifareUltralight
import android.nfc.tech.NfcA
import android.os.Handler
import android.os.HandlerThread
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Lecture/écriture NFC avec la puce du téléphone (mode « natif »), exposée à Flutter
 * par un MethodChannel. Volontairement proche des commandes du ChameleonUltra : scan,
 * authentification/lecture/écriture MIFARE Classic, et échange brut ISO14443-A (NfcA)
 * pour les tags Ultralight/NTAG. La puce du téléphone ne sait pas casser une clé
 * inconnue ni lire le 125 kHz : ces cas échouent simplement, sans bloquer.
 *
 * Toutes les entrées/sorties sur le tag se font sur un thread dédié (jamais le thread UI),
 * et les réponses repartent sur le thread UI, comme l'exige MethodChannel.
 */
class PhoneNfcManager(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "nlc/phone_nfc"
    }

    private val adapter: NfcAdapter? = NfcAdapter.getDefaultAdapter(activity)

    @Volatile
    private var currentTag: Tag? = null

    // Technologie actuellement connectée au tag. Une seule à la fois.
    private var mifareClassic: MifareClassic? = null
    private var nfcA: NfcA? = null

    private val ioThread = HandlerThread("nlc-nfc-io").apply { start() }
    private val ioHandler = Handler(ioThread.looper)
    private val mainHandler = Handler(activity.mainLooper)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        // Réponses synchrones (pas d'I/O tag) : traitées directement.
        when (call.method) {
            "isAvailable" -> {
                result.success(adapter != null && adapter.isEnabled)
                return
            }
            "start" -> {
                startReader()
                result.success(null)
                return
            }
            "stop" -> {
                stopReader()
                result.success(null)
                return
            }
        }

        // Le reste touche au tag : exécution sur le thread d'I/O.
        ioHandler.post {
            try {
                val value = handleTagCall(call)
                reply(result) { it.success(value) }
            } catch (e: Throwable) {
                reply(result) { it.error("nfc_error", e.message, null) }
            }
        }
    }

    private fun reply(result: MethodChannel.Result, block: (MethodChannel.Result) -> Unit) {
        mainHandler.post { block(result) }
    }

    private fun startReader() {
        val nfc = adapter ?: return
        val flags = NfcAdapter.FLAG_READER_NFC_A or
            NfcAdapter.FLAG_READER_NFC_B or
            NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK or
            NfcAdapter.FLAG_READER_NO_PLATFORM_SOUNDS
        nfc.enableReaderMode(activity, { tag ->
            currentTag = tag
        }, flags, null)
    }

    private fun stopReader() {
        try {
            adapter?.disableReaderMode(activity)
        } catch (_: Throwable) {
        }
        closeTechs()
        currentTag = null
    }

    private fun handleTagCall(call: MethodCall): Any? {
        return when (call.method) {
            "getCard" -> getCard()
            "mfcAuth" -> mfcAuth(
                call.argument<Int>("block")!!,
                call.argument<Int>("keyType")!!,
                bytes(call.argument("key"))
            )
            "mfcReadBlock" -> mfcReadBlock(
                call.argument<Int>("block")!!,
                call.argument<Int>("keyType")!!,
                bytes(call.argument("key"))
            )
            "mfcWriteBlock" -> mfcWriteBlock(
                call.argument<Int>("block")!!,
                call.argument<Int>("keyType")!!,
                bytes(call.argument("key")),
                bytes(call.argument("data"))
            )
            "transceive" -> transceive(bytes(call.argument("data")))
            else -> throw IllegalArgumentException("Unknown method ${call.method}")
        }
    }

    private fun bytes(value: Any?): ByteArray = when (value) {
        is ByteArray -> value
        is List<*> -> ByteArray(value.size) { (value[it] as Number).toByte() }
        null -> ByteArray(0)
        else -> throw IllegalArgumentException("Expected bytes")
    }

    // keyType ChameleonUltra : 0x60 = clé A, 0x61 = clé B.
    private fun isKeyB(keyType: Int): Boolean = keyType == 0x61

    private fun getCard(): Map<String, Any?>? {
        val tag = currentTag ?: return null
        val techs = tag.techList.toList()
        val map = HashMap<String, Any?>()
        map["techs"] = techs

        val a = NfcA.get(tag)
        if (a != null) {
            map["uid"] = tag.id.toList().map { it.toInt() and 0xFF }
            map["atqa"] = a.atqa.toList().map { it.toInt() and 0xFF }
            map["sak"] = a.sak.toInt() and 0xFF
        } else {
            map["uid"] = tag.id.toList().map { it.toInt() and 0xFF }
            map["atqa"] = emptyList<Int>()
            map["sak"] = 0
        }

        // ATS (si la carte est ISO-DEP / type 4).
        val isoDep = IsoDep.get(tag)
        val ats = isoDep?.historicalBytes
        map["ats"] = ats?.toList()?.map { it.toInt() and 0xFF } ?: emptyList<Int>()

        // Infos MIFARE Classic (taille/nombre de blocs) pour détecter le type sans
        // casser de clé. Nécessite une courte connexion.
        val mfc = MifareClassic.get(tag)
        if (mfc != null) {
            map["mfcType"] = mfc.type
            map["mfcSize"] = mfc.size
            map["mfcSectorCount"] = mfc.sectorCount
            map["mfcBlockCount"] = mfc.blockCount
        } else {
            map["mfcBlockCount"] = 0
        }
        return map
    }

    private fun openClassic(): MifareClassic {
        val tag = currentTag ?: throw IllegalStateException("no tag")
        var mfc = mifareClassic
        if (mfc == null || !mfc.isConnected) {
            closeNfcA()
            mfc = MifareClassic.get(tag) ?: throw IllegalStateException("not MifareClassic")
            mfc.timeout = 1000
            mfc.connect()
            mifareClassic = mfc
        }
        return mfc
    }

    private fun openNfcA(): NfcA {
        val tag = currentTag ?: throw IllegalStateException("no tag")
        var a = nfcA
        if (a == null || !a.isConnected) {
            closeClassic()
            a = NfcA.get(tag) ?: throw IllegalStateException("not NfcA")
            a.timeout = 1000
            a.connect()
            nfcA = a
        }
        return a
    }

    private fun closeClassic() {
        try {
            mifareClassic?.close()
        } catch (_: Throwable) {
        }
        mifareClassic = null
    }

    private fun closeNfcA() {
        try {
            nfcA?.close()
        } catch (_: Throwable) {
        }
        nfcA = null
    }

    private fun closeTechs() {
        closeClassic()
        closeNfcA()
    }

    private fun mfcAuth(block: Int, keyType: Int, key: ByteArray): Boolean {
        return try {
            val mfc = openClassic()
            val sector = mfc.blockToSector(block)
            if (isKeyB(keyType)) {
                mfc.authenticateSectorWithKeyB(sector, key)
            } else {
                mfc.authenticateSectorWithKeyA(sector, key)
            }
        } catch (_: Throwable) {
            // Perte du champ : on retente une fois avec une reconnexion.
            closeClassic()
            try {
                val mfc = openClassic()
                val sector = mfc.blockToSector(block)
                if (isKeyB(keyType)) {
                    mfc.authenticateSectorWithKeyB(sector, key)
                } else {
                    mfc.authenticateSectorWithKeyA(sector, key)
                }
            } catch (_: Throwable) {
                false
            }
        }
    }

    private fun mfcReadBlock(block: Int, keyType: Int, key: ByteArray): List<Int> {
        val mfc = openClassic()
        val sector = mfc.blockToSector(block)
        val ok = if (isKeyB(keyType)) {
            mfc.authenticateSectorWithKeyB(sector, key)
        } else {
            mfc.authenticateSectorWithKeyA(sector, key)
        }
        if (!ok) throw IllegalStateException("auth failed")
        return mfc.readBlock(block).toList().map { it.toInt() and 0xFF }
    }

    private fun mfcWriteBlock(block: Int, keyType: Int, key: ByteArray, data: ByteArray): Boolean {
        val mfc = openClassic()
        val sector = mfc.blockToSector(block)
        val ok = if (isKeyB(keyType)) {
            mfc.authenticateSectorWithKeyB(sector, key)
        } else {
            mfc.authenticateSectorWithKeyA(sector, key)
        }
        if (!ok) return false
        mfc.writeBlock(block, if (data.size == 16) data else data.copyOf(16))
        return true
    }

    // Échange brut ISO14443-A (CRC ajouté/vérifié par le contrôleur NFC).
    private fun transceive(data: ByteArray): List<Int> {
        val a = openNfcA()
        return a.transceive(data).toList().map { it.toInt() and 0xFF }
    }

    fun dispose() {
        stopReader()
        ioThread.quitSafely()
    }
}
