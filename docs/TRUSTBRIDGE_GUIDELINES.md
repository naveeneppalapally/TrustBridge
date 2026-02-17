# TrustBridge Guidelines & Standards
## Industry Standards + Custom Design System

**Version:** 1.0  
**Last Updated:** February 16, 2026  
**Project:** TrustBridge - Privacy-First Parental Controls  

---

## 📋 Overview

TrustBridge follows **TWO layers of guidelines**:

### **Layer 1: Industry Standards (Foundation)**
- ✅ Material Design 3 (Google)
- ✅ Flutter Best Practices (Dart)
- ✅ Android Guidelines (Kotlin)
- ✅ Firebase Best Practices
- ✅ OWASP Security Standards

### **Layer 2: Custom Design System (Differentiation)**
- ✅ **iOS-Motion Hybrid Design System** (Custom)
- ✅ Spring physics animations
- ✅ Glass effects (glassmorphism)
- ✅ Premium iOS-quality polish on Android
- ✅ 2026-modern aesthetics

**Result:** TrustBridge looks like **Apple designed it for Android in 2026** 🎨

---

## 🎨 TrustBridge Custom Design System

### **iOS-Motion Hybrid Design System**

**Philosophy:**
```
"Android platform + iOS aesthetic + 2026 trends"
```

**Core Principles:**
1. **Spring physics** on all interactions (no linear animations)
2. **Generous spacing** (breathable, not cramped)
3. **Rounded aesthetics** (16-24dp radius)
4. **Fast transitions** (200-300ms max)
5. **Optimistic UI** (instant feedback)
6. **Strategic blur** (glass effects)
7. **Flat shadows** (minimal elevation)

---

### **Anti-AI-Slop Rules** ⚠️

**❌ NEVER:**
- Purple/blue tech gradients everywhere
- Excessive shadows (drop-shadow overkill)
- Over-rounded corners (>24dp)
- Generic 3D blobs
- Stock illustrations
- Instagram maximalism

**✅ ALWAYS:**
- Clean functional design
- Strategic white space
- Purposeful color
- Real data (not lorem ipsum)
- Subtle tasteful effects
- Professional polish

---

## 🎨 Color System (Custom)

### **Light Theme**
```dart
// Primary Colors
primary: #2196F3 (Trust Blue)
surface: #FFFFFF (pure white)
background: #F8F9FA (light gray, softer than white)

// Text
text: #1A1A1A (dark black)
secondaryText: #6B7280 (medium gray)

// Semantic
success: #10B981 (green)
warning: #F59E0B (amber)
error: #EF4444 (red, not harsh)
info: #3B82F6 (blue)

// Status
activeFree: #10B981 (green)
homework: #F59E0B (amber)
bedtime: #EF4444 (soft red)
offline: #9CA3AF (gray)
```

### **Dark Theme**
```dart
// Primary Colors
primary: #60A5FA (brighter blue for dark bg)
surface: #1F2937 (blue-tinted dark gray)
background: #111827 (very dark blue-gray)

// Text
text: #F9FAFB (near white)
secondaryText: #9CA3AF (light gray)

// Semantic
success: #34D399 (bright green)
warning: #FBBF24 (bright amber)
error: #F87171 (soft bright red)
info: #60A5FA (bright blue)
```

**Contrast Compliance:**
- ✅ Light body text: 17.4:1 (WCAG AAA)
- ✅ Dark body text: 16.8:1 (WCAG AAA)
- ✅ All text meets WCAG AA minimum

---

## 📐 Typography System (Custom)

**Font:** System default (Roboto on Android, SF Pro feel)

```dart
// Type Scale
display: 48sp, weight 700    // Hero numbers, large titles
heading: 28sp, weight 600    // Screen titles
title:   20sp, weight 600    // Section headers, card titles
body:    16sp, weight 400    // Main content
caption: 14sp, weight 400    // Metadata, helper text
label:   14sp, weight 600    // Buttons

// Spacing
lineHeight: 1.4x             // Tighter for modern feel
letterSpacing: -0.01em       // Subtle tracking
```

**Why different from Material Design?**
- Material uses 1.5x line height → we use 1.4x (tighter, more modern)
- Material doesn't use negative tracking → we use -0.01em (premium feel)

---

## 🧱 Component Specs (Custom)

### **Cards (iOS-inspired)**
```dart
// Standard Card
background: Surface color (solid, not glass)
borderRadius: 16dp               // More than Material's 12dp
padding: 20dp                    // More than Material's 16dp
shadow: 0 4px 12px rgba(0,0,0,0.08)  // Very subtle
border: none                     // Clean look

// Hover State (tablet only)
transform: translateY(-4dp) scale(1.02)
shadow: 0 8px 24px rgba(0,0,0,0.12)
transition: 200ms spring         // NOT linear!

// Press State
transform: scale(0.98)
transition: 100ms spring
```

