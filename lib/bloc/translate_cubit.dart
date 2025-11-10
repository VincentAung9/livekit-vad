import 'package:flutter_bloc/flutter_bloc.dart';

class TranslateCubit extends Cubit<String> {
  TranslateCubit() : super("");
  void emitTranslate(String value) => emit(value);
}
