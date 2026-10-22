// Security rules for Log together, against the Firestore emulator.
// Run: npm run emulator-test (from firebase/), which wraps `node --test`
// in `firebase-tools emulators:exec`.
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  collection,
  collectionGroup,
  deleteField,
  query,
  where,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

const FAMILY = 'alice:11111111-1111-4111-8111-111111111111';
const CODE = 'ABCD2345';
const DAY = 24 * 3600 * 1000;

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-baby',
    firestore: { rules: readFileSync(process.env.FIRESTORE_RULES_FILE ?? new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
});

const db = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

function entry(id, uid, overrides = {}) {
  return {
    id,
    childId: 'child-1',
    kind: 'feed',
    startedAt: 1_760_000_000_000,
    endedAt: 1_760_000_000_000,
    side: 'left',
    amount: 0,
    stoolColor: null,
    note: null,
    createdAt: 1_760_000_000_000,
    updatedAt: 1_760_000_000_000,
    deleted: false,
    updatedBy: uid,
    syncedAt: serverTimestamp(),
    ...overrides,
  };
}

function child(id, uid, overrides = {}) {
  return {
    id,
    name: 'Elsa',
    birthDate: 1_759_800_000_000,
    createdAt: 1_759_800_000_000,
    lastVisitAt: null,
    updatedAt: 1_759_800_000_000,
    deleted: false,
    updatedBy: uid,
    syncedAt: serverTimestamp(),
    ...overrides,
  };
}

function member(uid, role, invite = null) {
  return { uid, name: uid.toUpperCase(), role, joinedAt: serverTimestamp(), invite, platform: 'android' };
}

/** What the app does to start sharing: family and owner membership in one batch. */
async function startFamily(uid = 'alice', familyId = FAMILY) {
  const store = db(uid);
  const batch = writeBatch(store);
  batch.set(doc(store, 'families', familyId), { ownerUid: uid, createdAt: serverTimestamp(), schema: 1 });
  batch.set(doc(store, 'families', familyId, 'members', uid), member(uid, 'owner'));
  await batch.commit();
  return store;
}

async function invite(store, uid = 'alice', code = CODE, familyId = FAMILY, expiresInMs = 7 * DAY) {
  await setDoc(doc(store, 'invites', code), {
    familyId,
    createdBy: uid,
    createdAt: serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + expiresInMs),
  });
}

/** Writes outside the rules, for states the app can't reach on its own. */
async function removeMember(store, uid) {
  const batch = writeBatch(store);
  batch.update(doc(store, 'families', FAMILY), { invitesValidAfter: serverTimestamp() });
  batch.delete(doc(store, 'families', FAMILY, 'members', uid));
  return batch.commit();
}

async function seed(fn) {
  await env.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));
}

describe('starting a family', () => {
  test('the owner creates the family and their membership together', async () => {
    const store = db('alice');
    const batch = writeBatch(store);
    batch.set(doc(store, 'families', FAMILY), { ownerUid: 'alice', createdAt: serverTimestamp(), schema: 1 });
    batch.set(doc(store, 'families', FAMILY, 'members', 'alice'), member('alice', 'owner'));
    await assertSucceeds(batch.commit());
    await assertSucceeds(getDoc(doc(store, 'families', FAMILY)));
  });

  test('signed-out phones can do nothing', async () => {
    await assertFails(setDoc(doc(anon(), 'families', FAMILY), { ownerUid: 'x', createdAt: serverTimestamp(), schema: 1 }));
    await startFamily();
    await assertFails(getDoc(doc(anon(), 'families', FAMILY)));
    await assertFails(getDoc(doc(anon(), 'invites', CODE)));
  });

  test('nobody can create a family in someone else\'s name', async () => {
    await assertFails(setDoc(doc(db('mallory'), 'families', FAMILY), { ownerUid: 'alice', createdAt: serverTimestamp(), schema: 1 }));
  });

  test('nobody can claim to be the owner of a family they did not start', async () => {
    await startFamily();
    await assertFails(setDoc(doc(db('mallory'), 'families', FAMILY, 'members', 'mallory'), member('mallory', 'owner')));
  });

  test('the family document never changes after it is made', async () => {
    const store = await startFamily();
    await assertFails(updateDoc(doc(store, 'families', FAMILY), { ownerUid: 'mallory' }));
  });
});

