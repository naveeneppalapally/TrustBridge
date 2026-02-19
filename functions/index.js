/* eslint-disable max-lines */
const admin = require("firebase-admin");
const {logger} = require("firebase-functions");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");

admin.initializeApp();

const db = admin.firestore();

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
    const title = typeof data.title === "string" ? data.title.trim() : "";
    const body = typeof data.body === "string" ? data.body.trim() : "";
    const route = typeof data.route === "string" ? data.route.trim() : "";

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

    const parentDoc = await db.collection("parents").doc(parentId).get();
    const token =
      parentDoc.exists && typeof parentDoc.get("fcmToken") === "string"
        ? parentDoc.get("fcmToken").trim()
        : "";

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
        type: "access_request",
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
      await queueRef.set(
        {
          processed: true,
          status: "failed",
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          errorCode: error && error.code ? String(error.code) : "unknown",
          errorMessage:
            error && error.message
              ? String(error.message).slice(0, 500)
              : "Unknown error",
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

exports.expireApprovedAccessRequests = onSchedule(
  {
    schedule: "every 5 minutes",
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
