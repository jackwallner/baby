package com.jackwallner.baby.data

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseNetworkException
import com.google.firebase.FirebaseOptions
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthRecentLoginRequiredException
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.auth.GoogleAuthProvider
import com.google.firebase.firestore.DocumentChange
import com.google.firebase.firestore.DocumentReference
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.FirebaseFirestoreSettings
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.PersistentCacheSettings
import com.google.firebase.firestore.QuerySnapshot
import com.google.firebase.firestore.Source
import com.jackwallner.baby.BuildConfig
import com.jackwallner.baby.model.InviteCode
import com.jackwallner.baby.model.LogState
import com.jackwallner.baby.model.RemoteChild
import com.jackwallner.baby.model.RemoteEntry
import com.jackwallner.baby.model.SyncChanges
import com.jackwallner.baby.model.SyncDiff
import com.jackwallner.baby.model.SyncDocs
import java.util.Date
import java.util.UUID
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

/** Where the shared log lives: the Console project, or the local emulators in debug runs. */
data class SharingConfig(
    val apiKey: String,
    val appId: String,
    val projectId: String,
    val senderId: String,
    val webClientId: String,
    /** Debug only: the Firebase Local Emulator Suite host (10.0.2.2 from an emulator). */
    val emulatorHost: String? = null,
) {
    companion object {
        /** Null without google-services.json, which hides Log together. */
        fun fromBuild(): SharingConfig? = SharingConfig(
            BuildConfig.FIREBASE_API_KEY, BuildConfig.FIREBASE_APP_ID, BuildConfig.FIREBASE_PROJECT_ID,
            BuildConfig.FIREBASE_SENDER_ID, BuildConfig.FIREBASE_WEB_CLIENT_ID,
        ).takeIf { it.apiKey.isNotBlank() && it.appId.isNotBlank() && it.projectId.isNotBlank() && it.webClientId.isNotBlank() }

        /** The emulators' demo project: no Console project, nothing leaves the host. */
        fun emulator(host: String) = SharingConfig("demo-key", "1:1:android:1", "demo-baby", "1", "demo-web-client", host)
    }
}

/** Someone in the shared log. */
data class Member(val uid: String, val name: String, val isOwner: Boolean)

/** Gets a Google ID token for Firebase: Credential Manager on a phone, a fake token on the emulators. */
fun interface GoogleSignIn {
    suspend fun idToken(): String
}

/** A failure the person can act on, worded for them. */
class SharingException(message: String) : Exception(message)

/**
 * Log together on Android: one Firestore family per shared log, joined with
 * an invite code, Google sign-in through Firebase Auth. Off (local only)
 * until someone starts or joins. Every local change is written to the
 * family; every change from the family is merged in, newest `updatedAt`
 * winning. Firestore's offline cache queues writes made without a signal.
 */
