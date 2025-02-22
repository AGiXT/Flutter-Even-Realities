import 'dart:math';

class EvenAIDataMethod {
  static List<String> measureStringList(String text) {
    List<String> list = [];
    int maxLength = 100; // Maximum length of each string
    int start = 0;
    int end = maxLength;

    while (start < text.length) {
      if (end > text.length) {
        end = text.length;
      }
      list.add(text.substring(start, end));
      start = end;
      end += maxLength;
    }

    return list;
  }

  static int transferToNewScreen(int type, int status) {
    // Implement the logic to transfer to a new screen based on type and status
    return type + status;
  }
}