describe('invites', () => {
  test('a member makes an invite with a well-formed code', async () => {
    const store = await startFamily();
    await assertSucceeds(invite(store));
  });

  test('a code outside the alphabet is refused', async () => {
    const store = await startFamily();
    await assertFails(invite(store, 'alice', 'ABCD1234'));
    await assertFails(invite(store, 'alice', 'abcd2345'));
    await assertFails(invite(store, 'alice', 'ABCD234'));
  });

  test('a non-member can\'t make an invite to a family', async () => {
    await startFamily();
    await assertFails(invite(db('mallory'), 'mallory'));
  });

  test('an invite can\'t last more than seven days', async () => {
    const store = await startFamily();
    await assertFails(invite(store, 'alice', CODE, FAMILY, 30 * DAY));
  });

  test('an existing code can\'t be overwritten to point at another family', async () => {
    const store = await startFamily();
    await invite(store);
    const other = await startFamily('mallory', 'mallory:22222222-2222-4222-8222-222222222222');
    await assertFails(invite(other, 'mallory', CODE, 'mallory:22222222-2222-4222-8222-222222222222'));
  });

  test('anyone signed in can look up a code, nobody can list them', async () => {
    const store = await startFamily();
    await invite(store);
    await assertSucceeds(getDoc(doc(db('bob'), 'invites', CODE)));
    await assertFails(getDocs(collection(db('bob'), 'invites')));
  });
});

describe('joining', () => {
  test('a valid invite lets someone add themselves as a member', async () => {
    const store = await startFamily();
    await invite(store);
    const bob = db('bob');
    await assertSucceeds(setDoc(doc(bob, 'families', FAMILY, 'members', 'bob'), member('bob', 'member', CODE)));
    await assertSucceeds(getDoc(doc(bob, 'families', FAMILY)));
    await assertSucceeds(getDocs(collection(bob, 'families', FAMILY, 'members')));
  });

  test('joining without an invite is refused', async () => {
    await startFamily();
    await assertFails(setDoc(doc(db('bob'), 'families', FAMILY, 'members', 'bob'), member('bob', 'member', null)));
    await assertFails(setDoc(doc(db('bob'), 'families', FAMILY, 'members', 'bob'), member('bob', 'member', 'ZZZZ2345')));
  });

  test('an expired invite is refused', async () => {
    await startFamily();
    await seed((s) => setDoc(doc(s, 'invites', CODE), {
      familyId: FAMILY, createdBy: 'alice', createdAt: Timestamp.now(), expiresAt: Timestamp.fromMillis(Date.now() - 1000),
    }));
    await assertFails(setDoc(doc(db('bob'), 'families', FAMILY, 'members', 'bob'), member('bob', 'member', CODE)));
  });

  test('an invite for one family does not open another', async () => {
    const store = await startFamily();
    await startFamily('carol', 'carol:22222222-2222-4222-8222-222222222222');
    await invite(store);
    await assertFails(setDoc(doc(db('bob'), 'families', 'carol:22222222-2222-4222-8222-222222222222', 'members', 'bob'), member('bob', 'member', CODE)));
  });

  test('nobody can add someone else', async () => {
    const store = await startFamily();
    await invite(store);
    await assertFails(setDoc(doc(db('bob'), 'families', FAMILY, 'members', 'carol'), member('carol', 'member', CODE)));
  });

  test('a member can rename themselves but not promote themselves', async () => {
    const store = await startFamily();
    await invite(store);
    const bob = db('bob');
    await setDoc(doc(bob, 'families', FAMILY, 'members', 'bob'), member('bob', 'member', CODE));
    await assertSucceeds(updateDoc(doc(bob, 'families', FAMILY, 'members', 'bob'), { name: 'Bob' }));
    await assertFails(updateDoc(doc(bob, 'families', FAMILY, 'members', 'bob'), { role: 'owner' }));
  });
});

