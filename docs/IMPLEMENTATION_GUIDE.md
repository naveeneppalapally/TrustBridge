# Implementation Guide - Build Your App Step by Step

This guide shows you exactly HOW to build each feature with complete code examples.

---

## WEEK 1-2: PROJECT SETUP & AUTHENTICATION

### Day 1: Create Flutter Project

```bash
# Create project
flutter create parental_controls_app
cd parental_controls_app

# Test it runs
flutter run
```

### Day 2: Add Dependencies

Edit `pubspec.yaml`:

```yaml
name: parental_controls_app
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
  
  # State Management
  provider: ^6.1.1
  
  # HTTP & API
  http: ^1.1.2
  
  # Local Storage
  shared_preferences: ^2.2.2
  sqflite: ^2.3.0
  path: ^1.8.3
  
  # Utilities
  intl: ^0.18.1
  uuid: ^4.2.2
  
  # UI
  fl_chart: ^0.65.0
  shimmer: ^3.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.1
```

Run:
```bash
flutter pub get
```

### Day 3: Firebase Setup

**1. Create Firebase Project:**
- Go to https://console.firebase.google.com
- Click "Add Project"
- Name: "ParentalControlsApp"
- Disable Google Analytics (for now)

**2. Add Android App:**
- Click "Add App" → Android
- Package name: `com.yourcompany.parentalcontrols`
- Download `google-services.json`
- Place in: `android/app/google-services.json`

**3. Configure Android:**

Edit `android/build.gradle`:
```gradle
buildscript {
    dependencies {
        classpath 'com.google.gms:google-services:4.4.0'
    }
}
```

Edit `android/app/build.gradle`:
```gradle
plugins {
    id 'com.android.application'
    id 'kotlin-android'
    id 'com.google.gms.google-services'  // Add this
}

android {
    defaultConfig {
        applicationId "com.yourcompany.parentalcontrols"
        minSdkVersion 24  // Important: Android 7+
        targetSdkVersion 33
    }
}

dependencies {
    implementation platform('com.google.firebase:firebase-bom:32.7.0')
    implementation 'com.google.firebase:firebase-analytics'
}
```

**4. Initialize Firebase:**

Edit `lib/main.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parental Controls',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: SplashScreen(),
    );
  }
}

class SplashScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield, size: 100, color: Colors.blue),
            SizedBox(height: 20),
            Text(
              'ParentalShield',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
```

Run and test:
```bash
flutter run
```

### Day 4-5: Authentication Service

Create `lib/services/auth_service.dart`:

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  String? _verificationId;
  
  // Get current user
  User? get currentUser => _auth.currentUser;
  
  // Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  
  // Send OTP
  Future<bool> sendOTP(String phoneNumber) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-verification (Android only)
          await _auth.signInWithCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          throw e.message ?? 'Verification failed';
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
      return true;
    } catch (e) {
      print('Error sending OTP: $e');
      return false;
    }
  }
  
  // Verify OTP
  Future<User?> verifyOTP(String otp) async {
    try {
      if (_verificationId == null) {
        throw 'Verification ID is null';
      }
      
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );
      
      UserCredential userCredential = await _auth.signInWithCredential(credential);
      
      // Create parent profile if new user
      if (userCredential.additionalUserInfo?.isNewUser ?? false) {
        await _createParentProfile(userCredential.user!);
      }
      
      return userCredential.user;
    } catch (e) {
      print('Error verifying OTP: $e');
      return null;
    }
  }
  
  // Create parent profile in Firestore
  Future<void> _createParentProfile(User user) async {
    await _firestore.collection('parents').doc(user.uid).set({
      'parentId': user.uid,
      'phone': user.phoneNumber,
      'createdAt': FieldValue.serverTimestamp(),
      'subscription': {
        'tier': 'free',
        'validUntil': null,
      }
    });
  }
  
  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
