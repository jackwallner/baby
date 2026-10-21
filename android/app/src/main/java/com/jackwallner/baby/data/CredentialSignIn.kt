package com.jackwallner.baby.data

import android.app.Activity
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential

/** The person closed Google's sheet: not an error worth a message. */
class SignInCancelled : Exception()

/** "Sign in with Google" through Credential Manager, for Firebase Auth. */
class CredentialSignIn(private val activity: Activity, private val webClientId: String) : GoogleSignIn {
    override suspend fun idToken(): String {
        val request = GetCredentialRequest.Builder()
            .addCredentialOption(GetSignInWithGoogleOption.Builder(webClientId).build())
            .build()
        val credential = try {
            CredentialManager.create(activity).getCredential(activity, request).credential
        } catch (e: GetCredentialCancellationException) {
            throw SignInCancelled()
        } catch (e: NoCredentialException) {
            throw SharingException("Add a Google account to this phone (Settings > Passwords & accounts), then try again.")
        } catch (e: GetCredentialException) {
            throw SharingException("Google sign-in didn't finish. Try again.")
        }
        if (credential is CustomCredential && credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
            return GoogleIdTokenCredential.createFrom(credential.data).idToken
        }
        throw SharingException("Google sign-in didn't return an account. Try again.")
    }
}
