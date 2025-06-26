import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:get/get.dart';
import 'dart:convert';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Bluetooth Classic App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class BluetoothController extends GetxController {
  // Observable variables
  final RxBool isBluetoothOn = false.obs;
  final RxBool isScanning = false.obs;
  final RxBool isConnecting = false.obs;
  final RxBool isConnected = false.obs;
  final RxString connectedDeviceName = ''.obs;
  final RxString receivedData = ''.obs;
  final RxList<String> dataHistory = <String>[].obs;
  final RxList<BluetoothDevice> devicesList = <BluetoothDevice>[].obs;
  final TextEditingController sendController = TextEditingController();
  
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _readCharacteristic;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _characteristicSubscription;

  @override
  void onInit() {
    super.onInit();
    _initializeBluetooth();
  }

  @override
  void onClose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _characteristicSubscription?.cancel();
    _connectedDevice?.disconnect();
    sendController.dispose();
    super.onClose();
  }

  Future<void> _initializeBluetooth() async {
    // Check if Bluetooth is supported
    if (await FlutterBluePlus.isSupported == false) {
      Get.snackbar(
        'Not Supported',
        'Bluetooth not supported by this device',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade100,
        colorText: Colors.red.shade800,
      );
      return;
    }

    // Request permissions
    await _requestPermissions();

    // Listen to Bluetooth adapter state
    FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
      isBluetoothOn.value = state == BluetoothAdapterState.on;
    });

    // Check initial state
    isBluetoothOn.value = await FlutterBluePlus.isOn;
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.location,
    ].request();

    print('Permission statuses: $statuses');
  }

  Future<void> scanAndShowDevices() async {
    if (!isBluetoothOn.value) {
      Get.snackbar(
        'Bluetooth Error',
        'Please enable Bluetooth first',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade100,
        colorText: Colors.red.shade800,
      );
      return;
    }

    devicesList.clear();
    isScanning.value = true;

    Get.dialog(
      WillPopScope(
        onWillPop: () async {
          await FlutterBluePlus.stopScan();
          isScanning.value = false;
          return true;
        },
        child: AlertDialog(
          title: const Text('Scanning for Devices'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Looking for nearby devices...'),
              const SizedBox(height: 16),
              Obx(() => Text('Found ${devicesList.length} devices')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                FlutterBluePlus.stopScan();
                isScanning.value = false;
                Get.back();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                FlutterBluePlus.stopScan();
                isScanning.value = false;
                Get.back();
                if (devicesList.isNotEmpty) {
                  _showDeviceSelectionDialog(devicesList);
                } else {
                  Get.snackbar(
                    'No Devices',
                    'No devices found',
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: Colors.orange.shade100,
                    colorText: Colors.orange.shade800,
                  );
                }
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
      barrierDismissible: false,
    );

    try {
      // Start scanning
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          for (ScanResult result in results) {
            if (!devicesList.any((device) => device.remoteId == result.device.remoteId)) {
              if (result.device.platformName.isNotEmpty) {
                devicesList.add(result.device);
              }
            }
          }
        },
        onError: (e) {
          Get.snackbar(
            'Scan Error',
            'Error during scan: $e',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red.shade100,
            colorText: Colors.red.shade800,
          );
        },
      );

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );

      // Auto-stop scanning after timeout
      await Future.delayed(const Duration(seconds: 15));
      await FlutterBluePlus.stopScan();
      isScanning.value = false;

    } catch (e) {
      isScanning.value = false;
      Get.back();
      Get.snackbar(
        'Scan Error',
        'Error scanning devices: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade100,
        colorText: Colors.red.shade800,
      );
    }
  }

  void _showDeviceSelectionDialog(List<BluetoothDevice> devices) {
    Get.dialog(
      AlertDialog(
        title: const Text('Select Device'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: devices.length,
            itemBuilder: (context, index) {
              BluetoothDevice device = devices[index];
              return ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(device.platformName.isNotEmpty ? device.platformName : 'Unknown Device'),
                subtitle: Text(device.remoteId.toString()),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Get.back();
                  connectToDevice(device);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    isConnecting.value = true;

    try {
      // Connect to device
      await device.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = device;
      
      // Listen for connection state changes
      _connectionSubscription = device.connectionState.listen((BluetoothConnectionState state) {
        if (state == BluetoothConnectionState.disconnected) {
          isConnected.value = false;
          connectedDeviceName.value = '';
          _connectedDevice = null;
          _writeCharacteristic = null;
          _readCharacteristic = null;
          Get.snackbar(
            'Disconnected',
            'Device disconnected',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.orange.shade100,
            colorText: Colors.orange.shade800,
          );
        }
      });

      // Discover services
      List<BluetoothService> services = await device.discoverServices();
      
      // Find characteristics for communication
      for (BluetoothService service in services) {
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          if (characteristic.properties.write) {
            _writeCharacteristic = characteristic;
          }
          if (characteristic.properties.read || characteristic.properties.notify) {
            _readCharacteristic = characteristic;
            // Enable notifications if supported
            if (characteristic.properties.notify) {
              await characteristic.setNotifyValue(true);
              _characteristicSubscription = characteristic.onValueReceived.listen((value) {
                String receivedText = utf8.decode(value);
                receivedData.value = receivedText;
                dataHistory.insert(0, 'Received: $receivedText - ${DateTime.now().toString().substring(11, 19)}');
                if (dataHistory.length > 50) {
                  dataHistory.removeLast();
                }
              });
            }
          }
        }
      }

      isConnecting.value = false;
      isConnected.value = true;
      connectedDeviceName.value = device.platformName.isNotEmpty ? device.platformName : 'Unknown Device';

      Get.snackbar(
        'Connected',
        'Connected to ${connectedDeviceName.value}',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.shade100,
        colorText: Colors.green.shade800,
        icon: const Icon(Icons.check_circle, color: Colors.green),
      );

    } catch (e) {
      isConnecting.value = false;
      Get.snackbar(
        'Connection Failed',
        'Failed to connect: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade100,
        colorText: Colors.red.shade800,
      );
    }
  }

  Future<void> sendData(String data) async {
    if (_connectedDevice == null || !isConnected.value) {
      Get.snackbar(
        'No Connection',
        'No device connected',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange.shade100,
        colorText: Colors.orange.shade800,
      );
      return;
    }

    if (data.isEmpty) {
      Get.snackbar(
        'Empty Data',
        'Enter data to send',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange.shade100,
        colorText: Colors.orange.shade800,
      );
      return;
    }

    if (_writeCharacteristic == null) {
      Get.snackbar(
        'No Write Characteristic',
        'Device does not support writing data',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange.shade100,
        colorText: Colors.orange.shade800,
      );
      return;
    }

    try {
      List<int> bytes = utf8.encode(data);
      await _writeCharacteristic!.write(bytes);
      
      dataHistory.insert(0, 'Sent: $data - ${DateTime.now().toString().substring(11, 19)}');
      if (dataHistory.length > 50) {
        dataHistory.removeLast();
      }
      
      sendController.clear();
      Get.snackbar(
        'Data Sent',
        'Data sent successfully',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.shade100,
        colorText: Colors.green.shade800,
        icon: const Icon(Icons.send, color: Colors.green),
      );
    } catch (e) {
      Get.snackbar(
        'Send Error',
        'Error sending data: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade100,
        colorText: Colors.red.shade800,
      );
    }
  }

  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      isConnected.value = false;
      connectedDeviceName.value = '';
      receivedData.value = '';
      dataHistory.clear();
      _connectedDevice = null;
      _writeCharacteristic = null;
      _readCharacteristic = null;
      Get.snackbar(
        'Disconnected',
        'Device disconnected successfully',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.blue.shade100,
        colorText: Colors.blue.shade800,
        icon: const Icon(Icons.bluetooth_disabled, color: Colors.blue),
      );
    }
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final BluetoothController controller = Get.put(BluetoothController());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Classic App'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Message
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.waving_hand, color: Colors.orange.shade600, size: 28),
                  const SizedBox(width: 12),
                  const Text(
                    'Welcome Shaban',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),

            // Bluetooth Status
            Obx(() => Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: controller.isBluetoothOn.value 
                    ? Colors.green.shade50 
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: controller.isBluetoothOn.value 
                      ? Colors.green.shade200 
                      : Colors.red.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.bluetooth,
                    color: controller.isBluetoothOn.value 
                        ? Colors.green.shade700 
                        : Colors.red.shade700,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Bluetooth: ${controller.isBluetoothOn.value ? 'ON' : 'OFF'}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: controller.isBluetoothOn.value 
                          ? Colors.green.shade700 
                          : Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            )),

            const SizedBox(height: 20),

            // Get Devices Button
            Obx(() => SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: controller.isBluetoothOn.value && !controller.isScanning.value && !controller.isConnecting.value
                    ? controller.scanAndShowDevices
                    : null,
                icon: controller.isScanning.value || controller.isConnecting.value
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.search),
                label: Text(
                  controller.isScanning.value 
                      ? 'Scanning...' 
                      : controller.isConnecting.value 
                          ? 'Connecting...' 
                          : 'Get Devices'
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            )),

            const SizedBox(height: 20),

            // Connection Status Dashboard
            Obx(() => controller.isConnected.value ? Expanded(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Device Dashboard',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: controller.disconnect,
                              icon: const Icon(Icons.close, size: 16),
                              label: const Text('Disconnect'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.device_hub, color: Colors.green),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Device: ${controller.connectedDeviceName.value}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Row(
                          children: [
                            Icon(Icons.circle, color: Colors.green, size: 12),
                            SizedBox(width: 8),
                            Text(
                              'Status: Connected',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Send Data Section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Send Data',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: controller.sendController,
                                decoration: const InputDecoration(
                                  hintText: 'Enter data to send...',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                onSubmitted: controller.sendData,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => controller.sendData(controller.sendController.text),
                              icon: const Icon(Icons.send, size: 16),
                              label: const Text('Send'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Data History
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Data History',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Obx(() => controller.dataHistory.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No data exchanged yet...',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: controller.dataHistory.length,
                                    itemBuilder: (context, index) {
                                      String entry = controller.dataHistory[index];
                                      bool isSent = entry.startsWith('Sent:');
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 4),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: isSent 
                                              ? Colors.blue.shade100 
                                              : Colors.green.shade100,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              isSent ? Icons.arrow_upward : Icons.arrow_downward,
                                              size: 16,
                                              color: isSent ? Colors.blue : Colors.green,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                entry,
                                                style: const TextStyle(fontSize: 12),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  )),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ) : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}