describe('the log', () => {
  async function aliceAndBob() {
    const alice = await startFamily();
    await invite(alice);
    const bob = db('bob');
    await setDoc(doc(bob, 'families', FAMILY, 'members', 'bob'), member('bob', 'member', CODE));
    return { alice, bob };
  }

  test('members write babies and entries, and see each other\'s', async () => {
    const { alice, bob } = await aliceAndBob();
    await assertSucceeds(setDoc(doc(alice, 'families', FAMILY, 'children', 'child-1'), child('child-1', 'alice')));
    await assertSucceeds(setDoc(doc(bob, 'families', FAMILY, 'entries', 'e1'), entry('e1', 'bob')));
    const seen = await getDocs(collection(alice, 'families', FAMILY, 'entries'));
    if (seen.size !== 1 || seen.docs[0].data().updatedBy !== 'bob') throw new Error('Alice should see Bob\'s feed');
  });

  test('outsiders can\'t read or write the log', async () => {
    const { alice } = await aliceAndBob();
    await setDoc(doc(alice, 'families', FAMILY, 'entries', 'e1'), entry('e1', 'alice'));
    const mallory = db('mallory');
    await assertFails(getDoc(doc(mallory, 'families', FAMILY, 'entries', 'e1')));
    await assertFails(getDocs(collection(mallory, 'families', FAMILY, 'entries')));
    await assertFails(setDoc(doc(mallory, 'families', FAMILY, 'entries', 'e2'), entry('e2', 'mallory')));
    await assertFails(getDocs(collection(mallory, 'families', FAMILY, 'members')));
  });

  test('an entry has the local model\'s shape', async () => {
    const { alice } = await aliceAndBob();
    const ref = (id) => doc(alice, 'families', FAMILY, 'entries', id);
    await assertFails(setDoc(ref('e1'), entry('other-id', 'alice')));
    await assertFails(setDoc(ref('e1'), entry('e1', 'alice', { extra: true })));
    await assertFails(setDoc(ref('e1'), entry('e1', 'alice', { startedAt: 'yesterday' })));
    await assertFails(setDoc(ref('e1'), entry('e1', 'alice', { updatedBy: 'bob' })));
    await assertFails(setDoc(ref('e1'), entry('e1', 'alice', { syncedAt: Timestamp.fromMillis(0) })));
    await assertFails(setDoc(ref('e1'), entry('e1', 'alice', { note: 'x'.repeat(2001) })));
    await assertSucceeds(setDoc(ref('e1'), entry('e1', 'alice', { kind: 'dirty', side: null, stoolColor: 'yellow', amount: 60.5 })));
  });

  test('last writer wins: an older edit can\'t replace a newer one', async () => {
    const { alice, bob } = await aliceAndBob();
    await setDoc(doc(alice, 'families', FAMILY, 'entries', 'e1'), entry('e1', 'alice', { updatedAt: 2000 }));
    // Bob was offline and edited the version he had, before Alice's change.
    await assertFails(setDoc(doc(bob, 'families', FAMILY, 'entries', 'e1'), entry('e1', 'bob', { updatedAt: 1500, side: 'right' })));
    await assertSucceeds(setDoc(doc(bob, 'families', FAMILY, 'entries', 'e1'), entry('e1', 'bob', { updatedAt: 2500, side: 'right' })));
    const stored = await getDoc(doc(alice, 'families', FAMILY, 'entries', 'e1'));
    if (stored.data().side !== 'right') throw new Error('the newer edit should stand');
  });

  test('a delete is a tombstone that a stale edit can\'t resurrect', async () => {
    const { alice, bob } = await aliceAndBob();
    await setDoc(doc(alice, 'families', FAMILY, 'entries', 'e1'), entry('e1', 'alice', { updatedAt: 1000 }));
    await assertSucceeds(setDoc(doc(alice, 'families', FAMILY, 'entries', 'e1'), entry('e1', 'alice', { updatedAt: 3000, deleted: true })));
    await assertFails(setDoc(doc(bob, 'families', FAMILY, 'entries', 'e1'), entry('e1', 'bob', { updatedAt: 2000 })));
  });

  test('a baby has the local model\'s shape and the same last-writer rule', async () => {
    const { alice, bob } = await aliceAndBob();
    const ref = (s) => doc(s, 'families', FAMILY, 'children', 'child-1');
    await assertFails(setDoc(ref(alice), child('child-1', 'alice', { name: 'x'.repeat(81) })));
    await assertFails(setDoc(ref(alice), child('child-1', 'alice', { birthDate: '2026-10-01' })));
    await assertSucceeds(setDoc(ref(alice), child('child-1', 'alice', { updatedAt: 5000 })));
    await assertFails(setDoc(ref(bob), child('child-1', 'bob', { updatedAt: 4000, name: 'Old' })));
  });

  test('a first upload of a few hundred entries fits in one batch', async () => {
    const { alice } = await aliceAndBob();
    const batch = writeBatch(alice);
    for (let i = 0; i < 400; i++) {
      batch.set(doc(alice, 'families', FAMILY, 'entries', `e${i}`), entry(`e${i}`, 'alice', { startedAt: 1_760_000_000_000 + i }));
    }
    await assertSucceeds(batch.commit());
  });
});

