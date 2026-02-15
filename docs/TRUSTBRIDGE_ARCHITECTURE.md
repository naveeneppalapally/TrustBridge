# TrustBridge - Complete Technical Architecture

**Version:** 1.0  
**Date:** February 15, 2026  
**App Name:** TrustBridge  
**Platform:** Android (Flutter)  
**Design System:** iOS-Motion Hybrid

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Flutter App Architecture](#flutter-app-architecture)
3. [State Management (BLoC)](#state-management-bloc)
4. [Firebase Backend Architecture](#firebase-backend-architecture)
5. [Android VPN Service Architecture](#android-vpn-service-architecture)
6. [Data Flow Diagrams](#data-flow-diagrams)
7. [Security Architecture](#security-architecture)
8. [Performance Optimization](#performance-optimization)
9. [Testing Strategy](#testing-strategy)
10. [Development Roadmap](#development-roadmap)

---

## System Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     TRUSTBRIDGE SYSTEM                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐              ┌──────────────┐            │
│  │  PARENT APP  │◄────────────►│  CHILD APP   │            │
│  │  (Flutter)   │   Real-time  │  (Flutter)   │            │
│  └──────┬───────┘   Sync via   └──────┬───────┘            │
│         │          Firestore          │                     │
│         │                             │                     │
│         ▼                             ▼                     │
│  ┌──────────────────────────────────────────┐              │
│  │         FIREBASE BACKEND                 │              │
│  │  ┌────────────┬────────────┬──────────┐ │              │
│  │  │ Firestore  │   Auth     │   FCM    │ │              │
│  │  │  (NoSQL)   │  (Phone)   │ (Push)   │ │              │
│  │  └────────────┴────────────┴──────────┘ │              │
│  └──────────────────────────────────────────┘              │
│                                                              │
│  ┌──────────────────────────────────────────┐              │
│  │    ANDROID VPN SERVICE (Child Device)    │              │
│  │  ┌────────────┬────────────┬──────────┐ │              │
│  │  │ DNS Filter │ Scheduler  │  Monitor │ │              │
│  │  │  (Kotlin)  │  (Kotlin)  │ (Kotlin) │ │              │
│  │  └────────────┴────────────┴──────────┘ │              │
│  └──────────────────────────────────────────┘              │
│                                                              │
│  ┌──────────────────────────────────────────┐              │
│  │      NEXTDNS (Optional Integration)      │              │
│  │        Advanced DNS Filtering            │              │
│  └──────────────────────────────────────────┘              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Technology Stack

**Frontend:**
- Flutter 3.x (Dart 3.x)
- Material Design 3 + iOS-Motion Hybrid
- BLoC for state management
- go_router for navigation

**Backend:**
- Firebase Authentication (Phone OTP)
- Cloud Firestore (NoSQL database)
- Firebase Cloud Messaging (Push notifications)
- Firebase Cloud Functions (Serverless)

**Native Android:**
- Kotlin 1.9+
- Android VpnService API
- SQLite for local blocklists
- WorkManager for background tasks

**External Services:**
- NextDNS (Optional managed DNS filtering)
- Razorpay (Payment processing - India)
- Google Play Billing (Subscriptions)

---

## Flutter App Architecture

### Architecture Pattern: Clean Architecture + BLoC

Clean Architecture provides clear separation of concerns with three main layers:
1. **Presentation Layer** - UI and state management (BLoC)
2. **Domain Layer** - Business logic and entities
3. **Data Layer** - Data sources and repositories

### Project Structure

```
lib/
├── main.dart                          # App entry point
├── app/
│   ├── app.dart                       # MaterialApp setup
│   ├── theme/                         # iOS-Motion Hybrid theme
│   │   ├── light_theme.dart
│   │   ├── dark_theme.dart
│   │   ├── colors.dart
│   │   ├── typography.dart
│   │   └── glass_effects.dart
│   └── routes/
│       └── app_router.dart            # Navigation (go_router)
│
├── core/
│   ├── constants/
│   │   ├── api_constants.dart
│   │   ├── storage_keys.dart
│   │   └── app_constants.dart
│   ├── errors/
│   │   ├── failures.dart
│   │   └── exceptions.dart
│   ├── network/
│   │   └── network_info.dart
│   ├── utils/
│   │   ├── date_utils.dart
│   │   ├── validators.dart
│   │   └── extensions.dart
│   └── platform/
│       └── platform_channel.dart      # Native communication
│
├── features/
│   ├── auth/
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   └── parent_model.dart
│   │   │   ├── datasources/
│   │   │   │   ├── auth_remote_datasource.dart
│   │   │   │   └── auth_local_datasource.dart
│   │   │   └── repositories/
│   │   │       └── auth_repository_impl.dart
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── parent.dart
│   │   │   ├── repositories/
│   │   │   │   └── auth_repository.dart
│   │   │   └── usecases/
│   │   │       ├── send_otp.dart
│   │   │       ├── verify_otp.dart
│   │   │       └── sign_out.dart
│   │   └── presentation/
│   │       ├── bloc/
│   │       │   ├── auth_bloc.dart
│   │       │   ├── auth_event.dart
│   │       │   └── auth_state.dart
│   │       ├── screens/
│   │       │   ├── login_screen.dart
│   │       │   └── otp_screen.dart
│   │       └── widgets/
│   │           ├── phone_input.dart
│   │           └── otp_input.dart
│   │
│   ├── children/
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   ├── child_model.dart
│   │   │   │   ├── policy_model.dart
│   │   │   │   └── schedule_model.dart
│   │   │   ├── datasources/
│   │   │   │   └── children_remote_datasource.dart
│   │   │   └── repositories/
│   │   │       └── children_repository_impl.dart
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   ├── child.dart
│   │   │   │   ├── policy.dart
│   │   │   │   └── schedule.dart
│   │   │   ├── repositories/
│   │   │   │   └── children_repository.dart
│   │   │   └── usecases/
│   │   │       ├── add_child.dart
│   │   │       ├── get_children.dart
│   │   │       ├── update_child.dart
│   │   │       └── delete_child.dart
│   │   └── presentation/
│   │       ├── bloc/
│   │       │   ├── children_bloc.dart
│   │       │   ├── children_event.dart
│   │       │   └── children_state.dart
│   │       ├── screens/
│   │       │   ├── dashboard_screen.dart
│   │       │   ├── add_child_screen.dart
│   │       │   ├── child_detail_screen.dart
│   │       │   └── schedule_editor_screen.dart
│   │       └── widgets/
│   │           ├── child_card.dart
│   │           ├── status_indicator.dart
│   │           └── schedule_card.dart
│   │
│   ├── blocking/
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   └── category_model.dart
│   │   │   ├── datasources/
│   │   │   │   ├── blocklist_local_datasource.dart
│   │   │   │   └── nextdns_remote_datasource.dart
│   │   │   └── repositories/
│   │   │       └── blocking_repository_impl.dart
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── category.dart
│   │   │   ├── repositories/
│   │   │   │   └── blocking_repository.dart
│   │   │   └── usecases/
│   │   │       ├── toggle_category.dart
│   │   │       ├── add_custom_domain.dart
│   │   │       └── sync_blocklist.dart
│   │   └── presentation/
│   │       ├── bloc/
│   │       │   ├── blocking_bloc.dart
│   │       │   ├── blocking_event.dart
│   │       │   └── blocking_state.dart
│   │       └── screens/
│   │           └── category_blocking_screen.dart
│   │
│   ├── requests/
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   └── request_model.dart
│   │   │   ├── datasources/
│   │   │   │   └── requests_remote_datasource.dart
│   │   │   └── repositories/
│   │   │       └── requests_repository_impl.dart
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── override_request.dart
│   │   │   ├── repositories/
│   │   │   │   └── requests_repository.dart
│   │   │   └── usecases/
│   │   │       ├── create_request.dart
│   │   │       ├── approve_request.dart
│   │   │       ├── deny_request.dart
│   │   │       └── listen_to_requests.dart
│   │   └── presentation/
│   │       ├── bloc/
│   │       │   ├── requests_bloc.dart
│   │       │   ├── requests_event.dart
│   │       │   └── requests_state.dart
│   │       ├── screens/
│   │       │   ├── request_approval_screen.dart
│   │       │   ├── request_access_screen.dart
│   │       │   └── request_status_screen.dart
│   │       └── widgets/
│   │           └── request_card.dart
│   │
│   ├── reports/
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   └── usage_report_model.dart
│   │   │   ├── datasources/
│   │   │   │   └── reports_remote_datasource.dart
│   │   │   └── repositories/
│   │   │       └── reports_repository_impl.dart
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── usage_report.dart
│   │   │   ├── repositories/
│   │   │   │   └── reports_repository.dart
│   │   │   └── usecases/
│   │   │       ├── get_daily_report.dart
│   │   │       └── get_weekly_trend.dart
│   │   └── presentation/
│   │       ├── bloc/
│   │       │   ├── reports_bloc.dart
│   │       │   ├── reports_event.dart
│   │       │   └── reports_state.dart
│   │       ├── screens/
│   │       │   └── usage_reports_screen.dart
│   │       └── widgets/
│   │           ├── donut_chart.dart
│   │           └── line_chart.dart
│   │
│   └── vpn/
│       ├── data/
│       │   ├── datasources/
│       │   │   └── vpn_platform_datasource.dart
│       │   └── repositories/
│       │       └── vpn_repository_impl.dart
│       ├── domain/
│       │   ├── repositories/
│       │   │   └── vpn_repository.dart
│       │   └── usecases/
│       │       ├── start_vpn.dart
│       │       ├── stop_vpn.dart
│       │       └── check_vpn_status.dart
│       └── presentation/
│           └── bloc/
│               ├── vpn_bloc.dart
│               ├── vpn_event.dart
│               └── vpn_state.dart
│
└── shared/
    ├── widgets/
    │   ├── glass_card.dart
    │   ├── glass_button.dart
    │   ├── spring_button.dart
    │   ├── status_indicator.dart
    │   └── loading_skeleton.dart
    └── animations/
        ├── spring_animation.dart
        ├── slide_transition.dart
        └── fade_scale_transition.dart
```

### Key Dependencies (pubspec.yaml)

```yaml
name: trustbridge
description: Privacy-first parental controls for Android
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  
  # Firebase
  firebase_core: ^2.24.2
  firebase_auth: ^4.15.3
  cloud_firestore: ^4.13.6
  firebase_messaging: ^14.7.9
  firebase_analytics: ^10.7.4
  
  # State Management
  flutter_bloc: ^8.1.3
  equatable: ^2.0.5
  hydrated_bloc: ^9.1.2
  
  # Navigation
  go_router: ^13.0.0
  
  # HTTP & API
  http: ^1.1.2
  dio: ^5.4.0
  
  # Local Storage
  shared_preferences: ^2.2.2
  sqflite: ^2.3.0
  path: ^1.8.3
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  
  # Encryption
  flutter_secure_storage: ^9.0.0
  encrypt: ^5.0.3
  
  # Utilities
  intl: ^0.18.1
  uuid: ^4.2.2
  connectivity_plus: ^5.0.2
  package_info_plus: ^5.0.1
  
  # UI & Animations
  fl_chart: ^0.65.0
  shimmer: ^3.0.0
  flutter_animate: ^4.5.0
  lottie: ^3.0.0
  cached_network_image: ^3.3.1
  
  # Platform Integration
  url_launcher: ^6.2.2
  share_plus: ^7.2.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.1
  bloc_test: ^9.1.5
  mocktail: ^1.0.1
  integration_test:
    sdk: flutter
```

---

## State Management (BLoC)

### Why BLoC?

- ✅ Clean separation of business logic from UI
- ✅ Easy to test (pure Dart classes)
- ✅ Reactive programming with streams
- ✅ Well-documented and widely adopted
- ✅ Perfect for real-time updates (Firestore)

### BLoC Pattern Structure

```
Event → BLoC → State
  ↑              ↓
  └──────────────┘
   (User Input)  (UI Update)
```

### Example: Children BLoC

**children_event.dart**

```dart
abstract class ChildrenEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadChildren extends ChildrenEvent {}

class AddChild extends ChildrenEvent {
  final String nickname;
  final AgeBand ageBand;
  
  AddChild(this.nickname, this.ageBand);
  
  @override
  List<Object?> get props => [nickname, ageBand];
}

class UpdateChildPolicy extends ChildrenEvent {
  final String childId;
  final Policy policy;
  
  UpdateChildPolicy(this.childId, this.policy);
  
  @override
  List<Object?> get props => [childId, policy];
}

class DeleteChild extends ChildrenEvent {
  final String childId;
  
  DeleteChild(this.childId);
  
  @override
  List<Object?> get props => [childId];
}
```

**children_state.dart**

```dart
abstract class ChildrenState extends Equatable {
  @override
  List<Object?> get props => [];
}

class ChildrenInitial extends ChildrenState {}

class ChildrenLoading extends ChildrenState {}

class ChildrenLoaded extends ChildrenState {
  final List<Child> children;
  
  ChildrenLoaded(this.children);
  
  @override
  List<Object?> get props => [children];
}

class ChildrenError extends ChildrenState {
  final String message;
  
  ChildrenError(this.message);
  
  @override
  List<Object?> get props => [message];
}
```

**children_bloc.dart**

```dart
class ChildrenBloc extends Bloc<ChildrenEvent, ChildrenState> {
  final GetChildren getChildren;
  final AddChildUseCase addChild;
  final UpdateChildUseCase updateChild;
  final DeleteChildUseCase deleteChild;
  
  StreamSubscription? _childrenSubscription;
  
  ChildrenBloc({
    required this.getChildren,
    required this.addChild,
    required this.updateChild,
    required this.deleteChild,
  }) : super(ChildrenInitial()) {
    on<LoadChildren>(_onLoadChildren);
    on<AddChild>(_onAddChild);
    on<UpdateChildPolicy>(_onUpdateChildPolicy);
    on<DeleteChild>(_onDeleteChild);
  }
  
  Future<void> _onLoadChildren(
    LoadChildren event,
    Emitter<ChildrenState> emit,
  ) async {
    emit(ChildrenLoading());
    
    // Listen to real-time updates from Firestore
    _childrenSubscription?.cancel();
    _childrenSubscription = getChildren().listen(
      (children) => emit(ChildrenLoaded(children)),
      onError: (error) => emit(ChildrenError(error.toString())),
    );
  }
  
  Future<void> _onAddChild(
    AddChild event,
    Emitter<ChildrenState> emit,
  ) async {
    try {
      await addChild(
        nickname: event.nickname,
        ageBand: event.ageBand,
      );
      // State updates automatically via stream
    } catch (e) {
      emit(ChildrenError(e.toString()));
    }
  }
  
  Future<void> _onUpdateChildPolicy(
    UpdateChildPolicy event,
    Emitter<ChildrenState> emit,
  ) async {
    try {
      await updateChild(
        childId: event.childId,
        policy: event.policy,
      );
    } catch (e) {
      emit(ChildrenError(e.toString()));
    }
  }
  
  Future<void> _onDeleteChild(
    DeleteChild event,
    Emitter<ChildrenState> emit,
  ) async {
    try {
      await deleteChild(childId: event.childId);
    } catch (e) {
      emit(ChildrenError(e.toString()));
    }
  }
  
  @override
  Future<void> close() {
    _childrenSubscription?.cancel();
    return super.close();
  }
}
```

### Using BLoC in UI

```dart
class DashboardScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ChildrenBloc(
        getChildren: context.read<GetChildren>(),
        addChild: context.read<AddChildUseCase>(),
        updateChild: context.read<UpdateChildUseCase>(),
        deleteChild: context.read<DeleteChildUseCase>(),
      )..add(LoadChildren()),
      child: BlocBuilder<ChildrenBloc, ChildrenState>(
        builder: (context, state) {
          if (state is ChildrenLoading) {
            return LoadingSkeleton();
          } else if (state is ChildrenLoaded) {
            return ChildrenGrid(children: state.children);
          } else if (state is ChildrenError) {
            return ErrorMessage(message: state.message);
          }
          return SizedBox();
        },
      ),
    );
  }
}
```

---

## Firebase Backend Architecture

### Firestore Database Schema

#### Collection: parents

```javascript
parents/{parentId}
{
  parentId: string,
  phone: string,
  createdAt: timestamp,
  subscription: {
    tier: 'free' | 'premium' | 'family',
    validUntil: timestamp | null,
    autoRenew: boolean
  },
  preferences: {
    language: 'en' | 'hi',
    timezone: string
  },
  fcmToken: string  // For push notifications
}
```

#### Collection: children

```javascript
children/{childId}
{
  childId: string,
  parentId: string,  // Index for queries
  nickname: string,
  ageBand: '6-9' | '10-13' | '14-17',
  deviceIds: string[],
  policy: {
    blockedCategories: string[],
    blockedDomains: string[],
    allowedDomains: string[],
    schedules: [
      {
        id: string,
        name: string,
        type: 'bedtime' | 'school' | 'homework' | 'custom',
        days: string[],  // ['monday', 'tuesday', ...]
        startTime: string,  // 'HH:MM'
        endTime: string,
        enabled: boolean,
        action: 'blockAll' | 'blockDistracting'
      }
    ],
    activeQuickMode: 'homework' | 'bedtime' | 'free' | null,
    safeSearchEnabled: boolean,
    youtubeRestrictedMode: boolean
  },
  nextDnsSettings: {
    profileId: string | null,
    enabled: boolean,
    lastSyncedAt: timestamp | null
  },
  createdAt: timestamp,
  updatedAt: timestamp
}
```

#### Collection: devices

```javascript
devices/{deviceId}
{
  deviceId: string,  // UUID
  childId: string,  // Index
  name: string,
  platform: 'android',
  osVersion: string,
  appVersion: string,
  vpnStatus: 'active' | 'inactive' | 'error',
  lastSeen: timestamp,
  capabilities: {
    hasVpnService: boolean,
    hasUsageStats: boolean,
    hasDeviceAdmin: boolean
  }
}
```

#### Collection: override_requests

```javascript
override_requests/{requestId}
{
  requestId: string,
  childId: string,  // Index
  parentId: string,  // Index
  deviceId: string,
  target: {
    type: 'app' | 'category' | 'domain',
    identifier: string,  // App package, category name, or domain
    displayName: string
  },
  durationMinutes: number,
  reason: string | null,
  status: 'pending' | 'approved' | 'denied' | 'expired',
  requestedAt: timestamp,
  respondedAt: timestamp | null,
  expiresAt: timestamp | null,  // For approved requests
  parentResponse: string | null
}
```

#### Subcollection: usage_reports

```javascript
children/{childId}/usage_reports/{date}  // date format: YYYY-MM-DD
{
  date: string,  // YYYY-MM-DD
  totalMinutes: number,
  minutesByCategory: {
    'social-networks': number,
    'games': number,
    'streaming': number,
    'education': number,
    'other': number
  },
  minutesByApp: {
    'com.instagram.android': number,
    'com.whatsapp': number,
    // ...
  },
  blockedAttempts: {
    total: number,
    byCategory: {
      'social-networks': number,
      // ...
    },
    byApp: {
      'com.instagram.android': number,
      // ...
    }
  },
  syncedAt: timestamp
}
```

#### Collection: blocklists (shared)

```javascript
blocklists/{category}
{
  category: string,  // 'social-networks', 'games', etc.
  domains: string[],  // ['instagram.com', 'facebook.com', ...]
  version: number,
  updatedAt: timestamp
}
```

### Firestore Indexes

Create these composite indexes for optimal query performance:

```javascript
// Index 1: Query children by parent
Collection: children
Fields: parentId (Ascending), createdAt (Descending)

// Index 2: Query requests by parent
Collection: override_requests
Fields: parentId (Ascending), status (Ascending), requestedAt (Descending)

// Index 3: Query requests by child
Collection: override_requests
Fields: childId (Ascending), status (Ascending), requestedAt (Descending)

// Index 4: Query devices by child
Collection: devices
Fields: childId (Ascending), lastSeen (Descending)
```

### Firestore Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper functions
    function isAuthenticated() {
      return request.auth != null;
    }
    
    function isParent(parentId) {
      return isAuthenticated() && request.auth.uid == parentId;
    }
    
    function isChildOwner(childId) {
      return isAuthenticated() && 
        exists(/databases/$(database)/documents/children/$(childId)) &&
        get(/databases/$(database)/documents/children/$(childId)).data.parentId == request.auth.uid;
    }
    
    function isDeviceOwner(deviceId) {
      let device = get(/databases/$(database)/documents/devices/$(deviceId)).data;
      return isChildOwner(device.childId);
    }
    
    // Parents collection
    match /parents/{parentId} {
      allow read, write: if isParent(parentId);
    }
    
    // Children collection
    match /children/{childId} {
      allow read, write: if isChildOwner(childId);
      
      // Usage reports subcollection
      match /usage_reports/{date} {
        allow read: if isChildOwner(childId);
        allow write: if isChildOwner(childId);
      }
    }
    
    // Devices collection
    match /devices/{deviceId} {
      allow read: if isDeviceOwner(deviceId);
      allow write: if isAuthenticated();  // Device can update own status
    }
    
    // Override requests
    match /override_requests/{requestId} {
      // Parents can read their requests
      allow read: if isAuthenticated() && 
        (resource.data.parentId == request.auth.uid || 
         isChildOwner(resource.data.childId));
      
      // Children (via device) can create requests
      allow create: if isAuthenticated();
      
      // Parents can update (approve/deny)
      allow update: if isParent(resource.data.parentId) &&
        request.resource.data.status in ['approved', 'denied'] &&
        resource.data.status == 'pending';
    }
    
    // Blocklists (read-only for all authenticated users)
    match /blocklists/{category} {
      allow read: if isAuthenticated();
      allow write: if false;  // Admin only (via Cloud Functions)
    }
  }
}
```

### Firebase Cloud Functions

```javascript
// functions/index.js

const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

// 1. Send FCM notification when child creates request
exports.onRequestCreated = functions.firestore
  .document('override_requests/{requestId}')
  .onCreate(async (snap, context) => {
    const request = snap.data();
    
    // Get parent's FCM token
    const parentDoc = await admin.firestore()
      .collection('parents')
      .doc(request.parentId)
      .get();
    
    const fcmToken = parentDoc.data().fcmToken;
    if (!fcmToken) return;
    
    // Get child info
    const childDoc = await admin.firestore()
      .collection('children')
      .doc(request.childId)
      .get();
    
    const childName = childDoc.data().nickname;
    
    // Send notification
    await admin.messaging().send({
      token: fcmToken,
      notification: {
        title: `${childName} needs permission`,
        body: `Wants access to ${request.target.displayName}`,
      },
      data: {
        type: 'request',
        requestId: context.params.requestId,
        childId: request.childId
      },
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'requests'
        }
      }
    });
  });

// 2. Auto-expire approved requests
exports.expireRequests = functions.pubsub
  .schedule('every 5 minutes')
  .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();
    
    const expiredRequests = await admin.firestore()
      .collection('override_requests')
      .where('status', '==', 'approved')
      .where('expiresAt', '<=', now)
      .get();
    
    const batch = admin.firestore().batch();
    
    expiredRequests.docs.forEach(doc => {
      batch.update(doc.ref, { status: 'expired' });
    });
    
    await batch.commit();
    
    return null;
  });

// 3. Update blocklists daily (from curated sources)
exports.updateBlocklists = functions.pubsub
  .schedule('every 24 hours')
  .onRun(async (context) => {
    // Fetch updated blocklists from trusted sources
    // Update Firestore blocklists collection
    // Increment version number
    return null;
  });

// 4. Clean up old usage reports (30-day retention)
exports.cleanupOldReports = functions.pubsub
  .schedule('every 24 hours')
  .onRun(async (context) => {
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    
    const cutoffDate = thirtyDaysAgo.toISOString().split('T')[0];
    
    // Query all children
    const childrenSnapshot = await admin.firestore()
      .collection('children')
      .get();
    
    const batch = admin.firestore().batch();
    let count = 0;
    
    for (const childDoc of childrenSnapshot.docs) {
      const reportsSnapshot = await childDoc.ref
        .collection('usage_reports')
        .where('date', '<', cutoffDate)
        .get();
      
      reportsSnapshot.docs.forEach(doc => {
        batch.delete(doc.ref);
        count++;
        
        // Firestore batch limit is 500
        if (count >= 500) {
          batch.commit();
          batch = admin.firestore().batch();
          count = 0;
        }
      });
    }
    
    if (count > 0) {
      await batch.commit();
    }
    
    return null;
  });

// 5. Send notification when request is approved/denied
exports.onRequestUpdated = functions.firestore
  .document('override_requests/{requestId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    
    // Only trigger if status changed from pending
    if (before.status !== 'pending' || after.status === 'pending') {
      return;
    }
    
    // Get device's FCM token (child device)
    const deviceDoc = await admin.firestore()
      .collection('devices')
      .doc(after.deviceId)
      .get();
    
    const fcmToken = deviceDoc.data().fcmToken;
    if (!fcmToken) return;
    
    const isApproved = after.status === 'approved';
    
    await admin.messaging().send({
      token: fcmToken,
      notification: {
        title: isApproved ? 'Request Approved!' : 'Request Denied',
        body: isApproved 
          ? `You can access ${after.target.displayName} now`
          : after.parentResponse || 'Your parent denied the request',
      },
      data: {
        type: 'request_response',
        requestId: context.params.requestId,
        status: after.status
      },
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'request_responses'
        }
      }
    });
  });
