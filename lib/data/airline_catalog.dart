import 'dart:math' as math;

/// Offline airline identity data used by calendar recognition and flight
/// enrichment. Calendar titles usually contain an IATA prefix (for example
/// `SQ328`), while some providers write the three-letter ICAO callsign (for
/// example `SIA328`). Keeping both forms here makes recognition independent of
/// the language used by the calendar app.
class AirlineIdentity {
  const AirlineIdentity({
    required this.iataCode,
    required this.chineseName,
    required this.englishName,
    this.icaoCode = '',
    this.aliases = const [],
  });

  final String iataCode;
  final String chineseName;
  final String englishName;
  final String icaoCode;
  final List<String> aliases;
}

// This is intentionally a compact, offline list of the global scheduled
// carriers most commonly found in personal itineraries. It covers the IATA
// prefix first, with ICAO and local-name aliases alongside it. Unknown
// prefixes still remain importable; they simply display the prefix itself.
const _airlineIdentities = <AirlineIdentity>[
  // Mainland China, Hong Kong, Macau and Taiwan.
  AirlineIdentity(
    iataCode: '3U',
    icaoCode: 'CSC',
    chineseName: '四川航空',
    englishName: 'Sichuan Airlines',
  ),
  AirlineIdentity(
    iataCode: '8L',
    icaoCode: 'LKE',
    chineseName: '祥鹏航空',
    englishName: 'Lucky Air',
  ),
  AirlineIdentity(
    iataCode: '9C',
    icaoCode: 'CQH',
    chineseName: '春秋航空',
    englishName: 'Spring Airlines',
  ),
  AirlineIdentity(
    iataCode: '9H',
    icaoCode: 'CGN',
    chineseName: '长安航空',
    englishName: 'Air Changan',
  ),
  AirlineIdentity(
    iataCode: 'BK',
    icaoCode: 'OKA',
    chineseName: '奥凯航空',
    englishName: 'Okay Airways',
  ),
  AirlineIdentity(
    iataCode: 'CA',
    icaoCode: 'CCA',
    chineseName: '中国国际航空',
    englishName: 'Air China',
    aliases: ['国航', '中国国航'],
  ),
  AirlineIdentity(
    iataCode: 'CN',
    icaoCode: 'GDC',
    chineseName: '大新华航空',
    englishName: 'Grand China Air',
  ),
  AirlineIdentity(
    iataCode: 'CZ',
    icaoCode: 'CSN',
    chineseName: '中国南方航空',
    englishName: 'China Southern Airlines',
    aliases: ['南航'],
  ),
  AirlineIdentity(
    iataCode: 'EU',
    icaoCode: 'UEA',
    chineseName: '成都航空',
    englishName: 'Chengdu Airlines',
  ),
  AirlineIdentity(
    iataCode: 'FM',
    icaoCode: 'CSH',
    chineseName: '上海航空',
    englishName: 'Shanghai Airlines',
  ),
  AirlineIdentity(
    iataCode: 'FU',
    icaoCode: 'FZA',
    chineseName: '福州航空',
    englishName: 'Fuzhou Airlines',
  ),
  AirlineIdentity(
    iataCode: 'G5',
    icaoCode: 'HXA',
    chineseName: '华夏航空',
    englishName: 'China Express Airlines',
  ),
  AirlineIdentity(
    iataCode: 'GJ',
    icaoCode: 'CDC',
    chineseName: '长龙航空',
    englishName: 'Loong Air',
  ),
  AirlineIdentity(
    iataCode: 'GS',
    icaoCode: 'GCR',
    chineseName: '天津航空',
    englishName: 'Tianjin Airlines',
  ),
  AirlineIdentity(
    iataCode: 'HO',
    icaoCode: 'DKH',
    chineseName: '吉祥航空',
    englishName: 'Juneyao Airlines',
  ),
  AirlineIdentity(
    iataCode: 'HU',
    icaoCode: 'CHH',
    chineseName: '海南航空',
    englishName: 'Hainan Airlines',
    aliases: ['海航'],
  ),
  AirlineIdentity(
    iataCode: 'JD',
    icaoCode: 'CBJ',
    chineseName: '首都航空',
    englishName: 'Beijing Capital Airlines',
  ),
  AirlineIdentity(
    iataCode: 'KN',
    icaoCode: 'CUA',
    chineseName: '中国联合航空',
    englishName: 'China United Airlines',
  ),
  AirlineIdentity(
    iataCode: 'KY',
    icaoCode: 'KNA',
    chineseName: '昆明航空',
    englishName: 'Kunming Airlines',
  ),
  AirlineIdentity(
    iataCode: 'MF',
    icaoCode: 'CXA',
    chineseName: '厦门航空',
    englishName: 'XiamenAir',
    aliases: ['厦航'],
  ),
  AirlineIdentity(
    iataCode: 'MU',
    icaoCode: 'CES',
    chineseName: '中国东方航空',
    englishName: 'China Eastern Airlines',
    aliases: ['东航'],
  ),
  AirlineIdentity(
    iataCode: 'NS',
    icaoCode: 'HBH',
    chineseName: '河北航空',
    englishName: 'Hebei Airlines',
  ),
  AirlineIdentity(
    iataCode: 'OQ',
    icaoCode: 'CQN',
    chineseName: '重庆航空',
    englishName: 'Chongqing Airlines',
  ),
  AirlineIdentity(
    iataCode: 'PN',
    icaoCode: 'CHB',
    chineseName: '西部航空',
    englishName: 'West Air',
  ),
  AirlineIdentity(
    iataCode: 'QW',
    icaoCode: 'QDA',
    chineseName: '青岛航空',
    englishName: 'Qingdao Airlines',
  ),
  AirlineIdentity(
    iataCode: 'SC',
    icaoCode: 'CDG',
    chineseName: '山东航空',
    englishName: 'Shandong Airlines',
    aliases: ['山航'],
  ),
  AirlineIdentity(
    iataCode: 'TV',
    icaoCode: 'TBA',
    chineseName: '西藏航空',
    englishName: 'Tibet Airlines',
  ),
  AirlineIdentity(
    iataCode: 'UQ',
    icaoCode: 'CUH',
    chineseName: '乌鲁木齐航空',
    englishName: 'Urumqi Air',
  ),
  AirlineIdentity(
    iataCode: 'ZH',
    icaoCode: 'CSZ',
    chineseName: '深圳航空',
    englishName: 'Shenzhen Airlines',
    aliases: ['深航'],
  ),
  AirlineIdentity(
    iataCode: 'AE',
    icaoCode: 'MDA',
    chineseName: '华信航空',
    englishName: 'Mandarin Airlines',
  ),
  AirlineIdentity(
    iataCode: 'B7',
    icaoCode: 'UIA',
    chineseName: '立荣航空',
    englishName: 'UNI Air',
  ),
  AirlineIdentity(
    iataCode: 'BR',
    icaoCode: 'EVA',
    chineseName: '长荣航空',
    englishName: 'EVA Air',
  ),
  AirlineIdentity(
    iataCode: 'CI',
    icaoCode: 'CAL',
    chineseName: '中华航空',
    englishName: 'China Airlines',
  ),
  AirlineIdentity(
    iataCode: 'CX',
    icaoCode: 'CPA',
    chineseName: '国泰航空',
    englishName: 'Cathay Pacific',
  ),
  AirlineIdentity(
    iataCode: 'HB',
    icaoCode: 'ALC',
    chineseName: '大湾区航空',
    englishName: 'Greater Bay Airlines',
  ),
  AirlineIdentity(
    iataCode: 'HX',
    icaoCode: 'CRK',
    chineseName: '香港航空',
    englishName: 'Hong Kong Airlines',
  ),
  AirlineIdentity(
    iataCode: 'UO',
    icaoCode: 'HKE',
    chineseName: '香港快运航空',
    englishName: 'Hong Kong Express',
    aliases: ['香港快运', '香港快運', '香港快運航空', 'Hong Kong Express Airways'],
  ),
  AirlineIdentity(
    iataCode: 'JX',
    icaoCode: 'SJX',
    chineseName: '星宇航空',
    englishName: 'STARLUX Airlines',
  ),
  AirlineIdentity(
    iataCode: 'NX',
    icaoCode: 'AMU',
    chineseName: '澳门航空',
    englishName: 'Air Macau',
  ),
  AirlineIdentity(
    iataCode: 'IT',
    icaoCode: 'TTW',
    chineseName: '台湾虎航',
    englishName: 'Tigerair Taiwan',
  ),

  // Southeast Asia.
  AirlineIdentity(
    iataCode: 'AK',
    icaoCode: 'AXM',
    chineseName: '亚洲航空',
    englishName: 'AirAsia',
    aliases: ['亚航'],
  ),
  AirlineIdentity(
    iataCode: 'D7',
    icaoCode: 'XAX',
    chineseName: '亚洲航空长途',
    englishName: 'AirAsia X',
  ),
  AirlineIdentity(
    iataCode: 'FD',
    icaoCode: 'AIQ',
    chineseName: '泰国亚洲航空',
    englishName: 'Thai AirAsia',
  ),
  AirlineIdentity(
    iataCode: 'QZ',
    icaoCode: 'AWQ',
    chineseName: '印尼亚洲航空',
    englishName: 'Indonesia AirAsia',
  ),
  AirlineIdentity(
    iataCode: 'Z2',
    icaoCode: 'APG',
    chineseName: '菲律宾亚洲航空',
    englishName: 'Philippines AirAsia',
  ),
  AirlineIdentity(
    iataCode: '5J',
    icaoCode: 'CEB',
    chineseName: '宿务太平洋航空',
    englishName: 'Cebu Pacific',
  ),
  AirlineIdentity(
    iataCode: 'PR',
    icaoCode: 'PAL',
    chineseName: '菲律宾航空',
    englishName: 'Philippine Airlines',
  ),
  AirlineIdentity(
    iataCode: 'SQ',
    icaoCode: 'SIA',
    chineseName: '新加坡航空',
    englishName: 'Singapore Airlines',
  ),
  AirlineIdentity(
    iataCode: 'TR',
    icaoCode: 'TGW',
    chineseName: '酷航',
    englishName: 'Scoot',
  ),
  AirlineIdentity(
    iataCode: 'MH',
    icaoCode: 'MAS',
    chineseName: '马来西亚航空',
    englishName: 'Malaysia Airlines',
  ),
  AirlineIdentity(
    iataCode: 'OD',
    icaoCode: 'MXD',
    chineseName: '马印航空',
    englishName: 'Batik Air Malaysia',
  ),
  AirlineIdentity(
    iataCode: 'FY',
    icaoCode: 'FFM',
    chineseName: '飞萤航空',
    englishName: 'Firefly',
  ),
  AirlineIdentity(
    iataCode: 'BI',
    icaoCode: 'RBA',
    chineseName: '文莱皇家航空',
    englishName: 'Royal Brunei Airlines',
  ),
  AirlineIdentity(
    iataCode: 'GA',
    icaoCode: 'GIA',
    chineseName: '印尼鹰航空',
    englishName: 'Garuda Indonesia',
  ),
  AirlineIdentity(
    iataCode: 'ID',
    icaoCode: 'BTK',
    chineseName: '巴迪航空',
    englishName: 'Batik Air',
  ),
  AirlineIdentity(
    iataCode: 'JT',
    icaoCode: 'LNI',
    chineseName: '狮子航空',
    englishName: 'Lion Air',
  ),
  AirlineIdentity(
    iataCode: 'QG',
    icaoCode: 'CTV',
    chineseName: '连城航空',
    englishName: 'Citilink',
  ),
  AirlineIdentity(
    iataCode: 'VJ',
    icaoCode: 'VJC',
    chineseName: '越捷航空',
    englishName: 'VietJet Air',
  ),
  AirlineIdentity(
    iataCode: 'VN',
    icaoCode: 'HVN',
    chineseName: '越南航空',
    englishName: 'Vietnam Airlines',
  ),
  AirlineIdentity(
    iataCode: 'TG',
    icaoCode: 'THA',
    chineseName: '泰国国际航空',
    englishName: 'Thai Airways',
  ),
  AirlineIdentity(
    iataCode: 'PG',
    icaoCode: 'BKP',
    chineseName: '曼谷航空',
    englishName: 'Bangkok Airways',
  ),
  AirlineIdentity(
    iataCode: 'SL',
    icaoCode: 'TLM',
    chineseName: '泰国狮航',
    englishName: 'Thai Lion Air',
  ),
  AirlineIdentity(
    iataCode: 'WE',
    icaoCode: 'THD',
    chineseName: '泰国微笑航空',
    englishName: 'Thai Smile',
  ),
  AirlineIdentity(
    iataCode: '8M',
    icaoCode: 'MMA',
    chineseName: '缅甸国际航空',
    englishName: 'Myanmar Airways International',
  ),

  // Japan, Korea and South Asia.
  AirlineIdentity(
    iataCode: 'JL',
    icaoCode: 'JAL',
    chineseName: '日本航空',
    englishName: 'Japan Airlines',
  ),
  AirlineIdentity(
    iataCode: 'NH',
    icaoCode: 'ANA',
    chineseName: '全日空航空',
    englishName: 'All Nippon Airways',
    aliases: ['全日空'],
  ),
  AirlineIdentity(
    iataCode: 'MM',
    icaoCode: 'APJ',
    chineseName: '乐桃航空',
    englishName: 'Peach Aviation',
  ),
  AirlineIdentity(
    iataCode: 'GK',
    icaoCode: 'JJP',
    chineseName: '捷星日本航空',
    englishName: 'Jetstar Japan',
  ),
  AirlineIdentity(
    iataCode: 'BC',
    icaoCode: 'SKY',
    chineseName: '天马航空',
    englishName: 'Skymark Airlines',
  ),
  AirlineIdentity(
    iataCode: '7C',
    icaoCode: 'JJA',
    chineseName: '济州航空',
    englishName: 'Jeju Air',
  ),
  AirlineIdentity(
    iataCode: 'KE',
    icaoCode: 'KAL',
    chineseName: '大韩航空',
    englishName: 'Korean Air',
  ),
  AirlineIdentity(
    iataCode: 'OZ',
    icaoCode: 'AAR',
    chineseName: '韩亚航空',
    englishName: 'Asiana Airlines',
  ),
  AirlineIdentity(
    iataCode: 'LJ',
    icaoCode: 'JNA',
    chineseName: '真航空',
    englishName: 'Jin Air',
  ),
  AirlineIdentity(
    iataCode: 'TW',
    icaoCode: 'TWB',
    chineseName: '德威航空',
    englishName: 'Tway Air',
  ),
  AirlineIdentity(
    iataCode: 'BX',
    icaoCode: 'ABL',
    chineseName: '釜山航空',
    englishName: 'Air Busan',
  ),
  AirlineIdentity(
    iataCode: 'AI',
    icaoCode: 'AIC',
    chineseName: '印度航空',
    englishName: 'Air India',
  ),
  AirlineIdentity(
    iataCode: '6E',
    icaoCode: 'IGO',
    chineseName: '靛蓝航空',
    englishName: 'IndiGo',
  ),
  AirlineIdentity(
    iataCode: 'UK',
    icaoCode: 'VTI',
    chineseName: '维斯塔拉航空',
    englishName: 'Vistara',
  ),
  AirlineIdentity(
    iataCode: 'SG',
    icaoCode: 'SEJ',
    chineseName: '香料航空',
    englishName: 'SpiceJet',
  ),
  AirlineIdentity(
    iataCode: 'I5',
    icaoCode: 'IAD',
    chineseName: '亚洲航空印度',
    englishName: 'Air India Express',
  ),
  AirlineIdentity(
    iataCode: 'UL',
    icaoCode: 'ALK',
    chineseName: '斯里兰卡航空',
    englishName: 'SriLankan Airlines',
  ),
  AirlineIdentity(
    iataCode: 'BG',
    icaoCode: 'BBC',
    chineseName: '孟加拉航空',
    englishName: 'Biman Bangladesh Airlines',
  ),
  AirlineIdentity(
    iataCode: 'RA',
    icaoCode: 'RNA',
    chineseName: '尼泊尔航空',
    englishName: 'Nepal Airlines',
  ),

  // Middle East and Africa.
  AirlineIdentity(
    iataCode: 'EK',
    icaoCode: 'UAE',
    chineseName: '阿联酋航空',
    englishName: 'Emirates',
  ),
  AirlineIdentity(
    iataCode: 'EY',
    icaoCode: 'ETD',
    chineseName: '阿提哈德航空',
    englishName: 'Etihad Airways',
  ),
  AirlineIdentity(
    iataCode: 'FZ',
    icaoCode: 'FDB',
    chineseName: '迪拜航空',
    englishName: 'flydubai',
  ),
  AirlineIdentity(
    iataCode: 'G9',
    icaoCode: 'ABY',
    chineseName: '阿拉伯航空',
    englishName: 'Air Arabia',
  ),
  AirlineIdentity(
    iataCode: 'QR',
    icaoCode: 'QTR',
    chineseName: '卡塔尔航空',
    englishName: 'Qatar Airways',
  ),
  AirlineIdentity(
    iataCode: 'GF',
    icaoCode: 'GFA',
    chineseName: '海湾航空',
    englishName: 'Gulf Air',
  ),
  AirlineIdentity(
    iataCode: 'WY',
    icaoCode: 'OMA',
    chineseName: '阿曼航空',
    englishName: 'Oman Air',
  ),
  AirlineIdentity(
    iataCode: 'KU',
    icaoCode: 'KAC',
    chineseName: '科威特航空',
    englishName: 'Kuwait Airways',
  ),
  AirlineIdentity(
    iataCode: 'SV',
    icaoCode: 'SVA',
    chineseName: '沙特阿拉伯航空',
    englishName: 'Saudia',
  ),
  AirlineIdentity(
    iataCode: 'RJ',
    icaoCode: 'RJA',
    chineseName: '皇家约旦航空',
    englishName: 'Royal Jordanian',
  ),
  AirlineIdentity(
    iataCode: 'ME',
    icaoCode: 'MEA',
    chineseName: '中东航空',
    englishName: 'Middle East Airlines',
  ),
  AirlineIdentity(
    iataCode: 'ET',
    icaoCode: 'ETH',
    chineseName: '埃塞俄比亚航空',
    englishName: 'Ethiopian Airlines',
  ),
  AirlineIdentity(
    iataCode: 'MS',
    icaoCode: 'MSR',
    chineseName: '埃及航空',
    englishName: 'EgyptAir',
  ),
  AirlineIdentity(
    iataCode: 'AT',
    icaoCode: 'RAM',
    chineseName: '摩洛哥皇家航空',
    englishName: 'Royal Air Maroc',
  ),
  AirlineIdentity(
    iataCode: 'KQ',
    icaoCode: 'KQA',
    chineseName: '肯尼亚航空',
    englishName: 'Kenya Airways',
  ),
  AirlineIdentity(
    iataCode: 'SA',
    icaoCode: 'SAA',
    chineseName: '南非航空',
    englishName: 'South African Airways',
  ),
  AirlineIdentity(
    iataCode: 'MK',
    icaoCode: 'MAU',
    chineseName: '毛里求斯航空',
    englishName: 'Air Mauritius',
  ),
  AirlineIdentity(
    iataCode: 'WB',
    icaoCode: 'RWD',
    chineseName: '卢旺达航空',
    englishName: 'RwandAir',
  ),

  // Europe and Türkiye.
  AirlineIdentity(
    iataCode: 'BA',
    icaoCode: 'BAW',
    chineseName: '英国航空',
    englishName: 'British Airways',
  ),
  AirlineIdentity(
    iataCode: 'VS',
    icaoCode: 'VIR',
    chineseName: '维珍大西洋航空',
    englishName: 'Virgin Atlantic',
  ),
  AirlineIdentity(
    iataCode: 'U2',
    icaoCode: 'EZY',
    chineseName: '易捷航空',
    englishName: 'easyJet',
  ),
  AirlineIdentity(
    iataCode: 'FR',
    icaoCode: 'RYR',
    chineseName: '瑞安航空',
    englishName: 'Ryanair',
  ),
  AirlineIdentity(
    iataCode: 'W6',
    icaoCode: 'WZZ',
    chineseName: '威兹航空',
    englishName: 'Wizz Air',
  ),
  AirlineIdentity(
    iataCode: 'LH',
    icaoCode: 'DLH',
    chineseName: '汉莎航空',
    englishName: 'Lufthansa',
  ),
  AirlineIdentity(
    iataCode: 'LX',
    icaoCode: 'SWR',
    chineseName: '瑞士国际航空',
    englishName: 'SWISS',
  ),
  AirlineIdentity(
    iataCode: 'OS',
    icaoCode: 'AUA',
    chineseName: '奥地利航空',
    englishName: 'Austrian Airlines',
  ),
  AirlineIdentity(
    iataCode: 'KL',
    icaoCode: 'KLM',
    chineseName: '荷兰皇家航空',
    englishName: 'KLM Royal Dutch Airlines',
  ),
  AirlineIdentity(
    iataCode: 'AF',
    icaoCode: 'AFR',
    chineseName: '法国航空',
    englishName: 'Air France',
  ),
  AirlineIdentity(
    iataCode: 'VY',
    icaoCode: 'VLG',
    chineseName: '伏林航空',
    englishName: 'Vueling',
  ),
  AirlineIdentity(
    iataCode: 'IB',
    icaoCode: 'IBE',
    chineseName: '伊比利亚航空',
    englishName: 'Iberia',
  ),
  AirlineIdentity(
    iataCode: 'AZ',
    icaoCode: 'ITY',
    chineseName: '意大利航空',
    englishName: 'ITA Airways',
  ),
  AirlineIdentity(
    iataCode: 'SK',
    icaoCode: 'SAS',
    chineseName: '北欧航空',
    englishName: 'Scandinavian Airlines',
  ),
  AirlineIdentity(
    iataCode: 'DY',
    icaoCode: 'NAX',
    chineseName: '挪威航空',
    englishName: 'Norwegian',
  ),
  AirlineIdentity(
    iataCode: 'AY',
    icaoCode: 'FIN',
    chineseName: '芬兰航空',
    englishName: 'Finnair',
  ),
  AirlineIdentity(
    iataCode: 'TP',
    icaoCode: 'TAP',
    chineseName: '葡萄牙航空',
    englishName: 'TAP Air Portugal',
  ),
  AirlineIdentity(
    iataCode: 'LO',
    icaoCode: 'LOT',
    chineseName: '波兰航空',
    englishName: 'LOT Polish Airlines',
  ),
  AirlineIdentity(
    iataCode: 'A3',
    icaoCode: 'AEE',
    chineseName: '爱琴海航空',
    englishName: 'Aegean Airlines',
  ),
  AirlineIdentity(
    iataCode: 'TK',
    icaoCode: 'THY',
    chineseName: '土耳其航空',
    englishName: 'Turkish Airlines',
  ),
  AirlineIdentity(
    iataCode: 'PC',
    icaoCode: 'PGT',
    chineseName: '飞马航空',
    englishName: 'Pegasus Airlines',
  ),
  AirlineIdentity(
    iataCode: 'SU',
    icaoCode: 'AFL',
    chineseName: '俄罗斯航空',
    englishName: 'Aeroflot',
  ),
  AirlineIdentity(
    iataCode: 'S7',
    icaoCode: 'SBI',
    chineseName: '西伯利亚航空',
    englishName: 'S7 Airlines',
  ),
  AirlineIdentity(
    iataCode: 'U6',
    icaoCode: 'SVR',
    chineseName: '乌拉尔航空',
    englishName: 'Ural Airlines',
  ),

  // North and South America.
  AirlineIdentity(
    iataCode: 'AA',
    icaoCode: 'AAL',
    chineseName: '美国航空',
    englishName: 'American Airlines',
  ),
  AirlineIdentity(
    iataCode: 'UA',
    icaoCode: 'UAL',
    chineseName: '美国联合航空',
    englishName: 'United Airlines',
  ),
  AirlineIdentity(
    iataCode: 'DL',
    icaoCode: 'DAL',
    chineseName: '达美航空',
    englishName: 'Delta Air Lines',
  ),
  AirlineIdentity(
    iataCode: 'AC',
    icaoCode: 'ACA',
    chineseName: '加拿大航空',
    englishName: 'Air Canada',
  ),
  AirlineIdentity(
    iataCode: 'WS',
    icaoCode: 'WJA',
    chineseName: '西捷航空',
    englishName: 'WestJet',
  ),
  AirlineIdentity(
    iataCode: 'AS',
    icaoCode: 'ASA',
    chineseName: '阿拉斯加航空',
    englishName: 'Alaska Airlines',
  ),
  AirlineIdentity(
    iataCode: 'B6',
    icaoCode: 'JBU',
    chineseName: '捷蓝航空',
    englishName: 'JetBlue',
  ),
  AirlineIdentity(
    iataCode: 'WN',
    icaoCode: 'SWA',
    chineseName: '西南航空',
    englishName: 'Southwest Airlines',
  ),
  AirlineIdentity(
    iataCode: 'F9',
    icaoCode: 'FFT',
    chineseName: '边疆航空',
    englishName: 'Frontier Airlines',
  ),
  AirlineIdentity(
    iataCode: 'NK',
    icaoCode: 'NKS',
    chineseName: '精神航空',
    englishName: 'Spirit Airlines',
  ),
  AirlineIdentity(
    iataCode: 'HA',
    icaoCode: 'HAL',
    chineseName: '夏威夷航空',
    englishName: 'Hawaiian Airlines',
  ),
  AirlineIdentity(
    iataCode: 'AM',
    icaoCode: 'AMX',
    chineseName: '墨西哥航空',
    englishName: 'Aeromexico',
  ),
  AirlineIdentity(
    iataCode: 'CM',
    icaoCode: 'CMP',
    chineseName: '巴拿马航空',
    englishName: 'Copa Airlines',
  ),
  AirlineIdentity(
    iataCode: 'AV',
    icaoCode: 'AVA',
    chineseName: '哥伦比亚航空',
    englishName: 'Avianca',
  ),
  AirlineIdentity(
    iataCode: 'LA',
    icaoCode: 'LAN',
    chineseName: '智利南美航空',
    englishName: 'LATAM Airlines',
  ),
  AirlineIdentity(
    iataCode: 'G3',
    icaoCode: 'GLO',
    chineseName: '高尔航空',
    englishName: 'GOL Linhas Aereas',
  ),

  // Oceania and Pacific.
  AirlineIdentity(
    iataCode: 'QF',
    icaoCode: 'QFA',
    chineseName: '澳洲航空',
    englishName: 'Qantas',
  ),
  AirlineIdentity(
    iataCode: 'VA',
    icaoCode: 'VOZ',
    chineseName: '维珍澳大利亚航空',
    englishName: 'Virgin Australia',
  ),
  AirlineIdentity(
    iataCode: 'JQ',
    icaoCode: 'JST',
    chineseName: '捷星航空',
    englishName: 'Jetstar',
  ),
  AirlineIdentity(
    iataCode: 'NZ',
    icaoCode: 'ANZ',
    chineseName: '新西兰航空',
    englishName: 'Air New Zealand',
  ),
  AirlineIdentity(
    iataCode: 'FJ',
    icaoCode: 'FJI',
    chineseName: '斐济航空',
    englishName: 'Fiji Airways',
  ),
  AirlineIdentity(
    iataCode: 'SB',
    icaoCode: 'ACI',
    chineseName: '法属新喀里多尼亚航空',
    englishName: 'Aircalin',
  ),
  AirlineIdentity(
    iataCode: 'PX',
    icaoCode: 'ANG',
    chineseName: '巴布亚新几内亚航空',
    englishName: 'Air Niugini',
  ),
];

