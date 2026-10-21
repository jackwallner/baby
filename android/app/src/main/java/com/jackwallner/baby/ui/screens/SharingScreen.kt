package com.jackwallner.baby.ui.screens

import android.content.ClipData
import android.content.Context
import android.content.ContextWrapper
import android.app.Activity
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.jackwallner.baby.LocalGraph
import com.jackwallner.baby.data.CredentialSignIn
import com.jackwallner.baby.data.GoogleSignIn
import com.jackwallner.baby.data.Member
import com.jackwallner.baby.data.SharingException
import com.jackwallner.baby.data.SignInCancelled
import com.jackwallner.baby.model.Format
import com.jackwallner.baby.model.InviteCode
import com.jackwallner.baby.ui.Group
import com.jackwallner.baby.ui.NavRow
import com.jackwallner.baby.ui.PrimaryButton
import com.jackwallner.baby.ui.RowDivider
import com.jackwallner.baby.ui.SectionLabel
import com.jackwallner.baby.ui.TextAction
import com.jackwallner.baby.ui.ValueRow
import com.jackwallner.baby.ui.theme.LocalPalette
import com.jackwallner.baby.ui.theme.Tokens
import com.jackwallner.baby.ui.theme.graphicBorder
import java.time.ZoneId
import kotlinx.coroutines.launch

/** Google sign-in for this screen: Credential Manager, or the emulators' fake token in debug runs. */
@Composable
fun rememberGoogleSignIn(): GoogleSignIn {
    val sharing = LocalGraph.current.sharing
    val context = LocalContext.current
    return remember(sharing.config) {
        sharing.testSignIn ?: CredentialSignIn(context.findActivity(), sharing.config?.webClientId.orEmpty())
    }
}

private tailrec fun Context.findActivity(): Activity = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> error("No activity for Google sign-in")
}

/** Every sharing failure as one sentence; a closed Google sheet says nothing. */
private fun message(e: Exception): String? = when (e) {
    is SignInCancelled -> null
    is SharingException -> e.message
    else -> "Something went wrong. Your log on this phone is safe. Try again."
}

/** Settings > Log together. Hidden when this build has no Firebase project. */
@Composable
fun LogTogetherGroup(open: (com.jackwallner.baby.ui.SettingsPage) -> Unit) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val sharing = graph.sharing
    if (!sharing.isAvailable) return
    val scope = rememberCoroutineScope()
    val signIn = rememberGoogleSignIn()
    var error by remember { mutableStateOf<String?>(null) }
    sharing.notice?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = palette.notice, modifier = Modifier.testTag("settings.partner.notice")) }
    Group(
        header = "Log together",
        footer = "Parents, grandparents and nannies each log from their own Android phone into the same log, with a Google sign-in. iPhone partners can't join an Android log yet.",
    ) {
        if (sharing.isOn) {
            val me = sharing.myUid
            val others = sharing.members.filter { it.uid != me }.map { it.name }
            ValueRow("Logging with", if (others.isEmpty()) "No one yet" else others.joinToString(", "), tag = "settings.partner.with")
            RowDivider()
            NavRow("Invite someone or leave", tag = "settings.partner.share") { open(com.jackwallner.baby.ui.SettingsPage.SHARING) }
        } else {
            NavRow("Invite someone", tag = "settings.partner.share") { open(com.jackwallner.baby.ui.SettingsPage.SHARING) }
            RowDivider()
            NavRow("Join someone else's log", tag = "settings.partner.join") { open(com.jackwallner.baby.ui.SettingsPage.JOIN) }
        }
        if (sharing.hasLeftoverAccount) {
            RowDivider()
            NavRow("Delete sharing sign-in", tag = "settings.partner.deleteAccount", color = palette.notice) {
                scope.launch {
                    error = try {
                        sharing.deleteAccount(signIn)
                        null
                    } catch (e: Exception) {
                        message(e)
                    }
                }
            }
        }
    }
    error?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = palette.notice) }
}