```

---

## Android VPN Service Architecture

### Native Android Structure

```
android/app/src/main/kotlin/com/trustbridge/app/
├── MainActivity.kt                    # Flutter integration
├── vpn/
│   ├── TrustBridgeVpnService.kt      # Main VPN service
│   ├── VpnStateManager.kt            # State management
│   ├── dns/
│   │   ├── DnsResolver.kt            # DNS query handler
│   │   ├── DnsPacketParser.kt        # Parse DNS packets
│   │   └── BlocklistManager.kt       # Local blocklist cache
│   ├── scheduler/
│   │   ├── ScheduleManager.kt        # Schedule enforcement
│   │   ├── AlarmReceiver.kt          # Alarm broadcast receiver
│   │   └── TimeUtils.kt              # Time calculations
│   └── monitor/
│       ├── UsageMonitor.kt           # Track app usage
│       ├── BypassDetector.kt         # Detect bypass attempts
│       └── NetworkMonitor.kt         # Network state changes
├── plugins/
│   └── VpnPlugin.kt                  # Flutter↔Native bridge
├── database/
│   ├── BlocklistDatabase.kt          # SQLite database
│   ├── BlocklistDao.kt               # Database access object
│   └── entities/
│       └── BlockedDomain.kt          # Entity class
└── utils/
    ├── NotificationHelper.kt         # Persistent notification
    └── PreferencesHelper.kt          # Encrypted preferences
