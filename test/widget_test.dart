import 'package:flutter_test/flutter_test.dart';
import 'package:aquar_app/main.dart';
void main(){testWidgets('AQUAR login screen renders',(tester)async{await tester.pumpWidget(const AquarApp());expect(find.text('AQUAR'),findsOneWidget);expect(find.text('Đăng nhập'),findsOneWidget);});}
