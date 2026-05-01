import 'package:beagle_core/beagle_core.dart';
import 'package:test/test.dart';

void main() {
  group('FilterGenerator', () {
    test('developer default with extension allowlist ends with `- *`', () {
      final f = FilterGenerator().generate(Filters.developerDefault);
      final lines = f.lines;
      expect(lines, contains('+ *.md'));
      expect(lines, contains('+ *.json'));
      expect(lines, contains('+ *.yaml'));
      expect(lines, contains('+ **/'));
      expect(lines.last, '- *');
    });

    test('hidden + vcs + node_modules + build excludes present', () {
      final f = FilterGenerator().generate(Filters.developerDefault);
      expect(f.lines, contains('- .*'));
      expect(f.lines, contains('- .git/**'));
      expect(f.lines, contains('- node_modules/**'));
      expect(f.lines, contains('- build/**'));
      expect(f.lines, contains('- *~'));
      expect(f.lines, contains('- *.swp'));
      expect(f.lines, contains('- .DS_Store'));
    });

    test('custom rules without prefix become excludes', () {
      final f = FilterGenerator().generate(const Filters(
        customRules: ['secret/**'],
      ));
      expect(f.lines, contains('- secret/**'));
    });

    test('custom rules preserve explicit + or -', () {
      final f = FilterGenerator().generate(const Filters(
        customRules: ['+ keep/**', '- drop/**'],
      ));
      expect(f.lines, contains('+ keep/**'));
      expect(f.lines, contains('- drop/**'));
    });

    test('output is byte-stable across runs', () {
      final a = FilterGenerator().generate(Filters.developerDefault).render();
      final b = FilterGenerator().generate(Filters.developerDefault).render();
      expect(a, equals(b));
    });
  });
}