```

### VPN Service Flow

```
┌──────────────────────────────────────────────────────┐
│              TrustBridgeVpnService                    │
├──────────────────────────────────────────────────────┤
│                                                       │
│  1. onCreate()                                        │
│     ├─ Load blocklists from SQLite                   │
│     ├─ Initialize DNS resolver                       │
│     ├─ Set up notification channel                   │
│     └─ Register network callbacks                    │
│                                                       │
│  2. onStartCommand(START)                            │
│     ├─ Request VPN permission (if needed)            │
│     ├─ Build VPN interface:                          │
│     │  ├─ Address: 10.0.0.2/32                       │
│     │  ├─ Route: 0.0.0.0/0 (all traffic)             │
│     │  ├─ DNS: 1.1.1.1 (or NextDNS)                  │
│     │  └─ Disallow self (bypass own traffic)         │
│     ├─ Establish VPN connection                      │
│     ├─ Start foreground with notification            │
│     └─ Start DNS filtering thread                    │
│                                                       │
│  3. DNS Filtering Loop (Background Thread)           │
│     ┌──────────────────────────────────┐            │
│     │  while (isRunning) {              │            │
│     │    1. Read packet from VPN        │            │
│     │    2. Parse DNS query             │            │
│     │    3. Extract domain               │            │
│     │    4. Check against blocklist      │            │
│     │    5. If blocked:                  │            │
│     │       └─ Return NXDOMAIN          │            │
│     │    6. Else:                        │            │
│     │       └─ Forward to upstream DNS  │            │
│     │    7. Write response to VPN       │            │
│     │    8. Log blocked attempts        │            │
│     │  }                                 │            │
│     └──────────────────────────────────┘            │
│                                                       │
│  4. Schedule Enforcement                             │
│     ├─ Listen for schedule changes (Firestore)       │
│     ├─ Set alarms for schedule start/end             │
│     ├─ On schedule active:                           │
│     │  └─ Update active blocklist                    │
│     └─ Send notification to child device             │
│                                                       │
│  5. onDestroy()                                      │
│     ├─ Close VPN interface                           │
│     ├─ Stop DNS thread                               │
│     ├─ Cancel alarms                                 │
│     └─ Clean up resources                            │
│                                                       │
└──────────────────────────────────────────────────────┘
```

### Key Kotlin Implementation

**TrustBridgeVpnService.kt**

```kotlin
package com.trustbridge.app.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import com.trustbridge.app.MainActivity
import com.trustbridge.app.vpn.dns.DnsResolver
import com.trustbridge.app.vpn.dns.BlocklistManager
import com.trustbridge.app.vpn.scheduler.ScheduleManager
import java.io.FileInputStream
import java.io.FileOutputStream