final _airlineByPrefix = <String, AirlineIdentity>{
  for (final identity in _airlineIdentities) ...{
    identity.iataCode: identity,
    if (identity.icaoCode.trim().isNotEmpty) identity.icaoCode: identity,
  },
};

String _normalizeAirlineText(String value) =>
    value.trim().toUpperCase().replaceAll(RegExp(r'[\s\-_.·•&/]+'), '');

/// Returns the canonical Chinese airline name for an IATA or ICAO prefix.
String? airlineNameForPrefix(String prefix) =>
    _airlineByPrefix[_normalizeAirlineText(prefix)]?.chineseName;

/// Returns the ICAO callsign prefix for an IATA code or an already supplied
/// ICAO prefix. It is useful for providers such as ADSBdb that do not accept
/// every two-letter commercial prefix.
String? airlineIcaoForCode(String code) =>
    _airlineByPrefix[_normalizeAirlineText(code)]?.icaoCode;

/// Returns the IATA code for a typed airline name, IATA code or ICAO code.
/// This is used when a flight number contains digits only and the airline
/// field is the only source of the prefix.
String? airlineIataForName(String value) {
  final query = _normalizeAirlineText(value);
  if (query.isEmpty) return null;
  final direct = _airlineByPrefix[query];
  if (direct != null) return direct.iataCode;
  for (final identity in _airlineIdentities) {
    final values = <String>[
      identity.chineseName,
      identity.englishName,
      ...identity.aliases,
    ];
    if (values.any((item) => _normalizeAirlineText(item) == query)) {
      return identity.iataCode;
    }
  }
  return null;
}

