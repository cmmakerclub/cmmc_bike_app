// Copyright 2017, Paul DeMarco.
// All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import "dart:convert";
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'widgets.dart';
import 'package:barcode_scan/barcode_scan.dart';
import 'package:flutter/services.dart';
import "package:pointycastle/pointycastle.dart";

void main() {
  runApp(new FlutterBlueApp());
}

class FlutterBlueApp extends StatefulWidget {
  FlutterBlueApp({this.title}) : super();

  final String title;

  @override
  _FlutterBlueAppState createState() => new _FlutterBlueAppState();
}

class _FlutterBlueAppState extends State<FlutterBlueApp> {
  FlutterBlue _flutterBlue = FlutterBlue.instance;

  /// Scanning
  StreamSubscription _scanSubscription;
  Map<DeviceIdentifier, ScanResult> scanResults = new Map();
  bool isScanning = false;

  /// State
  StreamSubscription _stateSubscription;
  BluetoothState state = BluetoothState.unknown;

  /// Device
  BluetoothDevice device;
  bool get isConnected => (device != null);
  StreamSubscription deviceConnection;
  StreamSubscription deviceStateSubscription;
  List<BluetoothService> services = new List();
  Map<Guid, StreamSubscription> valueChangedSubscriptions = {};
  BluetoothDeviceState deviceState = BluetoothDeviceState.disconnected;

  String barcode = "";
  String connectToDeviceName = "";
  bool isConnecting = false;
  @override
  void initState() {
    super.initState();
    
    // Immediately get the state of FlutterBlue
    _flutterBlue.state.then((s) {
      setState(() {
        state = s;
      });
    });
    // Subscribe to state changes
    _stateSubscription = _flutterBlue.onStateChanged().listen((s) {
      setState(() {
        state = s;
      });
    });
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _stateSubscription = null;
    _scanSubscription?.cancel();
    _scanSubscription = null;
    deviceConnection?.cancel();
    deviceConnection = null;
    super.dispose();
  }

  Future scanQR() async {
    
    try {
      String barcode = await BarcodeScanner.scan();
      setState(() {
        this.barcode = barcode;
        connectToDeviceName = barcode;
        _startScan();
        
      });
    } on PlatformException catch (e) {
      if (e.code == BarcodeScanner.CameraAccessDenied) {
        setState(() {
          this.barcode = 'The user did not grant the camera permission!';
        });
      } else {
        setState(() => this.barcode = 'Unknown error: $e');
      }
    } on FormatException{
      setState(() => this.barcode = 'null (User returned using the "back"-button before scanning anything. Result)');
    } catch (e) {
      setState(() => this.barcode = 'Unknown error: $e');
    }
  }

  _startScan() {
    _scanSubscription = _flutterBlue
        .scan(
      timeout: const Duration(seconds: 5),
      withServices: [
          new Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E')
        ]
      )
        .listen((scanResult) {
          print('name: ${scanResult.device.name}');
          print('device id: ${scanResult.device.id}');
          print('localName: ${scanResult.advertisementData.localName}');
          print(
              'manufacturerData: ${scanResult.advertisementData.manufacturerData}');
          print('serviceData: ${scanResult.advertisementData.serviceData}');
          setState(() {
            scanResults[scanResult.device.id] = scanResult;
          });
    }, onDone: _stopScan);

    setState(() {
      isScanning = true;
    });
  }

  _stopScan() {
    _scanSubscription?.cancel();
    _scanSubscription = null;
    setState(() {
      isScanning = false;
    });
  }

  _connect(BluetoothDevice d) async {
    device = d;
    // Connect to device
    deviceConnection = _flutterBlue
      .connect(device, timeout: const Duration(seconds: 4))
        .listen(
          null,
          onDone: _disconnect,
        );

    // Update the connection state immediately
    device.state.then((s) {
      setState(() {
        deviceState = s;
      });
    });

    // Subscribe to connection changes
    deviceStateSubscription = device.onStateChanged().listen((s) {
      setState(() {
        deviceState = s;
      });
      if (s == BluetoothDeviceState.connected) {
        device.discoverServices().then((s) {
          setState(() {
            services = s;
            setState(() {
              _sendDataUnlock();              
            });
          });
        });
      }
    });
  }

  _disconnect() {
    // Remove all value changed listeners
    valueChangedSubscriptions.forEach((uuid, sub) => sub.cancel());
    valueChangedSubscriptions.clear();
    deviceStateSubscription?.cancel();
    deviceStateSubscription = null;
    deviceConnection?.cancel();
    deviceConnection = null;

    setState(() {
      scanResults = new Map();
      connectToDeviceName = "";
      isConnecting = false;
      device = null;
    });
  }