describe('leaving and removing', () => {
  async function aliceAndBob() {
    const alice = await startFamily();
    await invite(alice);
    const bob = db('bob');
    await setDoc(doc(bob, 'families', FAMILY, 'members', 'bob'), member('bob', 'member', CODE));
    return { alice, bob };
  }

  test('a member leaves and loses access', async () => {
    const { bob } = await aliceAndBob();
    await assertSucceeds(removeMember(bob, 'bob'));
    await assertFails(getDocs(collection(bob, 'families', FAMILY, 'entries')));
  });

  test('the owner removes someone; a member can\'t remove the owner', async () => {
    const { alice, bob } = await aliceAndBob();
    await assertFails(deleteDoc(doc(bob, 'families', FAMILY, 'members', 'alice')));
    await assertSucceeds(removeMember(alice, 'bob'));
    await assertFails(setDoc(doc(bob, 'families', FAMILY, 'entries', 'e1'), entry('e1', 'bob')));
  });

  test('the last member scrubs the log and leaves an inaccessible family identity', async () => {
    const alice = await startFamily();
    await setDoc(doc(alice, 'families', FAMILY, 'entries', 'e1'), entry('e1', 'alice'));
    await invite(alice);
    await assertSucceeds(setDoc(doc(alice, 'families', FAMILY, 'entries', 'e1'), {
      id: 'e1', childId: '', kind: 'feed', startedAt: 0, createdAt: 0,
      updatedAt: Date.now(), deleted: true, updatedBy: 'alice', syncedAt: serverTimestamp(),
    }));
    const scrubbed = (await getDoc(doc(alice, 'families', FAMILY, 'entries', 'e1'))).data();
    if ('note' in scrubbed || 'side' in scrubbed || scrubbed.childId !== '') throw new Error('care data must be scrubbed');
    await assertSucceeds(updateDoc(doc(alice, 'invites', CODE), { revokedAt: serverTimestamp() }));
    await assertFails(deleteDoc(doc(alice, 'families', FAMILY)));
    await assertSucceeds(removeMember(alice, 'alice'));
    await assertFails(getDoc(doc(alice, 'families', FAMILY)));
    await assertFails(getDocs(collection(alice, 'families', FAMILY, 'entries')));
  });

  test('outsiders can\'t delete invites or entries', async () => {
    const { alice } = await aliceAndBob();
    await setDoc(doc(alice, 'families', FAMILY, 'entries', 'e1'), entry('e1', 'alice'));
    await assertFails(deleteDoc(doc(db('mallory'), 'invites', CODE)));
    await assertFails(deleteDoc(doc(db('mallory'), 'families', FAMILY, 'entries', 'e1')));
  });
});


