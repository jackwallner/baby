# RevenueCat publishes consumer ProGuard rules with its Android SDK.
# Credential Manager finds its Play services provider by reflection.
-if class androidx.credentials.CredentialManager
-keep class androidx.credentials.playservices.** {
  *;
}
