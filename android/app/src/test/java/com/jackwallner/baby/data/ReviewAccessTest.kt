package com.jackwallner.baby.data

import com.jackwallner.baby.FakePrefs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReviewAccessTest {
    // A throwaway fixture, not a real reviewer code.
    private val fixture = "local-review-fixture"
    private val digest = ReviewAccess.sha256(fixture)

    @Test
    fun digestIsLowercaseSha256Hex() {
        assertTrue(Regex("[a-f0-9]{64}").matches(digest))
        assertEquals(
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            ReviewAccess.sha256(""),
        )
    }

    @Test
    fun unconfiguredAccessCannotUnlock() {
        assertFalse(ReviewAccess(FakePrefs(), "").activate(fixture))
        assertFalse(ReviewAccess(FakePrefs(), "invalid").activate("invalid"))
        assertFalse(ReviewAccess(FakePrefs(), "").isGranted)
    }

    @Test
    fun wrongOrBlankCodeDoesNotGrantAccess() {
        val prefs = FakePrefs()
        val access = ReviewAccess(prefs, digest)
        assertFalse(access.activate("wrong"))
        assertFalse(access.activate("  "))
        assertFalse(access.isGranted)
        assertTrue(prefs.all.isEmpty())
    }

    @Test
    fun validCodePersistsOnlyTheDigest() {
        val prefs = FakePrefs()
        assertTrue(ReviewAccess(prefs, digest).activate(" $fixture "))
        assertTrue(ReviewAccess(prefs, digest).isGranted)
        assertEquals(setOf("reviewAccessDigest"), prefs.all.keys)
        assertEquals(digest, prefs.getString("reviewAccessDigest", null))
    }

    @Test
    fun rotatingTheDigestRevokesAnExistingGrant() {
        val prefs = FakePrefs()
        assertTrue(ReviewAccess(prefs, digest).activate(fixture))
        assertFalse(ReviewAccess(prefs, ReviewAccess.sha256("another-fixture")).isGranted)
        assertFalse(ReviewAccess(prefs, "").isGranted)
    }
}