**Material Design equivalent would be:**
- Card with 12dp radius
- 8dp padding
- elevation: 2 (different shadow)

**We override for premium feel** ✨

---

### **Buttons (Tall iOS-style)**
```dart
// Primary Button
height: 50dp                     // Material uses 48dp
borderRadius: 12dp               // Material uses 4-8dp
padding: 24dp horizontal         // Material uses 16dp
background: Solid primary        // No gradient!
text: 17sp, weight 600           // Material uses 14sp

// Press Animation
scale: 0.96                      // Spring physics
duration: 100ms spring           // NOT linear ease!
```

**Why taller?**
- iOS standard is 50dp
- Feels more premium
- Better for one-handed use

---

### **Glass Effects (Strategic Use)** 💎

**Apply ONLY to:**
- ✓ Bottom sheets (modals)
- ✓ Navigation bars
- ✓ Floating action buttons
- ✓ Status indicator cards
- ✓ Request approval overlays

**NOT for:**
- ❌ Regular cards
- ❌ List items
- ❌ Form fields
- ❌ Static content

**Specs:**
```dart
// Light Theme Glass
background: rgba(255,255,255,0.90)
backdropFilter: blur(30px) saturate(180%)
border: 1px solid rgba(255,255,255,0.3)
boxShadow: 0 8px 32px rgba(0,0,0,0.08)

// Dark Theme Glass
background: rgba(31,41,55,0.90)
backdropFilter: blur(30px) saturate(180%)
border: 1px solid rgba(255,255,255,0.1)
boxShadow: 0 8px 32px rgba(0,0,0,0.4)
```

**Package:**
```yaml
dependencies:
  glassmorphism: ^3.0.0
```

---

## 🎭 Animation System (Custom)

### **Spring Physics (iOS-style)**

**Material Design uses:**
- Linear easing
- Standard durations (300ms, 500ms)
- No spring physics

**TrustBridge uses:**
```dart
// Standard Spring
tension: 400
friction: 30
mass: 1

// Bouncy Spring (playful)
tension: 500
friction: 25
mass: 0.8

// Gentle Spring (large elements)
tension: 300
friction: 35
mass: 1.2
```

**Timing Guidelines:**
```dart
microInteractions:   100ms  // Button press
standardTransitions: 200ms  // Card tap, toggle
pageTransitions:     300ms  // Screen changes
modalPresentations:  350ms  // Bottom sheet slide
loadingStates:       150ms  // Skeleton fade in
```

**Package:**
```yaml
dependencies:
  flutter_animate: ^4.5.0
```

**Never use linear easing - always spring or:**
```dart
easeOut: Curves.easeOutBack
easeIn:  Curves.easeIn
```

---

### **Specific Animations**

**Button Press:**
```dart
GestureDetector(
  onTapDown: (_) => scale = 0.96,
  onTapUp: (_) => scale = 1.0,
  onTapCancel: () => scale = 1.0,
  child: AnimatedScale(
    scale: scale,
    duration: Duration(milliseconds: 100),
    curve: Curves.easeOutBack,  // Spring feel
    child: button,
  ),
)
```

**Card Tap:**
```dart
// Lift 4dp + scale 102%
transform: translateY(-4dp) scale(1.02)
duration: 150ms spring
```

**Page Transition:**
```dart
PageRouteBuilder(
  transitionDuration: Duration(milliseconds: 300),
  pageBuilder: (context, animation, secondaryAnimation) => page,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,  // Spring!
      )),
      child: child,
    );
  },
)
```

---

## 📱 Screen Designs (12 Screens)

**TrustBridge has 12 fully-specified screens:**

### **Parent App (8 screens):**
1. Login/Onboarding
2. Dashboard (Child List)
3. Add Child
4. Child Detail
5. Schedule Editor
6. Category Blocking
7. Request Approval Modal
8. Usage Reports

### **Child App (4 screens):**
9. Child Status Screen
10. Request Access Screen
11. Blocked Overlay (Full-Screen)
12. Request Status Screen

**Each screen has:**
- ✅ Mobile layout (1080x2400px portrait)
- ✅ Tablet layout (2560x1600px landscape)
- ✅ Light theme
- ✅ Dark theme
- ✅ Complete component specs
- ✅ Animation specifications

**Total designs:** 12 screens × 2 themes × 2 devices = **48 designs**

---

## 🎯 Design Principles

### **1. Privacy-First Visual Language**
```
Show protection, not surveillance
✅ Shield icons (protection)
❌ Eye icons (watching)

✅ "Paused" language
❌ "Blocked" language

✅ Encouraging tone
❌ Punitive tone
```

### **2. Transparency Through Design**
```
Children always know:
- What's blocked
- Why it's blocked
- When it will be available
- How to request access
```

