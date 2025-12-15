import 'package:flutter/material.dart';
import '../services/cast_service.dart';
import '../models/cast_config.dart';

/// Cast button widget for Chromecast/AirPlay
class CastButton extends StatefulWidget {
  /// Cast service instance
  final CastService? castService;

  /// Icon color
  final Color color;

  /// Icon size
  final double size;

  /// Callback when cast devices are found
  final void Function(List<CastDevice>)? onDevicesFound;

  /// Callback when device is selected
  final void Function(CastDevice)? onDeviceSelected;

  /// Callback when cast state changes
  final void Function(CastState, CastDevice?)? onStateChanged;

  const CastButton({
    super.key,
    this.castService,
    this.color = Colors.white,
    this.size = 24,
    this.onDevicesFound,
    this.onDeviceSelected,
    this.onStateChanged,
  });

  @override
  State<CastButton> createState() => _CastButtonState();
}

class _CastButtonState extends State<CastButton> {
  late CastService _castService;
  final ValueNotifier<List<CastDevice>> _devices = ValueNotifier([]);
  final ValueNotifier<bool> _isSearching = ValueNotifier(false);
  final ValueNotifier<CastState> _state = ValueNotifier(CastState.notConnected);

  @override
  void initState() {
    super.initState();
    _castService = widget.castService ?? CastService();
    _initCast();
  }

  @override
  void dispose() {
    _devices.dispose();
    _isSearching.dispose();
    _state.dispose();
    super.dispose();
  }

  Future<void> _initCast() async {
    await _castService.initialize();
    _castService.onCastStateChanged = (state, device) {
      _state.value = state;
      widget.onStateChanged?.call(state, device);
    };
  }

  Future<void> _scanForDevices() async {
    _isSearching.value = true;

    final devices = await _castService.getDevices();
    _devices.value = devices;
    _isSearching.value = false;

    widget.onDevicesFound?.call(devices);

    if (devices.isNotEmpty && mounted) {
      _showDevicePicker();
    }
  }

  void _showDevicePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => ValueListenableBuilder<CastState>(
        valueListenable: _state,
        builder: (context, state, _) {
          return _DevicePickerSheet(
            devices: _devices.value,
            state: state,
            onDeviceSelected: (device) {
              Navigator.pop(context);
              _connectToDevice(device);
            },
            onDisconnect: () {
              Navigator.pop(context);
              _castService.disconnect();
            },
          );
        },
      ),
    );
  }

  Future<void> _connectToDevice(CastDevice device) async {
    widget.onDeviceSelected?.call(device);
    await _castService.castTo(device);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _isSearching,
      builder: (context, isSearching, child) {
        return IconButton(
          icon: _buildIcon(isSearching),
          onPressed: isSearching ? null : _scanForDevices,
          iconSize: widget.size,
          color: widget.color,
        );
      },
    );
  }

  Widget _buildIcon(bool isSearching) {
    if (isSearching) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(widget.color),
        ),
      );
    }

    return ValueListenableBuilder<CastState>(
      valueListenable: _state,
      builder: (context, state, _) {
        switch (state) {
          case CastState.connected:
          case CastState.playing:
          case CastState.paused:
            return Icon(Icons.cast_connected, color: widget.color);
          case CastState.connecting:
            return Icon(Icons.cast, color: widget.color.withOpacity(0.5));
          default:
            return Icon(Icons.cast, color: widget.color);
        }
      },
    );
  }
}

/// Device picker bottom sheet
class _DevicePickerSheet extends StatelessWidget {
  final List<CastDevice> devices;
  final CastState state;
  final void Function(CastDevice) onDeviceSelected;
  final VoidCallback onDisconnect;

  const _DevicePickerSheet({
    required this.devices,
    required this.state,
    required this.onDeviceSelected,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final isConnected = state == CastState.connected ||
        state == CastState.playing ||
        state == CastState.paused;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cast to device',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (devices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No devices found',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            )
          else
            ...devices.map((device) => ListTile(
                  leading: const Icon(Icons.tv, color: Colors.white),
                  title: Text(
                    device.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: device.model != null
                      ? Text(device.model!,
                          style: const TextStyle(color: Colors.white54))
                      : null,
                  onTap: () => onDeviceSelected(device),
                )),
          if (isConnected) ...[
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.close, color: Colors.red),
              title: const Text(
                'Disconnect',
                style: TextStyle(color: Colors.red),
              ),
              onTap: onDisconnect,
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
