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
      title: 'Parking Sensor Scanner',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const ParkingSensorScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SensorData {
  final String position;
  final double distance;
  final String status;
  final Color color;

  SensorData({
    required this.position,
    required this.distance,
    required this.status,
    required this.color,
  });

  factory SensorData.fromJson(Map<String, dynamic> json) {
    double distance = (json['distance'] ?? 0).toDouble();
    String status = distance > 50
        ? 'SAFE'
        : distance > 25
        ? 'CAUTION'
        : 'DANGER';
    Color color = distance > 50
        ? Colors.green
        : distance > 25
        ? Colors.orange
        : Colors.red;

    return SensorData(
      position: json['position'] ?? '',
      distance: distance,
      status: status,
      color: color,
    );
  }
}

class BluetoothController extends GetxController {
  // Observable variables
  final RxBool isBluetoothEnabled = false.obs;
  final RxBool isPermissionGranted = false.obs;
  final RxBool isScanning = false.obs;
  final RxBool isConnecting = false.obs;
  final RxBool isConnected = false.obs;
  final RxString connectedDeviceName = ''.obs;
  final RxString connectedDeviceId = ''.obs;
  final RxList<BluetoothDevice> availableDevices = <BluetoothDevice>[].obs;

  // Sensor data
  final Rx<SensorData> leftRearSensor = SensorData(
    position: 'Left Rear',
    distance: 0,
    status: 'SAFE',
    color: Colors.green,
  ).obs;

  final Rx<SensorData> rightRearSensor = SensorData(
    position: 'Right Rear',
    distance: 0,
    status: 'SAFE',
    color: Colors.green,
  ).obs;

  final Rx<SensorData> leftFrontSensor = SensorData(
    position: 'Left Front',
    distance: 0,
    status: 'SAFE',
    color: Colors.green,
  ).obs;

  final Rx<SensorData> rightFrontSensor = SensorData(
    position: 'Right Front',
    distance: 0,
    status: 'SAFE',
    color: Colors.green,
  ).obs;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _readCharacteristic;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _characteristicSubscription;
  Timer? _dataSimulationTimer;

  @override
  void onInit() {
    super.onInit();
    _initializeBluetooth();
  }

  @override
  void onClose() {
    _cleanup();
    super.onClose();
  }

