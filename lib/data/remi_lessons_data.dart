/// Catálogo de lições da Remi indexado por código estável (`en`/`pt`/`es`/`fr`).
///
/// Metas e nomes de lição são IDs estáveis em inglês (não são labels de UI).
/// As frases de cada lição estão no idioma-alvo correspondente.
const remiGoalIds = <String>[
  'Travel',
  'Daily Life',
  'Work',
  'Friends',
  'Events',
];

final Map<String, Map<String, Map<String, List<String>>>> remiLessonsByCode = {
  'en': _en,
  'pt': _pt,
  'es': _es,
  'fr': _fr,
};

const _en = {
  'Travel': {
    'Introductions': [
      'Hi! My name is Alex.',
      'Nice to meet you.',
      'Where are you from?',
      'I’m from Brazil.',
    ],
    'Airport': [
      'Where is gate 24?',
      'Can I see your passport?',
      'My flight is delayed.',
      'Where can I get a taxi?',
    ],
    'Hotel': [
      'I have a reservation.',
      'What time is check-in?',
      'Can I get the Wi-Fi password?',
      'Thank you very much.',
    ],
    'Coffee Shop': [
      'Can I get a medium coffee?',
      'How much is it?',
      'I would like a latte.',
      'Thank you!',
    ],
    'Asking Directions': [
      'Where is the subway station?',
      'How do I get downtown?',
      'Is it far from here?',
      'Thank you for your help.',
    ],
  },
  'Daily Life': {
    'Daily Conversations': [
      'How was your day?',
      'What are your plans today?',
      'I’m a little tired today.',
      'Today was a busy day.',
    ],
    'Shopping': [
      'How much does this cost?',
      'Do you accept credit cards?',
      'Can I try this on?',
      'That looks great.',
    ],
    'Restaurant': [
      'Can I see the menu?',
      'I would like a burger.',
      'Can I get the bill please?',
      'Everything was delicious.',
    ],
    'Small Talk': [
      'Nice weather today.',
      'What do you do for work?',
      'Do you live in Toronto?',
      'That’s really interesting.',
    ],
  },
  'Work': {
    'Job Interview': [
      'Tell me about yourself.',
      'I have experience with customers.',
      'I’m a fast learner.',
      'Thank you for the opportunity.',
    ],
    'Office': [
      'Can you help me with this?',
      'I will finish this today.',
      'Let’s schedule a meeting.',
      'I’ll send you an email.',
    ],
    'Customer Service': [
      'How can I help you?',
      'Thank you for your patience.',
      'I understand your concern.',
      'Have a great day!',
    ],
  },
  'Friends': {
    'Meeting People': [
      'Hi! How are you?',
      'What do you do?',
      'Do you live in Toronto?',
      'It’s nice meeting you.',
    ],
    'Making Friends': [
      'Do you want to hang out?',
      'What are your hobbies?',
      'Let’s practice English together.',
      'You seem really friendly.',
    ],
    'Weekend Plans': [
      'What are you doing this weekend?',
      'Do you want to grab a coffee?',
      'I’m going to an event tonight.',
      'That sounds fun.',
    ],
  },
  'Events': {
    'Social Events': [
      'Is this your first time here?',
      'This event is really nice.',
      'Where are you from?',
      'I love meeting new people.',
    ],
    'Group Conversations': [
      'What are you guys talking about?',
      'That’s really interesting.',
      'I totally agree.',
      'Can I join the conversation?',
    ],
    'Networking': [
      'What do you do for work?',
      'Here’s my Instagram.',
      'Let’s stay in touch.',
      'It was great meeting you.',
    ],
  },
};