class TrustBridgeVpnService : VpnService() {
    
    private var vpnInterface: ParcelFileDescriptor? = null
    private var dnsThread: Thread? = null
    private var isRunning = false
    
    private lateinit var blocklistManager: BlocklistManager
    private lateinit var scheduleManager: ScheduleManager
    private lateinit var dnsResolver: DnsResolver
    
    companion object {
        const val NOTIFICATION_ID = 1001
        const val CHANNEL_ID = "vpn_channel"
        const val ACTION_START = "START"
        const val ACTION_STOP = "STOP"
        const val ACTION_UPDATE_POLICY = "UPDATE_POLICY"
    }
    
    override fun onCreate() {
        super.onCreate()
        blocklistManager = BlocklistManager(this)
        scheduleManager = ScheduleManager(this)
        dnsResolver = DnsResolver(blocklistManager)
        createNotificationChannel()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startVpn()
            ACTION_STOP -> stopVpn()
            ACTION_UPDATE_POLICY -> updatePolicy()
        }
        return START_STICKY
    }
    
    private fun startVpn() {
        if (isRunning) return
        
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
        
        // Build VPN interface
        val builder = Builder()
        builder.setSession("TrustBridge")
        builder.addAddress("10.0.0.2", 32)
        builder.addRoute("0.0.0.0", 0)
        builder.addDnsServer(getDnsServer())
        builder.setBlocking(false)
        
        // Disallow our own app to prevent loops
        try {
            builder.addDisallowedApplication(packageName)
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        vpnInterface = builder.establish()
        isRunning = true
        
        // Start DNS filtering thread
        startDnsFiltering()
        
        // Sync policy from Firestore
        syncPolicy()
    }
    
    private fun startDnsFiltering() {
        dnsThread = Thread {
            val inputStream = FileInputStream(vpnInterface!!.fileDescriptor)
            val outputStream = FileOutputStream(vpnInterface!!.fileDescriptor)
            val buffer = ByteArray(32767)
            
            while (isRunning && !Thread.currentThread().isInterrupted) {
                try {
                    val length = inputStream.read(buffer)
                    if (length > 0) {
                        val packet = buffer.copyOf(length)
                        handlePacket(packet, outputStream)
                    }
                } catch (e: Exception) {
                    if (isRunning) {
                        e.printStackTrace()
                    }
                    break
                }
            }
        }.apply { 
            priority = Thread.MAX_PRIORITY
            start() 
        }
    }
    
    private fun handlePacket(packet: ByteArray, output: FileOutputStream) {
        try {
            val response = dnsResolver.handleDnsQuery(packet)
            output.write(response)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
    
    private fun getDnsServer(): String {
        // TODO: Get from preferences (1.1.1.1 or NextDNS)
        return "1.1.1.1"
    }
    
    private fun syncPolicy() {
        // TODO: Sync blocklist from Firestore
        // Listen to child policy changes
        // Update BlocklistManager
    }
    
    private fun updatePolicy() {
        // Reload blocklist from database
        blocklistManager.reloadBlocklist()
    }
    
    private fun stopVpn() {
        isRunning = false
        dnsThread?.interrupt()
        vpnInterface?.close()
        vpnInterface = null
        stopForeground(true)
        stopSelf()
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Parental Controls",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "Keeps parental controls active"
            channel.setShowBadge(false)
            
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Protection Active")
            .setContentText("TrustBridge is protecting this device")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
    
    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }
}
```

**BlocklistManager.kt**

```kotlin
package com.trustbridge.app.vpn.dns

import android.content.Context
import com.trustbridge.app.database.BlocklistDatabase
import kotlinx.coroutines.*

class BlocklistManager(private val context: Context) {
    
    private val db: BlocklistDatabase = BlocklistDatabase.getInstance(context)
    private val cache: MutableSet<String> = mutableSetOf()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    init {
        loadBlocklistToCache()
    }
    
    fun isBlocked(domain: String): Boolean {
        // Check exact match
        if (cache.contains(domain)) return true
        
        // Check wildcard (*.example.com)
        val parts = domain.split(".")
        for (i in parts.indices) {
            val wildcard = "*." + parts.subList(i, parts.size).joinToString(".")
            if (cache.contains(wildcard)) return true
        }
        
        return false
    }
    
    fun reloadBlocklist() {
        scope.launch {
            loadBlocklistToCache()
        }
    }
    
    suspend fun updateBlocklist(categories: List<String>) {
        withContext(Dispatchers.IO) {
            // Fetch from Firestore
            val domains = fetchDomainsForCategories(categories)
            
            // Update local database
            db.blocklistDao().deleteAll()
            db.blocklistDao().insertAll(domains)
            
            // Reload cache
            loadBlocklistToCache()
        }
    }
    
    private fun loadBlocklistToCache() {
        scope.launch {
            cache.clear()
            val domains = db.blocklistDao().getAllDomains()
            cache.addAll(domains)
        }
    }
    
    private suspend fun fetchDomainsForCategories(categories: List<String>): List<String> {
        // TODO: Fetch from Firestore blocklists collection
        return emptyList()
    }
    
    fun close() {
        scope.cancel()
    }
}
```

**DnsResolver.kt**

```kotlin
package com.trustbridge.app.vpn.dns

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

class DnsResolver(private val blocklistManager: BlocklistManager) {
    
    private val upstreamDns = InetAddress.getByName("1.1.1.1")
    private val socket = DatagramSocket()
    
    fun handleDnsQuery(packet: ByteArray): ByteArray {
        try {
            val query = DnsPacketParser.parse(packet) ?: return packet
            val domain = query.domain
            
            // Check if blocked
            if (blocklistManager.isBlocked(domain)) {
                // Log blocked attempt
                logBlockedAttempt(domain)
                
                // Return NXDOMAIN response
                return DnsPacketParser.createNxDomainResponse(query)
            }
            
            // Forward to upstream DNS
            return forwardToUpstream(packet)
            
        } catch (e: Exception) {
            e.printStackTrace()
            return packet
        }
    }
    
    private fun forwardToUpstream(packet: ByteArray): ByteArray {
        val sendPacket = DatagramPacket(packet, packet.size, upstreamDns, 53)
        socket.send(sendPacket)
        
        val receiveBuffer = ByteArray(512)
        val receivePacket = DatagramPacket(receiveBuffer, receiveBuffer.size)
        socket.soTimeout = 5000  // 5 second timeout
        socket.receive(receivePacket)
        
        return receivePacket.data.copyOf(receivePacket.length)
    }
    
    private fun logBlockedAttempt(domain: String) {
        // TODO: Log to local database for usage reports
        // Aggregate by domain and category
    }
    
    fun close() {
        socket.close()
    }
}
```

**VpnPlugin.kt** (Flutter ↔ Native Bridge)

```kotlin
package com.trustbridge.app.plugins

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import com.trustbridge.app.vpn.TrustBridgeVpnService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class VpnPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    
    override fun onAttachedToFlutterEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.trustbridge/vpn")
        channel.setMethodCallHandler(this)
        context = binding.applicationContext
    }
    
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startVpn" -> {
                val intent = VpnService.prepare(context)
                if (intent != null) {
                    result.error("PERMISSION_REQUIRED", "VPN permission needed", null)
                } else {
                    startVpnService()
                    result.success(true)
                }
            }
            "stopVpn" -> {
                stopVpnService()
                result.success(true)
            }
            "checkVpnStatus" -> {
                // TODO: Check if VPN is running
                result.success(true)
            }
            "updatePolicy" -> {
                updatePolicy()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }
    
    private fun startVpnService() {
        val intent = Intent(context, TrustBridgeVpnService::class.java)
        intent.action = TrustBridgeVpnService.ACTION_START
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }
    
    private fun stopVpnService() {
        val intent = Intent(context, TrustBridgeVpnService::class.java)
        intent.action = TrustBridgeVpnService.ACTION_STOP
        context.startService(intent)
    }
    
    private fun updatePolicy() {
        val intent = Intent(context, TrustBridgeVpnService::class.java)
        intent.action = TrustBridgeVpnService.ACTION_UPDATE_POLICY
        context.startService(intent)
    }
    
    override fun onDetachedFromFlutterEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