```

### Day 6: Login Screen

Create `lib/screens/auth/login_screen.dart`:

```dart
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  
  bool _otpSent = false;
  bool _isLoading = false;
  String? _errorMessage;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Icon(Icons.shield, size: 100, color: Colors.blue),
              SizedBox(height: 20),
              
              Text(
                'ParentalShield',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              
              Text(
                'Screen time made simple & private',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
              SizedBox(height: 50),
              
              // Phone Number Input
              if (!_otpSent) ...[
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    hintText: '+91-XXXXXXXXXX',
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                    errorText: _errorMessage,
                  ),
                ),
                SizedBox(height: 20),
                
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _sendOTP,
                    child: _isLoading
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text('Get OTP'),
                  ),
                ),
              ],
              
              // OTP Input
              if (_otpSent) ...[
                Text(
                  'Enter OTP sent to ${_phoneController.text}',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 20),
                
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: 'OTP',
                    hintText: '000000',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                    errorText: _errorMessage,
                  ),
                ),
                SizedBox(height: 20),
                
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOTP,
                    child: _isLoading
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text('Verify OTP'),
                  ),
                ),
                SizedBox(height: 10),
                
                TextButton(
                  onPressed: () {
                    setState(() {
                      _otpSent = false;
                      _errorMessage = null;
                    });
                  },
                  child: Text('Change Number'),
                ),
              ],
              
              SizedBox(height: 30),
              
              Text(
                'By signing up, you agree to our Terms & Privacy Policy',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Future<void> _sendOTP() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    String phone = _phoneController.text.trim();
    
    // Validate phone number
    if (!phone.startsWith('+')) {
      phone = '+91$phone'; // Default to India
    }
    
    bool success = await _authService.sendOTP(phone);
    
    setState(() {
      _isLoading = false;
      if (success) {
        _otpSent = true;
      } else {
        _errorMessage = 'Failed to send OTP. Try again.';
      }
    });
  }
  
  Future<void> _verifyOTP() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    String otp = _otpController.text.trim();
    
    var user = await _authService.verifyOTP(otp);
    
    setState(() {
      _isLoading = false;
    });
    
    if (user != null) {
      // Navigate to dashboard
      Navigator.pushReplacementNamed(context, '/dashboard');
    } else {
      setState(() {
        _errorMessage = 'Invalid OTP. Try again.';
      });
    }
  }
  
  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }
}
```

---

## WEEK 3-4: CHILD MANAGEMENT & DASHBOARD

### Create Data Models

Create `lib/models/child_profile.dart`:

```dart
class ChildProfile {
  final String childId;
  final String parentId;
  final String nickname;
  final AgeBand ageBand;
  final List<String> deviceIds;
  final String currentPolicyId;
  final DateTime createdAt;
  
  ChildProfile({
    required this.childId,
    required this.parentId,
    required this.nickname,
    required this.ageBand,
    required this.deviceIds,
    required this.currentPolicyId,
    required this.createdAt,
  });
  
  factory ChildProfile.fromFirestore(Map<String, dynamic> data) {
    return ChildProfile(
      childId: data['childId'],
      parentId: data['parentId'],
      nickname: data['nickname'],
      ageBand: AgeBand.values.firstWhere(
        (e) => e.toString() == 'AgeBand.${data['ageBand']}',
      ),
      deviceIds: List<String>.from(data['devices'] ?? []),
      currentPolicyId: data['currentPolicy'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }
  
  Map<String, dynamic> toFirestore() {
    return {
      'childId': childId,
      'parentId': parentId,
      'nickname': nickname,
      'ageBand': ageBand.name,
      'devices': deviceIds,
      'currentPolicy': currentPolicyId,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

enum AgeBand {
  young,    // 6-9
  middle,   // 10-13
  teen,     // 14-17
}

extension AgeBandExtension on AgeBand {
  String get displayName {
    switch (this) {
      case AgeBand.young:
        return '6-9 years';
      case AgeBand.middle:
        return '10-13 years';
      case AgeBand.teen:
        return '14-17 years';
    }
  }
}
```

### Firestore Service

Create `lib/services/firestore_service.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/child_profile.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Get children for parent
  Stream<List<ChildProfile>> getChildren(String parentId) {
    return _firestore
        .collection('children')
        .where('parentId', isEqualTo: parentId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ChildProfile.fromFirestore(doc.data()))
            .toList());
  }
  
  // Add child
  Future<String> addChild(ChildProfile child) async {
    DocumentReference ref = await _firestore.collection('children').add(child.toFirestore());
    return ref.id;
  }
  
  // Update child
  Future<void> updateChild(String childId, Map<String, dynamic> updates) async {
    await _firestore.collection('children').doc(childId).update(updates);
  }
  
  // Delete child
  Future<void> deleteChild(String childId) async {
    await _firestore.collection('children').doc(childId).delete();
  }
  
  // Get single child
  Future<ChildProfile?> getChild(String childId) async {
    DocumentSnapshot doc = await _firestore.collection('children').doc(childId).get();
    if (doc.exists) {
      return ChildProfile.fromFirestore(doc.data() as Map<String, dynamic>);
    }
    return null;
  }
}
```

### Dashboard Screen

Create `lib/screens/parent/dashboard_screen.dart`:

```dart
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../models/child_profile.dart';

class DashboardScreen extends StatelessWidget {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  
  @override
  Widget build(BuildContext context) {
    String parentId = _authService.currentUser!.uid;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('ParentalShield'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
      body: StreamBuilder<List<ChildProfile>>(
        stream: _firestoreService.getChildren(parentId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          
          List<ChildProfile> children = snapshot.data ?? [];
          
          if (children.isEmpty) {
            return _buildEmptyState(context);
          }
          
          return ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: children.length,
            itemBuilder: (context, index) {
              return ChildCard(child: children[index]);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.pushNamed(context, '/add-child');
        },
        icon: Icon(Icons.add),
        label: Text('Add Child'),
      ),
    );
  }
  
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.family_restroom, size: 100, color: Colors.grey),
          SizedBox(height: 20),
          Text(
            'No children added yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 10),
          Text(
            'Tap the button below to add your first child',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class ChildCard extends StatelessWidget {
  final ChildProfile child;
  
  ChildCard({required this.child});
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            '/child-detail',
            arguments: child.childId,
          );
        },
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    child: Text(child.nickname[0].toUpperCase()),
                    radius: 25,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          child.nickname,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          child.ageBand.displayName,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right),
                ],
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  _buildStatusChip('Protected', Colors.green, Icons.check_circle),
                  SizedBox(width: 8),
                  _buildStatusChip('${child.deviceIds.length} Device(s)', 
                      Colors.blue, Icons.phone_android),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildStatusChip(String label, Color color, IconData icon) {
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      backgroundColor: color.withOpacity(0.1),
      labelStyle: TextStyle(color: color, fontSize: 12),
    );
  }
}
```

---

## WEEK 5-6: ANDROID VPN SERVICE

### Configure AndroidManifest.xml

Edit `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    
    <!-- Permissions -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.PACKAGE_USAGE_STATS" 
        tools:ignore="ProtectedPermissions" />
    <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"
        tools:ignore="QueryAllPackagesPermission" />
    
