import 'dart:convert';
import 'dart:typed_data';

// import 'package:agixt_even_realities/ble_manager.dart'; // Removed old import
import 'package:agixt_even_realities/services/evenai_proto.dart';
import 'package:agixt_even_realities/utils/utils.dart';
import 'ble.dart'; // Import BleReceive definition
import 'package:get/get.dart';
import 'bluetooth_service.dart'; // Import BluetoothService

class Proto {
  static String lR() {
    final BluetoothService bluetoothService = Get.find<BluetoothService>();
    if (bluetoothService.isLeftConnected.value && bluetoothService.isRightConnected.value) return "R";
    if (bluetoothService.isRightConnected.value) return "R";
    return "L";
  }

  /// Returns the time consumed by the command and whether it is successful
  static Future<(int, bool)> micOn({
    String? lr,
  }) async {
    var begin = Utils.getTimestampMs();
    var data = Uint8List.fromList([0x0E, 0x01]);
    final BluetoothService bluetoothService = Get.find<BluetoothService>();
    var receive = BleReceive();
    receive.isTimeout = true;
    String targetSide = lr ?? lR();
    try {
      if (targetSide == "R" && bluetoothService.isRightConnected.value) {
        // TODO: Implement actual Bluetooth write and read logic for right device
        // Placeholder for now
        receive.isTimeout = true;
      } else if (targetSide == "L" && bluetoothService.isLeftConnected.value) {
        // TODO: Implement actual Bluetooth write and read logic for left device
        receive.isTimeout = true;
      }
    } catch (e) {
      print("Error in micOn: $e");
      receive.isTimeout = true;
    }

    var end = Utils.getTimestampMs();
    var startMic = (begin + ((end - begin) ~/ 2));

    print("Proto---micOn---startMic---$startMic-------");
    return (startMic, (!receive.isTimeout && receive.data[1] == 0xc9));
  }

  /// Even AI
  static int _evenaiSeq = 0;
  // AI result transmission (also compatible with AI startup and Q&A status synchronization)
  static Future<bool> sendEvenAIData(String text,
      {int? timeoutMs,
      required int newScreen,
      required int pos,
      required int current_page_num,
      required int max_page_num}) async {
    var data = utf8.encode(text);
    var syncSeq = _evenaiSeq & 0xff;

    List<Uint8List> dataList = EvenaiProto.evenaiMultiPackListV2(0x4E,
        data: data,
        syncSeq: syncSeq,
        newScreen: newScreen,
        pos: pos,
        current_page_num: current_page_num,
        max_page_num: max_page_num);
    _evenaiSeq++;

    print(
        '${DateTime.now()} proto--sendEvenAIData---text---$text---_evenaiSeq----$_evenaiSeq---newScreen---$newScreen---pos---$pos---current_page_num--$current_page_num---max_page_num--$max_page_num--dataList----$dataList---');

    final BluetoothService bluetoothService = Get.find<BluetoothService>();
    bool isSuccess = false;
    try {
      if (bluetoothService.isLeftConnected.value) {
        // TODO: Implement actual Bluetooth write logic for left device
        // Placeholder for now
        isSuccess = false;
      }
    } catch (e) {
      print("Error sending data to Left: $e");
      isSuccess = false;
    }

    print(
        '${DateTime.now()} sendEvenAIData-----isSuccess-----$isSuccess-------');
    if (!isSuccess) {
      print("${DateTime.now()} sendEvenAIData failed  L ");
      return false;
    } else {
      if (bluetoothService.isRightConnected.value) {
        // TODO: Implement actual Bluetooth write logic for right device
        // Placeholder for now
        isSuccess = false;
      }

      if (!isSuccess) {
        print("${DateTime.now()} sendEvenAIData failed R ");
        return false;
      }
      return true;
    }
  }

  static int _beatHeartSeq = 0;
  static Future<bool> sendHeartBeat() async {
    var length = 6;
    var data = Uint8List.fromList([
      0x25,
      length & 0xff,
      (length >> 8) & 0xff,
      _beatHeartSeq % 0xff,
      0x04,
      _beatHeartSeq % 0xff //0xff,
    ]);
    _beatHeartSeq++;

    print('${DateTime.now()} sendHeartBeat--------data---$data--');
    final BluetoothService bluetoothService = Get.find<BluetoothService>();
    var ret = BleReceive();
    ret.isTimeout = true;
    try {
      if (bluetoothService.isLeftConnected.value) {
        // TODO: Implement actual Bluetooth write and read logic for left device
        ret.isTimeout = true;
      }
    } catch (e) {
      print("Error sending heartbeat to Left: $e");
      ret.isTimeout = true;
    }

    print('${DateTime.now()} sendHeartBeat----L----ret---${ret.data}--');
    if (ret.isTimeout) {
      print('${DateTime.now()} sendHeartBeat----L----time out--');
      return false;
    } else if (ret.data[0].toInt() == 0x25 &&
        ret.data.length > 5 &&
        ret.data[4].toInt() == 0x04) {
      var retR = BleReceive();
      retR.isTimeout = true;
      try {
        if (bluetoothService.isRightConnected.value) {
          // TODO: Implement actual Bluetooth write and read logic for right device
          retR.isTimeout = true;
        }
      } catch (e) {
        print("Error sending heartbeat to Right: $e");
        retR.isTimeout = true;
      }
      print('${DateTime.now()} sendHeartBeat----R----retR---${retR.data}--');
      if (retR.isTimeout) {
        return false;
      } else if (retR.data[0].toInt() == 0x25 &&
          retR.data.length > 5 &&
          retR.data[4].toInt() == 0x04) {
        return true;
      } else {
        return false;
      }
    } else {
      return false;
    }
  }

