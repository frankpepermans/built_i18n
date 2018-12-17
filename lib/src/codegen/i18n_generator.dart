import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:dart_style/dart_style.dart';
import 'package:source_gen/source_gen.dart';
import 'package:build/build.dart';
import 'package:csv/csv.dart';

class I18nGenerator extends Generator {
  @override
  FutureOr<String> generate(LibraryReader library, BuildStep buildStep) async {
    final ClassElement element = library.allElements.firstWhere(
        (Element element) =>
            element.location.components.first.contains(buildStep.inputId.path),
        orElse: () => null) as ClassElement;

    if (element == null) return null;

    final path = element.librarySource.uri
        .resolve(
            '${element.librarySource.shortName.split('/').last.split('.dart').first}.csv')
        .pathSegments;
    final assetId = new AssetId(path.first, path.sublist(1).join('/'));
    final csv = await buildStep.readAsString(assetId);
    final rows = const CsvToListConverter().convert(csv);
    final locales = rows.first.sublist(1);
    final buildData = <String, List<List<String>>>{};

    rows.sublist(1).forEach((row) {
      final String id = row[0];

      for (int i = 1, len = row.length; i < len; i++) {
        final String locale = locales[i - 1];
        final String message = row[i];

        buildData.putIfAbsent(locale, () => <List<String>>[]);

        buildData[locale].add([id, toCode(id, message, locale)]);
      }
    });

    buildData.forEach((locale, lines) {
      buildStep.writeAsString(
          assetId.changeExtension('.${locale.toLowerCase()}.dart'),
          new DartFormatter().format('''import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

String formatDateTime(final DateTime dateTime, final String locale) =>
    '\${new DateFormat.yMd(locale).format(dateTime)} \${new DateFormat('HH:mm').format(dateTime)}';

final MessageLookup messages = new MessageLookup();

class MessageLookup extends MessageLookupByLibrary {
  @override
  String get localeName => '$locale';

  @override
  final Map<String, Function> messages = <String, Function>{
    ${lines.map((list) => list.last).join(', ')}
  };
}
'''));
    });

    return null;
  }

  String toCode(String id, String trans, String locale) {
    //'bundles.title': () => Intl.message('Bundles')
    final params = new RegExp(r'\$([\w]+)').allMatches(trans).map((match) =>
        'final ${match.group(1) == 'dateTime' ? 'DateTime' : 'String'} ${match.group(1)}');

    return """'$id': (${params.join(', ')}) => Intl.message('''${trans.replaceAll('dateTime', '''{formatDateTime(dateTime, '$locale')}''')}''')""";
  }

  const I18nGenerator();
}
