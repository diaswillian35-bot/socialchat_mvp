class CountryData {
  final String code;
  final String name;
  final String flag;


  const CountryData({
    required this.code,
    required this.name,
    required this.flag,
  });
}


const List<CountryData> countriesData = [


  // América do Sul
  CountryData(code: 'ar', name: 'Argentina', flag: 'AR'),
  CountryData(code: 'bo', name: 'Bolívia', flag: 'BO'),
  CountryData(code: 'br', name: 'Brasil', flag: 'BR'),
  CountryData(code: 'cl', name: 'Chile', flag: 'CL'),
  CountryData(code: 'co', name: 'Colômbia', flag: 'CO'),
  CountryData(code: 'ec', name: 'Equador', flag: 'EC'),
  CountryData(code: 'gy', name: 'Guiana', flag: 'GY'),
  CountryData(code: 'py', name: 'Paraguai', flag: 'PY'),
  CountryData(code: 'pe', name: 'Peru', flag: 'PE'),
  CountryData(code: 'sr', name: 'Suriname', flag: 'SR'),
  CountryData(code: 'uy', name: 'Uruguai', flag: 'UY'),
  CountryData(code: 've', name: 'Venezuela', flag: 'VE'),


  // América do Norte
  CountryData(code: 'ca', name: 'Canadá', flag: 'CA'),
  CountryData(code: 'us', name: 'Estados Unidos', flag: 'US'),
  CountryData(code: 'mx', name: 'México', flag: 'MX'),


  // Europa
  CountryData(code: 'pt', name: 'Portugal', flag: 'PT'),
  CountryData(code: 'es', name: 'Espanha', flag: 'ES'),
  CountryData(code: 'fr', name: 'França', flag: 'FR'),
  CountryData(code: 'de', name: 'Alemanha', flag: 'DE'),
  CountryData(code: 'it', name: 'Itália', flag: 'IT'),
  CountryData(code: 'ch', name: 'Suíça', flag: 'CH'),
  CountryData(code: 'at', name: 'Áustria', flag: 'AT'),
  CountryData(code: 'be', name: 'Bélgica', flag: 'BE'),
  CountryData(code: 'nl', name: 'Holanda', flag: 'NL'),
  CountryData(code: 'se', name: 'Suécia', flag: 'SE'),
  CountryData(code: 'no', name: 'Noruega', flag: 'NO'),
  CountryData(code: 'dk', name: 'Dinamarca', flag: 'DK'),
  CountryData(code: 'fi', name: 'Finlândia', flag: 'FI'),
  CountryData(code: 'pl', name: 'Polônia', flag: 'PL'),
  CountryData(code: 'cz', name: 'República Tcheca', flag: 'CZ'),
  CountryData(code: 'sk', name: 'Eslováquia', flag: 'SK'),
  CountryData(code: 'hu', name: 'Hungria', flag: 'HU'),
  CountryData(code: 'ro', name: 'Romênia', flag: 'RO'),
  CountryData(code: 'bg', name: 'Bulgária', flag: 'BG'),
  CountryData(code: 'gr', name: 'Grécia', flag: 'GR'),
  CountryData(code: 'hr', name: 'Croácia', flag: 'HR'),
  CountryData(code: 'si', name: 'Eslovênia', flag: 'SI'),
  CountryData(code: 'ee', name: 'Estônia', flag: 'EE'),
  CountryData(code: 'lv', name: 'Letônia', flag: 'LV'),
  CountryData(code: 'lt', name: 'Lituânia', flag: 'LT'),
  CountryData(code: 'ie', name: 'Irlanda', flag: 'IE'),
  CountryData(code: 'gb', name: 'Reino Unido', flag: 'GB'),
  CountryData(code: 'ru', name: 'Rússia', flag: 'RU'),


  // Oceania
  CountryData(code: 'au', name: 'Austrália', flag: 'AU'),
  CountryData(code: 'nz', name: 'Nova Zelândia', flag: 'NZ'),


  // Ásia
  CountryData(code: 'jp', name: 'Japão', flag: 'JP'),
  CountryData(code: 'kr', name: 'Coreia do Sul', flag: 'KR'),
  CountryData(code: 'cn', name: 'China', flag: 'CN'),
  CountryData(code: 'in', name: 'Índia', flag: 'IN'),
  CountryData(code: 'ae', name: 'Emirados Árabes Unidos', flag: 'AE'),
];