### **3. Trust-Building Aesthetics**
```
✅ Soft colors (not harsh)
✅ Rounded shapes (friendly)
✅ Generous spacing (breathable)
✅ Clear hierarchy (understandable)
✅ Smooth animations (premium)
```

---

## 🔄 How Standards Work Together

### **Layer 1: Material Design 3 (Foundation)**

**What we USE from Material:**
- ✅ Color system architecture (ColorScheme)
- ✅ Component names (Card, Button, AppBar)
- ✅ Layout grid (4dp base unit)
- ✅ Typography scale concept
- ✅ Accessibility standards (48dp touch targets)
- ✅ Dark/light theme system

**What we OVERRIDE:**
- ⚠️ Border radius (16-24dp vs Material's 12dp)
- ⚠️ Padding (20dp vs Material's 16dp)
- ⚠️ Shadows (custom subtle shadows vs elevation system)
- ⚠️ Animations (spring physics vs linear)
- ⚠️ Button heights (50dp vs 48dp)

### **Layer 2: iOS-Motion Hybrid (Premium Layer)**

**On top of Material, we add:**
- ✅ Spring physics animations
- ✅ Glass effects (glassmorphism)
- ✅ Taller buttons (iOS-style 50dp)
- ✅ More rounded corners (16-24dp)
- ✅ Tighter line heights (1.4x vs 1.5x)
- ✅ Negative letter spacing (-0.01em)

**Example - Compare Button:**

**Material Design 3:**
```dart
ElevatedButton(
  style: ElevatedButton.styleFrom(
    minimumSize: Size(64, 48),      // 48dp height
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),  // 8dp radius
    ),
  ),
  child: Text('Button'),
)
```

**TrustBridge (iOS-Motion Hybrid):**
```dart
ElevatedButton(
  style: ElevatedButton.styleFrom(
    minimumSize: Size(64, 50),      // 50dp height (taller!)
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),  // 12dp radius (rounder!)
    ),
    padding: EdgeInsets.symmetric(horizontal: 24),  // More padding!
  ),
  child: Text(
    'Button',
    style: TextStyle(
      fontSize: 17,       // 17sp (larger!)
      fontWeight: FontWeight.w600,
      letterSpacing: -0.01,  // Tighter!
    ),
  ),
)
```

**Result:** Looks like iOS on Android! ✨

---

## 📦 Required Packages

**Beyond standard Flutter, TrustBridge needs:**

```yaml
dependencies:
  # Standard (all Flutter apps)
  flutter:
    sdk: flutter
  provider: ^6.1.1
  
  # Firebase (backend)
  firebase_core: ^2.24.0
  firebase_auth: ^4.15.0
  cloud_firestore: ^4.13.0
  
  # TrustBridge Custom Design System
  flutter_animate: ^4.5.0      # Spring animations
  glassmorphism: ^3.0.0        # Glass effects
  fl_chart: ^0.65.0            # Custom charts
  flutter_svg: ^2.0.9          # Custom icons
  
  # Material Design 3
  material_color_utilities: ^0.8.0
```

**Why these packages?**
- `flutter_animate` → Spring physics (iOS-style)
- `glassmorphism` → Blur effects (modern 2026)
- `fl_chart` → Custom charts (not Material charts)
- Material charts would look generic ❌

---

## 🎨 Design Tokens (Exported as Code)

**TrustBridge defines design tokens for consistency:**

```dart
// lib/theme/design_tokens.dart

class DesignTokens {
  // Spring Physics
  static const springCurve = Curves.easeOutBack;
  static const springDuration = Duration(milliseconds: 300);
  
  // Glass Effect
  static const glassBlur = 40.0;
  static const glassOpacity = 0.90;
  
  // Border Radius
  static const radiusSmall = 12.0;
  static const radiusMedium = 16.0;
  static const radiusLarge = 20.0;
  static const radiusXLarge = 24.0;
  
  // Spacing
  static const spacingXS = 4.0;
  static const spacingS = 8.0;
  static const spacingM = 12.0;
  static const spacingL = 16.0;
  static const spacingXL = 20.0;
  static const spacingXXL = 24.0;
  static const spacingXXXL = 32.0;
  
  // Button Heights (iOS-style)
  static const buttonHeightPrimary = 50.0;   // iOS standard
  static const buttonHeightSecondary = 44.0;
  
  // Touch Targets
  static const touchTargetMin = 48.0;  // WCAG/iOS/Android standard
}
```

**Usage:**
```dart
// Consistent across entire app
Container(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
  ),
)

AnimatedScale(
  duration: DesignTokens.springDuration,
  curve: DesignTokens.springCurve,
)
```

---

## 🎯 Key Differences Summary

| Aspect | Material Design 3 | TrustBridge (iOS-Motion) |
|--------|------------------|--------------------------|
| **Philosophy** | Functional, standard | Premium, iOS-inspired |
| **Animations** | Linear easing | Spring physics |
| **Border Radius** | 8-12dp | 16-24dp |
| **Button Height** | 48dp | 50dp (iOS) |
| **Padding** | 16dp standard | 20-24dp (generous) |
| **Shadows** | Elevation system | Custom subtle shadows |
| **Glass Effects** | None | Strategic glassmorphism |
| **Line Height** | 1.5x | 1.4x (tighter) |
| **Letter Spacing** | 0 | -0.01em (tighter) |
| **Speed** | 300-500ms | 200-300ms (faster) |

**Result:** TrustBridge feels like a **premium iOS app that runs on Android** 🚀

---

## 📋 Implementation Checklist

When implementing any screen, verify:

### **Standard Guidelines (Foundation):**
- [ ] Material Design 3 components used as base
- [ ] Flutter best practices followed
- [ ] Proper error handling
- [ ] Null safety
- [ ] 48dp touch targets minimum
- [ ] WCAG AA contrast ratios

### **Custom Design System (Premium Layer):**
- [ ] Spring physics on interactions (not linear)
- [ ] 16-24dp border radius (not 8-12dp)
- [ ] 50dp button height (not 48dp)
- [ ] 20-24dp padding (not 16dp)
- [ ] Glass effects only on specified components
- [ ] 200-300ms transitions (not 300-500ms)
- [ ] Tighter line height 1.4x (not 1.5x)
- [ ] Custom color palette (not Material defaults)

### **Privacy & Transparency:**
- [ ] No surveillance aesthetics (eye icons, etc.)
- [ ] Encouraging language (not punitive)
- [ ] Clear explanations visible
- [ ] Trust-building visual language

---

## 🎨 Design File References

**TrustBridge design system document:**
- **File:** `TrustBridge_iOS_Motion_Hybrid_Design_System.md`
- **Location:** Project docs
- **Size:** 916 lines
- **Contains:** Complete specifications for all 12 screens

**Design exports location:**
- **Folder:** `/app_design/`
- **Format:** Figma exports (PNG + HTML code)
- **Naming:** `{screen_name}_{device}_{theme}.png`
- **Example:** `dashboard_mobile_light.png`

**Progress tracking:**
- **File:** `docs/PROGRESS_JOURNAL.md`
- **Purpose:** Track which designs used per commit
- **Format:** `[design: folder_name]` in commit messages

---

## 🎯 Design Decision Framework

When making any design decision, ask:

### **1. Does it follow industry standards?**
- Material Design 3 foundation ✅
- Flutter best practices ✅
- Android guidelines ✅
- Accessibility standards ✅

### **2. Does it match our custom system?**
- iOS-Motion Hybrid principles ✅
- Spring physics animations ✅
- Premium polish ✅
- 2026 modern aesthetics ✅

### **3. Does it support our philosophy?**
- Privacy-first visual language ✅
- Transparency over surveillance ✅
- Trust-building design ✅
- Child-friendly (not punitive) ✅

**If YES to all three → Implement it!** ✨

---

## 📚 Documentation Hierarchy

```
TrustBridge Documentation
│
├── Industry Standards (Generic, applies to all apps)
│   ├── Material Design 3 Guidelines
│   ├── Flutter Best Practices
│   ├── Android Guidelines (Kotlin)
│   ├── Firebase Best Practices
│   └── OWASP Security Standards
│
└── TrustBridge Custom (Specific to this app)
    ├── iOS-Motion Hybrid Design System ⭐
    ├── Design Tokens (code)
    ├── Component Specifications
    ├── Animation Specifications
    ├── Screen Designs (48 total)
    └── Implementation Examples
```

**This document (GUIDELINES.md)** = Bridge between both layers

---

## 🎊 Summary

**TrustBridge uses:**

✅ **Material Design 3** as foundation  
✅ **Flutter best practices** for code  
✅ **Android guidelines** for platform  
✅ **Firebase patterns** for backend  

**PLUS:**

✨ **iOS-Motion Hybrid Design System** for premium feel  
✨ **Spring physics** for smooth animations  
✨ **Glassmorphism** for modern aesthetics  
✨ **Custom specifications** for every screen  

**Result:**  
An Android app that **feels like Apple designed it in 2026** 🚀

---

## 📖 Related Documents

- **STANDARD_GUIDELINES.md** - Industry standards deep dive
- **TRUSTBRIDGE_PRD.md** - Product requirements
- **IMPLEMENTATION_GUIDE.md** - Code examples
- **QUICK_START_CHECKLIST.md** - Day-by-day plan
- **PROGRESS_JOURNAL.md** - Development history

---

**END OF DOCUMENT**

**Questions?** Refer to the iOS-Motion Hybrid Design System document for specific screen layouts, component specs, and animation details.
