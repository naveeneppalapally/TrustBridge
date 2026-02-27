const path = require('node:path');
const fs = require('node:fs');
const {createRequire} = require('node:module');
const {describe, test, before, after, afterEach} = require('node:test');

const requireFromFunctions = createRequire(
  path.resolve(__dirname, '../../functions/package.json'),
);
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = requireFromFunctions('@firebase/rules-unit-testing');

const PROJECT_ID = 'trustbridge-rules-test';
const PARENT_ID = 'parent-uid-123';
const OTHER_ID = 'other-uid-456';

let testEnv;

function testDoc(pathValue, authUid) {
  const context = authUid == null ? testEnv.unauthenticatedContext() :
    testEnv.authenticatedContext(authUid);
  return context.firestore().doc(pathValue);
}

function parentDocData(parentId = PARENT_ID) {
  return {
    parentId,
    phone: '+911234567890',
    createdAt: new Date(),
    preferences: {
      language: 'en',
      timezone: 'Asia/Kolkata',
      pushNotificationsEnabled: true,
    },
    onboardingComplete: false,
    fcmToken: null,
  };
}

function childDocData(parentId = PARENT_ID) {
  const now = new Date();
  return {
    nickname: 'Aarav',
    ageBand: '6-9',
    deviceIds: [],
    protectionEnabled: true,
    policy: {
      blockedCategories: ['social-networks'],
      blockedDomains: ['example.com'],
      safeSearchEnabled: true,
      schedules: [],
    },
    createdAt: now,
    updatedAt: now,
    parentId,
  };
}

function accessRequestData(parentId = PARENT_ID) {
  return {
    childId: 'child-1',
    parentId,
    childNickname: 'Aarav',
    appOrSite: 'instagram.com',
    durationMinutes: 30,
    durationLabel: '30 min',
    reason: 'Need for project',
    status: 'pending',
    parentReply: null,
    requestedAt: new Date(),
    respondedAt: null,
    expiresAt: null,
  };
}

async function seedChildWithDevice({
  childId = 'child-1',
  parentId = PARENT_ID,
  deviceId = 'device-1',
} = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await firestore.doc(`children/${childId}`).set(childDocData(parentId));
    await firestore
      .doc(`children/${childId}/devices/${deviceId}`)
      .set({
        parentId,
        model: 'Pixel',
        osVersion: 'Android 14',
        pairedAt: new Date(),
      });
  });
}

before(async () => {
  const rules = fs.readFileSync(
    path.resolve(__dirname, '../../firestore.rules'),
    'utf8',
  );

  const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
  const [host, portText] = emulatorHost.split(':');

  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules,
      host,
      port: Number(portText),
    },
  });
});

after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

afterEach(async () => {
  if (testEnv) {
    await testEnv.clearFirestore();
  }
});

describe('parents/{parentId}', () => {
  test('owner can create and read their own document', async () => {
    await assertSucceeds(
      testDoc(`parents/${PARENT_ID}`, PARENT_ID).set(parentDocData()),
    );

    await assertSucceeds(
      testDoc(`parents/${PARENT_ID}`, PARENT_ID).get(),
    );
  });

  test('other user cannot read parent document', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc(`parents/${PARENT_ID}`).set(parentDocData());
    });

    await assertFails(
      testDoc(`parents/${PARENT_ID}`, OTHER_ID).get(),
    );
  });

  test('unauthenticated users cannot read parent document', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc(`parents/${PARENT_ID}`).set(parentDocData());
    });

    await assertFails(
      testDoc(`parents/${PARENT_ID}`, null).get(),
    );
  });
});

