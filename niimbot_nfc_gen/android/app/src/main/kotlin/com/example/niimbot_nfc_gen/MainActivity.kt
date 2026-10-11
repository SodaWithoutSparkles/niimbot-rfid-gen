package com.example.niimbot_nfc_gen

import android.nfc.NfcAdapter
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

/**
 * Holds NFC reader mode for as long as this activity is in the foreground.
 *
 * flutter_nfc_kit only enables reader mode inside `poll()`, which leaves a
 * window where Android falls back to default tag dispatch. With no NFC intent
 * filter in the manifest the system then toasts "unknown tag" on every tap.
 *
 * The proven reference app (references/nfcraw-en-src) avoids this by enabling
 * reader mode in onResume and holding it, so we do the same. flutter_nfc_kit
 * re-enables reader mode itself during poll(); Android keeps only the most
 * recent callback, so the two do not conflict.
 */
class MainActivity : FlutterActivity() {

    private var nfcAdapter: NfcAdapter? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        nfcAdapter = NfcAdapter.getDefaultAdapter(this)
    }

    override fun onResume() {
        super.onResume()
        enableReaderMode()
    }

    override fun onPause() {
        nfcAdapter?.disableReaderMode(this)
        super.onPause()
    }

    /**
     * Reader mode swallows the tap so the system does not try to dispatch it.
     *
     * The callback is a no-op on purpose: it only exists to stop the default
     * behaviour. Any tag we actually need is collected by flutter_nfc_kit's own
     * reader callback during poll().
     */
    private fun enableReaderMode() {
        val adapter = nfcAdapter ?: return
        val options = Bundle().apply {
            // On some phones the presence check re-activates the tag; without it
            // the tag will not respond at all. Same value as the reference app.
            putInt(NfcAdapter.EXTRA_READER_PRESENCE_CHECK_DELAY, 5000)
        }
        adapter.enableReaderMode(
            this,
            { /* intentionally ignored, see above */ },
            NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK,
            options,
        )
    }
}