import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/access_request.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/models/support_ticket.dart';
import 'package:trustbridge_app/services/firestore_service.dart';

void main() {
  group('FirestoreService child operations', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
    });

    test('addChild writes expected document including parentId', () async {
      final child = await firestoreService.addChild(
        parentId: 'parentA',
        nickname: '  Leo  ',
        ageBand: AgeBand.young,
      );

      final snapshot =
          await fakeFirestore.collection('children').doc(child.id).get();

      expect(snapshot.exists, isTrue);
      final data = snapshot.data()!;
      expect(data['parentId'], 'parentA');
      expect(data['nickname'], 'Leo');
      expect(data['ageBand'], AgeBand.young.value);
    });

    test('addChild throws ArgumentError when nickname is empty', () async {
      expect(
        () => firestoreService.addChild(
          parentId: 'parentA',
          nickname: '   ',
          ageBand: AgeBand.middle,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('getChildrenStream returns only requested parent children', () async {
      final expectedChild = await firestoreService.addChild(
        parentId: 'parentA',
        nickname: 'Maya',
        ageBand: AgeBand.middle,
      );
      await firestoreService.addChild(
        parentId: 'parentB',
        nickname: 'Ravi',
        ageBand: AgeBand.teen,
      );

      final children =
          await firestoreService.getChildrenStream('parentA').first;

      expect(children.length, 1);
      expect(children.first.id, expectedChild.id);
      expect(children.first.nickname, 'Maya');
    });

    test('getChildrenStream ordering is deterministic by createdAt', () async {
      await fakeFirestore.collection('children').doc('childLate').set(
            _childDocData(
              parentId: 'parentA',
              nickname: 'Late',
              ageBand: AgeBand.young,
              createdAt: DateTime(2026, 2, 16, 10, 0, 0),
            ),
          );
      await fakeFirestore.collection('children').doc('childEarly').set(
            _childDocData(
              parentId: 'parentA',
              nickname: 'Early',
              ageBand: AgeBand.young,
              createdAt: DateTime(2026, 2, 16, 9, 0, 0),
            ),
          );

      final children =
          await firestoreService.getChildrenStream('parentA').first;

      expect(children.map((child) => child.id).toList(), [
        'childEarly',
        'childLate',
      ]);
    });

    test('getChild returns null when document is missing', () async {
      final child = await firestoreService.getChild(
        parentId: 'parentA',
        childId: 'does-not-exist',
      );

      expect(child, isNull);
    });

    test('getChild returns null when parentId does not match', () async {
      final child = await firestoreService.addChild(
        parentId: 'parentB',
        nickname: 'Sophie',
        ageBand: AgeBand.middle,
      );

      final result = await firestoreService.getChild(
        parentId: 'parentA',
        childId: child.id,
      );

      expect(result, isNull);
    });

    test('updateChild updates mutable fields and refreshes updatedAt',
        () async {
      final created = await firestoreService.addChild(
        parentId: 'parentA',
        nickname: 'Arjun',
        ageBand: AgeBand.young,
      );
      final originalSnapshot =
          await fakeFirestore.collection('children').doc(created.id).get();
      final originalUpdatedAt =
          (originalSnapshot.data()!['updatedAt'] as Timestamp).toDate();
      final originalCreatedAt =
          (originalSnapshot.data()!['createdAt'] as Timestamp).toDate();

      await Future<void>.delayed(const Duration(milliseconds: 10));

      final updatedChild = ChildProfile(
        id: created.id,
        nickname: 'Arjun Updated',
        ageBand: AgeBand.teen,
        deviceIds: const ['device-1'],
        policy: Policy.presetForAgeBand(AgeBand.teen),
        createdAt: created.createdAt,
        updatedAt: created.updatedAt,
        pausedUntil: DateTime(2026, 2, 16, 12, 0),
      );

      await firestoreService.updateChild(
        parentId: 'parentA',
        child: updatedChild,
      );

      final updatedSnapshot =
          await fakeFirestore.collection('children').doc(created.id).get();
      final data = updatedSnapshot.data()!;

      expect(data['nickname'], 'Arjun Updated');
      expect(data['ageBand'], AgeBand.teen.value);
      expect(data['deviceIds'], ['device-1']);
      expect(data['parentId'], 'parentA');
      expect(data['pausedUntil'], isA<Timestamp>());

      final updatedAt = (data['updatedAt'] as Timestamp).toDate();
      final createdAt = (data['createdAt'] as Timestamp).toDate();
      expect(updatedAt.isBefore(originalUpdatedAt), isFalse);
      expect(createdAt, originalCreatedAt);
    });

    test('deleteChild removes document', () async {
      final child = await firestoreService.addChild(
        parentId: 'parentA',
        nickname: 'Delete Me',
        ageBand: AgeBand.middle,
      );

      await firestoreService.deleteChild(
        parentId: 'parentA',
        childId: child.id,
      );

      final snapshot =
          await fakeFirestore.collection('children').doc(child.id).get();
      expect(snapshot.exists, isFalse);
    });

    test('updateChild on missing document throws FirebaseException', () async {
      final missingChild = ChildProfile(
        id: 'missing-child-id',
        nickname: 'Missing',
        ageBand: AgeBand.middle,
        deviceIds: const [],
        policy: Policy.presetForAgeBand(AgeBand.middle),
        createdAt: DateTime(2026, 2, 16),
        updatedAt: DateTime(2026, 2, 16),
      );

      expect(
        () => firestoreService.updateChild(
          parentId: 'parentA',
          child: missingChild,
        ),
        throwsA(isA<FirebaseException>()),
      );
    });
  });

  group('FirestoreService parent operations', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
    });

    test('updateParentPreferences merges preference values', () async {
      await fakeFirestore.collection('parents').doc('parentA').set({
        'parentId': 'parentA',
        'preferences': {
          'language': 'en',
          'timezone': 'Asia/Kolkata',
          'pushNotificationsEnabled': true,
          'weeklySummaryEnabled': true,
          'securityAlertsEnabled': true,
        },
      });

      await firestoreService.updateParentPreferences(
        parentId: 'parentA',
        language: 'hi',
        pushNotificationsEnabled: false,
      );

      final snapshot =
          await fakeFirestore.collection('parents').doc('parentA').get();
      final data = snapshot.data()!;
      final preferences = data['preferences'] as Map<String, dynamic>;

      expect(preferences['language'], 'hi');
      expect(preferences['pushNotificationsEnabled'], false);
      expect(preferences['timezone'], 'Asia/Kolkata');
      expect(preferences['weeklySummaryEnabled'], true);
      expect(preferences['securityAlertsEnabled'], true);
    });

    test('updateParentPreferences writes privacy and security fields',
        () async {
      await fakeFirestore.collection('parents').doc('parentB').set({
        'parentId': 'parentB',
        'preferences': {
          'activityHistoryEnabled': true,
          'crashReportsEnabled': true,
          'personalizedTipsEnabled': true,
          'biometricLoginEnabled': false,
          'incognitoModeEnabled': false,
          'nextDnsEnabled': false,
          'nextDnsProfileId': null,
        },
      });

      await firestoreService.updateParentPreferences(
        parentId: 'parentB',
        activityHistoryEnabled: false,
        crashReportsEnabled: false,
        personalizedTipsEnabled: false,
        biometricLoginEnabled: true,
        incognitoModeEnabled: true,
        vpnProtectionEnabled: true,
        nextDnsEnabled: true,
        nextDnsProfileId: 'abc123',
      );

      final snapshot =
          await fakeFirestore.collection('parents').doc('parentB').get();
      final preferences =
          snapshot.data()!['preferences'] as Map<String, dynamic>;

      expect(preferences['activityHistoryEnabled'], false);
      expect(preferences['crashReportsEnabled'], false);
      expect(preferences['personalizedTipsEnabled'], false);
      expect(preferences['biometricLoginEnabled'], true);
      expect(preferences['incognitoModeEnabled'], true);
      expect(preferences['vpnProtectionEnabled'], true);
      expect(preferences['nextDnsEnabled'], true);
      expect(preferences['nextDnsProfileId'], 'abc123');
    });

    test('updateParentPreferences throws ArgumentError for empty parentId', () {
      expect(
        () => firestoreService.updateParentPreferences(
          parentId: '   ',
          language: 'en',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('createSupportTicket writes normalized support ticket document',
        () async {
      final ticketId = await firestoreService.createSupportTicket(
        parentId: 'parent-support-a',
        subject: '  Policy Question  ',
        message:
            '  Schedules are not behaving as expected after recent changes.  ',
        childId: 'child-123',
      );

      final snapshot =
          await fakeFirestore.collection('supportTickets').doc(ticketId).get();
      expect(snapshot.exists, isTrue);

      final data = snapshot.data()!;
      expect(data['parentId'], 'parent-support-a');
      expect(data['subject'], 'Policy Question');
      expect(
        data['message'],
        'Schedules are not behaving as expected after recent changes.',
      );
      expect(data['childId'], 'child-123');
      expect(data['status'], 'open');
      expect(data['createdAt'], isA<Timestamp>());
      expect(data['updatedAt'], isA<Timestamp>());
    });

    test('createSupportTicket throws ArgumentError for invalid inputs', () {
      expect(
        () => firestoreService.createSupportTicket(
          parentId: ' ',
          subject: 'Policy Question',
          message: 'Need help.',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => firestoreService.createSupportTicket(
          parentId: 'parent-support-b',
          subject: ' ',
          message: 'Need help.',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => firestoreService.createSupportTicket(
          parentId: 'parent-support-b',
          subject: 'Policy Question',
          message: '   ',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('submitBetaFeedback writes structured ticket to supportTickets',
        () async {
      final ticketId = await firestoreService.submitBetaFeedback(
        parentId: 'parent-beta-a',
        category: 'Bug Report',
        severity: 'High',
        title: 'Policy screen save spinner stuck',
        details:
            'Saving policy from child detail gets stuck on spinner after airplane mode '
            'toggle. Happened twice on Pixel 7 with Android 14.',
        childId: 'child-beta-1',
      );

      final snapshot =
          await fakeFirestore.collection('supportTickets').doc(ticketId).get();
      expect(snapshot.exists, isTrue);

      final data = snapshot.data()!;
      expect(data['parentId'], 'parent-beta-a');
      expect((data['subject'] as String).startsWith('[Beta][High] Bug Report'),
          isTrue);
      expect(data['message'], contains('Category: Bug Report'));
      expect(data['message'], contains('Severity: High'));
      expect(data['message'], contains('Child ID: child-beta-1'));
      expect(data['status'], 'open');
    });

    test('submitBetaFeedback rejects unsupported category', () {
      expect(
        () => firestoreService.submitBetaFeedback(
          parentId: 'parent-beta-b',
          category: 'Unknown Category',
          severity: 'Medium',
          title: 'Sample title',
          details:
              'This is long enough details text to pass all minimum validation checks.',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('getSupportTicketsStream returns parent tickets newest first',
        () async {
      await fakeFirestore.collection('supportTickets').doc('ticket-old').set({
        'parentId': 'parent-history-a',
        'subject': 'Older issue',
        'message': 'Older issue details text for sorting checks.',
        'status': 'open',
        'createdAt': Timestamp.fromDate(DateTime(2026, 2, 17, 9, 30)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 2, 17, 9, 35)),
      });
      await fakeFirestore.collection('supportTickets').doc('ticket-new').set({
        'parentId': 'parent-history-a',
        'subject': 'Newest issue',
        'message': 'Newest issue details should appear first in history.',
        'status': 'resolved',
        'createdAt': Timestamp.fromDate(DateTime(2026, 2, 17, 11, 30)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 2, 17, 11, 45)),
      });
      await fakeFirestore
          .collection('supportTickets')
          .doc('ticket-other-parent')
          .set({
        'parentId': 'parent-history-b',
        'subject': 'Other parent issue',
        'message': 'Should be filtered out.',
        'status': 'open',
        'createdAt': Timestamp.fromDate(DateTime(2026, 2, 17, 12, 0)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 2, 17, 12, 0)),
      });

      final tickets = await firestoreService
          .getSupportTicketsStream('parent-history-a')
          .first;

      expect(tickets.length, 2);
      expect(tickets.map((ticket) => ticket.id), ['ticket-new', 'ticket-old']);
      expect(tickets.first.status, SupportTicketStatus.resolved);
      expect(tickets.last.status, SupportTicketStatus.open);
    });

    test('saveFcmToken and removeFcmToken update parent document', () async {
      await firestoreService.saveFcmToken('parent-token-a', 'token-abc');

      final savedSnapshot =
          await fakeFirestore.collection('parents').doc('parent-token-a').get();
      expect(savedSnapshot.exists, isTrue);
      expect(savedSnapshot.data()!['fcmToken'], 'token-abc');
      expect(savedSnapshot.data()!['fcmTokenUpdatedAt'], isA<Timestamp>());

      await firestoreService.removeFcmToken('parent-token-a');

      final removedSnapshot =
          await fakeFirestore.collection('parents').doc('parent-token-a').get();
      expect(removedSnapshot.data()!.containsKey('fcmToken'), isFalse);
    });

    test('queueParentNotification writes queued notification payload',
        () async {
      await firestoreService.queueParentNotification(
        parentId: 'parent-notify-a',
        title: 'New request',
        body: 'Aarav requested youtube.com for 30 min',
        route: '/parent-requests',
      );

      final queue = await fakeFirestore.collection('notification_queue').get();
      expect(queue.docs.length, 1);

      final data = queue.docs.first.data();
      expect(data['parentId'], 'parent-notify-a');
      expect(data['title'], 'New request');
      expect(data['route'], '/parent-requests');
      expect(data['processed'], false);
      expect(data['sentAt'], isA<Timestamp>());
    });

    test('completeOnboarding persists completion state', () async {
      await firestoreService.completeOnboarding('parent-onboarding-a');

      final snapshot = await fakeFirestore
          .collection('parents')
          .doc('parent-onboarding-a')
          .get();
      expect(snapshot.exists, isTrue);
      expect(snapshot.data()!['onboardingComplete'], isTrue);
      expect(snapshot.data()!['onboardingCompletedAt'], isA<Timestamp>());
    });

    test('isOnboardingComplete returns false for new parent profile', () async {
      await fakeFirestore.collection('parents').doc('parent-onboarding-b').set({
        'parentId': 'parent-onboarding-b',
        'preferences': {'language': 'en'},
      });

      final completed =
          await firestoreService.isOnboardingComplete('parent-onboarding-b');
      expect(completed, isFalse);
    });

    test('isOnboardingComplete returns true after completion', () async {
      await firestoreService.completeOnboarding('parent-onboarding-c');
      final completed =
          await firestoreService.isOnboardingComplete('parent-onboarding-c');
      expect(completed, isTrue);
    });
  });

  group('FirestoreService access request operations', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
    });

    test('submitAccessRequest stores request under parent subcollection',
        () async {
      final request = AccessRequest.create(
        childId: 'child-a',
        parentId: 'parent-a',
        childNickname: 'Aarav',
        appOrSite: 'instagram.com',
        duration: RequestDuration.thirtyMin,
        reason: 'Need for project',
      );

      final id = await firestoreService.submitAccessRequest(request);
      final snapshot = await fakeFirestore
          .collection('parents')
          .doc('parent-a')
          .collection('access_requests')
          .doc(id)
          .get();

      expect(snapshot.exists, isTrue);
      expect(snapshot.data()!['childId'], 'child-a');
      expect(snapshot.data()!['status'], RequestStatus.pending.name);
    });

    test('getPendingRequestsStream returns only pending requests', () async {
      final pending = AccessRequest.create(
        childId: 'child-a',
        parentId: 'parent-a',
        childNickname: 'Aarav',
        appOrSite: 'youtube.com',
        duration: RequestDuration.oneHour,
      );
      await firestoreService.submitAccessRequest(pending);

      await fakeFirestore
          .collection('parents')
          .doc('parent-a')
          .collection('access_requests')
          .add({
        ...pending.toFirestore(),
        'status': RequestStatus.approved.name,
      });

      final requests =
          await firestoreService.getPendingRequestsStream('parent-a').first;
      expect(requests.length, 1);
      expect(requests.first.status, RequestStatus.pending);
    });

    test('getChildRequestsStream filters by child id', () async {
      final requestA = AccessRequest.create(
        childId: 'child-a',
        parentId: 'parent-a',
        childNickname: 'Aarav',
        appOrSite: 'minecraft.net',
        duration: RequestDuration.fifteenMin,
      );
      final requestB = AccessRequest.create(
        childId: 'child-b',
        parentId: 'parent-a',
        childNickname: 'Maya',
        appOrSite: 'roblox.com',
        duration: RequestDuration.thirtyMin,
      );

      await firestoreService.submitAccessRequest(requestA);
      await firestoreService.submitAccessRequest(requestB);

      final requests = await firestoreService
          .getChildRequestsStream(parentId: 'parent-a', childId: 'child-a')
          .first;

      expect(requests.length, 1);
      expect(requests.first.childId, 'child-a');
      expect(requests.first.appOrSite, 'minecraft.net');
    });

    test('respondToAccessRequest marks request approved and sets expiry',
        () async {
      final request = AccessRequest.create(
        childId: 'child-a',
        parentId: 'parent-a',
        childNickname: 'Aarav',
        appOrSite: 'youtube.com',
        duration: RequestDuration.thirtyMin,
      );
      final requestId = await firestoreService.submitAccessRequest(request);

      await firestoreService.respondToAccessRequest(
        parentId: 'parent-a',
        requestId: requestId,
        status: RequestStatus.approved,
        reply: 'Okay for homework only',
      );

      final snapshot = await fakeFirestore
          .collection('parents')
          .doc('parent-a')
          .collection('access_requests')
          .doc(requestId)
          .get();
      final data = snapshot.data()!;

      expect(data['status'], RequestStatus.approved.name);
      expect(data['parentReply'], 'Okay for homework only');
      expect(data['respondedAt'], isA<Timestamp>());
      expect(data['expiresAt'], isA<Timestamp>());
    });

    test('respondToAccessRequest marks request denied without expiry',
        () async {
      final request = AccessRequest.create(
        childId: 'child-b',
        parentId: 'parent-a',
        childNickname: 'Maya',
        appOrSite: 'reddit.com',
        duration: RequestDuration.untilScheduleEnds,
      );
      final requestId = await firestoreService.submitAccessRequest(request);

      await firestoreService.respondToAccessRequest(
        parentId: 'parent-a',
        requestId: requestId,
        status: RequestStatus.denied,
      );

      final snapshot = await fakeFirestore
          .collection('parents')
          .doc('parent-a')
          .collection('access_requests')
          .doc(requestId)
          .get();
      final data = snapshot.data()!;

      expect(data['status'], RequestStatus.denied.name);
      expect(data['respondedAt'], isA<Timestamp>());
      expect(data['expiresAt'], isNull);
    });

    test('respondToAccessRequest applies approved duration override', () async {
      final request = AccessRequest.create(
        childId: 'child-c',
        parentId: 'parent-a',
        childNickname: 'Nia',
        appOrSite: 'example.com',
        duration: RequestDuration.oneHour,
      );
      final requestId = await firestoreService.submitAccessRequest(request);

      await firestoreService.respondToAccessRequest(
        parentId: 'parent-a',
        requestId: requestId,
        status: RequestStatus.approved,
        approvedDurationOverride: RequestDuration.fifteenMin,
      );

      final snapshot = await fakeFirestore
          .collection('parents')
          .doc('parent-a')
          .collection('access_requests')
          .doc(requestId)
          .get();
      final data = snapshot.data()!;

      final respondedAt = (data['respondedAt'] as Timestamp).toDate();
      final expiresAt = (data['expiresAt'] as Timestamp).toDate();
      final diffMinutes = expiresAt.difference(respondedAt).inMinutes;

      expect(data['status'], RequestStatus.approved.name);
      expect(diffMinutes, inInclusiveRange(14, 16));
    });

    test('respondToAccessRequest rejects duration override for denied status',
        () async {
      final request = AccessRequest.create(
        childId: 'child-d',
        parentId: 'parent-a',
        childNickname: 'Maya',
        appOrSite: 'reddit.com',
        duration: RequestDuration.oneHour,
      );
      final requestId = await firestoreService.submitAccessRequest(request);

      await expectLater(
        () => firestoreService.respondToAccessRequest(
          parentId: 'parent-a',
          requestId: requestId,
          status: RequestStatus.denied,
          approvedDurationOverride: RequestDuration.fifteenMin,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('getAllRequestsStream returns pending and history requests', () async {
      final pending = AccessRequest.create(
        childId: 'child-a',
        parentId: 'parent-a',
        childNickname: 'Aarav',
        appOrSite: 'minecraft.net',
        duration: RequestDuration.fifteenMin,
      );
      final approved = AccessRequest.create(
        childId: 'child-b',
        parentId: 'parent-a',
        childNickname: 'Maya',
        appOrSite: 'youtube.com',
        duration: RequestDuration.oneHour,
      );

      final pendingId = await firestoreService.submitAccessRequest(pending);
      final approvedId = await firestoreService.submitAccessRequest(approved);
      await firestoreService.respondToAccessRequest(
        parentId: 'parent-a',
        requestId: approvedId,
        status: RequestStatus.approved,
      );

      final requests =
          await firestoreService.getAllRequestsStream('parent-a').first;

      final ids = requests.map((request) => request.id).toList();
      expect(ids, contains(pendingId));
      expect(ids, contains(approvedId));
      expect(
        requests.any((request) => request.status == RequestStatus.pending),
        isTrue,
      );
      expect(
        requests.any((request) => request.status == RequestStatus.approved),
        isTrue,
      );
    });
  });

  group('Firestore permission error handling', () {
    test('getChildrenOnce propagates permission denied failures', () async {
      final service = _PermissionDeniedFirestoreService();

      expect(
        service.getChildrenOnce('parent-test'),
        throwsA(
          isA<FirebaseException>().having(
            (error) => error.code,
            'code',
            'permission-denied',
          ),
        ),
      );
    });
  });
}

class _PermissionDeniedFirestoreService extends FirestoreService {
  _PermissionDeniedFirestoreService()
      : super(firestore: FakeFirebaseFirestore());

  @override
  Future<List<ChildProfile>> getChildrenOnce(String parentId) {
    return Future<List<ChildProfile>>.error(
      FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Simulated permission failure.',
      ),
    );
  }
}

Map<String, dynamic> _childDocData({
  required String parentId,
  required String nickname,
  required AgeBand ageBand,
  required DateTime createdAt,
}) {
  return {
    'nickname': nickname,
    'ageBand': ageBand.value,
    'deviceIds': <String>[],
    'policy': Policy.presetForAgeBand(ageBand).toMap(),
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(createdAt),
    'parentId': parentId,
  };
}