  void _cleanup() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _characteristicSubscription?.cancel();
    _dataSimulationTimer?.cancel();
    _connectedDevice?.disconnect();
  }

  Future<void> _initializeBluetooth() async {
    try {
      // Check if Bluetooth is supported
      if (await FlutterBluePlus.isSupported == false) {
        _showErrorSnackbar(
          'Bluetooth not supported',
          'This device does not support Bluetooth',
        );
        return;
      }

      // Request permissions
      await _requestPermissions();

      // Listen to Bluetooth adapter state
      FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
        isBluetoothEnabled.value = state == BluetoothAdapterState.on;
      });

      // Check initial state
      isBluetoothEnabled.value = await FlutterBluePlus.isOn;
    } catch (e) {
      _showErrorSnackbar(
        'Initialization Error',
        'Failed to initialize Bluetooth: $e',
      );
    }
  }

  Future<void> _requestPermissions() async {
    try {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.location,
      ].request();

      bool allGranted = statuses.values.every(
        (status) =>
            status == PermissionStatus.granted ||
            status == PermissionStatus.limited,
      );

      isPermissionGranted.value = allGranted;

      if (!allGranted) {
        _showErrorSnackbar(
          'Permissions Required',
          'Please grant all Bluetooth permissions',
        );
      }
    } catch (e) {
      _showErrorSnackbar(
        'Permission Error',
        'Failed to request permissions: $e',
      );
    }
  }

  Future<void> scanForDevices() async {
    if (!isBluetoothEnabled.value) {
      _showErrorSnackbar('Bluetooth Disabled', 'Please enable Bluetooth first');
      return;
    }

    if (!isPermissionGranted.value) {
      await _requestPermissions();
      if (!isPermissionGranted.value) return;
    }

    try {
      availableDevices.clear();
      isScanning.value = true;

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );

      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          for (ScanResult result in results) {
            BluetoothDevice device = result.device;
            print('Discovered: ${device.platformName} - ${device.remoteId}');

            if (!availableDevices.any((d) => d.remoteId == device.remoteId)) {
              availableDevices.add(device);
            }
          }
        },
        onError: (e) {
          _showErrorSnackbar('Scan Error', 'Error during scan: $e');
        },
      );

      // Failsafe: manually stop scan after 10 seconds
      Future.delayed(const Duration(seconds: 10), () async {
        await stopScan();
        if (availableDevices.isEmpty) {
          _showInfoSnackbar(
            'No Devices Found',
            'No Bluetooth devices were discovered',
          );
        } else {
          _showDeviceSelectionDialog();
        }
      });
    } catch (e) {
      isScanning.value = false;
      _showErrorSnackbar('Scan Error', 'Failed to scan for devices: $e');
    }
  }

  Future<void> sca233nForDevices() async {
    if (!isBluetoothEnabled.value) {
      _showErrorSnackbar('Bluetooth Disabled', 'Please enable Bluetooth first');
      return;
    }

    if (!isPermissionGranted.value) {
      await _requestPermissions();
      if (!isPermissionGranted.value) return;
    }

    try {
      availableDevices.clear();
      isScanning.value = true;

      // Start scanning
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          for (ScanResult result in results) {
            if (!availableDevices.any(
              (device) => device.remoteId == result.device.remoteId,
            )) {
              if (result.device.platformName.isNotEmpty ||
                  result.advertisementData.localName.isNotEmpty) {
                availableDevices.add(result.device);
              }
            }
          }
        },
        onError: (e) {
          _showErrorSnackbar('Scan Error', 'Error during scan: $e');
        },
      );

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        androidUsesFineLocation: true,
      );

      // Auto-stop scanning after timeout
      await Future.delayed(const Duration(seconds: 10));
      await stopScan();

      if (availableDevices.isNotEmpty) {
        _showDeviceSelectionDialog();
      } else {
        _showInfoSnackbar(
          'No Devices Found',
          'No Bluetooth devices were discovered',
        );
      }
    } catch (e) {
      isScanning.value = false;
      _showErrorSnackbar('Scan Error', 'Failed to scan for devices: $e');
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
      isScanning.value = false;
    } catch (e) {
      _showErrorSnackbar('Stop Scan Error', 'Failed to stop scan: $e');
    }
  }

  void _showDeviceSelectionDialog() {
    Get.dialog(
      AlertDialog(
        title: const Text(
          'Select Device',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: availableDevices.length,
            itemBuilder: (context, index) {
              BluetoothDevice device = availableDevices[index];
              String deviceName = device.platformName.isNotEmpty
                  ? device.platformName
                  : 'Unknown Device';

              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.bluetooth, color: Colors.white),
                  ),
                  title: Text(
                    deviceName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(device.remoteId.toString()),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Get.back();
                    connectToDevice(device);
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
        ],
      ),
    );
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      isConnecting.value = true;

      // Connect to device
      await device.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = device;

      // Listen for connection state changes
      _connectionSubscription = device.connectionState.listen((
        BluetoothConnectionState state,
      ) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });

      // Discover services
      List<BluetoothService> services = await device.discoverServices();

      // Find characteristics for communication
      await _setupCharacteristics(services);

      // Update connection state
      isConnecting.value = false;
      isConnected.value = true;
      connectedDeviceName.value = device.platformName.isNotEmpty
          ? device.platformName
          : 'Unknown Device';
      connectedDeviceId.value = device.remoteId.toString();

      _showSuccessSnackbar(
        'Connected',
        'Successfully connected to ${connectedDeviceName.value}',
      );

      // Start simulating sensor data for demo purposes
      _startDataSimulation();
    } catch (e) {
      isConnecting.value = false;
      _showErrorSnackbar(
        'Connection Failed',
        'Failed to connect to device: $e',
      );
    }
  }

  Future<void> _setupCharacteristics(List<BluetoothService> services) async {
    for (BluetoothService service in services) {
      for (BluetoothCharacteristic characteristic in service.characteristics) {
        if (characteristic.properties.write) {
          _writeCharacteristic = characteristic;
        }
        if (characteristic.properties.read ||
            characteristic.properties.notify) {
          _readCharacteristic = characteristic;

          // Enable notifications if supported
          if (characteristic.properties.notify) {
            await characteristic.setNotifyValue(true);
            _characteristicSubscription = characteristic.onValueReceived.listen(
              (value) {
                _handleReceivedData(value);
              },
            );
          }
        }
      }
    }
  }

  void _handleReceivedData(List<int> data) {
    try {
      String receivedText = utf8.decode(data);
      Map<String, dynamic> sensorData = jsonDecode(receivedText);

      // Update sensor data based on received JSON
      if (sensorData.containsKey('leftRear')) {
        leftRearSensor.value = SensorData.fromJson({
          'position': 'Left Rear',
          'distance': sensorData['leftRear'],
        });
      }

      if (sensorData.containsKey('rightRear')) {
        rightRearSensor.value = SensorData.fromJson({
          'position': 'Right Rear',
          'distance': sensorData['rightRear'],
        });
      }

      if (sensorData.containsKey('leftFront')) {
        leftFrontSensor.value = SensorData.fromJson({
          'position': 'Left Front',
          'distance': sensorData['leftFront'],
        });
      }

      if (sensorData.containsKey('rightFront')) {
        rightFrontSensor.value = SensorData.fromJson({
          'position': 'Right Front',
          'distance': sensorData['rightFront'],
        });
      }
    } catch (e) {
      print('Error parsing sensor data: $e');
    }
  }

  void _startDataSimulation() {
    // Simulate real sensor data for demo
    _dataSimulationTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (isConnected.value) {
        // Simulate varying distances
        leftRearSensor.value = SensorData.fromJson({
          'position': 'Left Rear',
          'distance': 30 + (DateTime.now().millisecond % 40),
        });

        rightRearSensor.value = SensorData.fromJson({
          'position': 'Right Rear',
          'distance': 45 + (DateTime.now().millisecond % 30),
        });

        leftFrontSensor.value = SensorData.fromJson({
          'position': 'Left Front',
          'distance': 60 + (DateTime.now().millisecond % 25),
        });

        rightFrontSensor.value = SensorData.fromJson({
          'position': 'Right Front',
          'distance': 20 + (DateTime.now().millisecond % 35),
        });
      }
    });
  }

  void _handleDisconnection() {
    isConnected.value = false;
    connectedDeviceName.value = '';
    connectedDeviceId.value = '';
    _connectedDevice = null;
    _writeCharacteristic = null;
    _readCharacteristic = null;
    _dataSimulationTimer?.cancel();

    _showInfoSnackbar('Disconnected', 'Device has been disconnected');
  }

  Future<void> disconnectDevice() async {
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
        _handleDisconnection();
        _showSuccessSnackbar(
          'Disconnected',
          'Device disconnected successfully',
        );
      } catch (e) {
        _showErrorSnackbar('Disconnect Error', 'Failed to disconnect: $e');
      }
    }
  }

  Future<void> sendCommand(String command) async {
    if (_connectedDevice == null || !isConnected.value) {
      _showErrorSnackbar('No Connection', 'No device connected');
      return;
    }

    if (_writeCharacteristic == null) {
      _showErrorSnackbar('Write Error', 'Device does not support writing data');
      return;
    }

    try {
      List<int> bytes = utf8.encode(command);
      await _writeCharacteristic!.write(bytes);
      _showSuccessSnackbar('Command Sent', 'Command sent successfully');
    } catch (e) {
      _showErrorSnackbar('Send Error', 'Failed to send command: $e');
    }
  }

  void _showSuccessSnackbar(String title, String message) {
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.green.shade100,
      colorText: Colors.green.shade800,
      icon: const Icon(Icons.check_circle, color: Colors.green),
      duration: const Duration(seconds: 3),
    );
  }

  void _showErrorSnackbar(String title, String message) {
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.red.shade100,
      colorText: Colors.red.shade800,
      icon: const Icon(Icons.error, color: Colors.red),
      duration: const Duration(seconds: 4),
    );
  }

  void _showInfoSnackbar(String title, String message) {
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.blue.shade100,
      colorText: Colors.blue.shade800,
      icon: const Icon(Icons.info, color: Colors.blue),
      duration: const Duration(seconds: 3),
    );
  }
}