class SharingService(
    private val context: Context,
    private val prefs: SharedPreferences,
    private val events: EventStore,
    private val appName: String = FirebaseApp.DEFAULT_APP_NAME,
) {
    var config: SharingConfig? = SharingConfig.fromBuild()
        private set
    val isAvailable: Boolean get() = config != null

    var familyId by mutableStateOf(prefs.getString(K_FAMILY, null))
        private set
    val isOn: Boolean get() = familyId != null
    var isOwner by mutableStateOf(prefs.getBoolean(K_OWNER, false))
        private set
    var members by mutableStateOf<List<Member>>(emptyList())
        private set
    var inviteCode by mutableStateOf(prefs.getString(K_INVITE, null))
        private set
    var inviteExpires by mutableStateOf(prefs.getLong(K_INVITE_EXPIRES, 0L))
        private set
    /** Shown once in Settings, e.g. after the owner removed this phone. */
    var notice by mutableStateOf<String?>(null)
    /** A code from an opened invite link, waiting for the Join screen. */
    var pendingCode by mutableStateOf<String?>(null)
    /**
     * Signed in to the sharing service but not in a shared log: a leave whose
     * sign-in deletion didn't finish. Settings then offers to delete it.
     */
    var hasLeftoverAccount by mutableStateOf(prefs.getBoolean(K_ACCOUNT, false) && prefs.getString(K_FAMILY, null) == null)
        private set
    /** Debug runs against the emulators sign in with a fake Google token. */
    var testSignIn: GoogleSignIn? = null
        private set

    private var app: FirebaseApp? = null
    private val listeners = mutableListOf<ListenerRegistration>()
    private var watermark: Long
        get() = prefs.getLong(K_WATERMARK, 0L)
        set(value) = prefs.edit { putLong(K_WATERMARK, value) }

    val myUid: String? get() = app?.let { FirebaseAuth.getInstance(it).currentUser?.uid }

    init {
        events.onCommit = { before, after -> push(SyncDiff.changes(before, after, System.currentTimeMillis())) }
        events.isShared = isOn && isAvailable
    }

    /** Debug and tests only: point at the Local Emulator Suite before anything opens Firebase. */
    fun useEmulator(host: String, testName: String) {
        if (app != null) return
        config = SharingConfig.emulator(host)
        testSignIn = GoogleSignIn {
            val id = UUID.randomUUID().toString().take(12)
            """{"sub":"$id","email":"$id@example.com","email_verified":true,"name":"$testName"}"""
        }
    }

    private fun firebase(): FirebaseApp {
        app?.let { return it }
        val c = config ?: throw SharingException("Logging together isn't set up in this build.")
        val options = FirebaseOptions.Builder().setApiKey(c.apiKey).setApplicationId(c.appId)
            .setProjectId(c.projectId).setGcmSenderId(c.senderId).build()
        val opened = FirebaseApp.getApps(context).firstOrNull { it.name == appName }
            ?: FirebaseApp.initializeApp(context, options, appName)
        val db = FirebaseFirestore.getInstance(opened)
        c.emulatorHost?.let {
            db.useEmulator(it, 8080)
            FirebaseAuth.getInstance(opened).useEmulator(it, 9099)
        }
        db.firestoreSettings = FirebaseFirestoreSettings.Builder()
            .setLocalCacheSettings(PersistentCacheSettings.newBuilder().build())
            .build()
        app = opened
        return opened
    }

    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance(firebase())
    private val auth: FirebaseAuth get() = FirebaseAuth.getInstance(firebase())
    private fun family(id: String): DocumentReference = db.collection("families").document(id)

    /** App start: reconnect to the shared log this phone is in. */
    fun resume() {
        val id = familyId ?: return
        if (!isAvailable) return
        if (auth.currentUser == null) {
            dropped("You were signed out of logging together. Everything logged so far is still on this phone.")
            return
        }
        events.isShared = true
        attach(id)
    }

    // MARK: Starting, joining, inviting

    /** Makes a new shared log from everything on this phone. */
    suspend fun start(signIn: GoogleSignIn) {
        val user = signedIn(signIn)
        val id = UUID.randomUUID().toString()
        val batch = db.batch()
        batch.set(family(id), mapOf("ownerUid" to user.uid, "createdAt" to FieldValue.serverTimestamp(), "schema" to SyncDocs.SCHEMA))
        batch.set(family(id).collection("members").document(user.uid), memberFields(user, "owner", null))
        online { batch.commit().await() }
        becomeMember(id, owner = true)
        push(SyncDiff.everything(events.state))
        attach(id)
    }

    /**
     * Joins the log an invite points at. The log arrives before this returns,
     * so a first-run join lands on the shared baby. Babies already on this
     * phone go into the shared log too.
     */
    suspend fun join(code: String, signIn: GoogleSignIn) {
        val user = signedIn(signIn)
        val invite = online { db.collection("invites").document(code).get(Source.SERVER).await() }
        val id = invite.getString("familyId")
        val expires = invite.getTimestamp("expiresAt")?.toDate()?.time ?: 0L
        if (!invite.exists() || id == null) throw SharingException("That code doesn't match a shared log. Check it, or ask for a new one.")
        if (expires < System.currentTimeMillis()) throw SharingException("That invite has expired. Ask for a new one.")
        if (id == familyId) return
        if (familyId != null) throw SharingException("This phone is already logging together. Leave that log first.")
        try {
            online { family(id).collection("members").document(user.uid).set(memberFields(user, "member", code)).await() }
        } catch (e: FirebaseFirestoreException) {
            throw SharingException("That invite has expired or was withdrawn. Ask for a new one.")
        }
        val mine = events.state
        val (children, childMark) = fetch(family(id).collection("children").get(Source.SERVER)) { SyncDocs.child(it) }
        val (entries, entryMark) = fetch(family(id).collection("entries").get(Source.SERVER)) { SyncDocs.entry(it) }
        becomeMember(id, owner = false)
        watermark = maxOf(childMark, entryMark)
        events.applyRemote(children, entries)
        push(SyncDiff.everything(mine))
        attach(id)
    }

    private suspend fun <T> fetch(task: com.google.android.gms.tasks.Task<QuerySnapshot>, read: (Map<String, Any?>) -> T?): Pair<List<T>, Long> {
        val snap = online { task.await() }
        return snap.documents.mapNotNull { d -> d.data?.let(read) } to snap.documents.maxOfOrNull(::syncedAt).let { it ?: 0L }
    }

    /** The current invite, or a new one when it is missing or has a day or less left. */
    suspend fun invite(): String {
        val id = familyId ?: throw SharingException("Start logging together first.")
        val now = System.currentTimeMillis()
        inviteCode?.let { if (inviteExpires - now > DAY_MS) return it }
        val uid = auth.currentUser?.uid ?: throw SharingException("Sign in again to make an invite.")
        repeat(4) {
            val code = InviteCode.generate()
            val expires = now + InviteCode.LIFETIME_MS
            val fields = mapOf("familyId" to id, "createdBy" to uid, "createdAt" to FieldValue.serverTimestamp(), "expiresAt" to Timestamp(Date(expires)))
            try {
                online { db.collection("invites").document(code).set(fields).await() }
                inviteCode = code
                inviteExpires = expires
                prefs.edit { putString(K_INVITE, code).putLong(K_INVITE_EXPIRES, expires) }
                return code
            } catch (e: FirebaseFirestoreException) {
                // Taken by another family (one in a trillion): draw again.
                if (e.code != FirebaseFirestoreException.Code.PERMISSION_DENIED) throw e
            }
        }
        throw SharingException("Couldn't make an invite. Try again in a moment.")
    }

    // MARK: Leaving

    /**
     * Leaves the shared log and deletes this phone's sign-in from the sharing
     * service. Everything logged so far stays on this phone. The last person
     * to leave deletes the shared copy.
     */
    suspend fun leave(signIn: GoogleSignIn) {
        val id = familyId ?: return
        val user = auth.currentUser
        if (user != null) {
            detach()
            try {
                online {
                    val f = family(id)
                    val others = f.collection("members").get(Source.SERVER).await().documents.filter { it.id != user.uid }
                    if (others.isEmpty()) clearFamily(f)
                    inviteCode?.let { runCatching { db.collection("invites").document(it).delete().await() } }
                    f.collection("members").document(user.uid).delete().await()
                }
            } catch (e: Exception) {
                attach(id)
                throw e
            }
        }
        dropped(null)
        if (user != null) deleteAccount(signIn)
    }

    /** Deletes this phone's sign-in from the sharing service (Play's account deletion). */
    suspend fun deleteAccount(signIn: GoogleSignIn) {
        val user = auth.currentUser
        if (user == null) {
            markAccount(false)
            return
        }
        try {
            try {
                online { user.delete().await() }
            } catch (e: FirebaseAuthRecentLoginRequiredException) {
                // Deleting needs a fresh sign-in.
                user.reauthenticate(GoogleAuthProvider.getCredential(signIn.idToken(), null)).await()
                online { user.delete().await() }
            }
        } catch (e: Exception) {
            hasLeftoverAccount = familyId == null
            throw SharingException("Your sharing sign-in wasn't deleted. Check your connection, then try Delete sharing sign-in in Settings.")
        }
        auth.signOut()
        markAccount(false)
    }

    private fun markAccount(on: Boolean) {
        prefs.edit { putBoolean(K_ACCOUNT, on) }
        hasLeftoverAccount = on && familyId == null
    }

    /** The owner takes someone out; their phone keeps its copy and stops syncing. */
    suspend fun remove(member: Member) {
        val id = familyId ?: return
        online {
            family(id).collection("members").document(member.uid).delete().await()
            // Their old invite would let them straight back in.
            inviteCode?.let { db.collection("invites").document(it).delete().await() }
        }
        clearInvite()
    }

    private suspend fun clearFamily(f: DocumentReference) {
        for (name in listOf("entries", "children")) {
            val docs = f.collection(name).get(Source.SERVER).await().documents
            docs.chunked(BATCH).forEach { chunk -> db.batch().apply { chunk.forEach { delete(it.reference) } }.commit().await() }
        }
        f.delete().await()
    }

    // MARK: Syncing

    private fun attach(id: String) {
        detach()
        val f = family(id)
        val since = Timestamp(Date(maxOf(0L, watermark - OVERLAP_MS)))
        listeners += f.collection("children").addSnapshotListener { snap, error ->
            if (error != null) return@addSnapshotListener failed(error)
            if (snap != null) receive(snap, children = true)
        }
        // Only what changed since this phone last caught up, so a year-old log
        // doesn't cost a full read on every launch.
        listeners += f.collection("entries").whereGreaterThanOrEqualTo("syncedAt", since).addSnapshotListener { snap, error ->
            if (error != null) return@addSnapshotListener failed(error)
            if (snap != null) receive(snap, children = false)
        }
        listeners += f.collection("members").addSnapshotListener { snap, error ->
            if (error != null) return@addSnapshotListener failed(error)
            if (snap == null) return@addSnapshotListener
            val list = snap.documents.map { d ->
                Member(d.id, d.getString("name").orEmpty().ifBlank { "Someone" }, d.getString("role") == "owner")
            }.sortedWith(compareByDescending<Member> { it.isOwner }.thenBy { it.name })
            members = list
            val me = myUid
            if (!snap.metadata.isFromCache && me != null && list.none { it.uid == me }) {
                dropped("You're no longer in the shared log. Everything logged so far is still on this phone.")
            } else {
                isOwner = list.any { it.uid == me && it.isOwner }
                prefs.edit { putBoolean(K_OWNER, isOwner) }
            }
        }
    }

    private fun receive(snap: QuerySnapshot, children: Boolean) {
        val changed = snap.documentChanges.filter { it.type != DocumentChange.Type.REMOVED }.map { it.document.data }
        if (children) events.applyRemote(changed.mapNotNull(SyncDocs::child), emptyList())
        else events.applyRemote(emptyList(), changed.mapNotNull(SyncDocs::entry))
        if (!children) snap.documents.filter { !it.metadata.hasPendingWrites() }.maxOfOrNull(::syncedAt)?.let { mark ->
            if (mark > watermark) watermark = mark
        }
    }

    private fun failed(error: FirebaseFirestoreException) {
        Log.w(TAG, "Shared log listener stopped", error)
        if (error.code == FirebaseFirestoreException.Code.PERMISSION_DENIED) {
            dropped("You're no longer in the shared log. Everything logged so far is still on this phone.")
        }
    }

    /** Writes a local change to the shared log; Firestore queues it while offline. */
    private fun push(changes: SyncChanges) {
        val id = familyId ?: return
        if (changes.isEmpty || app == null) return
        val uid = auth.currentUser?.uid ?: return
        val f = family(id)
        val writes = changes.children.map { r -> f.collection("children").document(r.child.id) to SyncDocs.childFields(r, uid) } +
            changes.entries.map { r -> f.collection("entries").document(r.event.id) to SyncDocs.entryFields(r, uid) }
        writes.chunked(BATCH).forEach { chunk ->
            val batch = db.batch()
            chunk.forEach { (ref, fields) -> batch.set(ref, fields + ("syncedAt" to FieldValue.serverTimestamp())) }
            batch.commit().addOnFailureListener { Log.w(TAG, "A shared log write was refused", it) }
        }
    }

    private fun detach() {
        listeners.forEach { it.remove() }
        listeners.clear()
    }

    // MARK: State

    private fun becomeMember(id: String, owner: Boolean) {
        familyId = id
        isOwner = owner
        notice = null
        hasLeftoverAccount = false
        watermark = 0L
        clearInvite()
        prefs.edit { putString(K_FAMILY, id).putBoolean(K_OWNER, owner) }
        events.isShared = true
    }

    /** Back to local only. The log on this phone is untouched. */
    private fun dropped(message: String?) {
        detach()
        familyId = null
        isOwner = false
        members = emptyList()
        notice = message
        hasLeftoverAccount = prefs.getBoolean(K_ACCOUNT, false)
        clearInvite()
        prefs.edit { remove(K_FAMILY).remove(K_OWNER).remove(K_WATERMARK) }
        events.isShared = false
    }

    private fun clearInvite() {
        inviteCode = null
        inviteExpires = 0L
        prefs.edit { remove(K_INVITE).remove(K_INVITE_EXPIRES) }
    }

    private suspend fun signedIn(signIn: GoogleSignIn): FirebaseUser {
        auth.currentUser?.let { return it }
        val token = signIn.idToken()
        val user = online { auth.signInWithCredential(GoogleAuthProvider.getCredential(token, null)).await() }.user
            ?: throw SharingException("Google sign-in didn't finish. Try again.")
        markAccount(true)
        return user
    }

    private fun memberFields(user: FirebaseUser, role: String, invite: String?): Map<String, Any?> = mapOf(
        "uid" to user.uid,
        // First name only: it is what the other phones show.
        "name" to (user.displayName?.trim()?.substringBefore(' ')?.take(80)?.ifBlank { null } ?: "Someone"),
        "role" to role,
        "joinedAt" to FieldValue.serverTimestamp(),
        "invite" to invite,
        "platform" to "android",
    )

    /** Starting, joining and leaving need the server; a dead connection says so instead of spinning. */
    private suspend fun <T> online(block: suspend () -> T): T = try {
        withTimeout(TIMEOUT_MS) { block() }
    } catch (e: TimeoutCancellationException) {
        throw SharingException("Couldn't reach the shared log. Check your connection and try again.")
    } catch (e: FirebaseNetworkException) {
        throw SharingException("Couldn't reach the shared log. Check your connection and try again.")
    } catch (e: FirebaseFirestoreException) {
        if (e.code == FirebaseFirestoreException.Code.UNAVAILABLE) throw SharingException("Couldn't reach the shared log. Check your connection and try again.")
        throw e
    }

    companion object {
        private const val TAG = "Sharing"
        private const val K_FAMILY = "share.familyId"
        private const val K_OWNER = "share.owner"
        private const val K_INVITE = "share.inviteCode"
        private const val K_INVITE_EXPIRES = "share.inviteExpires"
        private const val K_WATERMARK = "share.watermark"
        private const val K_ACCOUNT = "share.signedIn"
        private const val DAY_MS = 24 * 3_600_000L
        /** Re-read a few minutes before the last server time seen, for writes still landing. */
        private const val OVERLAP_MS = 5 * 60_000L
        private const val TIMEOUT_MS = 20_000L
        private const val BATCH = 400

        private fun syncedAt(d: DocumentSnapshot): Long = d.getTimestamp("syncedAt")?.toDate()?.time ?: 0L
    }
}
