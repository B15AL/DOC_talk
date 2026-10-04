/// All user-facing text lives here, keyed by language code.
/// Adding a language = adding one map (later: download it as a JSON pack).
/// Logic never compares against these strings.
class Strings {
  static const fallbackLanguage = 'en';

  static String of(String lang, String key) =>
      _packs[lang]?[key] ?? _packs[fallbackLanguage]![key] ?? key;

  /// Display text for a stored answer value ("yes" or a choice option id).
  static String answerLabel(String lang, String value) =>
      const ['yes', 'no', 'unsure'].contains(value) ? of(lang, value) : of(lang, 'opt_$value');

  /// BCP-47 locale for speech-to-text / text-to-speech engines.
  static const Map<String, String> speechLocales = {
    'hi': 'hi_IN',
    'en': 'en_IN',
  };

  static const Map<String, Map<String, String>> _packs = {
    'en': {
      'app_title': 'Health AI Assistant',
      'tagline': 'Offline • Local language • Human in control',
      'choose_language': 'Choose language',
      'continue': 'Continue',
      'change_language': 'Change language',
      'start': 'Start new consultation',
      'saved_count': 'Saved consultations',
      'pending_sync': 'Not yet sent',
      'new_consultation': 'New consultation',
      'describe_title': 'Describe what you see or hear',
      'describe_hint': 'e.g. "Child has fever for 3 days and cough"',
      'start_questions': 'Start questions',
      'listening': 'Listening… tap again to stop',
      'mic_unavailable': 'Voice input not available on this phone. Please type.',
      'yes': 'Yes',
      'no': 'No',
      'unsure': 'Not sure',
      'summary_title': 'Consultation summary',
      'symptom_summary': 'Symptom summary',
      'suggestions_title': 'Possible next steps',
      'from_description': 'from description',
      'because': 'Because',
      'disclaimer':
          'This is only a suggestion, not a diagnosis. Please confirm with a clinician. The final decision is yours.',
      'confirm_save': 'I have reviewed this — save',
      'saved': 'Saved on this phone',
      'share_sms': 'Send summary by SMS',
      'finish': 'Finish & return home',
      'level_routine': 'Routine care',
      'level_clinicianReview': 'Clinician review needed',
      'level_urgentReferral': 'URGENT referral',

      'history': 'History',
      'no_history': 'No consultations saved yet.',
      'sent': 'Sent',
      'not_sent': 'Not sent',
      'details': 'Consultation details',
      'description': 'Description',

      'ai_title': 'Smart AI (offline)',
      'ai_subtitle':
          'A small AI model that understands the description better. Download once on Wi-Fi, then it works without internet. Rules and referrals are never decided by the AI.',
      'ai_use': 'Use smart AI',
      'ai_download': 'Download',
      'ai_cancel': 'Cancel',
      'ai_delete': 'Delete model',
      'ai_retry': 'Try again',
      'ai_status_unsupported': 'Not supported on this phone — keyword mode is used.',
      'ai_status_notDownloaded': 'Not downloaded',
      'ai_status_downloading': 'Downloading…',
      'ai_status_downloaded': 'Downloaded — ready offline',
      'ai_status_loading': 'Loading into memory…',
      'ai_status_ready': 'Ready',
      'ai_status_failed': 'Error',
      'ai_ram_warning': 'This phone may not have enough memory for this model.',
      'ai_phone_ram': 'Phone memory',
      'ai_try': 'Try it',
      'ai_try_button': 'Understand',
      'ai_nothing': 'No symptoms understood.',
      'ai_keywords': 'Keyword mode',
      'ai_note':
          'Trained for this app on Hindi, Hinglish and English notes. About 280 MB; works on phones with 2 GB+ memory.',
      'ai_import': 'Import model file',
      'ai_import_hint':
          'No internet? Copy the .gguf file to this phone (USB cable, Bluetooth, SD card) and pick it here.',
      'ai_status_importing': 'Copying model…',
      'understanding': 'Understanding the description…',
      'confirm_understood': 'Understood from the description',
      'confirm_understood_hint':
          'Untick anything that is wrong. Unticked items will be asked as questions.',

      // SMS conversation (feature phones)
      'sms_welcome': 'Health Assistant. Answer by number.',
      'sms_yes_no_help': '1=Yes 2=No 3=Not sure',
      'sms_invalid': 'Please reply with one of the numbers.',
      'sms_restart_hint': 'Send 0 to start again.',
      'sms_report_received': 'Report received. Ref:',

      // Questions
      'q_age_group': 'Age of the patient?',
      'opt_age_infant': 'Under 2 months',
      'opt_age_child': '2 months – 5 years',
      'opt_age_older': 'Over 5 years',
      'q_ds_unconscious': 'Is the patient unconscious, very drowsy or not responding?',
      'q_ds_convulsions': 'Has the patient had fits (convulsions)?',
      'q_ds_cannot_drink': 'Is the patient unable to drink anything (or baby unable to feed)?',
      'q_ds_vomits_everything': 'Does the patient vomit everything they eat or drink?',
      'q_ds_breathing': 'Is breathing very difficult or very fast?',
      'q_fever': 'Does the patient have fever?',
      'q_fever_days': 'For how many days has the fever been there?',
      'opt_d_1_2': '1–2 days',
      'opt_d_3_6': '3–6 days',
      'opt_d_7_plus': '7 days or more',
      'q_cough': 'Does the patient have a cough?',
      'q_cough_days': 'For how long has the cough been there?',
      'opt_c_lt_14': 'Less than 2 weeks',
      'opt_c_14_plus': '2 weeks or more',
      'q_diarrhea': 'Does the patient have loose motions (diarrhoea)?',
      'q_blood_in_stool': 'Is there blood in the stool?',

      // Suggestions
      's_urgent_danger':
          'Danger sign present. Refer urgently to the nearest higher facility (PHC/CHC/hospital). Arrange transport — do not delay.',
      's_infant_fever': 'Fever in a baby under 2 months can be serious. Refer urgently.',
      's_unsure_danger':
          'A danger sign could not be ruled out. Please get a clinician to examine the patient soon.',
      's_fever_long': 'Fever for 7 days or more. Refer for clinician evaluation.',
      's_fever_tests': 'If available: malaria rapid test (RDT) and temperature check.',
      's_cough_tb': 'Cough for 2 weeks or more. Refer for TB testing as per the local programme.',
      's_blood_stool': 'Blood in stool. Clinician review needed.',
      's_diarrhea_ors':
          'Give ORS (and zinc for children) as per your protocol. Watch for dehydration: sunken eyes, very thirsty, skin pinch goes back slowly.',
      's_common_checks':
          'Check temperature, breathing rate and oxygen level (if a pulse oximeter is available).',
      's_routine_observe':
          'No danger signs reported. Continue care here and advise the family to return if the patient gets worse.',
    },
    'hi': {
      'app_title': 'स्वास्थ्य AI सहायक',
      'tagline': 'ऑफ़लाइन • अपनी भाषा • फ़ैसला आपका',
      'choose_language': 'भाषा चुनें',
      'continue': 'आगे बढ़ें',
      'change_language': 'भाषा बदलें',
      'start': 'नई जाँच शुरू करें',
      'saved_count': 'सेव की गई जाँचें',
      'pending_sync': 'अभी भेजी नहीं गईं',
      'new_consultation': 'नई जाँच',
      'describe_title': 'जो दिख या सुनाई दे रहा है, बताइए',
      'describe_hint': 'जैसे: "बच्चे को 3 दिन से बुखार और खाँसी है"',
      'start_questions': 'सवाल शुरू करें',
      'listening': 'सुन रहे हैं… रोकने के लिए फिर दबाएँ',
      'mic_unavailable': 'इस फ़ोन पर आवाज़ से लिखना उपलब्ध नहीं है। कृपया टाइप करें।',
      'yes': 'हाँ',
      'no': 'नहीं',
      'unsure': 'पक्का नहीं पता',
      'summary_title': 'जाँच का सारांश',
      'symptom_summary': 'लक्षणों का सारांश',
      'suggestions_title': 'आगे क्या कर सकते हैं',
      'from_description': 'विवरण से',
      'because': 'कारण',
      'disclaimer':
          'यह सिर्फ़ सुझाव है, निदान नहीं। कृपया डॉक्टर/क्लिनिशियन से पुष्टि करें। अंतिम फ़ैसला आपका है।',
      'confirm_save': 'मैंने देख लिया है — सेव करें',
      'saved': 'इस फ़ोन में सेव हो गया',
      'share_sms': 'SMS से सारांश भेजें',
      'finish': 'पूरा करें और होम पर जाएँ',
      'level_routine': 'सामान्य देखभाल',
      'level_clinicianReview': 'डॉक्टर से जाँच ज़रूरी',
      'level_urgentReferral': 'तुरंत रेफ़र करें',

      'history': 'पिछली जाँचें',
      'no_history': 'अभी तक कोई जाँच सेव नहीं हुई।',
      'sent': 'भेजा गया',
      'not_sent': 'नहीं भेजा',
      'details': 'जाँच का विवरण',
      'description': 'विवरण',

      'ai_title': 'स्मार्ट AI (ऑफ़लाइन)',
      'ai_subtitle':
          'एक छोटा AI मॉडल जो विवरण को बेहतर समझता है। एक बार Wi-Fi पर डाउनलोड करें, फिर बिना इंटरनेट के चलता है। रेफ़रल का फ़ैसला AI कभी नहीं करता।',
      'ai_use': 'स्मार्ट AI इस्तेमाल करें',
      'ai_download': 'डाउनलोड करें',
      'ai_cancel': 'रद्द करें',
      'ai_delete': 'मॉडल हटाएँ',
      'ai_retry': 'फिर से कोशिश करें',
      'ai_status_unsupported': 'इस फ़ोन पर उपलब्ध नहीं — कीवर्ड मोड चलेगा।',
      'ai_status_notDownloaded': 'डाउनलोड नहीं हुआ',
      'ai_status_downloading': 'डाउनलोड हो रहा है…',
      'ai_status_downloaded': 'डाउनलोड हो गया — ऑफ़लाइन तैयार',
      'ai_status_loading': 'मेमोरी में लोड हो रहा है…',
      'ai_status_ready': 'तैयार',
      'ai_status_failed': 'गड़बड़ी',
      'ai_ram_warning': 'इस फ़ोन में इस मॉडल के लिए शायद पर्याप्त मेमोरी नहीं है।',
      'ai_phone_ram': 'फ़ोन की मेमोरी',
      'ai_try': 'आज़माएँ',
      'ai_try_button': 'समझें',
      'ai_nothing': 'कोई लक्षण समझ नहीं आया।',
      'ai_keywords': 'कीवर्ड मोड',
      'ai_note':
          'इस ऐप के लिए हिंदी, हिंग्लिश और अंग्रेज़ी नोट्स पर ट्रेन किया गया। लगभग 280 MB; 2 GB+ मेमोरी वाले फ़ोन पर चलता है।',
      'ai_import': 'मॉडल फ़ाइल चुनें',
      'ai_import_hint':
          'इंटरनेट नहीं है? .gguf फ़ाइल को USB, ब्लूटूथ या SD कार्ड से इस फ़ोन में कॉपी करें और यहाँ चुनें।',
      'ai_status_importing': 'मॉडल कॉपी हो रहा है…',
      'understanding': 'विवरण समझ रहे हैं…',
      'confirm_understood': 'विवरण से यह समझा गया',
      'confirm_understood_hint': 'जो गलत है उसका निशान हटाएँ। उनके बारे में सवाल पूछे जाएँगे।',

      'sms_welcome': 'स्वास्थ्य सहायक। नंबर से जवाब दें।',
      'sms_yes_no_help': '1=हाँ 2=नहीं 3=पक्का नहीं',
      'sms_invalid': 'कृपया दिए गए नंबरों में से एक भेजें।',
      'sms_restart_hint': 'फिर से शुरू करने के लिए 0 भेजें।',
      'sms_report_received': 'रिपोर्ट मिल गई। Ref:',

      'q_age_group': 'मरीज़ की उम्र?',
      'opt_age_infant': '2 महीने से कम',
      'opt_age_child': '2 महीने – 5 साल',
      'opt_age_older': '5 साल से ज़्यादा',
      'q_ds_unconscious': 'क्या मरीज़ बेहोश है, बहुत सुस्त है या जवाब नहीं दे रहा?',
      'q_ds_convulsions': 'क्या मरीज़ को दौरे (झटके) आए हैं?',
      'q_ds_cannot_drink': 'क्या मरीज़ कुछ भी पी नहीं पा रहा (या बच्चा दूध नहीं पी रहा)?',
      'q_ds_vomits_everything': 'क्या मरीज़ जो भी खाता-पीता है, सब उल्टी कर देता है?',
      'q_ds_breathing': 'क्या साँस लेने में बहुत तकलीफ़ है या साँस बहुत तेज़ चल रही है?',
      'q_fever': 'क्या मरीज़ को बुखार है?',
      'q_fever_days': 'बुखार कितने दिन से है?',
      'opt_d_1_2': '1–2 दिन',
      'opt_d_3_6': '3–6 दिन',
      'opt_d_7_plus': '7 दिन या ज़्यादा',
      'q_cough': 'क्या खाँसी है?',
      'q_cough_days': 'खाँसी कब से है?',
      'opt_c_lt_14': '2 हफ़्ते से कम',
      'opt_c_14_plus': '2 हफ़्ते या ज़्यादा',
      'q_diarrhea': 'क्या दस्त (लूज़ मोशन) हो रहे हैं?',
      'q_blood_in_stool': 'क्या मल में खून आ रहा है?',

      's_urgent_danger':
          'खतरे का लक्षण है। तुरंत नज़दीकी बड़े अस्पताल (PHC/CHC) रेफ़र करें। गाड़ी का इंतज़ाम करें — देर न करें।',
      's_infant_fever': '2 महीने से छोटे बच्चे में बुखार गंभीर हो सकता है। तुरंत रेफ़र करें।',
      's_unsure_danger': 'खतरे के लक्षण से इनकार नहीं किया जा सका। जल्दी किसी डॉक्टर से जाँच करवाएँ।',
      's_fever_long': '7 दिन या ज़्यादा से बुखार है। डॉक्टर के पास जाँच के लिए भेजें।',
      's_fever_tests': 'अगर उपलब्ध हो: मलेरिया रैपिड टेस्ट (RDT) और तापमान जाँच।',
      's_cough_tb': '2 हफ़्ते या ज़्यादा से खाँसी है। स्थानीय कार्यक्रम के अनुसार TB जाँच के लिए भेजें।',
      's_blood_stool': 'मल में खून है। डॉक्टर से जाँच ज़रूरी है।',
      's_diarrhea_ors':
          'अपने प्रोटोकॉल के अनुसार ORS (और बच्चों को ज़िंक) दें। पानी की कमी के लक्षण देखें: धँसी आँखें, बहुत प्यास, चुटकी से खींची त्वचा धीरे लौटे।',
      's_common_checks': 'तापमान, साँस की गति और ऑक्सीजन (अगर पल्स ऑक्सीमीटर हो) जाँचें।',
      's_routine_observe':
          'कोई खतरे का लक्षण नहीं बताया गया। यहीं देखभाल जारी रखें और हालत बिगड़ने पर वापस आने को कहें।',
    },
  };
}
