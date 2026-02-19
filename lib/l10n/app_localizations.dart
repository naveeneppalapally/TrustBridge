import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'TrustBridge'**
  String get appTitle;

  /// No description provided for @dashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboardTitle;

  /// No description provided for @childrenTitle.
  ///
  /// In en, this message translates to:
  /// **'Children'**
  String get childrenTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @protectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Protection'**
  String get protectionTitle;

  /// No description provided for @addChildButton.
  ///
  /// In en, this message translates to:
  /// **'Add Child'**
  String get addChildButton;

  /// No description provided for @editButton.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editButton;

  /// No description provided for @deleteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteButton;

  /// No description provided for @saveButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveButton;

  /// No description provided for @retryButton.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryButton;

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// No description provided for @welcomeMessage.
  ///
  /// In en, this message translates to:
  /// **'Welcome to TrustBridge'**
  String get welcomeMessage;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set healthy digital boundaries for your family'**
  String get welcomeSubtitle;

  /// No description provided for @childNicknameLabel.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get childNicknameLabel;

  /// No description provided for @childAgeBandLabel.
  ///
  /// In en, this message translates to:
  /// **'Age Band'**
  String get childAgeBandLabel;

  /// No description provided for @youngAgeBand.
  ///
  /// In en, this message translates to:
  /// **'6-9 years'**
  String get youngAgeBand;

  /// No description provided for @middleAgeBand.
  ///
  /// In en, this message translates to:
  /// **'10-13 years'**
  String get middleAgeBand;

  /// No description provided for @teenAgeBand.
  ///
  /// In en, this message translates to:
  /// **'14-17 years'**
  String get teenAgeBand;

  /// No description provided for @vpnProtectionTitle.
  ///
  /// In en, this message translates to:
  /// **'VPN Protection'**
  String get vpnProtectionTitle;

  /// No description provided for @enableProtectionButton.
  ///
  /// In en, this message translates to:
  /// **'Enable Protection'**
  String get enableProtectionButton;

  /// No description provided for @disableProtectionButton.
  ///
  /// In en, this message translates to:
  /// **'Disable Protection'**
  String get disableProtectionButton;

  /// No description provided for @protectionActiveMessage.
  ///
  /// In en, this message translates to:
  /// **'Protection running'**
  String get protectionActiveMessage;

  /// No description provided for @protectionInactiveMessage.
  ///
  /// In en, this message translates to:
  /// **'Ready to start'**
  String get protectionInactiveMessage;

  /// No description provided for @requestAccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Request Access'**
  String get requestAccessTitle;

  /// No description provided for @requestAccessButton.
  ///
  /// In en, this message translates to:
  /// **'Ask for Access'**
  String get requestAccessButton;

  /// No description provided for @appOrSiteLabel.
  ///
  /// In en, this message translates to:
  /// **'App or website'**
  String get appOrSiteLabel;

  /// No description provided for @durationLabel.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get durationLabel;

  /// No description provided for @reasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get reasonLabel;

  /// No description provided for @submitRequestButton.
  ///
  /// In en, this message translates to:
  /// **'Send Request'**
  String get submitRequestButton;

  /// No description provided for @pendingRequestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Pending Requests'**
  String get pendingRequestsTitle;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @approveButton.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approveButton;

  /// No description provided for @denyButton.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get denyButton;

  /// No description provided for @notificationSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationSettingsTitle;

  /// No description provided for @notificationEnabledMessage.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get notificationEnabledMessage;

  /// No description provided for @notificationDisabledMessage.
  ///
  /// In en, this message translates to:
  /// **'Tap to enable'**
  String get notificationDisabledMessage;

  /// No description provided for @languageSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSettingsTitle;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageHindi.
  ///
  /// In en, this message translates to:
  /// **'Hindi (हिंदी)'**
  String get languageHindi;

  /// No description provided for @feedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get feedbackTitle;

  /// No description provided for @analyticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get analyticsTitle;

  /// No description provided for @noChildrenMessage.
  ///
  /// In en, this message translates to:
  /// **'No children yet'**
  String get noChildrenMessage;

  /// No description provided for @noChildrenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add your first child to get started'**
  String get noChildrenSubtitle;

  /// No description provided for @noRequestsMessage.
  ///
  /// In en, this message translates to:
  /// **'No pending requests'**
  String get noRequestsMessage;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorGeneric;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error. Please try again.'**
  String get errorNetwork;

  /// No description provided for @errorPermission.
  ///
  /// In en, this message translates to:
  /// **'Permission denied'**
  String get errorPermission;

  /// No description provided for @durationFifteenMin.
  ///
  /// In en, this message translates to:
  /// **'15 minutes'**
  String get durationFifteenMin;

  /// No description provided for @durationThirtyMin.
  ///
  /// In en, this message translates to:
  /// **'30 minutes'**
  String get durationThirtyMin;

  /// No description provided for @durationOneHour.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get durationOneHour;

  /// No description provided for @durationUntilEnd.
  ///
  /// In en, this message translates to:
  /// **'Until schedule ends'**
  String get durationUntilEnd;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @statusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get statusApproved;

  /// No description provided for @statusDenied.
  ///
  /// In en, this message translates to:
  /// **'Denied'**
  String get statusDenied;

  /// No description provided for @statusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get statusExpired;

  /// No description provided for @notLoggedInMessage.
  ///
  /// In en, this message translates to:
  /// **'Not logged in'**
  String get notLoggedInMessage;

  /// No description provided for @accessRequestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Access Requests'**
  String get accessRequestsTitle;

  /// No description provided for @pendingTabTitle.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pendingTabTitle;

  /// No description provided for @allCaughtUpTitle.
  ///
  /// In en, this message translates to:
  /// **'All caught up!'**
  String get allCaughtUpTitle;

  /// No description provided for @noPendingRequestsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'No pending requests from your children.'**
  String get noPendingRequestsSubtitle;

  /// No description provided for @noHistoryYetTitle.
  ///
  /// In en, this message translates to:
  /// **'No history yet'**
  String get noHistoryYetTitle;

  /// No description provided for @noHistoryYetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Approved and denied requests will appear here.'**
  String get noHistoryYetSubtitle;

  /// No description provided for @wantsAccessToLabel.
  ///
  /// In en, this message translates to:
  /// **'Wants access to'**
  String get wantsAccessToLabel;

  /// No description provided for @addReplyButton.
  ///
  /// In en, this message translates to:
  /// **'Add reply'**
  String get addReplyButton;

  /// No description provided for @cancelReplyButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel reply'**
  String get cancelReplyButton;

  /// No description provided for @requestApprovedMessage.
  ///
  /// In en, this message translates to:
  /// **'Request approved.'**
  String get requestApprovedMessage;

  /// No description provided for @requestDeniedMessage.
  ///
  /// In en, this message translates to:
  /// **'Request denied.'**
  String get requestDeniedMessage;

  /// No description provided for @approvalModalTitle.
  ///
  /// In en, this message translates to:
  /// **'Approve request?'**
  String get approvalModalTitle;

  /// No description provided for @denialModalTitle.
  ///
  /// In en, this message translates to:
  /// **'Deny request?'**
  String get denialModalTitle;

  /// No description provided for @approvalModalSummary.
  ///
  /// In en, this message translates to:
  /// **'{childName} is requesting access to {appOrSite} for {duration}.'**
  String approvalModalSummary(
      Object childName, Object appOrSite, Object duration);

  /// No description provided for @approvalDurationLabel.
  ///
  /// In en, this message translates to:
  /// **'Approve for'**
  String get approvalDurationLabel;

  /// No description provided for @approvalExpiresPreview.
  ///
  /// In en, this message translates to:
  /// **'Access will expire around {time}.'**
  String approvalExpiresPreview(Object time);

  /// No description provided for @approvalUntilSchedulePreview.
  ///
  /// In en, this message translates to:
  /// **'Access stays allowed until schedule ends.'**
  String get approvalUntilSchedulePreview;

  /// No description provided for @quickRepliesLabel.
  ///
  /// In en, this message translates to:
  /// **'Quick replies'**
  String get quickRepliesLabel;

  /// No description provided for @quickReplyApproveStudy.
  ///
  /// In en, this message translates to:
  /// **'Approved for study. Stay focused.'**
  String get quickReplyApproveStudy;

  /// No description provided for @quickReplyApproveTakeBreak.
  ///
  /// In en, this message translates to:
  /// **'Okay for a short break.'**
  String get quickReplyApproveTakeBreak;

  /// No description provided for @quickReplyApproveCareful.
  ///
  /// In en, this message translates to:
  /// **'Approved. Please use it responsibly.'**
  String get quickReplyApproveCareful;

  /// No description provided for @quickReplyDenyNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not right now.'**
  String get quickReplyDenyNotNow;

  /// No description provided for @quickReplyDenyHomework.
  ///
  /// In en, this message translates to:
  /// **'Homework first, then we can revisit.'**
  String get quickReplyDenyHomework;

  /// No description provided for @quickReplyDenyLaterToday.
  ///
  /// In en, this message translates to:
  /// **'Let\'s discuss this later today.'**
  String get quickReplyDenyLaterToday;

  /// No description provided for @parentReplyOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Reply to child (optional)'**
  String get parentReplyOptionalLabel;

  /// No description provided for @keepPendingButton.
  ///
  /// In en, this message translates to:
  /// **'Keep Pending'**
  String get keepPendingButton;

  /// No description provided for @confirmApproveButton.
  ///
  /// In en, this message translates to:
  /// **'Approve Now'**
  String get confirmApproveButton;

  /// No description provided for @confirmDenyButton.
  ///
  /// In en, this message translates to:
  /// **'Deny Now'**
  String get confirmDenyButton;

  /// No description provided for @endAccessNowButton.
  ///
  /// In en, this message translates to:
  /// **'End Access Now'**
  String get endAccessNowButton;

  /// No description provided for @endAccessDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'End access now?'**
  String get endAccessDialogTitle;

  /// No description provided for @endAccessDialogSummary.
  ///
  /// In en, this message translates to:
  /// **'{childName} will lose access to {appOrSite} immediately.'**
  String endAccessDialogSummary(Object childName, Object appOrSite);

  /// No description provided for @accessEndedMessage.
  ///
  /// In en, this message translates to:
  /// **'Access ended.'**
  String get accessEndedMessage;

  /// No description provided for @requestReplyHint.
  ///
  /// In en, this message translates to:
  /// **'Message to {childName}... (optional)'**
  String requestReplyHint(Object childName);

  /// No description provided for @errorWithValue.
  ///
  /// In en, this message translates to:
  /// **'Error: {value}'**
  String errorWithValue(Object value);

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String minutesAgo(int count);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String hoursAgo(int count);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String daysAgo(int count);

  /// No description provided for @ageLabel.
  ///
  /// In en, this message translates to:
  /// **'Age: {ageBand}'**
  String ageLabel(Object ageBand);

  /// No description provided for @pausedLabel.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get pausedLabel;

  /// No description provided for @categoriesBlockedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} categories blocked'**
  String categoriesBlockedCount(int count);

  /// No description provided for @schedulesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} schedules'**
  String schedulesCount(int count);

  /// No description provided for @managedProfilesLabel.
  ///
  /// In en, this message translates to:
  /// **'MANAGED PROFILES'**
  String get managedProfilesLabel;

  /// No description provided for @blockedCategoriesLabel.
  ///
  /// In en, this message translates to:
  /// **'BLOCKED CATEGORIES'**
  String get blockedCategoriesLabel;

  /// No description provided for @schedulesLabel.
  ///
  /// In en, this message translates to:
  /// **'SCHEDULES'**
  String get schedulesLabel;

  /// No description provided for @addChildTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Child'**
  String get addChildTitle;

  /// No description provided for @ageBandGuideTooltip.
  ///
  /// In en, this message translates to:
  /// **'Age Band Guide'**
  String get ageBandGuideTooltip;

  /// No description provided for @addChildHeadline.
  ///
  /// In en, this message translates to:
  /// **'Add a new child profile'**
  String get addChildHeadline;

  /// No description provided for @addChildSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We will set up age-appropriate content filters'**
  String get addChildSubtitle;

  /// No description provided for @nicknameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Alex, Sam, Priya'**
  String get nicknameHint;

  /// No description provided for @nicknameHelper.
  ///
  /// In en, this message translates to:
  /// **'What should we call this child?'**
  String get nicknameHelper;

  /// No description provided for @enterNicknameError.
  ///
  /// In en, this message translates to:
  /// **'Please enter a nickname'**
  String get enterNicknameError;

  /// No description provided for @nicknameMinError.
  ///
  /// In en, this message translates to:
  /// **'Nickname must be at least 2 characters'**
  String get nicknameMinError;

  /// No description provided for @nicknameMaxError.
  ///
  /// In en, this message translates to:
  /// **'Nickname must be less than 20 characters'**
  String get nicknameMaxError;

  /// No description provided for @ageGroupLabel.
  ///
  /// In en, this message translates to:
  /// **'Age Group'**
  String get ageGroupLabel;

  /// No description provided for @whichAgeBandLabel.
  ///
  /// In en, this message translates to:
  /// **'Which age band?'**
  String get whichAgeBandLabel;

  /// No description provided for @ageYoungSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Young children - strictest filters'**
  String get ageYoungSubtitle;

  /// No description provided for @ageMiddleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Middle schoolers - moderate filters'**
  String get ageMiddleSubtitle;

  /// No description provided for @ageTeenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Teenagers - balanced approach'**
  String get ageTeenSubtitle;

  /// No description provided for @whatWillBeBlockedLabel.
  ///
  /// In en, this message translates to:
  /// **'What will be blocked?'**
  String get whatWillBeBlockedLabel;

  /// No description provided for @contentLabel.
  ///
  /// In en, this message translates to:
  /// **'Content:'**
  String get contentLabel;

  /// No description provided for @timeRestrictionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Time restrictions:'**
  String get timeRestrictionsLabel;

  /// No description provided for @safeSearchEnabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Safe search enabled'**
  String get safeSearchEnabledLabel;

  /// No description provided for @customizeLaterHint.
  ///
  /// In en, this message translates to:
  /// **'You can customize these settings later'**
  String get customizeLaterHint;

  /// No description provided for @childAddedSuccessMessage.
  ///
  /// In en, this message translates to:
  /// **'{childName} added successfully!'**
  String childAddedSuccessMessage(Object childName);

  /// No description provided for @failedToAddChildMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to add child: {error}'**
  String failedToAddChildMessage(Object error);

  /// No description provided for @vpnProtectionEngineTitle.
  ///
  /// In en, this message translates to:
  /// **'VPN Protection Engine'**
  String get vpnProtectionEngineTitle;

  /// No description provided for @dnsFilteringFoundationTitle.
  ///
  /// In en, this message translates to:
  /// **'DNS Filtering Foundation'**
  String get dnsFilteringFoundationTitle;

  /// No description provided for @vpnIntroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enable Android VPN permission to run TrustBridge network protection.'**
  String get vpnIntroSubtitle;

  /// No description provided for @currentStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Current Status'**
  String get currentStatusLabel;

  /// No description provided for @refreshStatusTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh status'**
  String get refreshStatusTooltip;

  /// No description provided for @policySyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Policy Sync'**
  String get policySyncTitle;

  /// No description provided for @syncNowButton.
  ///
  /// In en, this message translates to:
  /// **'Sync Now'**
  String get syncNowButton;

  /// No description provided for @syncingButton.
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get syncingButton;

  /// No description provided for @notYetSyncedMessage.
  ///
  /// In en, this message translates to:
  /// **'Not yet synced.'**
  String get notYetSyncedMessage;

  /// No description provided for @syncFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Sync failed: {error}'**
  String syncFailedMessage(Object error);

  /// No description provided for @childrenSyncedLabel.
  ///
  /// In en, this message translates to:
  /// **'Children synced'**
  String get childrenSyncedLabel;

  /// No description provided for @categoriesBlockedMetricLabel.
  ///
  /// In en, this message translates to:
  /// **'Categories blocked'**
  String get categoriesBlockedMetricLabel;

  /// No description provided for @domainsBlockedMetricLabel.
  ///
  /// In en, this message translates to:
  /// **'Domains blocked'**
  String get domainsBlockedMetricLabel;

  /// No description provided for @lastSyncedLabel.
  ///
  /// In en, this message translates to:
  /// **'Last synced'**
  String get lastSyncedLabel;

  /// No description provided for @processingLabel.
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get processingLabel;

  /// No description provided for @notAvailableLabel.
  ///
  /// In en, this message translates to:
  /// **'Not Available'**
  String get notAvailableLabel;

  /// No description provided for @syncPolicyRulesButton.
  ///
  /// In en, this message translates to:
  /// **'Sync Policy Rules'**
  String get syncPolicyRulesButton;

  /// No description provided for @restartVpnServiceButton.
  ///
  /// In en, this message translates to:
  /// **'Restart VPN Service'**
  String get restartVpnServiceButton;

  /// No description provided for @restartingButton.
  ///
  /// In en, this message translates to:
  /// **'Restarting...'**
  String get restartingButton;

  /// No description provided for @viewDnsQueryLogsButton.
  ///
  /// In en, this message translates to:
  /// **'View DNS Query Logs'**
  String get viewDnsQueryLogsButton;

  /// No description provided for @nextDnsIntegrationButton.
  ///
  /// In en, this message translates to:
  /// **'NextDNS Integration'**
  String get nextDnsIntegrationButton;

  /// No description provided for @domainPolicyTesterButton.
  ///
  /// In en, this message translates to:
  /// **'Domain Policy Tester'**
  String get domainPolicyTesterButton;

  /// No description provided for @vpnAndroidOnlyMessage.
  ///
  /// In en, this message translates to:
  /// **'VPN engine is available on Android only.'**
  String get vpnAndroidOnlyMessage;

  /// No description provided for @vpnPermissionRequiredMessage.
  ///
  /// In en, this message translates to:
  /// **'VPN permission is required before protection can start.'**
  String get vpnPermissionRequiredMessage;

  /// No description provided for @startProtectionHint.
  ///
  /// In en, this message translates to:
  /// **'Start protection to enforce category and domain policies.'**
  String get startProtectionHint;

  /// No description provided for @protectionChangesHint.
  ///
  /// In en, this message translates to:
  /// **'Protection changes apply immediately. Sync after policy edits.'**
  String get protectionChangesHint;

  /// No description provided for @permissionRecoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Permission Recovery'**
  String get permissionRecoveryTitle;

  /// No description provided for @vpnPermissionGrantedLabel.
  ///
  /// In en, this message translates to:
  /// **'VPN permission granted'**
  String get vpnPermissionGrantedLabel;

  /// No description provided for @vpnPermissionRequiredLabel.
  ///
  /// In en, this message translates to:
  /// **'Permission required'**
  String get vpnPermissionRequiredLabel;

  /// No description provided for @unsupportedOnThisPlatform.
  ///
  /// In en, this message translates to:
  /// **'Unsupported on this platform'**
  String get unsupportedOnThisPlatform;

  /// No description provided for @requestPermissionButton.
  ///
  /// In en, this message translates to:
  /// **'Request Permission'**
  String get requestPermissionButton;

  /// No description provided for @requestingButton.
  ///
  /// In en, this message translates to:
  /// **'Requesting...'**
  String get requestingButton;

  /// No description provided for @vpnSettingsButton.
  ///
  /// In en, this message translates to:
  /// **'VPN Settings'**
  String get vpnSettingsButton;

  /// No description provided for @settingsUpdatedSuccessMessage.
  ///
  /// In en, this message translates to:
  /// **'Settings updated successfully'**
  String get settingsUpdatedSuccessMessage;

  /// No description provided for @languageChangedMessage.
  ///
  /// In en, this message translates to:
  /// **'Language changed'**
  String get languageChangedMessage;

  /// No description provided for @languageChangedHindiMessage.
  ///
  /// In en, this message translates to:
  /// **'भाषा बदल दी गई'**
  String get languageChangedHindiMessage;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
