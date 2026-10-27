import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/dosing.dart';
import '../lib2_util.dart';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real file imports', () async {
    await initStoreLight();
    await dosing.load();
    final p = await dosing.importFiles(['/root/.claude/uploads/18428738-c972-5f0d-b25a-65d8d4d3c81a/8aeebbca-phcc-core-prescribing-handbook-2026-part-01.json']);
    print('${p.single.drugs} drugs, ${p.single.durations} durations');
    print(dosing.searchDrugs('amox').map((d) => d.name).toList());
    print(dosing.searchDrugs('acetaminophen').map((d) => d.name).toList());
    final para = dosing.searchDrugs('paracetamol').single;
    print('indication: ${para.regimens.first.indication} | notes: ${para.regimens.first.notes}');
    expect(para.regimens.first.indication.isNotEmpty, true);
    print('fever search: ${dosing.searchDrugs('fever').map((d) => d.name).toList()}');
    expect(p.single.drugs, 40);
  });
}
