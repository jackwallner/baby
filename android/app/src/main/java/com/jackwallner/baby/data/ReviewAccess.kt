package com.jackwallner.baby.data

import android.content.SharedPreferences
import androidx.core.content.edit
import java.security.MessageDigest

/**
 * The Play reviewer unlock. The build holds only the SHA-256 of the private
 * code (`PLAY_REVIEW_CODE_SHA256`). A matching code stores that digest on this
 * install, and access holds only while the stored digest still equals the one
 * built in, so rotating the digest revokes every earlier grant. It is never a
 * purchase and is never sent to RevenueCat.
 */
class ReviewAccess(private val prefs: SharedPreferences, private val expectedDigest: String) {
    private val configured get() = DIGEST_PATTERN.matches(expectedDigest)

    val isGranted get() = configured && prefs.getString(KEY, null) == expectedDigest

    fun activate(code: String): Boolean {
        if (!configured || code.isBlank()) return false
        val digest = sha256(code.trim())
        if (!MessageDigest.isEqual(digest.toByteArray(), expectedDigest.toByteArray())) return false
        prefs.edit { putString(KEY, digest) }
        return true
    }

    companion object {
        private const val KEY = "reviewAccessDigest"
        private val DIGEST_PATTERN = Regex("[a-f0-9]{64}")

        fun sha256(text: String): String =
            MessageDigest.getInstance("SHA-256").digest(text.toByteArray()).joinToString("") { "%02x".format(it) }
    }
}