  _readCharacteristic(BluetoothCharacteristic c) async {
    await device.readCharacteristic(c);
    setState(() {});
  }

  _writeCharacteristic(BluetoothCharacteristic c) async {
    await device.writeCharacteristic(c, [0x7c],
        type: CharacteristicWriteType.withoutResponse);      
    setState(() {});
  }

  _writeCharacteristicAuth(BluetoothCharacteristic c) async {
    Uint8List keyData = Uint8List.fromList([
        0x60, 0x3d, 0xeb, 0x10, 0x15, 0xca, 0x71, 0xbe, 0x2b, 0x73, 0xae, 0xf0, 0x85, 0x7d, 0x77, 0x81,
                      0x1f, 0x35, 0x2c, 0x07, 0x3b, 0x61, 0x08, 0xd7, 0x2d, 0x98, 0x10, 0xa3, 0x09, 0x14, 0xdf, 0xf4
      ]);
    Uint8List ivData = Uint8List.fromList([
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f
      ]);
    Uint8List message = Uint8List.fromList([
        0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61
      ]);  
    // Key must be multiple of block size (16 bytes).
    // var key = new Digest("SHA-256").process(keyData);
    // Can be anything.
    // The initialization vector must be unique for every message, so it is a
    // good idea to use a message digest as the IV.
    // IV must be equal to block size (16 bytes).
    // var iv = new Digest("SHA-256").process(ivData).sublist(0, 16);
    // The parameters your cipher will need. (PKCS7 does not need params.)
    CipherParameters params = new PaddedBlockCipherParameters(
        new ParametersWithIV(new KeyParameter(keyData), ivData), null);

    ////////////////
    // Encrypting //
    ////////////////

    // As for why you would need CBC mode and PKCS7 padding, consult the internet
    // (f.e. http://www.di-mgt.com.au/properpassword.html).
    BlockCipher encryptionCipher = new PaddedBlockCipher("AES/CBC/PKCS7");
    encryptionCipher.init(true, params);
    Uint8List encrypted = encryptionCipher.process(message);

    // |
    await device.writeCharacteristic(c, [124], type: CharacteristicWriteType.withoutResponse);

    for (int i = 0; i < encrypted.length; i++)
    {
      await device.writeCharacteristic(c, [encrypted[i]], type: CharacteristicWriteType.withoutResponse);
    }

    setState(() {});
  }

    _writeCharacteristicUnlock(BluetoothCharacteristic c) async {
    await device.writeCharacteristic(c, [0x75],
        type: CharacteristicWriteType.withoutResponse);        
    setState(() {});
  }

  _readDescriptor(BluetoothDescriptor d) async {
    await device.readDescriptor(d);
    setState(() {});
  }

  _writeDescriptor(BluetoothDescriptor d) async {
    await device.writeDescriptor(d, [0x12, 0x34]);
    setState(() {});
  }

  _setNotification(BluetoothCharacteristic c) async {
    if (c.isNotifying) {
      await device.setNotifyValue(c, false);
      // Cancel subscription
      valueChangedSubscriptions[c.uuid]?.cancel();
      valueChangedSubscriptions.remove(c.uuid);
    } else {
      await device.setNotifyValue(c, true);
      // ignore: cancel_subscriptions
      final sub = device.onValueChanged(c).listen((d) {
        setState(() {
          print('onValueChanged $d');
          if (utf8.decode(d) == "OK")
          {
            print("ok");
            _disconnect();
          }
        });
      });
      // Add to map
      valueChangedSubscriptions[c.uuid] = sub;
    }
    setState(() {});
  }

  _refreshDeviceState(BluetoothDevice d) async {
    var state = await d.state;
    setState(() {
      deviceState = state;
      print('State refreshed: $deviceState');
    });
  }

  _buildScanningButton() {
    if (isConnected || state != BluetoothState.on) {
      return null;
    }
    if (isScanning) {
      return new FloatingActionButton(
        child: new Icon(Icons.stop),
        onPressed: _stopScan,
        backgroundColor: Colors.red,
      );
    } else {
      return new FloatingActionButton(
             child: new Icon(Icons.search), onPressed: scanQR);
    }
  }

