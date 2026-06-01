const admin = require("firebase-admin");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");

admin.initializeApp();

exports.sendAdminSafetyAlert = onDocumentWritten(
  "admin_alerts/{alertId}",
  async (event) => {
    const after = event.data.after;
    if (!after.exists) return;

    const alert = after.data();
    if (alert.status !== "active") return;
    if (alert.pushStatus === "sent" || alert.pushStatus === "sending") return;

    const alertRef = after.ref;
    await alertRef.set(
      {
        pushStatus: "sending",
        pushStartedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    try {
      const tokenSnapshots = await admin.firestore()
        .collectionGroup("tokens")
        .get();

      const tokens = tokenSnapshots.docs
        .filter((doc) => doc.ref.path.startsWith("admin_fcm_tokens/"))
        .map((doc) => doc.get("token"))
        .filter((token) => typeof token === "string" && token.length > 0);

      if (tokens.length === 0) {
        await alertRef.set(
          {
            pushStatus: "no_admin_tokens",
            pushUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        return;
      }

      const displayName = alert.displayName || "Student";
      const rank = alert.stressRank || "High";
      const response = await admin.messaging().sendEachForMulticast({
        tokens,
        notification: {
          title: "Wellness signal needs review",
          body: `${displayName} has a ${rank} stress signal.`,
        },
        data: {
          type: "admin_safety_alert",
          alertId: event.params.alertId,
          userId: alert.userId || "",
          stressRank: rank,
        },
        android: {
          priority: "high",
          notification: {
            channelId: "admin_safety_alerts",
          },
        },
      });

      const invalidTokens = [];
      response.responses.forEach((result, index) => {
        if (!result.success) {
          const code = result.error && result.error.code;
          if (
            code === "messaging/registration-token-not-registered" ||
            code === "messaging/invalid-registration-token"
          ) {
            invalidTokens.push(tokens[index]);
          }
        }
      });

      await Promise.all(
        invalidTokens.map(async (token) => {
          const matches = tokenSnapshots.docs.filter(
            (doc) => doc.get("token") === token,
          );
          await Promise.all(matches.map((doc) => doc.ref.delete()));
        }),
      );

      await alertRef.set(
        {
          pushStatus: "sent",
          pushSuccessCount: response.successCount,
          pushFailureCount: response.failureCount,
          invalidTokenCount: invalidTokens.length,
          pushUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    } catch (error) {
      await alertRef.set(
        {
          pushStatus: "failed",
          pushError: String(error && error.message ? error.message : error),
          pushUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      throw error;
    }
  },
);