const _pt = {
  'Travel': {
    'Introductions': [
      'Oi! Meu nome é Alex.',
      'Prazer em te conhecer.',
      'De onde você é?',
      'Eu sou do Brasil.',
    ],
    'Airport': [
      'Onde fica o portão 24?',
      'Posso ver o seu passaporte?',
      'Meu voo está atrasado.',
      'Onde posso pegar um táxi?',
    ],
    'Hotel': [
      'Eu tenho uma reserva.',
      'Que horas é o check-in?',
      'Pode me passar a senha do Wi-Fi?',
      'Muito obrigado.',
    ],
    'Coffee Shop': [
      'Pode me trazer um café médio?',
      'Quanto custa?',
      'Eu gostaria de um latte.',
      'Obrigado!',
    ],
    'Asking Directions': [
      'Onde fica a estação de metrô?',
      'Como eu chego ao centro?',
      'É longe daqui?',
      'Obrigado pela ajuda.',
    ],
  },
  'Daily Life': {
    'Daily Conversations': [
      'Como foi o seu dia?',
      'Quais são os seus planos hoje?',
      'Estou um pouco cansado hoje.',
      'Hoje foi um dia corrido.',
    ],
    'Shopping': [
      'Quanto custa isso?',
      'Vocês aceitam cartão?',
      'Posso experimentar?',
      'Ficou ótimo.',
    ],
    'Restaurant': [
      'Posso ver o cardápio?',
      'Eu gostaria de um hambúrguer.',
      'Pode trazer a conta, por favor?',
      'Estava tudo delicioso.',
    ],
    'Small Talk': [
      'Que tempo bom hoje.',
      'O que você faz no trabalho?',
      'Você mora em Toronto?',
      'Isso é bem interessante.',
    ],
  },
  'Work': {
    'Job Interview': [
      'Fale um pouco sobre você.',
      'Tenho experiência com clientes.',
      'Eu aprendo rápido.',
      'Obrigado pela oportunidade.',
    ],
    'Office': [
      'Você pode me ajudar com isso?',
      'Eu termino isso hoje.',
      'Vamos marcar uma reunião.',
      'Eu te mando um e-mail.',
    ],
    'Customer Service': [
      'Como posso te ajudar?',
      'Obrigado pela paciência.',
      'Eu entendo a sua preocupação.',
      'Tenha um ótimo dia!',
    ],
  },
  'Friends': {
    'Meeting People': [
      'Oi! Como você está?',
      'O que você faz?',
      'Você mora em Toronto?',
      'Foi um prazer te conhecer.',
    ],
    'Making Friends': [
      'Quer sair algum dia?',
      'Quais são seus hobbies?',
      'Vamos praticar português juntos.',
      'Você parece bem simpático.',
    ],
    'Weekend Plans': [
      'O que você vai fazer no fim de semana?',
      'Quer tomar um café?',
      'Vou a um evento hoje à noite.',
      'Parece divertido.',
    ],
  },
  'Events': {
    'Social Events': [
      'É a sua primeira vez aqui?',
      'Esse evento está bem legal.',
      'De onde você é?',
      'Eu adoro conhecer pessoas novas.',
    ],
    'Group Conversations': [
      'Sobre o que vocês estão falando?',
      'Isso é bem interessante.',
      'Eu concordo totalmente.',
      'Posso entrar na conversa?',
    ],
    'Networking': [
      'O que você faz no trabalho?',
      'Aqui está o meu Instagram.',
      'Vamos manter contato.',
      'Foi ótimo te conhecer.',
    ],
  },
};

const _es = {
  'Travel': {
    'Introductions': [
      '¡Hola! Me llamo Alex.',
      'Mucho gusto.',
      '¿De dónde eres?',
      'Soy de Brasil.',
    ],
    'Airport': [
      '¿Dónde está la puerta 24?',
      '¿Puedo ver tu pasaporte?',
      'Mi vuelo está retrasado.',
      '¿Dónde puedo tomar un taxi?',
    ],
    'Hotel': [
      'Tengo una reserva.',
      '¿A qué hora es el check-in?',
      '¿Me das la contraseña del Wi-Fi?',
      'Muchas gracias.',
    ],
    'Coffee Shop': [
      '¿Me das un café mediano?',
      '¿Cuánto cuesta?',
      'Quisiera un latte.',
      '¡Gracias!',
    ],
    'Asking Directions': [
      '¿Dónde está la estación de metro?',
      '¿Cómo llego al centro?',
      '¿Está lejos de aquí?',
      'Gracias por tu ayuda.',
    ],
  },
  'Daily Life': {
    'Daily Conversations': [
      '¿Cómo estuvo tu día?',
      '¿Cuáles son tus planes hoy?',
      'Estoy un poco cansado hoy.',
      'Hoy fue un día ocupado.',
    ],
    'Shopping': [
      '¿Cuánto cuesta esto?',
      '¿Aceptan tarjetas?',
      '¿Puedo probármelo?',
      'Se ve genial.',
    ],
    'Restaurant': [
      '¿Puedo ver el menú?',
      'Quisiera una hamburguesa.',
      'La cuenta, por favor.',
      'Todo estuvo delicioso.',
    ],
    'Small Talk': [
      'Qué buen clima hoy.',
      '¿A qué te dedicas?',
      '¿Vives en Toronto?',
      'Eso es muy interesante.',
    ],
  },
  'Work': {
    'Job Interview': [
      'Cuéntame sobre ti.',
      'Tengo experiencia con clientes.',
      'Aprendo rápido.',
      'Gracias por la oportunidad.',
    ],
    'Office': [
      '¿Me puedes ayudar con esto?',
      'Lo termino hoy.',
      'Agendemos una reunión.',
      'Te envío un correo.',
    ],
    'Customer Service': [
      '¿Cómo puedo ayudarte?',
      'Gracias por tu paciencia.',
      'Entiendo tu preocupación.',
      '¡Que tengas un gran día!',
    ],
  },
  'Friends': {
    'Meeting People': [
      '¡Hola! ¿Cómo estás?',
      '¿A qué te dedicas?',
      '¿Vives en Toronto?',
      'Encantado de conocerte.',
    ],
    'Making Friends': [
      '¿Quieres salir algún día?',
      '¿Cuáles son tus hobbies?',
      'Practiquemos español juntos.',
      'Pareces muy amable.',
    ],
    'Weekend Plans': [
      '¿Qué harás este fin de semana?',
      '¿Quieres tomar un café?',
      'Voy a un evento esta noche.',
      'Suena divertido.',
    ],
  },
  'Events': {
    'Social Events': [
      '¿Es tu primera vez aquí?',
      'Este evento está muy bien.',
      '¿De dónde eres?',
      'Me encanta conocer gente nueva.',
    ],
    'Group Conversations': [
      '¿De qué están hablando?',
      'Eso es muy interesante.',
      'Estoy totalmente de acuerdo.',
      '¿Puedo unirme a la conversación?',
    ],
    'Networking': [
      '¿A qué te dedicas?',
      'Aquí está mi Instagram.',
      'Mantengámonos en contacto.',
      'Fue un gusto conocerte.',
    ],
  },
};