describe('security regressions', () => {
  async function shared() {
    const alice = await startFamily();
    await invite(alice);
    const bob = db('bob');
    await setDoc(doc(bob, 'families', FAMILY, 'members', 'bob'), member('bob', 'member', CODE));
    return { alice, bob };
  }

  test('removal must revoke every outstanding code atomically', async () => {
    const { alice } = await shared();
    await assertFails(deleteDoc(doc(alice, 'families', FAMILY, 'members', 'bob')));
  });

  test('a removed member cannot reuse any code from before removal', async () => {
    const { alice, bob } = await shared();
    await invite(bob, 'bob', 'BCDE2345');
    await seed(async (s) => {
      await deleteDoc(doc(s, 'families', FAMILY, 'members', 'bob'));
      await updateDoc(doc(s, 'families', FAMILY), { invitesValidAfter: Timestamp.now() });
    });
    for (const code of [CODE, 'BCDE2345']) {
      await assertFails(setDoc(doc(bob, 'families', FAMILY, 'members', 'bob'), member('bob', 'member', code)));
    }
  });

  test('an invite stops working when its creator leaves', async () => {
    const { bob } = await shared();
    await invite(bob, 'bob', 'BCDE2345');
    await seed((s) => deleteDoc(doc(s, 'families', FAMILY, 'members', 'bob')));
    await assertFails(setDoc(doc(db('carol'), 'families', FAMILY, 'members', 'carol'), member('carol', 'member', 'BCDE2345')));
  });

  test('a former owner cannot bootstrap membership in an existing family', async () => {
    const { alice } = await shared();
    await seed((s) => deleteDoc(doc(s, 'families', FAMILY, 'members', 'alice')));
    await assertFails(setDoc(doc(alice, 'families', FAMILY, 'members', 'alice'), member('alice', 'owner')));
  });

  test('a member cannot erase the family and replace its owner', async () => {
    const { bob } = await shared();
    await assertFails(deleteDoc(doc(bob, 'families', FAMILY)));
  });

  test('hard deletes cannot erase the last-writer guard on entries or children', async () => {
    const { alice, bob } = await shared();
    await setDoc(doc(alice, 'families', FAMILY, 'entries', 'e1'), entry('e1', 'alice', { updatedAt: 5000 }));
    await setDoc(doc(alice, 'families', FAMILY, 'children', 'c1'), child('c1', 'alice', { updatedAt: 5000 }));
    await assertFails(deleteDoc(doc(bob, 'families', FAMILY, 'entries', 'e1')));
    await assertFails(deleteDoc(doc(bob, 'families', FAMILY, 'children', 'c1')));
  });

  test('collection-group and filtered outsider queries cannot reveal entries', async () => {
    const { alice } = await shared();
    await setDoc(doc(alice, 'families', FAMILY, 'entries', 'e1'), entry('e1', 'alice'));
    const outsider = db('mallory');
    await assertFails(getDocs(collectionGroup(outsider, 'entries')));
    await assertFails(getDocs(query(collection(outsider, 'families', FAMILY, 'entries'), where('childId', '==', 'child-1'))));
    await assertFails(getDocs(collection(outsider, 'families')));
  });
});


describe('additional owner and expiry regressions', () => {
  test('a former owner cannot remove members after leaving', async () => {
    const alice = await startFamily();
    await invite(alice);
    await setDoc(doc(db('bob'), 'families', FAMILY, 'members', 'bob'), member('bob', 'member', CODE));
    await seed((store) => deleteDoc(doc(store, 'families', FAMILY, 'members', 'alice')));
    await assertFails(deleteDoc(doc(alice, 'families', FAMILY, 'members', 'bob')));
  });

  test('an invite cannot exceed the seven-day lifetime', async () => {
    const alice = await startFamily();
    await assertFails(invite(alice, 'alice', CODE, FAMILY, 7.5 * DAY));
  });
});


