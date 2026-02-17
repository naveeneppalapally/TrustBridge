/* eslint-disable max-lines */
const admin = require("firebase-admin");
const {logger} = require("firebase-functions");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");

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