```

### AndroidManifest.xml Configuration

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.trustbridge.app">
    
    <!-- Permissions -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.PACKAGE_USAGE_STATS" 
        tools:ignore="ProtectedPermissions" />
    <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"
        tools:ignore="QueryAllPackagesPermission" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
    
    <application
        android:label="TrustBridge"
        android:icon="@mipmap/ic_launcher">
        
        <!-- VPN Service -->
        <service
            android:name=".vpn.TrustBridgeVpnService"
            android:permission="android.permission.BIND_VPN_SERVICE"
            android:exported="true">
            <intent-filter>
                <action android:name="android.net.VpnService" />
            </intent-filter>
        </service>
        
        <!-- Alarm Receiver for Schedules -->
        <receiver
            android:name=".vpn.scheduler.AlarmReceiver"
            android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
            </intent-filter>
        </receiver>
        
        <!-- Main Activity -->
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
```

---

## Data Flow Diagrams

### 1. Request-Approve Flow

```
┌─────────────┐                                    ┌─────────────┐
│ Child App   │                                    │ Parent App  │
│ (Device)    │                                    │ (Phone)     │
└──────┬──────┘                                    └──────┬──────┘
       │                                                  │
       │ 1. Child taps Request Access                    │
       │                                                  │
       │ 2. Create request in Firestore                  │
       ├─────────────────────────────────────────────────►
       │    override_requests/{requestId}                │
       │    status: 'pending'                            │
       │                                                  │
       │                                                  │ 3. Firestore 
       │                                                  │    triggers FCM
       │                                                  │
       │                                                  ◄────────────
       │                                                  │ 4. Push 
       │                                                  │    notification
       │                                                  │
       │                                                  │ 5. Parent opens
       │                                                  │    approval modal
       │                                                  │
       │                                                  │ 6. Parent approves
       │                                                  │
       │ 7. Firestore updates request                    │
       ◄─────────────────────────────────────────────────┤
       │    status: 'approved'                           │
       │    expiresAt: now + duration                    │
       │                                                  │
       │ 8. Child app receives update                    │
       │    (Firestore listener)                         │
       │                                                  │
       │ 9. VPN service updates rules                    │
       │    (adds temporary exception)                   │
       │                                                  │
       │ 10. Child can access app                        │
       │     (for specified duration)                    │
       │                                                  │
       │ 11. After expiration:                           │
       │     Cloud Function sets status: 'expired'       │
       │     VPN removes exception                       │
       │                                                  │
```