describe('children top-level collection', () => {
  test('parent can create and read their own child profile', async () => {
    await assertSucceeds(
      testDoc('children/child-1', PARENT_ID).set(childDocData()),
    );

    await assertSucceeds(
      testDoc('children/child-1', PARENT_ID).get(),
    );
  });

  test('cross-parent child read is denied', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('children/child-1').set(childDocData());
    });

    await assertFails(
      testDoc('children/child-1', OTHER_ID).get(),
    );
  });

  test('child creation without nickname is denied', async () => {
    const badData = childDocData();
    delete badData.nickname;

    await assertFails(
      testDoc('children/child-bad', PARENT_ID).set(badData),
    );
  });

  test('parent can toggle protectionEnabled on owned child', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('children/child-1').set(childDocData());
    });

    await assertSucceeds(
      testDoc('children/child-1', PARENT_ID).update({
        protectionEnabled: false,
        updatedAt: new Date(),
      }),
    );
  });

  test('child device cannot toggle protectionEnabled on child profile', async () => {
    await seedChildWithDevice({
      childId: 'child-1',
      parentId: PARENT_ID,
      deviceId: 'device-1',
    });

    await assertFails(
      testDoc('children/child-1', 'device-1').update({
        protectionEnabled: false,
        updatedAt: new Date(),
      }),
    );
  });
});

describe('parents/{parentId}/access_requests/{requestId}', () => {
  test('owner can create a pending request', async () => {
    await assertSucceeds(
      testDoc(`parents/${PARENT_ID}/access_requests/req-1`, PARENT_ID)
        .set(accessRequestData()),
    );
  });

  test('request with non-pending status is denied', async () => {
    const invalid = accessRequestData();
    invalid.status = 'approved';

    await assertFails(
      testDoc(`parents/${PARENT_ID}/access_requests/req-bad`, PARENT_ID)
        .set(invalid),
    );
  });

  test('parent can approve a pending request', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore()
        .doc(`parents/${PARENT_ID}/access_requests/req-approve`)
        .set(accessRequestData());
    });

    await assertSucceeds(
      testDoc(`parents/${PARENT_ID}/access_requests/req-approve`, PARENT_ID)
        .update({
          status: 'approved',
          parentReply: 'Okay for homework',
          respondedAt: new Date(),
          expiresAt: new Date(Date.now() + 30 * 60 * 1000),
        }),
    );
  });

  test('other user cannot approve request', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore()
        .doc(`parents/${PARENT_ID}/access_requests/req-other`)
        .set(accessRequestData());
    });

    await assertFails(
      testDoc(`parents/${PARENT_ID}/access_requests/req-other`, OTHER_ID)
        .update({
          status: 'approved',
          respondedAt: new Date(),
        }),
    );
  });

  test('parent can end approved access early (approved -> expired)', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore()
        .doc(`parents/${PARENT_ID}/access_requests/req-expire-now`)
        .set({
          ...accessRequestData(),
          status: 'approved',
          respondedAt: new Date(),
          expiresAt: new Date(Date.now() + 30 * 60 * 1000),
        });
    });

    await assertSucceeds(
      testDoc(`parents/${PARENT_ID}/access_requests/req-expire-now`, PARENT_ID)
        .update({
          status: 'expired',
          expiresAt: new Date(),
          expiredAt: new Date(),
          updatedAt: new Date(),
        }),
    );
  });

  test('other user cannot end approved access early', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore()
        .doc(`parents/${PARENT_ID}/access_requests/req-expire-other`)
        .set({
          ...accessRequestData(),
          status: 'approved',
          respondedAt: new Date(),
          expiresAt: new Date(Date.now() + 30 * 60 * 1000),
        });
    });

    await assertFails(
      testDoc(`parents/${PARENT_ID}/access_requests/req-expire-other`, OTHER_ID)
        .update({
          status: 'expired',
          expiresAt: new Date(),
          expiredAt: new Date(),
          updatedAt: new Date(),
        }),
    );
  });
});