describe('revocation protocol', () => {
  test('a withdrawn code cannot be rebound to capture a joining phones log', async () => {
    const alice = await startFamily();
    await invite(alice);
    const evilFamily = 'mallory:22222222-2222-4222-8222-222222222222';
    const mallory = await startFamily('mallory', evilFamily);
    const carol = db('carol');
    await assertFails((async () => {
      // The old withdrawal protocol freed a code already sent to Carol.
      await deleteDoc(doc(alice, 'invites', CODE));
      await invite(mallory, 'mallory', CODE, evilFamily);
      const target = (await getDoc(doc(carol, 'invites', CODE))).data().familyId;
      await setDoc(doc(carol, 'families', target, 'members', 'carol'), member('carol', 'member', CODE));
      // Joining uploads the phone's existing local log (SharingService.join).
      await setDoc(doc(carol, 'families', target, 'entries', 'private'), entry('private', 'carol'));
      await getDoc(doc(mallory, 'families', evilFamily, 'entries', 'private'));
    })());
  });

  test('a former owner rejoining as a member cannot remove other members', async () => {
    const alice = await startFamily();
    await invite(alice);
    const bob = db('bob');
    await setDoc(doc(bob, 'families', FAMILY, 'members', 'bob'), member('bob', 'member', CODE));
    await removeMember(alice, 'alice');
    await invite(bob, 'bob', 'BCDE2345');
    await setDoc(doc(alice, 'families', FAMILY, 'members', 'alice'), member('alice', 'member', 'BCDE2345'));
    await assertFails(removeMember(alice, 'bob'));
    await assertSucceeds(getDoc(doc(bob, 'families', FAMILY)));
  });

  test('removal revokes old codes, preserves other members, and permits a fresh invite', async () => {
    const alice = await startFamily();
    await invite(alice);
    const bob = db('bob');
    await setDoc(doc(bob, 'families', FAMILY, 'members', 'bob'), member('bob', 'member', CODE));
    await assertSucceeds(removeMember(alice, 'bob'));
    await assertFails(getDocs(collection(bob, 'families', FAMILY, 'entries')));
    await assertFails(setDoc(doc(bob, 'families', FAMILY, 'members', 'bob'), member('bob', 'member', CODE)));
    await assertSucceeds(getDoc(doc(alice, 'families', FAMILY)));
    await invite(alice, 'alice', 'CDEF2345');
    await assertSucceeds(setDoc(doc(bob, 'families', FAMILY, 'members', 'bob'), member('bob', 'member', 'CDEF2345')));
  });

  test('a withdrawn code cannot join and unknown collections cannot be written', async () => {
    const alice = await startFamily();
    await invite(alice);
    await updateDoc(doc(alice, 'invites', CODE), { revokedAt: serverTimestamp() });
    await assertFails(setDoc(doc(db('bob'), 'families', FAMILY, 'members', 'bob'), member('bob', 'member', CODE)));
    await assertFails(setDoc(doc(alice, 'families', FAMILY, 'secrets', 'x'), { data: 'x' }));
  });

  test('withdrawal cannot be undone or used to change the code binding', async () => {
    const alice = await startFamily();
    await invite(alice);
    const ref = doc(alice, 'invites', CODE);
    await assertFails(updateDoc(doc(db('mallory'), 'invites', CODE), { revokedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref, { revokedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { revokedAt: null }));
    await assertFails(updateDoc(ref, { revokedAt: deleteField() }));
    await assertFails(updateDoc(ref, { revokedAt: serverTimestamp(), familyId: 'another-family' }));
    await assertFails(deleteDoc(ref));
    await assertFails(invite(alice));
    await assertSucceeds(getDoc(doc(db('bob'), 'invites', CODE)));
  });
});


describe('additional owner and expiry regressions', () => {
  test('an older eight-day invite is rejected once it is seven days old', async () => {
    await startFamily();
    await seed((store) => setDoc(doc(store, 'invites', CODE), {
      familyId: FAMILY, createdBy: 'alice',
      createdAt: Timestamp.fromMillis(Date.now() - 7.5 * DAY),
      expiresAt: Timestamp.fromMillis(Date.now() + 0.5 * DAY),
    }));
    await assertFails(setDoc(doc(db('bob'), 'families', FAMILY, 'members', 'bob'), member('bob', 'member', CODE)));
  });
});


describe('security regressions', () => {
  test('orphaned logs cannot be claimed by recreating their family', async () => {
    const alice = await startFamily();
    await setDoc(doc(alice, 'families', FAMILY, 'entries', 'e1'), entry('e1', 'alice'));
    await seed((store) => deleteDoc(doc(store, 'families', FAMILY)));
    const mallory = db('mallory');
    const batch = writeBatch(mallory);
    batch.set(doc(mallory, 'families', FAMILY), { ownerUid: 'mallory', createdAt: serverTimestamp(), schema: 1 });
    batch.set(doc(mallory, 'families', FAMILY, 'members', 'mallory'), member('mallory', 'owner'));
    await assertFails(batch.commit());
    await assertFails(getDoc(doc(mallory, 'families', FAMILY, 'entries', 'e1')));
  });
});