### 2. Schedule Enforcement Flow

```
┌─────────────────────────────────────────────────────────┐
│                  Schedule Enforcement                    │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  1. Parent creates/updates schedule in app              │
│     └─► Firestore: children/{childId}                   │
│                                                          │
│  2. Child device listens to policy changes              │
│     └─► Firestore snapshot listener                     │
│                                                          │
│  3. ScheduleManager calculates next trigger             │
│     ├─► Get current schedule                            │
│     ├─► Calculate time until start/end                  │
│     └─► Set AlarmManager alarm                          │
│                                                          │
│  4. When alarm fires (schedule starts):                 │
│     ├─► AlarmReceiver broadcasts intent                 │
│     ├─► VPN service receives broadcast                  │
│     ├─► BlocklistManager updates active rules           │
│     ├─► Show notification to child                      │
│     └─► Set alarm for schedule end                      │
│                                                          │
│  5. DNS filtering uses updated rules                    │
│     └─► Blocks additional categories during schedule    │
│                                                          │
│  6. When alarm fires (schedule ends):                   │
│     ├─► Restore default policy                          │
│     ├─► Show notification                               │
│     └─► Calculate next schedule trigger                 │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### 3. DNS Filtering Flow

```
┌────────────────────────────────────────────────────┐
│              DNS Query Processing                   │
├────────────────────────────────────────────────────┤
│                                                     │
│  App Request (e.g., instagram.com)                 │
│         │                                           │
│         ▼                                           │
│  ┌────────────────┐                                │
│  │  VPN Interface │                                │
│  │  (Intercepts)  │                                │
│  └────────┬───────┘                                │
│           │                                         │
│           ▼                                         │
│  ┌─────────────────────┐                           │
│  │  DnsPacketParser    │                           │
│  │  Parse DNS query    │                           │
│  │  Extract domain     │                           │
│  └────────┬────────────┘                           │
│           │                                         │
│           ▼                                         │
│  ┌─────────────────────┐                           │
│  │  BlocklistManager   │                           │
│  │  Check if blocked   │                           │
│  └────────┬────────────┘                           │
│           │                                         │
│      ┌────┴────┐                                   │
│      │         │                                    │
│   BLOCKED   ALLOWED                                │
│      │         │                                    │
│      ▼         ▼                                    │
│  ┌──────┐  ┌──────────────┐                       │
│  │NXDOM │  │ Forward to   │                       │
│  │ AIN  │  │ Upstream DNS │                       │
│  │      │  │ (1.1.1.1)    │                       │
│  └──┬───┘  └──────┬───────┘                       │
│     │             │                                 │
│     │             ▼                                 │
│     │      Get IP address                          │
│     │             │                                 │
│     └─────┬───────┘                                │
│           │                                         │
│           ▼                                         │
│  Return response to app                            │
│           │                                         │
│      ┌────┴─────┐                                  │
│      │          │                                   │
│   BLOCKED   CONNECTED                              │
│   (Shows     (Works                                │
│   overlay)   normally)                             │
│                                                     │
└────────────────────────────────────────────────────┘
```

---

## Security Architecture

### Data Security Layers

```
┌──────────────────────────────────────────────────────┐
│                  Security Layers                      │
├──────────────────────────────────────────────────────┤
│                                                       │
│  1. Transport Security                                │
│     ├─► HTTPS/TLS for all API calls                  │
│     ├─► WSS for Firestore real-time                  │
│     └─► Certificate pinning (optional)               │
│                                                       │
│  2. Authentication                                    │
│     ├─► Firebase Auth (phone OTP)                    │
│     ├─► JWT tokens auto-refreshed                    │
│     └─► Secure token storage (EncryptedSharedPrefs)  │
│                                                       │
│  3. Authorization                                     │
│     ├─► Firestore Security Rules                     │
│     ├─► Parent can only access own children          │
│     └─► Device can only update own status            │
│                                                       │
│  4. Data Encryption                                   │
│     ├─► At rest: Firestore encryption (default)      │
│     ├─► Local: EncryptedSharedPreferences            │
│     └─► Sensitive fields: AES-256 encryption         │
│                                                       │
│  5. Privacy Compliance                                │
│     ├─► No PII in logs                               │
│     ├─► Aggregate data only in usage reports         │
│     ├─► 30-day data retention                        │
│     └─► GDPR/DPDP compliant                          │
│                                                       │
└──────────────────────────────────────────────────────┘
```

### Bypass Prevention Mechanisms

```
1. VPN Disable Detection:
   - Monitor VPN state changes using NetworkCallback
   - Alert parent immediately via FCM
   - Show warning banner to child
   - Grace period: 5 minutes to re-enable
   - Persistent notification reminder

2. Private DNS Detection:
   - Check system DNS settings on app launch
   - Detect DNS-over-TLS (DoT) configuration
   - Alert parent if DNS settings changed
   - Show instructions to child on how to fix
   - Cannot enforce (Android limitation)

3. Time Manipulation:
   - Use server time (Firestore timestamp) for all scheduling
   - Validate schedule triggers against server time
   - Detect system time changes (>5 minutes difference)
   - Alert parent if time manipulation detected
   - Recalculate schedules based on server time

4. App Uninstall Protection:
   - Request Device Admin privileges (optional)
   - Require parent PIN to uninstall if Device Admin
   - Alert parent on uninstall attempt
   - Factory reset detection (best effort)
   - Re-enable on reboot

5. VPN Killswitch (System-Level):
   - Recommend parent enables "Always-on VPN" in Android settings
   - Block connections without VPN (Android 8+)
   - System-level enforcement (most secure)
   - Survives app crashes/force stops
```

### Threat Model

| Threat | Mitigation | Residual Risk |
|--------|-----------|---------------|
| Child disables VPN | Detection + parent alert + grace period | Medium - Child can still disable temporarily |
| Child uninstalls app | Device Admin + parent PIN | Low-Medium - Factory reset possible |
| Child uses another device | No technical solution | High - Requires parent supervision |
| Child changes system DNS | Detection + alert + instructions | Medium - Cannot enforce on Android |
| Child manipulates time | Server-time validation + detection | Low - Well mitigated |
| Child uses VPN/Proxy | Not easily detectable | High - Advanced bypass |
| Parent account compromised | OTP + optional 2FA | Low - Standard security |

---

## Performance Optimization

### App Performance Targets

```
Flutter App:
- Cold start: <2 seconds
- Hot reload: <500ms
- Frame rate: 60fps minimum (120fps on capable devices)
- Memory usage: <100MB for parent app, <50MB for child app
- APK size: <30MB (after compression)

