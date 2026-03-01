/* eslint-disable max-lines */
const admin = require("firebase-admin");
const {logger} = require("firebase-functions");
const {
  onDocumentCreated,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");

admin.initializeApp();

const db = admin.firestore();
const OFFLINE_LOSS_THRESHOLD_MS = 2 * 60 * 1000;
const OFFLINE_LOSS_EVENT_TYPE = "device_offline_30m";
const OFFLINE_LOSS_SWEEP_LIMIT = 200;
const OFFLINE_LOSS_STATE_DOC_ID = "offline_loss";
const OFFLINE_LOSS_MAX_LOOKBACK_MS = 7 * 24 * 60 * 60 * 1000;

function asTrimmedString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function readEpochMs(value) {
  if (typeof value === "number" && Number.isFinite(value) && value > 0) {
    return Math.trunc(value);
  }
  if (value && typeof value.toDate === "function") {
    const date = value.toDate();
    if (date instanceof Date && !Number.isNaN(date.getTime())) {
      return date.getTime();
    }
  }
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value.getTime();
  }
  return null;
}

function readStringSet(value) {
  if (!Array.isArray(value)) {
    return new Set();
  }
  const items = value
      .map((entry) => asTrimmedString(entry))
      .filter((entry) => entry.length > 0);
  return new Set(items);
}