/**
 * Starting and running a shared log: what it is, the invite code to read
 * out or send, who is in, and leaving. Port of the iOS SharingSheet.
 */
@Composable
fun SharingScreen(onBack: () -> Unit) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val sharing = graph.sharing
    val scope = rememberCoroutineScope()
    val signIn = rememberGoogleSignIn()
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmLeave by remember { mutableStateOf(false) }
    var removing by remember { mutableStateOf<Member?>(null) }

    fun run(block: suspend () -> Unit) {
        if (busy) return
        busy = true
        error = null
        scope.launch {
            try {
                block()
            } catch (e: Exception) {
                error = message(e)
            } finally {
                busy = false
            }
        }
    }

    // The invite is ready as soon as the page opens.
    LaunchedEffect(sharing.isOn) {
        if (sharing.isOn && sharing.inviteCode == null) run { sharing.invite() }
    }

    Page(if (sharing.isOn) "Invite someone" else "Log together", onBack, tag = "sharing") {
        if (!sharing.isOn) {
            Text(
                "Invite your partner, a grandparent or a nanny. Everyone logs from their own Android phone into the same log, and every phone shows the latest feed.",
                style = MaterialTheme.typography.bodyLarge, color = palette.ink2,
            )
            JoinSteps()
            Note(
                "Logging together signs in with Google and keeps a copy of every baby and entry on this phone in Google Firebase, so the other phones can see them. " +
                    "Anyone with your code or link can join and edit the log for 7 days, so share it only with people you trust. iPhone partners can't join yet.",
            )
            error?.let { ErrorText(it) }
            PrimaryButton(if (busy) "Starting…" else "Continue with Google", enabled = !busy, tag = "sharing.start") { run { sharing.start(signIn) } }
        } else {
            CodeCard(sharing.inviteCode, sharing.inviteExpires, busy, onRetry = { run { sharing.invite() } })
            error?.let { ErrorText(it) }
            Members(sharing.members, sharing.myUid, sharing.isOwner) { removing = it }
            JoinSteps()
            Note("Everyone in this log can add, edit and delete entries, and anyone with the code or link can join until it expires. An offline phone catches up when it reconnects. iPhone partners can't join yet.")
            TextAction("Leave shared log", color = palette.notice, tag = "sharing.leave") { confirmLeave = true }
        }
    }

    if (confirmLeave) {
        val alone = sharing.members.size <= 1
        AlertDialog(
            onDismissRequest = { confirmLeave = false },
            containerColor = palette.card,
            title = { Text("Leave the shared log?", color = palette.ink) },
            text = {
                Text(
                    "This phone keeps everything logged so far. New entries from the others stop arriving, and your sign-in is deleted from Baby Tracker's sharing service." +
                        if (alone) " You're the only one in it, so the shared copy is deleted too." else "",
                    color = palette.ink2,
                )
            },
            confirmButton = {
                TextAction("Leave", color = palette.notice, tag = "sharing.leaveConfirm") {
                    confirmLeave = false
                    run { sharing.leave(signIn) }
                }
            },
            dismissButton = { TextAction("Cancel", color = palette.ink2) { confirmLeave = false } },
        )
    }
    removing?.let { member ->
        AlertDialog(
            onDismissRequest = { removing = null },
            containerColor = palette.card,
            title = { Text("Remove ${member.name}?", color = palette.ink) },
            text = { Text("Their phone keeps what was logged so far but stops syncing. Your invite is withdrawn; make a new one for anyone else.", color = palette.ink2) },
            confirmButton = {
                TextAction("Remove", color = palette.notice, tag = "sharing.removeConfirm") {
                    removing = null
                    run { sharing.remove(member); sharing.invite() }
                }
            },
            dismissButton = { TextAction("Cancel", color = palette.ink2) { removing = null } },
        )
    }
}

