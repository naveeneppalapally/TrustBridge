// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'TrustBridge';

  @override
  String get dashboardTitle => 'डैशबोर्ड';

  @override
  String get childrenTitle => 'बच्चे';

  @override
  String get settingsTitle => 'सेटिंग्स';

  @override
  String get protectionTitle => 'सुरक्षा';

  @override
  String get addChildButton => 'बच्चा जोड़ें';

  @override
  String get editButton => 'संपादित करें';

  @override
  String get deleteButton => 'हटाएं';

  @override
  String get saveButton => 'सहेजें';

  @override
  String get retryButton => 'फिर से प्रयास करें';

  @override
  String get cancelButton => 'रद्द करें';

  @override
  String get continueButton => 'जारी रखें';

  @override
  String get welcomeMessage => 'TrustBridge में आपका स्वागत है';

  @override
  String get welcomeSubtitle =>
      'अपने परिवार के लिए स्वस्थ डिजिटल सीमाएं तय करें';

  @override
  String get childNicknameLabel => 'उपनाम';

  @override
  String get childAgeBandLabel => 'आयु वर्ग';

  @override
  String get youngAgeBand => '6-9 साल';

  @override
  String get middleAgeBand => '10-13 साल';

  @override
  String get teenAgeBand => '14-17 साल';

  @override
  String get vpnProtectionTitle => 'VPN सुरक्षा';

  @override
  String get enableProtectionButton => 'सुरक्षा चालू करें';

  @override
  String get disableProtectionButton => 'सुरक्षा बंद करें';

  @override
  String get protectionActiveMessage => 'सुरक्षा चालू है';

  @override
  String get protectionInactiveMessage => 'शुरू करने के लिए तैयार';

  @override
  String get requestAccessTitle => 'एक्सेस अनुरोध';

  @override
  String get requestAccessButton => 'एक्सेस मांगें';

  @override
  String get appOrSiteLabel => 'एप या वेबसाइट';

  @override
  String get durationLabel => 'अवधि';

  @override
  String get reasonLabel => 'कारण (वैकल्पिक)';

  @override
  String get submitRequestButton => 'अनुरोध भेजें';

  @override
  String get pendingRequestsTitle => 'लंबित अनुरोध';

  @override
  String get historyTitle => 'इतिहास';

  @override
  String get approveButton => 'स्वीकृत करें';

  @override
  String get denyButton => 'अस्वीकार करें';

  @override
  String get notificationSettingsTitle => 'सूचनाएं';

  @override
  String get notificationEnabledMessage => 'चालू';

  @override
  String get notificationDisabledMessage => 'चालू करने के लिए टैप करें';

  @override
  String get languageSettingsTitle => 'भाषा';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHindi => 'हिंदी';

  @override
  String get feedbackTitle => 'प्रतिक्रिया';

  @override
  String get analyticsTitle => 'विश्लेषण';

  @override
  String get noChildrenMessage => 'अभी तक कोई बच्चा नहीं जोड़ा गया';

  @override
  String get noChildrenSubtitle => 'शुरू करने के लिए अपना पहला बच्चा जोड़ें';

  @override
  String get noRequestsMessage => 'कोई लंबित अनुरोध नहीं';

  @override
  String get errorGeneric => 'कुछ गलत हो गया';

  @override
  String get errorNetwork => 'नेटवर्क त्रुटि। कृपया फिर से प्रयास करें।';

  @override
  String get errorPermission => 'अनुमति अस्वीकृत';

  @override
  String get durationFifteenMin => '15 मिनट';

  @override
  String get durationThirtyMin => '30 मिनट';

  @override
  String get durationOneHour => '1 घंटा';

  @override
  String get durationUntilEnd => 'शेड्यूल समाप्त होने तक';

  @override
  String get statusPending => 'लंबित';

  @override
  String get statusApproved => 'स्वीकृत';

  @override
  String get statusDenied => 'अस्वीकृत';

  @override
  String get statusExpired => 'समाप्त';

  @override
  String get notLoggedInMessage => 'लॉगिन नहीं है';

  @override
  String get accessRequestsTitle => 'एक्सेस अनुरोध';

  @override
  String get pendingTabTitle => 'लंबित';

  @override
  String get allCaughtUpTitle => 'सब अपडेट है!';

  @override
  String get noPendingRequestsSubtitle =>
      'आपके बच्चों से कोई लंबित अनुरोध नहीं है।';

  @override
  String get noHistoryYetTitle => 'अभी तक कोई इतिहास नहीं';

  @override
  String get noHistoryYetSubtitle => 'स्वीकृत और अस्वीकृत अनुरोध यहां दिखेंगे।';

  @override
  String get wantsAccessToLabel => 'एक्सेस चाहता/चाहती है';

  @override
  String get addReplyButton => 'जवाब जोड़ें';

  @override
  String get cancelReplyButton => 'जवाब रद्द करें';

  @override
  String get requestApprovedMessage => 'अनुरोध स्वीकृत कर दिया गया।';

  @override
  String get requestDeniedMessage => 'अनुरोध अस्वीकृत कर दिया गया।';

  @override
  String get approvalModalTitle => 'अनुरोध स्वीकृत करें?';

  @override
  String get denialModalTitle => 'अनुरोध अस्वीकार करें?';

  @override
  String approvalModalSummary(
      Object childName, Object appOrSite, Object duration) {
    return '$childName $appOrSite के लिए $duration का एक्सेस मांग रहा/रही है।';
  }

  @override
  String get approvalDurationLabel => 'कितनी देर के लिए स्वीकृत करें';

  @override
  String approvalExpiresPreview(Object time) {
    return 'एक्सेस लगभग $time पर समाप्त होगा।';
  }

  @override
  String get approvalUntilSchedulePreview =>
      'शेड्यूल समाप्त होने तक एक्सेस अनुमति रहेगी।';

  @override
  String get quickRepliesLabel => 'झटपट जवाब';

  @override
  String get quickReplyApproveStudy => 'पढ़ाई के लिए स्वीकृत। ध्यान बनाए रखें।';

  @override
  String get quickReplyApproveTakeBreak => 'ठीक है, थोड़े ब्रेक के लिए।';

  @override
  String get quickReplyApproveCareful =>
      'स्वीकृत। जिम्मेदारी से इस्तेमाल करें।';

  @override
  String get quickReplyDenyNotNow => 'अभी नहीं।';

  @override
  String get quickReplyDenyHomework => 'पहले होमवर्क, फिर बात करेंगे।';

  @override
  String get quickReplyDenyLaterToday => 'इस पर आज बाद में बात करते हैं।';

  @override
  String get parentReplyOptionalLabel => 'बच्चे के लिए जवाब (वैकल्पिक)';

  @override
  String get keepPendingButton => 'लंबित ही रखें';

  @override
  String get confirmApproveButton => 'अभी स्वीकृत करें';

  @override
  String get confirmDenyButton => 'अभी अस्वीकार करें';

  @override
  String requestReplyHint(Object childName) {
    return '$childName के लिए संदेश... (वैकल्पिक)';
  }

  @override
  String errorWithValue(Object value) {
    return 'त्रुटि: $value';
  }

  @override
  String get justNow => 'अभी';

  @override
  String minutesAgo(int count) {
    return '$countमि पहले';
  }

  @override
  String hoursAgo(int count) {
    return '$countघं पहले';
  }

  @override
  String daysAgo(int count) {
    return '$countदिन पहले';
  }

  @override
  String ageLabel(Object ageBand) {
    return 'उम्र: $ageBand';
  }

  @override
  String get pausedLabel => 'रोका गया';

  @override
  String categoriesBlockedCount(int count) {
    return '$count श्रेणियां ब्लॉक';
  }

  @override
  String schedulesCount(int count) {
    return '$count शेड्यूल';
  }

  @override
  String get managedProfilesLabel => 'प्रोफाइल्स';

  @override
  String get blockedCategoriesLabel => 'ब्लॉक श्रेणियां';

  @override
  String get schedulesLabel => 'शेड्यूल';

  @override
  String get addChildTitle => 'बच्चा जोड़ें';

  @override
  String get ageBandGuideTooltip => 'आयु वर्ग गाइड';

  @override
  String get addChildHeadline => 'नया बच्चा प्रोफाइल जोड़ें';

  @override
  String get addChildSubtitle => 'हम आयु-उपयुक्त कंटेंट फिल्टर लगाएंगे';

  @override
  String get nicknameHint => 'उदाहरण: Alex, Sam, Priya';

  @override
  String get nicknameHelper => 'हम इस बच्चे को क्या बुलाएं?';

  @override
  String get enterNicknameError => 'कृपया एक उपनाम दर्ज करें';

  @override
  String get nicknameMinError => 'उपनाम कम से कम 2 अक्षर का होना चाहिए';

  @override
  String get nicknameMaxError => 'उपनाम 20 अक्षर से कम होना चाहिए';

  @override
  String get ageGroupLabel => 'आयु समूह';

  @override
  String get whichAgeBandLabel => 'कौन सा आयु वर्ग?';

  @override
  String get ageYoungSubtitle => 'छोटे बच्चे - सबसे कठोर फिल्टर';

  @override
  String get ageMiddleSubtitle => 'मिडिल स्कूल - मध्यम फिल्टर';

  @override
  String get ageTeenSubtitle => 'किशोर - संतुलित दृष्टिकोण';

  @override
  String get whatWillBeBlockedLabel => 'क्या ब्लॉक होगा?';

  @override
  String get contentLabel => 'कंटेंट:';

  @override
  String get timeRestrictionsLabel => 'समय प्रतिबंध:';

  @override
  String get safeSearchEnabledLabel => 'सेफ सर्च चालू';

  @override
  String get customizeLaterHint => 'आप इन सेटिंग्स को बाद में बदल सकते हैं';

  @override
  String childAddedSuccessMessage(Object childName) {
    return '$childName सफलतापूर्वक जोड़ा गया!';
  }

  @override
  String failedToAddChildMessage(Object error) {
    return 'बच्चा जोड़ने में विफल: $error';
  }

  @override
  String get vpnProtectionEngineTitle => 'VPN सुरक्षा इंजिन';

  @override
  String get dnsFilteringFoundationTitle => 'DNS फिल्टरिंग फाउंडेशन';

  @override
  String get vpnIntroSubtitle =>
      'TrustBridge नेटवर्क सुरक्षा चलाने के लिए Android VPN अनुमति चालू करें।';

  @override
  String get currentStatusLabel => 'वर्तमान स्थिति';

  @override
  String get refreshStatusTooltip => 'स्थिति रिफ्रेश करें';

  @override
  String get policySyncTitle => 'पॉलिसी सिंक';

  @override
  String get syncNowButton => 'अभी सिंक करें';

  @override
  String get syncingButton => 'सिंक हो रहा है...';

  @override
  String get notYetSyncedMessage => 'अभी तक सिंक नहीं हुआ।';

  @override
  String syncFailedMessage(Object error) {
    return 'सिंक विफल: $error';
  }

  @override
  String get childrenSyncedLabel => 'सिंक हुए बच्चे';

  @override
  String get categoriesBlockedMetricLabel => 'ब्लॉक श्रेणियां';

  @override
  String get domainsBlockedMetricLabel => 'ब्लॉक डोमेन';

  @override
  String get lastSyncedLabel => 'अंतिम सिंक';

  @override
  String get processingLabel => 'प्रोसेस हो रहा है...';

  @override
  String get notAvailableLabel => 'उपलब्ध नहीं';

  @override
  String get syncPolicyRulesButton => 'पॉलिसी रूल सिंक करें';

  @override
  String get restartVpnServiceButton => 'VPN सेवा पुनः चालू करें';

  @override
  String get restartingButton => 'पुनः चालू हो रहा है...';

  @override
  String get viewDnsQueryLogsButton => 'DNS क्वेरी लॉग देखें';

  @override
  String get nextDnsIntegrationButton => 'NextDNS इंटीग्रेशन';

  @override
  String get domainPolicyTesterButton => 'डोमेन पॉलिसी टेस्टर';

  @override
  String get vpnAndroidOnlyMessage => 'VPN इंजिन सिर्फ Android पर उपलब्ध है।';

  @override
  String get vpnPermissionRequiredMessage =>
      'सुरक्षा शुरू करने से पहले VPN अनुमति जरूरी है।';

  @override
  String get startProtectionHint =>
      'श्रेणी और डोमेन नीति लागू करने के लिए सुरक्षा चालू करें।';

  @override
  String get protectionChangesHint =>
      'सुरक्षा बदलाव तुरंत लागू होते हैं। पॉलिसी एडिट के बाद सिंक करें।';

  @override
  String get permissionRecoveryTitle => 'अनुमति रिकवरी';

  @override
  String get vpnPermissionGrantedLabel => 'VPN अनुमति मिल गई';

  @override
  String get vpnPermissionRequiredLabel => 'VPN अनुमति जरूरी';

  @override
  String get unsupportedOnThisPlatform => 'इस प्लेटफॉर्म पर समर्थित नहीं';

  @override
  String get requestPermissionButton => 'अनुमति मांगें';

  @override
  String get requestingButton => 'मांग रहा है...';

  @override
  String get vpnSettingsButton => 'VPN सेटिंग्स';

  @override
  String get settingsUpdatedSuccessMessage =>
      'सेटिंग्स सफलतापूर्वक अपडेट हो गईं';

  @override
  String get languageChangedMessage => 'भाषा बदल दी गई';

  @override
  String get languageChangedHindiMessage => 'भाषा बदल दी गई';
}
