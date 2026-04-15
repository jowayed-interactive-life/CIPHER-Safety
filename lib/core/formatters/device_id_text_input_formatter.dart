import 'package:flutter/services.dart';

class DeviceIdTextInputFormatter extends TextInputFormatter {
  const DeviceIdTextInputFormatter();

  static String normalize(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();

  static String format(String value) {
    final String normalized = normalize(value);
    if (normalized.isEmpty) return normalized;

    final StringBuffer buffer = StringBuffer();
    for (int index = 0; index < normalized.length; index++) {
      if (index > 0 && index % 3 == 0) {
        buffer.write('-');
      }
      buffer.write(normalized[index]);
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String formatted = format(newValue.text);
    final int normalizedSelectionIndex = normalize(
      newValue.text.substring(0, newValue.selection.end),
    ).length;
    final int dashCountBeforeSelection =
        normalizedSelectionIndex == 0
            ? 0
            : (normalizedSelectionIndex - 1) ~/ 3;
    final int selectionIndex =
        normalizedSelectionIndex + dashCountBeforeSelection;

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: selectionIndex.clamp(0, formatted.length),
      ),
    );
  }
}