class ParkingSensorScreen extends StatelessWidget {
  const ParkingSensorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final BluetoothController controller = Get.put(BluetoothController());

    return Scaffold(
      backgroundColor: const Color(0xFFE8E1F5),
      appBar: AppBar(
        title: const Text(
          'Parking Sensor Scanner',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: const Color(0xFFE8E1F5),
        elevation: 0,
        actions: [
          Obx(
            () => controller.isConnected.value
                ? IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.black87),
                    onPressed: () => controller.sendCommand('refresh'),
                  )
                : const SizedBox.shrink(),
          ),
          Obx(
            () => controller.isConnected.value
                ? IconButton(
                    icon: const Icon(Icons.add, color: Colors.black87),
                    onPressed: () => _showAddDeviceDialog(controller),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Obx(() {
          if (controller.isConnected.value) {
            return _buildConnectedView(controller);
          } else {
            return _buildDisconnectedView(controller);
          }
        }),
      ),
    );
  }

  Widget _buildConnectedView(BluetoothController controller) {
    return Column(
      children: [
        // Connection Status Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Colors.green,
                radius: 24,
                child: Icon(
                  Icons.bluetooth_connected,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Connected to:',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Obx(
                      () => Text(
                        controller.connectedDeviceName.value,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Obx(
                      () => Text(
                        controller.connectedDeviceId.value,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // Live Parking Sensors Title
        const Text(
          'Live Parking Sensors',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),

        const SizedBox(height: 24),

        // Sensor Grid
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.0,
            children: [
              _buildSensorCard(controller.leftRearSensor),
              _buildSensorCard(controller.rightRearSensor),
              _buildSensorCard(controller.leftFrontSensor),
              _buildSensorCard(controller.rightFrontSensor),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Disconnect Button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: controller.disconnectDevice,
            icon: const Icon(Icons.bluetooth_disabled, color: Colors.white),
            label: const Text(
              'Disconnect Device',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDisconnectedView(BluetoothController controller) {
    return Column(
      children: [
        const SizedBox(height: 32),

        // Status Cards Row
        Row(
          children: [
            Expanded(
              child: Obx(
                () => _buildStatusCard(
                  'Bluetooth',
                  controller.isBluetoothEnabled.value ? 'Enabled' : 'Disabled',
                  controller.isBluetoothEnabled.value
                      ? Colors.green
                      : Colors.red,
                  Icons.bluetooth,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Obx(
                () => _buildStatusCard(
                  'Permissions',
                  controller.isPermissionGranted.value ? 'Granted' : 'Required',
                  controller.isPermissionGranted.value
                      ? Colors.green
                      : Colors.orange,
                  Icons.check_circle,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 32),

        // Scan Button
        Obx(
          () => SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed:
                  controller.isBluetoothEnabled.value &&
                      !controller.isScanning.value &&
                      !controller.isConnecting.value
                  ? controller.scanForDevices
                  : null,
              icon: controller.isScanning.value || controller.isConnecting.value
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.bluetooth_searching),
              label: Text(
                controller.isScanning.value
                    ? 'Scanning...'
                    : controller.isConnecting.value
                    ? 'Connecting...'
                    : 'Scan for Devices',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
          ),
        ),

        const Spacer(),

        // Bluetooth Icon and Description
        const Icon(Icons.bluetooth, size: 80, color: Colors.grey),
        const SizedBox(height: 16),
        const Text(
          'Tap "Scan for Devices" to discover\nBluetooth Classic devices',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),

        const SizedBox(height: 32),

        // Add Device Manually Button
        TextButton.icon(
          onPressed: () => _showAddDeviceDialog(controller),
          icon: const Icon(Icons.add, color: Colors.grey),
          label: const Text(
            'Add Device Manually',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),

        const Spacer(),
      ],
    );
  }

  Widget _buildStatusCard(
    String title,
    String status,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            status,
            style: TextStyle(
              fontSize: 14,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorCard(Rx<SensorData> sensorData) {
    return Obx(
      () => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: sensorData.value.color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: sensorData.value.color.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.directions_car, color: Colors.white, size: 32),
            const SizedBox(height: 12),
            Text(
              sensorData.value.position,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${sensorData.value.distance.toInt()}cm',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  sensorData.value.status == 'SAFE'
                      ? Icons.check_circle
                      : sensorData.value.status == 'CAUTION'
                      ? Icons.warning
                      : Icons.error,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  sensorData.value.status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAddDeviceDialog(BluetoothController controller) {
    final TextEditingController deviceController = TextEditingController();

    Get.dialog(
      AlertDialog(
        title: const Text('Add Device Manually'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: deviceController,
              decoration: const InputDecoration(
                labelText: 'Device MAC Address',
                hintText: 'XX:XX:XX:XX:XX:XX',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Enter the MAC address of your Bluetooth device',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              // Handle manual device addition
              Get.back();
              controller._showInfoSnackbar(
                'Feature Coming Soon',
                'Manual device addition will be available in the next update',
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