const _fr = {
  'Travel': {
    'Introductions': [
      'Salut ! Je m’appelle Alex.',
      'Enchanté.',
      'Tu viens d’où ?',
      'Je viens du Brésil.',
    ],
    'Airport': [
      'Où est la porte 24 ?',
      'Puis-je voir ton passeport ?',
      'Mon vol est en retard.',
      'Où puis-je prendre un taxi ?',
    ],
    'Hotel': [
      'J’ai une réservation.',
      'À quelle heure est le check-in ?',
      'Peux-tu me donner le mot de passe Wi-Fi ?',
      'Merci beaucoup.',
    ],
    'Coffee Shop': [
      'Je peux avoir un café moyen ?',
      'Ça coûte combien ?',
      'Je voudrais un latte.',
      'Merci !',
    ],
    'Asking Directions': [
      'Où est la station de métro ?',
      'Comment aller au centre-ville ?',
      'C’est loin d’ici ?',
      'Merci pour ton aide.',
    ],
  },
  'Daily Life': {
    'Daily Conversations': [
      'Comment s’est passée ta journée ?',
      'Quels sont tes plans aujourd’hui ?',
      'Je suis un peu fatigué aujourd’hui.',
      'Aujourd’hui était une journée chargée.',
    ],
    'Shopping': [
      'Combien ça coûte ?',
      'Vous acceptez les cartes ?',
      'Puis-je l’essayer ?',
      'Ça a l’air super.',
    ],
    'Restaurant': [
      'Puis-je voir le menu ?',
      'Je voudrais un burger.',
      'L’addition, s’il vous plaît.',
      'C’était délicieux.',
    ],
    'Small Talk': [
      'Il fait beau aujourd’hui.',
      'Tu fais quoi comme travail ?',
      'Tu habites à Toronto ?',
      'C’est vraiment intéressant.',
    ],
  },
  'Work': {
    'Job Interview': [
      'Parle-moi de toi.',
      'J’ai de l’expérience avec les clients.',
      'J’apprends vite.',
      'Merci pour l’opportunité.',
    ],
    'Office': [
      'Tu peux m’aider avec ça ?',
      'Je vais finir ça aujourd’hui.',
      'Planifions une réunion.',
      'Je t’envoie un e-mail.',
    ],
    'Customer Service': [
      'Comment puis-je t’aider ?',
      'Merci pour ta patience.',
      'Je comprends ta préoccupation.',
      'Bonne journée !',
    ],
  },
  'Friends': {
    'Meeting People': [
      'Salut ! Ça va ?',
      'Tu fais quoi ?',
      'Tu habites à Toronto ?',
      'Ravi de te rencontrer.',
    ],
    'Making Friends': [
      'Tu veux sortir un jour ?',
      'Quels sont tes hobbies ?',
      'Pratiquons le français ensemble.',
      'Tu as l’air très sympa.',
    ],
    'Weekend Plans': [
      'Tu fais quoi ce week-end ?',
      'Tu veux prendre un café ?',
      'Je vais à un événement ce soir.',
      'Ça a l’air fun.',
    ],
  },
  'Events': {
    'Social Events': [
      'C’est ta première fois ici ?',
      'Cet événement est vraiment sympa.',
      'Tu viens d’où ?',
      'J’adore rencontrer de nouvelles personnes.',
    ],
    'Group Conversations': [
      'Vous parlez de quoi ?',
      'C’est vraiment intéressant.',
      'Je suis totalement d’accord.',
      'Je peux rejoindre la conversation ?',
    ],
    'Networking': [
      'Tu fais quoi comme travail ?',
      'Voici mon Instagram.',
      'Restons en contact.',
      'C’était super de te rencontrer.',
    ],
  },
};

/// Retorna o mapa de metas→lições para um código de idioma.
Map<String, Map<String, List<String>>> remiCatalogFor(String languageCode) {
  final code = languageCode.trim().toLowerCase();
  return remiLessonsByCode[code] ?? remiLessonsByCode['en']!;
}
