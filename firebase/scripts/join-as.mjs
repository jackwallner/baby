// A second caregiver for captures and manual checks, against the emulators
// only: signs in with a fake Google token, redeems an invite and logs one
// entry, exactly as the app writes them. Also shows the schema is readable
// and writable outside Android (the iPhone app's future path).
//
//   node scripts/join-as.mjs ABCD2345 Maya [wet|dirty|feed]
import { randomUUID } from 'node:crypto';
import { initializeApp } from 'firebase/app';
import { GoogleAuthProvider, connectAuthEmulator, getAuth, signInWithCredential } from 'firebase/auth';
import { collection, connectFirestoreEmulator, doc, getDoc, getDocs, getFirestore, serverTimestamp, setDoc, terminate } from 'firebase/firestore';

const [code, name = 'Maya', kind = 'wet'] = process.argv.slice(2);
if (!code) throw new Error('usage: join-as.mjs CODE [name] [kind]');

const app = initializeApp({ projectId: 'demo-baby', apiKey: 'demo-key' });
const auth = getAuth(app);
connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
const db = getFirestore(app);
connectFirestoreEmulator(db, '127.0.0.1', 8080);

const sub = name.toLowerCase();
const token = JSON.stringify({ sub, email: `${sub}@example.com`, email_verified: true, name });
const { user } = await signInWithCredential(auth, GoogleAuthProvider.credential(token));

const invite = await getDoc(doc(db, 'invites', code.replace('-', '').toUpperCase()));
if (!invite.exists()) throw new Error('no such invite');
const familyId = invite.data().familyId;
await setDoc(doc(db, 'families', familyId, 'members', user.uid), {
  uid: user.uid, name, role: 'member', joinedAt: serverTimestamp(), invite: invite.id, platform: 'script',
});

const children = await getDocs(collection(db, 'families', familyId, 'children'));
const child = children.docs.map((d) => d.data()).find((c) => !c.deleted);
const now = Date.now();
const id = randomUUID().toUpperCase();
await setDoc(doc(db, 'families', familyId, 'entries', id), {
  id, childId: child.id, kind, startedAt: now - 4 * 60_000, endedAt: kind === 'feed' ? now - 4 * 60_000 : null,
  side: kind === 'feed' ? 'right' : null, amount: 0, stoolColor: kind === 'dirty' ? 'yellow' : null, note: null,
  createdAt: now, updatedAt: now, deleted: false, updatedBy: user.uid, syncedAt: serverTimestamp(),
});
console.log(`${name} joined family ${familyId} and logged ${kind} for ${child.name ?? 'Baby'}`);
await terminate(db);
process.exit(0);