@Composable
private fun CodeCard(code: String?, expires: Long, busy: Boolean, onRetry: () -> Unit) {
    val palette = LocalPalette.current
    val context = LocalContext.current
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    var copied by remember(code) { mutableStateOf(false) }
    Column(
        Modifier.fillMaxWidth().graphicBorder(palette).padding(Tokens.loose).testTag("sharing.codeCard"),
        verticalArrangement = Arrangement.spacedBy(Tokens.spacing),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (code == null) {
            Box(Modifier.heightIn(min = 72.dp), contentAlignment = Alignment.Center) {
                if (busy) CircularProgressIndicator(color = palette.accent, modifier = Modifier.size(28.dp))
                else TextAction("Make an invite", tag = "sharing.retry", onClick = onRetry)
            }
            Text("Making your invite…".takeIf { busy } ?: "No invite yet.", style = MaterialTheme.typography.bodyMedium, color = palette.ink2)
            return@Column
        }
        Text(
            InviteCode.display(code),
            style = MaterialTheme.typography.displaySmall.copy(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold),
            color = palette.ink,
            modifier = Modifier
                .padding(vertical = Tokens.tight)
                .testTag("sharing.code")
                .semantics { contentDescription = "Invite code ${code.toCharArray().joinToString(" ")}" },
        )
        Text(
            "On the other Android phone, choose Join a shared log and enter this code. It works until ${Format.monthDay(expires, ZoneId.systemDefault())}.",
            style = MaterialTheme.typography.bodyMedium, color = palette.ink2,
        )
        PrimaryButton("Send invite link", tag = "sharing.sendLink") {
            val text = "Join our baby log in Baby Tracker so we can both log feeds, diapers and sleep. Code ${InviteCode.display(code)}, or open ${InviteCode.link(code)}"
            val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_SUBJECT, "Join our baby log").putExtra(Intent.EXTRA_TEXT, text)
            context.startActivity(Intent.createChooser(send, "Send invite link"))
        }
        TextAction(if (copied) "Copied" else "Copy code", tag = "sharing.copy") {
            scope.launch {
                clipboard.setClipEntry(ClipEntry(ClipData.newPlainText("Invite code", InviteCode.display(code))))
                copied = true
            }
        }
    }
}

@Composable
private fun Members(members: List<Member>, me: String?, isOwner: Boolean, onRemove: (Member) -> Unit) {
    val palette = LocalPalette.current
    Column(Modifier.fillMaxWidth().graphicBorder(palette).padding(Tokens.loose).testTag("sharing.joined"), verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
        SectionLabel("Logging together")
        val others = members.filter { it.uid != me }
        if (others.isEmpty()) {
            Text("No one has joined yet. Once they enter the code, their name appears here.", style = MaterialTheme.typography.bodyMedium, color = palette.ink2)
        }
        members.forEach { m ->
            Row(Modifier.fillMaxWidth().heightIn(min = Tokens.minTouch), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(if (m.uid == me) "${m.name} (you)" else m.name, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, color = palette.ink)
                    if (m.isOwner) Text("Started the log", style = MaterialTheme.typography.bodySmall, color = palette.ink2)
                }
                if (isOwner && m.uid != me) TextAction("Remove", color = palette.notice, tag = "sharing.remove.${m.name}") { onRemove(m) }
            }
        }
    }
}