  static Future<String> getLegSn(String lr) async {
    var cmd = Uint8List.fromList([0x34]);
    final BluetoothService bluetoothService = Get.find<BluetoothService>();
    var resp = BleReceive();
    resp.isTimeout = true;
    try {
      if (lr == "R" && bluetoothService.isRightConnected.value) {
        // TODO: Implement actual Bluetooth write and read logic for right device
        resp.isTimeout = true;
      } else if (lr == "L" && bluetoothService.isLeftConnected.value) {
        // TODO: Implement actual Bluetooth write and read logic for left device
        resp.isTimeout = true;
      }
    } catch (e) {
      print("Error getting LegSn: $e");
      resp.isTimeout = true;
    }
    var sn = resp.data.length > 18 ? String.fromCharCodes(resp.data.sublist(2, 18).toList()) : "";
    return sn;
  }

  // tell the glasses to exit function to dashboard
  static Future<bool> exit() async {
    print("send exit all func");
    var data = Uint8List.fromList([0x18]);

    final BluetoothService bluetoothService = Get.find<BluetoothService>();
    var retL = BleReceive();
    retL.isTimeout = true;
    try {
      if (bluetoothService.isLeftConnected.value) {
        // TODO: Implement actual Bluetooth write and read logic for left device
        retL.isTimeout = true;
      }
    } catch (e) {
      print("Error sending exit to Left: $e");
      retL.isTimeout = true;
    }
    print('${DateTime.now()} exit----L----ret---${retL.data}--');
    if (retL.isTimeout) {
      return false;
    } else if (retL.data.isNotEmpty && retL.data.length > 1 && retL.data[1].toInt() == 0xc9) {
      var retR = BleReceive();
      retR.isTimeout = true;
      try {
        if (bluetoothService.isRightConnected.value) {
          // TODO: Implement actual Bluetooth write and read logic for right device
          retR.isTimeout = true;
        }
      } catch (e) {
        print("Error sending exit to Right: $e");
        retR.isTimeout = true;
      }
      print('${DateTime.now()} exit----R----retR---${retR.data}--');
      if (retR.isTimeout) {
        return false;
      } else if (retR.data.isNotEmpty && retR.data[1].toInt() == 0xc9) {
        return true;
      } else {
        return false;
      }
    } else {
      return false;
    }
  }

  static List<Uint8List> _getPackList(int cmd, Uint8List data,
      {int count = 20}) {
    final realCount = count - 3;
    List<Uint8List> send = [];
    int maxSeq = data.length ~/ realCount;
    if (data.length % realCount > 0) {
      maxSeq++;
    }
    for (var seq = 0; seq < maxSeq; seq++) {
      var start = seq * realCount;
      var end = start + realCount;
      if (end > data.length) {
        end = data.length;
      }
      var itemData = data.sublist(start, end);
      var pack = Utils.addPrefixToUint8List([cmd, maxSeq, seq], itemData);
      send.add(pack);
    }
    return send;
  }

  static Future<void> sendNewAppWhiteListJson(String whitelistJson) async {
    print("proto -> sendNewAppWhiteListJson: whitelist = $whitelistJson");
    final whitelistData = utf8.encode(whitelistJson);
    //  2、转换为接口格式
    final dataList = _getPackList(0x04, whitelistData, count: 180);
    print(
        "proto -> sendNewAppWhiteListJson: length = ${dataList.length}, dataList = $dataList");
    for (var i = 0; i < 3; i++) {
      final BluetoothService bluetoothService = Get.find<BluetoothService>();
      final isSuccess = false;
      try {
        if (bluetoothService.isLeftConnected.value) {
          // TODO: Implement actual Bluetooth write logic for left device
        }
      } catch (e) {
        print("Error sending whitelist to Left: $e");
      }
      if (isSuccess) {
        return;
      }
    }
  }

  /// 发送通知
  ///
  /// - app [Map] 通知消息数据
  static Future<void> sendNotify(Map appData, int notifyId,
      {int retry = 6}) async {
    final notifyJson = jsonEncode({
      "ncs_notification": appData,
    });
    final dataList =
        _getNotifyPackList(0x4B, notifyId, utf8.encode(notifyJson));
    print(
        "proto -> sendNotify: notifyId = $notifyId, data length = ${dataList.length} , data = $dataList, app = $notifyJson");
    for (var i = 0; i < retry; i++) {
      final BluetoothService bluetoothService = Get.find<BluetoothService>();
      final isSuccess = false;
      try {
        if (bluetoothService.isLeftConnected.value) {
          // TODO: Implement actual Bluetooth write logic for left device
        }
      } catch (e) {
        print("Error sending notify to Left: $e");
      }
      if (isSuccess) {
        return;
      }
    }
  }

  static List<Uint8List> _getNotifyPackList(
      int cmd, int msgId, Uint8List data) {
    List<Uint8List> send = [];
    int maxSeq = data.length ~/ 176;
    if (data.length % 176 > 0) {
      maxSeq++;
    }
    for (var seq = 0; seq < maxSeq; seq++) {
      var start = seq * 176;
      var end = start + 176;
      if (end > data.length) {
        end = data.length;
      }
      var itemData = data.sublist(start, end);
      var pack =
          Utils.addPrefixToUint8List([cmd, msgId, maxSeq, seq], itemData);
      send.add(pack);
    }
    return send;
  }
}