function parseVersion(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === "string") {
    const parsed = Number.parseInt(value.trim(), 10);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function uninstallAlertsEnabled(parentData) {
  if (!parentData || typeof parentData !== "object") {
    return true;
  }
  const prefs = parentData.alertPreferences;
  if (!prefs || typeof prefs !== "object") {
    return true;
  }
  return prefs.uninstallAttempt !== false;
}

exports.sendParentNotificationFromQueue = onDocumentCreated(
  {
    document: "notification_queue/{queueId}",
    region: "asia-south1",
    retry: false,
  },
  async (event) => {
    const queueSnapshot = event.data;
    if (!queueSnapshot) {
      logger.warn("Queue trigger received without data.", {
        queueId: event.params.queueId,
      });
      return;
    }

    const queueRef = queueSnapshot.ref;
    const data = queueSnapshot.data() || {};

    if (data.processed === true) {
      logger.info("Queue document already processed.", {
        queueId: event.params.queueId,
      });
      return;
    }

    const parentId =
      typeof data.parentId === "string" ? data.parentId.trim() : "";
    const childId = typeof data.childId === "string" ? data.childId.trim() : "";
    const deviceId =
      typeof data.deviceId === "string" ? data.deviceId.trim() : "";
    const eventType =
      typeof data.eventType === "string" ? data.eventType.trim() : "";
    const title = typeof data.title === "string" ? data.title.trim() : "";
    const body = typeof data.body === "string" ? data.body.trim() : "";
    const route = typeof data.route === "string" ? data.route.trim() : "";
    const isChildTarget =
      childId &&
      (eventType === "access_request_response" || route.startsWith("/child/"));

    if (!parentId || !title || !body || !route) {
      await queueRef.set(
        {
          processed: true,
          status: "invalid_payload",
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          errorCode: "missing_required_fields",
        },
        {merge: true},
      );
      logger.warn("Notification queue payload invalid.", {
        queueId: event.params.queueId,
      });
      return;
    }

    if (isChildTarget) {
      const devicesSnapshot = await db
          .collection("children")
          .doc(childId)
          .collection("devices")
          .get();

      const tokens = [];
      for (const doc of devicesSnapshot.docs) {
        if (deviceId && doc.id !== deviceId) {
          continue;
        }
        const token = typeof doc.get("fcmToken") === "string" ?
          doc.get("fcmToken").trim() : "";
        if (token) {
          tokens.push(token);
        }
      }
      const uniqueTokens = Array.from(new Set(tokens));

      if (!uniqueTokens.length) {
        await queueRef.set(
            {
              processed: true,
              status: "skipped_no_child_token",
              processedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );
        logger.info("Child has no FCM token. Notification skipped.", {
          queueId: event.params.queueId,
          childId,
          deviceId: deviceId || null,
        });
        return;
      }

      const failures = [];
      const messageIds = [];
      for (const token of uniqueTokens) {
        const message = {
          token,
          notification: {
            title,
            body,
          },
          data: {
            route,
            type: eventType || "access_request_response",
            queueId: event.params.queueId,
          },
          android: {
            priority: "high",
            notification: {
              channelId: "trustbridge_requests",
              clickAction: "FLUTTER_NOTIFICATION_CLICK",
            },
          },
        };

        try {
          const messageId = await admin.messaging().send(message);
          messageIds.push(messageId);
        } catch (error) {
          failures.push(error);
        }
      }

      if (!messageIds.length) {
        const firstError = failures[0];
        await queueRef.set(
            {
              processed: true,
              status: "failed",
              processedAt: admin.firestore.FieldValue.serverTimestamp(),
              errorCode:
                firstError && firstError.code ?
                  String(firstError.code) : "unknown",
              errorMessage:
                firstError && firstError.message ?
                  String(firstError.message).slice(0, 500) : "Unknown error",
            },
            {merge: true},
        );
        logger.error("Failed to send child notification.", {
          queueId: event.params.queueId,
          childId,
          error: firstError,
        });
        return;
      }

      await queueRef.set(
          {
            processed: true,
            status: failures.length ? "partial_sent" : "sent",
            processedAt: admin.firestore.FieldValue.serverTimestamp(),
            deliveredCount: messageIds.length,
            attemptedCount: uniqueTokens.length,
            fcmMessageId: messageIds[0],
          },
          {merge: true},
      );
      logger.info("Child notification sent.", {
        queueId: event.params.queueId,
        childId,
        deliveredCount: messageIds.length,
        attemptedCount: uniqueTokens.length,
      });
      return;
    }

    const parentDoc = await db.collection("parents").doc(parentId).get();
    const token =
      parentDoc.exists && typeof parentDoc.get("fcmToken") === "string" ?
        parentDoc.get("fcmToken").trim() : "";

    if (!token) {
      await queueRef.set(
          {
            processed: true,
            status: "skipped_no_token",
            processedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true},
      );
      logger.info("Parent has no FCM token. Notification skipped.", {
        queueId: event.params.queueId,
        parentId,
      });
      return;
    }

    const message = {
      token,
      notification: {
        title,
        body,
      },
      data: {
        route,
        type: eventType || "access_request",
        queueId: event.params.queueId,
      },
      android: {
        priority: "high",
        notification: {
          channelId: "trustbridge_requests",
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
        },
      },
    };

    try {
      const messageId = await admin.messaging().send(message);
      await queueRef.set(
          {
            processed: true,
            status: "sent",
            processedAt: admin.firestore.FieldValue.serverTimestamp(),
            fcmMessageId: messageId,
          },
          {merge: true},
      );
      logger.info("Parent notification sent.", {
        queueId: event.params.queueId,
        parentId,
        messageId,
      });
    } catch (error) {
      const errorCode =
        error && error.code ? String(error.code) : "unknown";
      if (errorCode === "messaging/registration-token-not-registered") {
        try {
          await parentDoc.ref.set(
              {
                fcmToken: admin.firestore.FieldValue.delete(),
                fcmTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              {merge: true},
          );
          logger.warn("Cleared stale parent FCM token after send failure.", {
            queueId: event.params.queueId,
            parentId,
          });
        } catch (clearError) {
          logger.warn("Failed clearing stale parent token.", {
            queueId: event.params.queueId,
            parentId,
            clearError,
          });
        }
      }

      await queueRef.set(
          {
            processed: true,
            status:
              errorCode === "messaging/registration-token-not-registered" ?
                "failed_invalid_token" : "failed",
            processedAt: admin.firestore.FieldValue.serverTimestamp(),
            errorCode,
            errorMessage:
              error && error.message ?
                String(error.message).slice(0, 500) :
                "Unknown error",
          },
          {merge: true},
      );
      logger.error("Failed to send parent notification.", {
        queueId: event.params.queueId,
        parentId,
        error,
      });
    }
  },
);

exports.pushChildPolicyUpdate = onDocumentWritten(
  {
    document: "children/{childId}/effective_policy/current",
    region: "asia-south1",
    retry: false,
  },
  async (event) => {
    const after = event.data && event.data.after;
    if (!after || !after.exists) {
      return;
    }

    const before = event.data && event.data.before;
    const beforeData = before && before.exists ? before.data() || {} : {};
    const afterData = after.data() || {};

    const beforeVersion = parseVersion(beforeData.version);
    const afterVersion = parseVersion(afterData.version);
    if (before && before.exists && afterVersion <= beforeVersion) {
      return;
    }

    const childId = asTrimmedString(event.params.childId);
    if (!childId) {
      return;
    }

    const parentId = asTrimmedString(afterData.parentId);
    const timestamp = String(Date.now());
    const version = String(afterVersion);

    const devicesSnapshot = await db
        .collection("children")
        .doc(childId)
        .collection("devices")
        .get();

    if (devicesSnapshot.empty) {
      logger.info("Policy update push skipped: no child devices.", {
        childId,
        version,
      });
      return;
    }

    let sentCount = 0;
    let failedCount = 0;
    for (const deviceDoc of devicesSnapshot.docs) {
      const token = asTrimmedString(deviceDoc.get("fcmToken"));
      if (!token) {
        continue;
      }

      const message = {
        token,
        data: {
          type: "policy_update",
          childId,
          parentId,
          version,
          timestamp,
        },
        android: {
          priority: "high",
        },
      };

      try {
        await admin.messaging().send(message);
        sentCount += 1;
      } catch (error) {
        failedCount += 1;
        const errorCode = error && error.code ? String(error.code) : "unknown";
        if (errorCode === "messaging/registration-token-not-registered") {
          try {
            await deviceDoc.ref.set(
                {
                  fcmToken: admin.firestore.FieldValue.delete(),
                  fcmTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
                },
                {merge: true},
            );
          } catch (clearError) {
            logger.warn("Failed clearing stale child FCM token.", {
              childId,
              deviceId: deviceDoc.id,
              clearError,
            });
          }
        }
        logger.warn("Policy update push failed for child device.", {
          childId,
          deviceId: deviceDoc.id,
          errorCode,
          errorMessage: error && error.message ? String(error.message) : "",
        });
      }
    }

    logger.info("Policy update push fanout complete.", {
      childId,
      parentId,
      version,
      sentCount,
      failedCount,
    });
  },
);

exports.alertParentOnOfflineLoss = onSchedule(
  {
    schedule: "every 1 minutes",
    region: "asia-south1",
    timeZone: "Asia/Kolkata",
    retryCount: 0,
  },
  async () => {
    const sweepStartedAtMs = Date.now();
    const cutoffMs = sweepStartedAtMs - OFFLINE_LOSS_THRESHOLD_MS;
    const lowerBoundMs = sweepStartedAtMs - OFFLINE_LOSS_MAX_LOOKBACK_MS;
    let scannedCount = 0;
    let queuedCount = 0;
    let alreadyAlertedCount = 0;
    let skippedMissingLinkCount = 0;
    let skippedDisabledPrefCount = 0;
    let errorCount = 0;

    try {
      const staleSnapshot = await db
          .collection("devices")
          .where("lastSeenEpochMs", ">=", lowerBoundMs)
          .where("lastSeenEpochMs", "<=", cutoffMs)
          .orderBy("lastSeenEpochMs", "desc")
          .limit(OFFLINE_LOSS_SWEEP_LIMIT)
          .get();

      for (const deviceDoc of staleSnapshot.docs) {
        scannedCount += 1;
        try {
          const raw = deviceDoc.data() || {};
          const deviceId = asTrimmedString(raw.deviceId) || deviceDoc.id;
          const parentId = asTrimmedString(raw.parentId);
          const childId = asTrimmedString(raw.childId);
          const lastSeenEpochMs =
            readEpochMs(raw.lastSeenEpochMs) || readEpochMs(raw.lastSeen);

          if (!deviceId || !parentId || !childId || !lastSeenEpochMs) {
            skippedMissingLinkCount += 1;
            continue;
          }

          if (sweepStartedAtMs - lastSeenEpochMs < OFFLINE_LOSS_THRESHOLD_MS) {
            continue;
          }

          const stateRef = deviceDoc.ref
              .collection("server_state")
              .doc(OFFLINE_LOSS_STATE_DOC_ID);

          const txResult = await db.runTransaction(async (transaction) => {
            const stateSnap = await transaction.get(stateRef);
            const state = stateSnap.data() || {};
            const alertedForLastSeenEpochMs =
              readEpochMs(state.alertedForLastSeenEpochMs);
            if (
              state.active === true &&
              alertedForLastSeenEpochMs === lastSeenEpochMs
            ) {
              return "already_alerted";
            }

            const childRef = db.collection("children").doc(childId);
            const childSnap = await transaction.get(childRef);
            if (!childSnap.exists) {
              return "child_missing";
            }
            const childData = childSnap.data() || {};
            const childParentId = asTrimmedString(childData.parentId);
            if (!childParentId || childParentId !== parentId) {
              return "child_mismatch";
            }

            const childDeviceIds = readStringSet(childData.deviceIds);
            if (!childDeviceIds.has(deviceId)) {
              return "device_unassigned";
            }

            const parentRef = db.collection("parents").doc(parentId);
            const parentSnap = await transaction.get(parentRef);
            if (!uninstallAlertsEnabled(parentSnap.data())) {
              return "pref_disabled";
            }

            const childNickname = asTrimmedString(childData.nickname);
            const childLabel = childNickname || "Your child";
            const eventChildNickname = childNickname || "Child";
            const offlineMinutes = Math.max(
                1,
                Math.floor((sweepStartedAtMs - lastSeenEpochMs) / 60000),
            );

            const bypassEventRef = db
                .collection("bypass_events")
                .doc(deviceId)
                .collection("events")
                .doc();
            transaction.set(bypassEventRef, {
              type: OFFLINE_LOSS_EVENT_TYPE,
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
              timestampEpochMs: sweepStartedAtMs,
              deviceId,
              childId,
              childNickname: eventChildNickname,
              parentId,
              read: false,
            });

            const queueRef = db.collection("notification_queue").doc();
            transaction.set(queueRef, {
              parentId,
              childId,
              deviceId,
              title: "Protection may be off on your child's phone",
              body:
                `${childLabel} has not checked in for ${offlineMinutes}+ ` +
                "minutes. Open TrustBridge to verify protection.",
              route: "/parent/bypass-alerts",
              eventType: OFFLINE_LOSS_EVENT_TYPE,
              processed: false,
              sentAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            transaction.set(
                stateRef,
                {
                  active: true,
                  deviceId,
                  parentId,
                  childId,
                  eventType: OFFLINE_LOSS_EVENT_TYPE,
                  alertedForLastSeenEpochMs: lastSeenEpochMs,
                  alertedAt: admin.firestore.FieldValue.serverTimestamp(),
                  alertedAtEpochMs: sweepStartedAtMs,
                },
                {merge: true},
            );
            return "queued";
          });

          switch (txResult) {
            case "queued":
              queuedCount += 1;
              break;
            case "already_alerted":
              alreadyAlertedCount += 1;
              break;
            case "pref_disabled":
              skippedDisabledPrefCount += 1;
              break;
            case "child_missing":
            case "child_mismatch":
            case "device_unassigned":
              skippedMissingLinkCount += 1;
              break;
            default:
              break;
          }
        } catch (error) {
          errorCount += 1;
          logger.error("Offline-loss watchdog failed for device.", {
            deviceDocId: deviceDoc.id,
            error,
          });
        }
      }

      logger.info("Offline-loss watchdog sweep complete.", {
        scannedCount,
        queuedCount,
        alreadyAlertedCount,
        skippedMissingLinkCount,
        skippedDisabledPrefCount,
        errorCount,
        thresholdMs: OFFLINE_LOSS_THRESHOLD_MS,
        lookbackMs: OFFLINE_LOSS_MAX_LOOKBACK_MS,
        sweepLimit: OFFLINE_LOSS_SWEEP_LIMIT,
        durationMs: Date.now() - sweepStartedAtMs,
      });
    } catch (error) {
      logger.error("Offline-loss watchdog sweep failed.", {
        scannedCount,
        queuedCount,
        alreadyAlertedCount,
        skippedMissingLinkCount,
        skippedDisabledPrefCount,
        errorCount,
        thresholdMs: OFFLINE_LOSS_THRESHOLD_MS,
        lookbackMs: OFFLINE_LOSS_MAX_LOOKBACK_MS,
        sweepLimit: OFFLINE_LOSS_SWEEP_LIMIT,
        durationMs: Date.now() - sweepStartedAtMs,
        error,
      });
      throw error;
    }
  },
);

exports.expireApprovedAccessRequests = onSchedule(
  {
    schedule: "every 1 minutes",
    region: "asia-south1",
    timeZone: "Asia/Kolkata",
    retryCount: 0,
  },
  async () => {
    const maxBatchSize = 200;
    const sweepStartedAt = Date.now();
    let totalExpired = 0;
    let batchesProcessed = 0;
    let latestExpiryCutoff = null;

    try {
      while (true) {
        const now = admin.firestore.Timestamp.now();
        const snapshot = await db
            .collectionGroup("access_requests")
            .where("status", "==", "approved")
            .where("expiresAt", "<=", now)
            .orderBy("expiresAt", "asc")
            .limit(maxBatchSize)
            .get();

        if (snapshot.empty) {
          break;
        }

        const batch = db.batch();
        for (const doc of snapshot.docs) {
          batch.update(doc.ref, {
            status: "expired",
            expiredAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        await batch.commit();
        totalExpired += snapshot.size;
        batchesProcessed += 1;

        const lastDoc = snapshot.docs[snapshot.docs.length - 1];
        const lastExpiresAt = lastDoc.get("expiresAt");
        if (lastExpiresAt && typeof lastExpiresAt.toDate === "function") {
          latestExpiryCutoff = lastExpiresAt.toDate().toISOString();
        }

        if (snapshot.size < maxBatchSize) {
          break;
        }
      }

      logger.info("Expired access requests sweep complete.", {
        totalExpired,
        batchesProcessed,
        durationMs: Date.now() - sweepStartedAt,
        latestExpiryCutoff,
      });
    } catch (error) {
      logger.error("Expired access requests sweep failed.", {
        totalExpired,
        batchesProcessed,
        durationMs: Date.now() - sweepStartedAt,
        latestExpiryCutoff,
        error,
      });
      throw error;
    }
  },
);
