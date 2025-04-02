import 'package:agixtsdk/agixtsdk.dart'; // Import AGiXT SDK
import 'package:get/get.dart'; // Import Get for potential config access later
import '../controllers/server_config_controller.dart'; // Import ServerConfigController

class ApiService {
  late AGiXTSDK _agixtSdk; // Use AGiXTSDK
  final ServerConfigController _configController = Get.find<ServerConfigController>(); // Get config controller instance

  ApiService() {
    // Initialize AGiXTSDK using values from ServerConfigController
    _agixtSdk = AGiXTSDK(
      baseUri: _configController.serverUrl.value,
      apiKey: _configController.apiKey.value.isNotEmpty ? _configController.apiKey.value : null,
      verbose: true, // Enable verbose logging for debugging
    );

    // Listen for config changes to re-initialize the SDK
    _configController.serverUrl.listen((_) => _reinitializeSdk());
    _configController.apiKey.listen((_) => _reinitializeSdk());
  }

  /* Future<String> sendChatRequest_OLD(String question) async {
      "messages": [
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": question}
      ],
    };
    print("sendChatRequest------data----------$data--------");

    try {
      final response = await _dio.post('/chat/completions', data: data);

      if (response.statusCode == 200) {
          print("Response: ${response.data}");

          final data = response.data;
          final content = data['choices']?[0]?['message']?['content'] ?? "Unable to answer the question";
          return content;
      } else {
        print("Request failed with status: ${response.statusCode}");
        return "Request failed with status: ${response.statusCode}";
      }
    } on DioError catch (e) {
      if (e.response != null) {
        print("Error: ${e.response?.statusCode}, ${e.response?.data}");
        return "AI request error: ${e.response?.statusCode}, ${e.response?.data}";
      } else {
        print("Error: ${e.message}");
        return "AI request error: ${e.message}";
      }
    }
  }
  */

  void _reinitializeSdk() {
    print("Reinitializing AGiXTSDK with new config...");
    _agixtSdk = AGiXTSDK(
      baseUri: _configController.serverUrl.value,
      apiKey: _configController.apiKey.value.isNotEmpty ? _configController.apiKey.value : null,
      verbose: true,
    );
  }

  Future<String> sendChatRequest(String question, {String agentName = "AGiXT", String conversationName = "EvenRealitiesChat"}) async {
    print("Sending AGiXT chat request: Agent=$agentName, Conversation=$conversationName, Question=$question");

    final chatPrompt = ChatCompletions(
      model: agentName, // Use agentName as the model identifier for AGiXT
      messages: [
        {"role": "user", "content": question}
      ],
      user: conversationName, // Use conversationName as the user identifier
      // Add other parameters like temperature, maxTokens if needed
    );

    try {
      final response = await _agixtSdk.chatCompletions(
        chatPrompt,
        (userInput) => _agixtSdk.chat(agentName, userInput, conversationName), // Pass the chat function
      );

      print("AGiXT Response: $response");
      final content = response['choices']?[0]?['message']?['content'] ?? "AGiXT was unable to answer the question";
      return content;
    } catch (e) {
      print("AGiXT request error: $e");
      return "AGiXT request error: $e"; // Return error message
    }
  }
}