describe('children/{childId}/devices/{deviceId}', () => {
  test('parent can write child device metadata while signed in as parent account', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('children/child-1').set(childDocData());
    });

    await assertSucceeds(
      testDoc('children/child-1/devices/device-parent-owned', PARENT_ID).set({
        parentId: PARENT_ID,
        model: 'Pixel 8',
        osVersion: 'Android 14',
        fcmToken: 'fcm-token-1',
        pairedAt: new Date(),
      }),
    );
  });

  test('non-owner cannot write child device metadata', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('children/child-1').set(childDocData());
    });

    await assertFails(
      testDoc('children/child-1/devices/device-parent-owned', OTHER_ID).set({
        parentId: PARENT_ID,
        model: 'Pixel 8',
      }),
    );
  });
});

describe('children/{childId}/policy/{policyDocId}', () => {
  test('parent can read and update policy subcollection docs for owned child', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const firestore = context.firestore();
      await firestore.doc('children/child-1').set(childDocData());
      await firestore.doc('children/child-1/policy/effective').set({
        blockedCategories: ['social'],
        blockedDomains: ['example.com'],
        updatedAt: new Date(),
      });
    });

    await assertSucceeds(
      testDoc('children/child-1/policy/effective', PARENT_ID).get(),
    );

    await assertSucceeds(
      testDoc('children/child-1/policy/effective', PARENT_ID).set({
        blockedCategories: ['social', 'gaming'],
        updatedAt: new Date(),
      }, {merge: true}),
    );
  });

  test('non-owner cannot read child policy subcollection docs', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const firestore = context.firestore();
      await firestore.doc('children/child-1').set(childDocData());
      await firestore.doc('children/child-1/policy/effective').set({
        blockedCategories: ['social'],
      });
    });

    await assertFails(
      testDoc('children/child-1/policy/effective', OTHER_ID).get(),
    );
  });
});

describe('devices/{deviceId}', () => {
  test('parent can write heartbeat doc for registered child device', async () => {
    await seedChildWithDevice({
      childId: 'child-1',
      parentId: PARENT_ID,
      deviceId: 'device-1',
    });

    await assertSucceeds(
      testDoc('devices/device-1', PARENT_ID).set({
        deviceId: 'device-1',
        parentId: PARENT_ID,
        childId: 'child-1',
        lastSeen: new Date(),
        lastSeenEpochMs: Date.now(),
        vpnActive: true,
        updatedAt: new Date(),
      }),
    );
  });

  test('heartbeat doc write is denied for unregistered device id', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('children/child-1').set(childDocData());
    });

    await assertFails(
      testDoc('devices/unregistered-device', PARENT_ID).set({
        deviceId: 'unregistered-device',
        parentId: PARENT_ID,
        childId: 'child-1',
        lastSeen: new Date(),
        lastSeenEpochMs: Date.now(),
      }),
    );
  });

  test('parent-owned device can update pending command execution state', async () => {
    await seedChildWithDevice({
      childId: 'child-1',
      parentId: PARENT_ID,
      deviceId: 'device-1',
    });

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const firestore = context.firestore();
      await firestore.doc('devices/device-1').set({
        deviceId: 'device-1',
        parentId: PARENT_ID,
        childId: 'child-1',
      });
      await firestore.doc('devices/device-1/pendingCommands/cmd-1').set({
        commandId: 'cmd-1',
        parentId: PARENT_ID,
        command: 'restartVpn',
        status: 'pending',
        attempts: 0,
        sentAt: new Date(),
      });
    });

    await assertSucceeds(
      testDoc('devices/device-1/pendingCommands/cmd-1', PARENT_ID).update({
        status: 'executed',
        attempts: 1,
        executedAt: new Date(),
        updatedAt: new Date(),
      }),
    );
  });

  test('parent can enqueue child cleanup command', async () => {
    await assertSucceeds(
      testDoc('devices/device-1/pendingCommands/cmd-cleanup', PARENT_ID).set({
        commandId: 'cmd-cleanup',
        parentId: PARENT_ID,
        command: 'clearPairingAndStopProtection',
        childId: 'child-1',
        reason: 'childProfileDeleted',
        status: 'pending',
        attempts: 0,
        sentAt: new Date(),
      }),
    );
  });
});