/** The three steps, written for the person holding the other phone. */
@Composable
private fun JoinSteps() {
    val palette = LocalPalette.current
    Column(Modifier.fillMaxWidth().graphicBorder(palette).padding(Tokens.loose), verticalArrangement = Arrangement.spacedBy(Tokens.spacing)) {
        listOf(
            "They install Baby Tracker" to "On their own Android phone. It's free.",
            "They enter your code" to "In Baby Tracker, choose Join a shared log. The link you send opens it too.",
            "You both log" to "Feeds, diapers and sleep from either phone land in the same log.",
        ).forEachIndexed { i, (title, detail) ->
            Row(horizontalArrangement = Arrangement.spacedBy(Tokens.spacing)) {
                Box(Modifier.size(28.dp).background(palette.actionFill, CircleShape), contentAlignment = Alignment.Center) {
                    Text("${i + 1}", style = MaterialTheme.typography.labelLarge, color = palette.buttonInk)
                }
                Column {
                    Text(title, style = MaterialTheme.typography.labelLarge, color = palette.ink)
                    Text(detail, style = MaterialTheme.typography.bodyMedium, color = palette.ink2)
                }
            }
        }
    }
}

@Composable
private fun Note(text: String) {
    val palette = LocalPalette.current
    Row(horizontalArrangement = Arrangement.spacedBy(Tokens.tight)) {
        Icon(Icons.Filled.Lock, null, tint = palette.ink2, modifier = Modifier.size(14.dp).padding(top = 2.dp))
        Text(text, style = MaterialTheme.typography.bodySmall, color = palette.ink2, modifier = Modifier.testTag("sharing.access"))
    }
}

@Composable
private fun ErrorText(text: String) {
    Text(text, style = MaterialTheme.typography.bodyMedium, color = LocalPalette.current.notice, modifier = Modifier.testTag("sharing.error"))
}

/** Settings > Join someone else's log. */
@Composable
fun JoinScreen(onBack: () -> Unit, onJoined: () -> Unit) {
    val sharing = LocalGraph.current.sharing
    val palette = LocalPalette.current
    Page("Join a shared log", onBack, tag = "join") {
        if (sharing.isOn) {
            Text("This phone is already in a shared log. To join a different one, leave it first under Invite someone or leave.", style = MaterialTheme.typography.bodyLarge, color = palette.ink2)
        } else {
            JoinForm(onJoined)
        }
    }
}

/**
 * The code (or the whole pasted message) and one button. Used in Settings
 * and as onboarding's second path.
 */
@Composable
fun JoinForm(onJoined: () -> Unit) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val sharing = graph.sharing
    val scope = rememberCoroutineScope()
    val signIn = rememberGoogleSignIn()
    var text by rememberSaveable { mutableStateOf(sharing.pendingCode?.let(InviteCode::display).orEmpty()) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val code = InviteCode.parse(text)
    LaunchedEffect(sharing.pendingCode) {
        sharing.pendingCode?.let { text = InviteCode.display(it) }
    }
    Column(verticalArrangement = Arrangement.spacedBy(Tokens.spacing)) {
        Text("Enter the code from the other phone, or paste the link they sent.", style = MaterialTheme.typography.bodyLarge, color = palette.ink2)
        OutlinedTextField(
            value = text,
            onValueChange = { text = it.take(400); error = null },
            label = { Text("Invite code or link") },
            placeholder = { Text("ABCD-2345") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, autoCorrectEnabled = false, imeAction = ImeAction.Done),
            colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = palette.accent, focusedLabelColor = palette.accent, cursorColor = palette.accent),
            modifier = Modifier.fillMaxWidth().testTag("join.code"),
        )
        if (graph.events.children.isNotEmpty()) {
            Note("The babies already on this phone join the shared log too, with everything logged for them.")
        }
        Note("Joining signs in with Google, and the shared log is kept in Google Firebase. iPhone partners can't join an Android log yet.")
        error?.let { ErrorText(it) }
        PrimaryButton(if (busy) "Joining…" else "Join with Google", enabled = code != null && !busy, tag = "join.submit") {
            val joining = code ?: return@PrimaryButton
            busy = true
            error = null
            scope.launch {
                try {
                    sharing.join(joining, signIn)
                    sharing.pendingCode = null
                    onJoined()
                } catch (e: Exception) {
                    error = message(e)
                } finally {
                    busy = false
                }
            }
        }
    }
}