  _tryConnectBle() {
    // return scanResults.values
    //     .map((r) => ScanResultTile(
    //           result: r,
    //           onTap: () => _connect(r.device),
    //         ))
    //     .toList();

    // print(scanResults);
    // return Text('Loading');
    scanResults.forEach((k,v) { 

      print('----------------------');
      print('${v.device.name} {$connectToDeviceName}');
      if (v.device.name == connectToDeviceName)
      {
        _stopScan();
        setState(() {
          isConnecting = true;
          print('${v.device}');
          _connect(v.device);
        });
      }
    });
  }

  _sendDataUnlock() async {
    
    for (int i = 0; i < services.length; i++)
    {
      for (int j = 0; j < services[i].characteristics.length; j++)
      {
        if (services[i].characteristics[j].uuid.toString() == '6e400003-b5a3-f393-e0a9-e50e24dcca9e')
        {
          await _setNotification(services[i].characteristics[j]);
        }
        if (services[i].characteristics[j].uuid.toString() == '80bf2a15-73bd-465e-a80f-c8c910821495')
        {
          print("send data");
          print(services[i].characteristics[j].uuid);
          await _writeCharacteristicAuth(services[i].characteristics[j]);
        }
      }
    }

    for (int i = 0; i < services.length; i++)
    {
      for (int j = 0; j < services[i].characteristics.length; j++)
      {
        if (services[i].characteristics[j].uuid.toString() == '6e400002-b5a3-f393-e0a9-e50e24dcca9e')
        {
          print("send data");
          print(services[i].characteristics[j].uuid);
          await _writeCharacteristicUnlock(services[i].characteristics[j]);
        }
      }
    }

    Future.delayed(const Duration(milliseconds: 300), () {
      // _disconnect();
    });

  }

  List<Widget> _buildServiceTiles() {
    return services
        .map(
          (s) => new ServiceTile(
                service: s,
                characteristicTiles: s.characteristics
                    .map(
                      (c) => new CharacteristicTile(
                            characteristic: c,
                            onReadPressed: () => _readCharacteristic(c),
                            onWritePressed: () => _writeCharacteristic(c),
                            onNotificationPressed: () => _setNotification(c),
                            descriptorTiles: c.descriptors
                                .map(
                                  (d) => new DescriptorTile(
                                        descriptor: d,
                                        onReadPressed: () => _readDescriptor(d),
                                        onWritePressed: () =>
                                            _writeDescriptor(d),
                                      ),
                                )
                                .toList(),
                          ),
                    )
                    .toList(),
              ),
        )
        .toList();
  }

  _buildActionButtons() {
    if (isConnected) {
      return <Widget>[
        new IconButton(
          icon: const Icon(Icons.cancel),
          onPressed: () => _disconnect(),
        )
      ];
    }
  }

  _buildAlertTile() {
    return new Container(
      color: Colors.redAccent,
      child: new ListTile(
        title: new Text(
          'Bluetooth adapter is ${state.toString().substring(15)}',
          style: Theme.of(context).primaryTextTheme.subhead,
        ),
        trailing: new Icon(
          Icons.error,
          color: Theme.of(context).primaryTextTheme.subhead.color,
        ),
      ),
    );
  }

  _buildDeviceStateTile() {
    return new ListTile(
        leading: (deviceState == BluetoothDeviceState.connected)
            ? const Icon(Icons.bluetooth_connected)
            : const Icon(Icons.bluetooth_disabled),
        title: new Text('Device is ${deviceState.toString().split('.')[1]}.'),
        subtitle: new Text('${device.id}'),
        trailing: new IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _refreshDeviceState(device),
          color: Theme.of(context).iconTheme.color.withOpacity(0.5),
        ));
  }

  _buildProgressBarTile() {
    return new LinearProgressIndicator();
  }

  @override
  Widget build(BuildContext context) {
    var tiles = new List<Widget>();
    if (state != BluetoothState.on) {
      tiles.add(_buildAlertTile());
    }
    if (isConnected) {
      tiles.add(_buildDeviceStateTile());
      tiles.addAll(_buildServiceTiles());

    } else {
      if (isConnecting == false) {
        _tryConnectBle();
      }
    }
    return new MaterialApp(
      home: new Scaffold(
        appBar: new AppBar(
          title: const Text('CMMC Bike'),
          actions: _buildActionButtons(),
        ),
        floatingActionButton: _buildScanningButton(),
        body: new Stack(
          children: <Widget>[
            (isScanning) ? _buildProgressBarTile() : new Container(),
            new ListView(
              children: tiles,
            )
          ],
        ),
      ),
    );
  }
}