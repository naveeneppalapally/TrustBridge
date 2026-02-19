// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'TrustBridge';

  @override
  String get dashboardTitle => 'Dashboard';

  @override
  String get childrenTitle => 'Children';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get protectionTitle => 'Protection';

  @override
  String get addChildButton => 'Add Child';

  @override
  String get editButton => 'Edit';

  @override
  String get deleteButton => 'Delete';

  @override
  String get saveButton => 'Save';

  @override
  String get retryButton => 'Retry';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get continueButton => 'Continue';

  @override
  String get welcomeMessage => 'Welcome to TrustBridge';

  @override
  String get welcomeSubtitle =>
      'Set healthy digital boundaries for your family';

  @override
  String get childNicknameLabel => 'Nickname';

  @override
  String get childAgeBandLabel => 'Age Band';

  @override
  String get youngAgeBand => '6-9 years';

  @override
  String get middleAgeBand => '10-13 years';

  @override
  String get teenAgeBand => '14-17 years';

  @override
  String get vpnProtectionTitle => 'VPN Protection';

  @override
  String get enableProtectionButton => 'Enable Protection';

  @override
  String get disableProtectionButton => 'Disable Protection';

  @override
  String get protectionActiveMessage => 'Protection running';

  @override
  String get protectionInactiveMessage => 'Ready to start';

  @override
  String get requestAccessTitle => 'Request Access';

  @override
  String get requestAccessButton => 'Ask for Access';

  @override
  String get appOrSiteLabel => 'App or website';

  @override
  String get durationLabel => 'Duration';

  @override
  String get reasonLabel => 'Reason (optional)';

  @override
  String get submitRequestButton => 'Send Request';

  @override
  String get pendingRequestsTitle => 'Pending Requests';

  @override
  String get historyTitle => 'History';

  @override
  String get approveButton => 'Approve';

  @override
  String get denyButton => 'Deny';

  @override
  String get notificationSettingsTitle => 'Notifications';

  @override
  String get notificationEnabledMessage => 'Enabled';

  @override
  String get notificationDisabledMessage => 'Tap to enable';

  @override
  String get languageSettingsTitle => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHindi => 'Hindi (हिंदी)';

  @override
  String get feedbackTitle => 'Feedback';

  @override
  String get analyticsTitle => 'Analytics';

  @override
  String get noChildrenMessage => 'No children yet';

  @override
  String get noChildrenSubtitle => 'Add your first child to get started';

  @override
  String get noRequestsMessage => 'No pending requests';

  @override
  String get errorGeneric => 'Something went wrong';

  @override
  String get errorNetwork => 'Network error. Please try again.';

  @override
  String get errorPermission => 'Permission denied';

  @override
  String get durationFifteenMin => '15 minutes';

  @override
  String get durationThirtyMin => '30 minutes';

  @override
  String get durationOneHour => '1 hour';

  @override
  String get durationUntilEnd => 'Until schedule ends';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusApproved => 'Approved';

  @override
  String get statusDenied => 'Denied';

  @override
  String get statusExpired => 'Expired';

  @override
  String get notLoggedInMessage => 'Not logged in';

  @override
  String get accessRequestsTitle => 'Access Requests';

  @override
  String get pendingTabTitle => 'Pending';

  @override
  String get allCaughtUpTitle => 'All caught up!';

  @override
  String get noPendingRequestsSubtitle =>
      'No pending requests from your children.';

  @override
  String get noHistoryYetTitle => 'No history yet';

  @override
  String get noHistoryYetSubtitle =>
      'Approved and denied requests will appear here.';

  @override
  String get wantsAccessToLabel => 'Wants access to';

  @override
  String get addReplyButton => 'Add reply';

  @override
  String get cancelReplyButton => 'Cancel reply';

  @override
  String get requestApprovedMessage => 'Request approved.';

  @override
  String get requestDeniedMessage => 'Request denied.';

  @override
  String get approvalModalTitle => 'Approve request?';

  @override
  String get denialModalTitle => 'Deny request?';

  @override
  String approvalModalSummary(
      Object childName, Object appOrSite, Object duration) {
    return '$childName is requesting access to $appOrSite for $duration.';
  }

  @override
  String get approvalDurationLabel => 'Approve for';

  @override
  String approvalExpiresPreview(Object time) {
    return 'Access will expire around $time.';
  }

  @override
  String get approvalUntilSchedulePreview =>
      'Access stays allowed until schedule ends.';

  @override
  String get quickRepliesLabel => 'Quick replies';

  @override
  String get quickReplyApproveStudy => 'Approved for study. Stay focused.';

  @override
  String get quickReplyApproveTakeBreak => 'Okay for a short break.';

  @override
  String get quickReplyApproveCareful => 'Approved. Please use it responsibly.';

  @override
  String get quickReplyDenyNotNow => 'Not right now.';

  @override
  String get quickReplyDenyHomework => 'Homework first, then we can revisit.';

  @override
  String get quickReplyDenyLaterToday => 'Let\'s discuss this later today.';

  @override
  String get parentReplyOptionalLabel => 'Reply to child (optional)';

  @override
  String get keepPendingButton => 'Keep Pending';

  @override
  String get confirmApproveButton => 'Approve Now';

  @override
  String get confirmDenyButton => 'Deny Now';

  @override
  String requestReplyHint(Object childName) {
    return 'Message to $childName... (optional)';
  }

  @override
  String errorWithValue(Object value) {
    return 'Error: $value';
  }

  @override
  String get justNow => 'just now';

  @override
  String minutesAgo(int count) {
    return '${count}m ago';
  }

  @override
  String hoursAgo(int count) {
    return '${count}h ago';
  }

  @override
  String daysAgo(int count) {
    return '${count}d ago';
  }

  @override
  String ageLabel(Object ageBand) {
    return 'Age: $ageBand';
  }

  @override
  String get pausedLabel => 'Paused';

  @override
  String categoriesBlockedCount(int count) {
    return '$count categories blocked';
  }

  @override
  String schedulesCount(int count) {
    return '$count schedules';
  }

  @override
  String get managedProfilesLabel => 'MANAGED PROFILES';

  @override
  String get blockedCategoriesLabel => 'BLOCKED CATEGORIES';

  @override
  String get schedulesLabel => 'SCHEDULES';

  @override
  String get addChildTitle => 'Add Child';

  @override
  String get ageBandGuideTooltip => 'Age Band Guide';

  @override
  String get addChildHeadline => 'Add a new child profile';

  @override
  String get addChildSubtitle =>
      'We will set up age-appropriate content filters';

  @override
  String get nicknameHint => 'e.g., Alex, Sam, Priya';

  @override
  String get nicknameHelper => 'What should we call this child?';

  @override
  String get enterNicknameError => 'Please enter a nickname';

  @override
  String get nicknameMinError => 'Nickname must be at least 2 characters';

  @override
  String get nicknameMaxError => 'Nickname must be less than 20 characters';

  @override
  String get ageGroupLabel => 'Age Group';

  @override
  String get whichAgeBandLabel => 'Which age band?';

  @override
  String get ageYoungSubtitle => 'Young children - strictest filters';

  @override
  String get ageMiddleSubtitle => 'Middle schoolers - moderate filters';

  @override
  String get ageTeenSubtitle => 'Teenagers - balanced approach';

  @override
  String get whatWillBeBlockedLabel => 'What will be blocked?';

  @override
  String get contentLabel => 'Content:';

  @override
  String get timeRestrictionsLabel => 'Time restrictions:';

  @override
  String get safeSearchEnabledLabel => 'Safe search enabled';

  @override
  String get customizeLaterHint => 'You can customize these settings later';

  @override
  String childAddedSuccessMessage(Object childName) {
    return '$childName added successfully!';
  }

  @override
  String failedToAddChildMessage(Object error) {
    return 'Failed to add child: $error';
  }

  @override
  String get vpnProtectionEngineTitle => 'VPN Protection Engine';

  @override
  String get dnsFilteringFoundationTitle => 'DNS Filtering Foundation';

  @override
  String get vpnIntroSubtitle =>
      'Enable Android VPN permission to run TrustBridge network protection.';

  @override
  String get currentStatusLabel => 'Current Status';

  @override
  String get refreshStatusTooltip => 'Refresh status';

  @override
  String get policySyncTitle => 'Policy Sync';

  @override
  String get syncNowButton => 'Sync Now';

  @override
  String get syncingButton => 'Syncing...';

  @override
  String get notYetSyncedMessage => 'Not yet synced.';

  @override
  String syncFailedMessage(Object error) {
    return 'Sync failed: $error';
  }

  @override
  String get childrenSyncedLabel => 'Children synced';

  @override
  String get categoriesBlockedMetricLabel => 'Categories blocked';

  @override
  String get domainsBlockedMetricLabel => 'Domains blocked';

  @override
  String get lastSyncedLabel => 'Last synced';

  @override
  String get processingLabel => 'Processing...';

  @override
  String get notAvailableLabel => 'Not Available';

  @override
  String get syncPolicyRulesButton => 'Sync Policy Rules';

  @override
  String get restartVpnServiceButton => 'Restart VPN Service';

  @override
  String get restartingButton => 'Restarting...';

  @override
  String get viewDnsQueryLogsButton => 'View DNS Query Logs';

  @override
  String get nextDnsIntegrationButton => 'NextDNS Integration';

  @override
  String get domainPolicyTesterButton => 'Domain Policy Tester';

  @override
  String get vpnAndroidOnlyMessage =>
      'VPN engine is available on Android only.';

  @override
  String get vpnPermissionRequiredMessage =>
      'VPN permission is required before protection can start.';

  @override
  String get startProtectionHint =>
      'Start protection to enforce category and domain policies.';

  @override
  String get protectionChangesHint =>
      'Protection changes apply immediately. Sync after policy edits.';

  @override
  String get permissionRecoveryTitle => 'Permission Recovery';

  @override
  String get vpnPermissionGrantedLabel => 'VPN permission granted';

  @override
  String get vpnPermissionRequiredLabel => 'Permission required';

  @override
  String get unsupportedOnThisPlatform => 'Unsupported on this platform';

  @override
  String get requestPermissionButton => 'Request Permission';

  @override
  String get requestingButton => 'Requesting...';

  @override
  String get vpnSettingsButton => 'VPN Settings';

  @override
  String get settingsUpdatedSuccessMessage => 'Settings updated successfully';

  @override
  String get languageChangedMessage => 'Language changed';

  @override
  String get languageChangedHindiMessage => 'भाषा बदल दी गई';
}