VPN Service:
- DNS latency: <50ms average
- Battery drain: <5% per day
- Memory usage: <50MB
- CPU usage: <2% when idle, <10% during active filtering
```

### Optimization Strategies

**1. Flutter App Optimizations:**

```dart
// Use const constructors wherever possible
const ChildCard({
  required this.child,
  required this.onTap,
});

// Lazy load screens
final router = GoRouter(
  routes: [
    GoRoute(
      path: '/child-detail/:id',
      builder: (context, state) {
        final childId = state.pathParameters['id']!;
        return ChildDetailScreen(childId: childId);
      },
    ),
  ],
);

// Optimize list rendering
ListView.builder(
  itemCount: children.length,
  itemBuilder: (context, index) {
    return ChildCard(child: children[index]);
  },
);

// Cache network images
CachedNetworkImage(
  imageUrl: avatarUrl,
  placeholder: (context, url) => CircularProgressIndicator(),
  errorWidget: (context, url, error) => Icon(Icons.error),
  memCacheWidth: 200,
  memCacheHeight: 200,
);

// State persistence
HydratedBloc.storage = await HydratedStorage.build(
  storageDirectory: await getApplicationDocumentsDirectory(),
);
```

**2. Firestore Optimizations:**

```dart
// Enable offline persistence
FirebaseFirestore.instance.settings = Settings(
  persistenceEnabled: true,
  cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
);

// Use pagination for large lists
Query query = FirebaseFirestore.instance
  .collection('children')
  .where('parentId', isEqualTo: parentId)
  .orderBy('createdAt', descending: true)
  .limit(20);

// Batch writes for multiple updates
WriteBatch batch = FirebaseFirestore.instance.batch();
batch.update(childRef, {'policy.activeQuickMode': 'homework'});
batch.update(deviceRef, {'lastSeen': FieldValue.serverTimestamp()});
await batch.commit();

// Use transactions for critical updates
await FirebaseFirestore.instance.runTransaction((transaction) async {
  DocumentSnapshot request = await transaction.get(requestRef);
  if (request.get('status') == 'pending') {
    transaction.update(requestRef, {
      'status': 'approved',
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }
});
```

**3. VPN Service Optimizations:**

```kotlin
// Use NIO for efficient packet handling
val channel = FileChannel.open(
    vpnInterface.fileDescriptor,
    StandardOpenOption.READ, StandardOpenOption.WRITE
)

// Connection pooling for upstream DNS
val connectionPool = Executor.newFixedThreadPool(4)

// Cache DNS responses (5 min TTL)
private val dnsCache = LruCache<String, ByteArray>(100)

// Async logging to avoid blocking
private val logExecutor = Executors.newSingleThreadExecutor()
fun logBlockedAttempt(domain: String) {
    logExecutor.execute {
        database.blockLogDao().insert(BlockLog(domain, System.currentTimeMillis()))
    }
}

// Minimize allocations in hot path
private val packetBuffer = ByteArray(32767)
private val responseBuffer = ByteArray(512)
```

**4. Battery Optimizations:**

```kotlin
// Use efficient I/O
val inputStream = FileInputStream(vpnInterface.fileDescriptor)
val outputStream = FileOutputStream(vpnInterface.fileDescriptor)

// Minimize wakelocks
val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
val wakeLock = powerManager.newWakeLock(
    PowerManager.PARTIAL_WAKE_LOCK,
    "TrustBridge::VpnWakeLock"
)
wakeLock.setReferenceCounted(false)

// Batch network operations
val pendingLogs = mutableListOf<BlockLog>()
if (pendingLogs.size >= 50 || lastSyncTime > 5.minutes.ago) {
    syncLogsToFirestore(pendingLogs)
    pendingLogs.clear()
}

// Respect battery saver mode
if (powerManager.isPowerSaveMode) {
    // Reduce sync frequency
    syncInterval = 15.minutes
}

// Use WorkManager for background tasks
val syncWorkRequest = PeriodicWorkRequestBuilder<SyncWorker>(
    15, TimeUnit.MINUTES
).setConstraints(
    Constraints.Builder()
        .setRequiredNetworkType(NetworkType.CONNECTED)
        .setRequiresBatteryNotLow(true)
        .build()
).build()
```

---

## Testing Strategy

### Test Pyramid

```
┌─────────────────────────────────────────┐
│                                          │
│            E2E Tests (5%)                │
│         ┌─────────────────┐             │
│         │   Full flows    │             │
│         └─────────────────┘             │
│                                          │
│          Integration Tests (15%)         │
│       ┌───────────────────────┐         │
│       │  Feature + Firebase   │         │
│       └───────────────────────┘         │
│                                          │
│           Widget Tests (30%)             │
│     ┌─────────────────────────────┐    │
│     │  UI + User Interactions     │    │
│     └─────────────────────────────┘    │
│                                          │
│            Unit Tests (50%)              │
│  ┌───────────────────────────────────┐ │
│  │ Business Logic + Data + Utils     │ │
│  └───────────────────────────────────┘ │
│                                          │
└─────────────────────────────────────────┘
```

### Unit Tests (Dart)

```dart
// test/features/children/domain/usecases/add_child_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockChildrenRepository extends Mock implements ChildrenRepository {}

void main() {
  late AddChildUseCase useCase;
  late MockChildrenRepository mockRepository;

  setUp(() {
    mockRepository = MockChildrenRepository();
    useCase = AddChildUseCase(mockRepository);
  });

  group('AddChildUseCase', () {
    test('should add child with correct preset policy', () async {
      // Arrange
      const nickname = 'Aarav';
      const ageBand = AgeBand.young;
      
      when(() => mockRepository.addChild(
        nickname: nickname,
        ageBand: ageBand,
      )).thenAnswer((_) async => Right(unit));
      
      // Act
      final result = await useCase(
        nickname: nickname,
        ageBand: ageBand,
      );
      
      // Assert
      expect(result, Right(unit));
      verify(() => mockRepository.addChild(
        nickname: nickname,
        ageBand: ageBand,
      )).called(1);
    });
    
    test('should return failure when repository fails', () async {
      // Arrange
      when(() => mockRepository.addChild(
        nickname: any(named: 'nickname'),
        ageBand: any(named: 'ageBand'),
      )).thenAnswer((_) async => Left(ServerFailure()));
      
      // Act
      final result = await useCase(
        nickname: 'Aarav',
        ageBand: AgeBand.young,
      );
      
      // Assert
      expect(result, Left(ServerFailure()));
    });
  });
}
```

### Widget Tests

```dart
// test/features/children/presentation/widgets/child_card_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ChildCard displays child information correctly', 
    (WidgetTester tester) async {
    // Arrange
    final child = Child(
      id: '1',
      nickname: 'Aarav',
      ageBand: AgeBand.young,
      status: ChildStatus.freeTime,
      screenTimeToday: Duration(hours: 2, minutes: 15),
    );
    
    // Act
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChildCard(child: child, onTap: () {}),
        ),
      ),
    );
    
    // Assert
    expect(find.text('Aarav'), findsOneWidget);
    expect(find.text('2h 15m today'), findsOneWidget);
    expect(find.byIcon(Icons.circle), findsOneWidget);  // Status indicator
  });

  testWidgets('ChildCard triggers onTap when pressed', 
    (WidgetTester tester) async {
    // Arrange
    bool tapped = false;
    final child = Child(
      id: '1',
      nickname: 'Aarav',
      ageBand: AgeBand.young,
    );
    
    // Act
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChildCard(
            child: child,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );
    
    await tester.tap(find.byType(ChildCard));
    
    // Assert
    expect(tapped, true);
  });
}
```

### Integration Tests

```dart
// integration_test/request_approve_flow_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Request-Approve Flow', () {
    testWidgets('complete request-approve workflow', 
      (WidgetTester tester) async {
      // Start app
      await tester.pumpWidget(MyApp());
      await tester.pumpAndSettle();
      
      // Login as parent
      await tester.enterText(find.byType(TextField), '+919876543210');
      await tester.tap(find.text('Send OTP'));
      await tester.pumpAndSettle();
      
      // Enter OTP
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      
      // Navigate to child detail
      await tester.tap(find.byType(ChildCard).first);
      await tester.pumpAndSettle();
      
      // Simulate child request (trigger from test backend)
      await simulateChildRequest();
      await tester.pumpAndSettle();
      
      // Verify notification appears
      expect(find.text('Access Request'), findsOneWidget);
      
      // Tap notification
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      
      // Verify approval modal
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Deny'), findsOneWidget);
      
      // Approve request
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      
      // Verify success
      expect(find.text('Request Approved'), findsOneWidget);
    });
  });
}
```

### Native Tests (Kotlin)

```kotlin
// android/app/src/test/kotlin/com/trustbridge/app/vpn/BlocklistManagerTest.kt