describe('bypass_events/{deviceId}/events/{eventId}', () => {
  test('parent can read safety alert event for owned child device', async () => {
    await seedChildWithDevice({
      childId: 'child-1',
      parentId: PARENT_ID,
      deviceId: 'device-1',
    });

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore()
        .doc('bypass_events/device-1/events/event-1')
        .set({
          type: 'vpn_disabled',
          deviceId: 'device-1',
          childId: 'child-1',
          parentId: PARENT_ID,
          childNickname: 'Aarav',
          timestampEpochMs: Date.now(),
          timestamp: new Date(),
          read: false,
        });
    });

    await assertSucceeds(
      testDoc('bypass_events/device-1/events/event-1', PARENT_ID).get(),
    );
  });

  test('parent can query own safety alerts via collectionGroup', async () => {
    await seedChildWithDevice({
      childId: 'child-1',
      parentId: PARENT_ID,
      deviceId: 'device-1',
    });

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore()
        .doc('bypass_events/device-1/events/event-2')
        .set({
          type: 'uninstall_attempt',
          deviceId: 'device-1',
          childId: 'child-1',
          parentId: PARENT_ID,
          childNickname: 'Aarav',
          timestampEpochMs: Date.now(),
          timestamp: new Date(),
          read: false,
        });
    });

    const query = testEnv.authenticatedContext(PARENT_ID).firestore()
      .collectionGroup('events')
      .where('parentId', '==', PARENT_ID);
    await assertSucceeds(query.get());
  });

  test('other parent cannot read safety alert event', async () => {
    await seedChildWithDevice({
      childId: 'child-1',
      parentId: PARENT_ID,
      deviceId: 'device-1',
    });

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore()
        .doc('bypass_events/device-1/events/event-3')
        .set({
          type: 'vpn_disabled',
          deviceId: 'device-1',
          childId: 'child-1',
          parentId: PARENT_ID,
          timestampEpochMs: Date.now(),
          timestamp: new Date(),
          read: false,
        });
    });

    await assertFails(
      testDoc('bypass_events/device-1/events/event-3', OTHER_ID).get(),
    );
  });
});

describe('notification_queue', () => {
  test('authenticated owner can enqueue notification', async () => {
    await assertSucceeds(
      testDoc('notification_queue/doc-1', PARENT_ID).set({
        parentId: PARENT_ID,
        title: 'Access request',
        body: 'Aarav requested instagram.com for 30 min',
        route: '/parent-requests',
        processed: false,
        sentAt: new Date(),
      }),
    );
  });

  test('notification queue read is denied for clients', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('notification_queue/doc-1').set({
        parentId: PARENT_ID,
        title: 'Access request',
        body: 'Aarav requested instagram.com for 30 min',
        route: '/parent-requests',
        processed: false,
        sentAt: new Date(),
      });
    });

    await assertFails(
      testDoc('notification_queue/doc-1', PARENT_ID).get(),
    );
  });

  test('unauthenticated queue create is denied', async () => {
    await assertFails(
      testDoc('notification_queue/doc-2', null).set({
        parentId: PARENT_ID,
        title: 'Access request',
        body: 'Aarav requested instagram.com for 30 min',
        route: '/parent-requests',
        processed: false,
        sentAt: new Date(),
      }),
    );
  });

  test('parent can enqueue child-targeted notification for registered device', async () => {
    await seedChildWithDevice({
      childId: 'child-1',
      parentId: PARENT_ID,
      deviceId: 'device-1',
    });

    await assertSucceeds(
      testDoc('notification_queue/doc-child', PARENT_ID).set({
        parentId: PARENT_ID,
        childId: 'child-1',
        deviceId: 'device-1',
        title: 'Decision',
        body: 'Request approved',
        route: '/child/status',
        eventType: 'access_request_response',
        processed: false,
        sentAt: new Date(),
      }),
    );
  });
});

describe('catch-all deny', () => {
  test('random collection access is denied', async () => {
    await assertFails(
      testDoc('random_collection/doc-1', PARENT_ID).get(),
    );
  });
});
