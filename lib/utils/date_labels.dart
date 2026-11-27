/// Libellés de dates façon WhatsApp : « Aujourd'hui », « Hier », jour de la semaine, date.
class DateLabels {
  DateLabels._();

  static const List<String> _weekdays = [
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche',
  ];
  static const List<String> _weekdaysShort = [
    'lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.',
  ];
  static const List<String> _months = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];

  static DateTime? parse(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse('$value')?.toLocal();
  }

  static DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

  static int _daysAgo(DateTime date) {
    return _day(DateTime.now()).difference(_day(date)).inDays;
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// 14:32
  static String clock(DateTime date) => '${_two(date.hour)}:${_two(date.minute)}';

  /// Séparateur de jour dans une conversation : Aujourd'hui / Hier / mardi / 12 novembre 2026
  static String dayLabel(DateTime date) {
    final ago = _daysAgo(date);
    if (ago <= 0) return 'Aujourd’hui';
    if (ago == 1) return 'Hier';
    if (ago < 7) return _weekdays[date.weekday - 1][0].toUpperCase() + _weekdays[date.weekday - 1].substring(1);
    final sameYear = date.year == DateTime.now().year;
    return '${date.day} ${_months[date.month - 1]}${sameYear ? '' : ' ${date.year}'}';
  }

  /// Heure à droite d'une discussion : 14:32 / Hier / lun. / 12/11/2026
  static String conversationStamp(DateTime date) {
    final ago = _daysAgo(date);
    if (ago <= 0) return clock(date);
    if (ago == 1) return 'Hier';
    if (ago < 7) return _weekdaysShort[date.weekday - 1];
    return '${_two(date.day)}/${_two(date.month)}/${date.year}';
  }

  /// Groupes de notifications : Aujourd'hui / Hier / Cette semaine / Plus tôt
  static String notificationGroup(DateTime date) {
    final ago = _daysAgo(date);
    if (ago <= 0) return 'Aujourd’hui';
    if (ago == 1) return 'Hier';
    if (ago < 7) return 'Cette semaine';
    return 'Plus tôt';
  }

  /// Date + heure d'une notification : « Aujourd'hui · 14:32 », « Hier · 09:10 », « 12 novembre · 18:00 »
  static String notificationStamp(DateTime date) {
    final ago = _daysAgo(date);
    if (ago <= 0) return 'Aujourd’hui · ${clock(date)}';
    if (ago == 1) return 'Hier · ${clock(date)}';
    if (ago < 7) return '${_weekdays[date.weekday - 1]} · ${clock(date)}';
    return '${date.day} ${_months[date.month - 1]} · ${clock(date)}';
  }
}
