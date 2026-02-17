import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/models/access_request.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/policy.dart';
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