    <application
        android:label="ParentalShield"
        android:icon="@mipmap/ic_launcher">
        
        <!-- VPN Service -->
        <service
            android:name=".ParentalControlVpnService"
            android:permission="android.permission.BIND_VPN_SERVICE"
            android:exported="true">
            <intent-filter>
                <action android:name="android.net.VpnService" />
            </intent-filter>
        </service>
        
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

### Create VPN Service (Kotlin)

Create `android/app/src/main/kotlin/com/yourcompany/parentalcontrols/ParentalControlVpnService.kt`:

```kotlin
package com.yourcompany.parentalcontrols

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

class ParentalControlVpnService : VpnService() {
    
    private var vpnInterface: ParcelFileDescriptor? = null
    private var isRunning = false
    
    companion object {
        const val NOTIFICATION_ID = 1001
        const val CHANNEL_ID = "vpn_channel"
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "START" -> startVpn()
            "STOP" -> stopVpn()
        }
        return START_STICKY
    }
    
    private fun startVpn() {
        if (isRunning) return
        
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
        
        val builder = Builder()
        builder.setSession("ParentalControls")
        builder.addAddress("10.0.0.2", 32)
        builder.addRoute("0.0.0.0", 0)
        builder.addDnsServer("1.1.1.1")
        builder.setBlocking(false)
        
        try {
            builder.addDisallowedApplication(packageName)
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        vpnInterface = builder.establish()
        isRunning = true
        
        // TODO: Start DNS filtering thread
    }
    
    private fun stopVpn() {
        isRunning = false
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
            .setContentText("Parental controls are enabled")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }
    
    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }
}
```

### Flutter Plugin for VPN Control

Create `android/app/src/main/kotlin/com/yourcompany/parentalcontrols/VpnPlugin.kt`:

```kotlin
package com.yourcompany.parentalcontrols

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class VpnPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    
    override fun onAttachedToFlutterEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "vpn_control")
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
            else -> result.notImplemented()
        }
    }
    
    private fun startVpnService() {
        val intent = Intent(context, ParentalControlVpnService::class.java)
        intent.action = "START"
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }
    
    private fun stopVpnService() {
        val intent = Intent(context, ParentalControlVpnService::class.java)
        intent.action = "STOP"
        context.startService(intent)
    }
    
    override fun onDetachedFromFlutterEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
```

Register plugin in `MainActivity.kt`:

```kotlin
package com.yourcompany.parentalcontrols

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(VpnPlugin())
    }
}
```

### Flutter VPN Service Wrapper

Create `lib/services/vpn_service.dart`:

```dart
import 'package:flutter/services.dart';

class VpnService {
  static const platform = MethodChannel('vpn_control');
  
  Future<bool> startVpn() async {
    try {
      final bool result = await platform.invokeMethod('startVpn');
      return result;
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_REQUIRED') {
        // TODO: Show permission request dialog
        return false;
      }
      throw e;
    }
  }
  
  Future<void> stopVpn() async {
    await platform.invokeMethod('stopVpn');
  }
}
```

---

## TESTING INSTRUCTIONS

### Test Authentication
1. Run app on real Android device
2. Enter phone number
3. Receive and enter OTP
4. Should navigate to dashboard

### Test VPN Service
1. Go to child device setup screen
2. Request VPN permission (system dialog appears)
3. Start VPN
4. Check persistent notification appears
5. Test DNS blocking (try accessing facebook.com)

---

**This is 40% of the implementation. Continue to next sections for:**
- Schedule management
- Request-approve flow
- Usage reporting
- Child app screens
- Play Store submission

Would you like me to continue with the remaining implementation sections?