import org.junit.Before
import org.junit.Test
import org.junit.Assert.*

class BlocklistManagerTest {
    
    private lateinit var blocklistManager: BlocklistManager
    
    @Before
    fun setup() {
        val context = InstrumentationRegistry.getInstrumentation().context
        blocklistManager = BlocklistManager(context)
    }
    
    @Test
    fun `isBlocked returns true for exact match`() {
        // Given
        blocklistManager.addDomain("instagram.com")
        
        // When
        val result = blocklistManager.isBlocked("instagram.com")
        
        // Then
        assertTrue(result)
    }
    
    @Test
    fun `isBlocked returns true for wildcard match`() {
        // Given
        blocklistManager.addDomain("*.facebook.com")
        
        // When
        val result = blocklistManager.isBlocked("m.facebook.com")
        
        // Then
        assertTrue(result)
    }
    
    @Test
    fun `isBlocked returns false for non-blocked domain`() {
        // Given
        blocklistManager.addDomain("instagram.com")
        
        // When
        val result = blocklistManager.isBlocked("google.com")
        
        // Then
        assertFalse(result)
    }
}
```

---

## Development Roadmap

### 12-Week Implementation Plan

#### **Week 1-2: Foundation**
- [ ] Day 1-2: Project setup (Flutter + Firebase + Git)
- [ ] Day 3-4: Authentication (Phone OTP)
- [ ] Day 5-6: Parent profile creation
- [ ] Day 7-10: Basic UI screens (Login, Dashboard shell)
- [ ] Day 11-12: Theme implementation (iOS-Motion Hybrid)
- [ ] Day 13-14: Navigation setup (go_router)

**Milestone**: User can sign up and see empty dashboard

#### **Week 3-4: Child Management**
- [ ] Day 15-17: Child data models & repositories
- [ ] Day 18-20: Add child flow (UI + logic)
- [ ] Day 21-23: Age-based preset policies
- [ ] Day 24-26: Child detail screen
- [ ] Day 27-28: Edit/delete child functionality

**Milestone**: Parent can manage children with preset policies

#### **Week 5-6: Android VPN Service**
- [ ] Day 29-31: VPN service setup (Kotlin)
- [ ] Day 32-34: DNS packet parsing
- [ ] Day 35-37: Blocklist manager (SQLite)
- [ ] Day 38-40: Flutter ↔ Native bridge
- [ ] Day 41-42: VPN permission flow

**Milestone**: VPN service can start and block basic domains

#### **Week 7-8: Blocking & Filtering**
- [ ] Day 43-45: Category blocking UI
- [ ] Day 46-48: Custom domain blocking
- [ ] Day 49-51: Blocklist sync from Firestore
- [ ] Day 52-54: NextDNS integration (optional)
- [ ] Day 55-56: Blocked overlay screen (child app)

**Milestone**: Complete blocking system works end-to-end

#### **Week 9-10: Schedules & Enforcement**
- [ ] Day 57-59: Schedule data models
- [ ] Day 60-62: Schedule editor UI
- [ ] Day 63-65: AlarmManager integration
- [ ] Day 66-68: Schedule enforcement logic
- [ ] Day 69-70: Quick modes (Homework, Bedtime, Free)

**Milestone**: Schedules trigger automatically and enforce policies

#### **Week 11-12: Request-Approve Flow**
- [ ] Day 71-73: Request creation (child app)
- [ ] Day 74-76: FCM push notifications
- [ ] Day 77-79: Approval modal (parent app)
- [ ] Day 80-82: Temporary exception handling
- [ ] Day 83-84: Request expiration

**Milestone**: Complete request-approve workflow functions

#### **Week 13-14: Usage Reports**
- [ ] Day 85-87: UsageStatsManager integration
- [ ] Day 88-90: Usage data aggregation
- [ ] Day 91-93: Charts (donut, line)
- [ ] Day 94-96: Reports screen UI
- [ ] Day 97-98: Blocked attempts logging

**Milestone**: Parents can view usage reports

#### **Week 15-16: Bypass Detection**
- [ ] Day 99-101: VPN disable detection
- [ ] Day 102-104: Private DNS detection
- [ ] Day 105-107: Time manipulation detection
- [ ] Day 108-110: Parent alert system
- [ ] Day 111-112: Child warning banners

**Milestone**: Bypass attempts are detected and reported

#### **Week 17-18: Polish & Testing**
- [ ] Day 113-115: UI/UX polish (animations, loading states)
- [ ] Day 116-118: Error handling & edge cases
- [ ] Day 119-121: Unit tests (80% coverage)
- [ ] Day 122-124: Integration tests
- [ ] Day 125-126: Performance optimization

**Milestone**: App is stable and production-ready

#### **Week 19-20: Compliance & Launch**
- [ ] Day 127-129: Privacy policy & terms
- [ ] Day 130-132: Play Store listing (screenshots, description)
- [ ] Day 133-135: Beta testing (10 families)
- [ ] Day 136-138: Bug fixes from beta
- [ ] Day 139-140: Submit to Play Store

**Milestone**: App submitted to Play Store for review

---

## Next Steps

You now have:
1. ✅ **Product Requirements** (PRODUCT_REQUIREMENTS_DOCUMENT.md)
2. ✅ **Designs** (iOS-quality from Stitch)
3. ✅ **Complete Architecture** (This document)

**Ready to start building!**

### Immediate Actions:

1. **Set up development environment:**
   ```bash
   flutter doctor
   flutter create trustbridge
   ```

2. **Initialize Firebase project:**
   - Create Firebase project
   - Add Android app
   - Download google-services.json

3. **Create Git repository:**
   ```bash
   git init
   git add .
   git commit -m "Initial commit - TrustBridge architecture"
   ```

4. **Start with Week 1 Day 1:**
   - Implement authentication flow
   - Set up project structure
   - Create base theme

---

## Appendix: Key Resources

### Documentation
- [Flutter Docs](https://flutter.dev/docs)
- [Firebase for Flutter](https://firebase.google.com/docs/flutter/setup)
- [BLoC Pattern](https://bloclibrary.dev/)
- [Android VpnService](https://developer.android.com/reference/android/net/VpnService)
- [Material Design 3](https://m3.material.io/)

### Tools
- [FlutterFire CLI](https://firebase.google.com/docs/flutter/setup)
- [Firebase Console](https://console.firebase.google.com/)
- [Android Studio](https://developer.android.com/studio)
- [VS Code](https://code.visualstudio.com/)

### Community
- [Flutter Discord](https://discord.gg/flutter)
- [r/FlutterDev](https://reddit.com/r/FlutterDev)
- [Stack Overflow - Flutter](https://stackoverflow.com/questions/tagged/flutter)

---

**Document Version:** 1.0  
**Last Updated:** February 15, 2026  
**Status:** Ready for Implementation

---