/// Finds a known airline name embedded in a calendar title or description.
/// Some calendar providers omit the two-letter prefix and write titles such
/// as `Singapore Airlines 328 ...`; keeping this helper separate from the
/// exact-name lookup lets the parser recover the prefix without making the
/// title format provider-specific.
String? airlineIataFromText(String value) {
  final query = _normalizeAirlineText(value);
  if (query.isEmpty) return null;
  final identities = [..._airlineIdentities]
    ..sort((left, right) {
      final leftLength = [
        left.englishName,
        left.chineseName,
        ...left.aliases,
      ].fold<int>(0, (length, name) => math.max(length, name.length));
      final rightLength = [
        right.englishName,
        right.chineseName,
        ...right.aliases,
      ].fold<int>(0, (length, name) => math.max(length, name.length));
      return rightLength.compareTo(leftLength);
    });
  for (final identity in identities) {
    final names = <String>[
      identity.englishName,
      identity.chineseName,
      ...identity.aliases,
    ];
    if (names.any((name) => query.contains(_normalizeAirlineText(name)))) {
      return identity.iataCode;
    }
  }
  return null;
}

/// Resolves a calendar title to a Chinese display name. Explicit airline
/// names in the title win when the prefix is unknown; known English names are
/// also detected so titles such as `Singapore Airlines SQ328` are recognized.
String resolveAirlineName(String prefix, {String text = ''}) {
  final direct = airlineNameForPrefix(prefix);
  if (direct != null) return direct;
  final normalizedText = _normalizeAirlineText(text);
  final sorted = [..._airlineIdentities]
    ..sort(
      (left, right) =>
          right.englishName.length.compareTo(left.englishName.length),
    );
  for (final identity in sorted) {
    final names = <String>[
      identity.chineseName,
      identity.englishName,
      ...identity.aliases,
    ];
    if (names.any(
      (name) => normalizedText.contains(_normalizeAirlineText(name)),
    )) {
      return identity.chineseName;
    }
  }
  return prefix.trim().toUpperCase();
}
