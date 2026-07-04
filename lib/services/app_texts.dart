class AppTexts {
  static String get(String key) {
    final lang = _currentLang;


    return _texts[lang]?[key] ??
        _texts[_fallbackLang(lang)]?[key] ??
        _texts['en']![key] ??
        key;
  }


  static String _currentLang = 'pt-BR';


  static void setLang(String code) {
  final c = code.trim();


  if (c == 'pt') {
    _currentLang = 'pt-BR';
  } else {
    _currentLang = c;
  }
}



  static String _fallbackLang(String code) {
    if (code == 'pt-BR' || code == 'pt-PT') return code;
    if (code.startsWith('pt')) return 'pt-BR';
    return 'en';
  }


  static final Map<String, Map<String, String>> _texts = {
    'en': {
      'free_account': 'Free account',
      'premium_active': 'Premium active',
      'notifications': 'Notifications',
      'faq': 'FAQ',
      'contact': 'Contact',
      'terms': 'Terms',
      'privacy_policy': 'Privacy Policy',
      'about': 'About',
      'menu': 'Menu',
      'profile': 'Profile',
      'invite': 'Invites',
      'premium': 'Premium',
      'language': 'Language',
      'logout': 'Logout',
    },
    'pt-BR': {
      'menu': 'Menu',
      'profile': 'Perfil',
      'invite': 'Convites',
      'premium': 'Premium',
      'language': 'Idioma',
      'logout': 'Sair',
      'free_account': 'Conta gratuita',
      'premium_active': 'Premium ativo',
      'notifications': 'Notificações',
      'faq': 'FAQ',
      'contact': 'Contato',
      'terms': 'Termos',
      'privacy_policy': 'Política de Privacidade',
      'about': 'Sobre',
    },
    'pt-PT': {
      'menu': 'Menu',
      'profile': 'Perfil',
      'invite': 'Convites',
      'premium': 'Premium',
      'language': 'Idioma',
      'logout': 'Sair',
      'free_account': 'Conta gratuita',
      'premium_active': 'Premium ativo',
      'notifications': 'Notificações',
      'faq': 'FAQ',
      'contact': 'Contacto',
      'terms': 'Termos',
      'privacy_policy': 'Política de Privacidade',
      'about': 'Sobre',
    },
  };
}
