import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// import 'package:screen_brightness/screen_brightness.dart';

/// Fullscreen camera capture screen (WhatsApp-style)
/// Opens camera → user captures → preview with Retake/Send → returns file path
class CameraCaptureScreen extends StatefulWidget {
  final bool isClockIn;

  const CameraCaptureScreen({super.key, this.isClockIn = true});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  String? _capturedPath;
  bool _isCapturing = false;
  bool _triggerFlash = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    // 🛡️ CRITICAL FIX: Wait for the first frame to render before starting camera.
    // This ensures the Android Looper is fully active on the UI thread.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed && mounted) {
        _initCamera();
      }
    });
    _forceHighBrightness();
  }

  Future<void> _forceHighBrightness() async {
    // try {
    //   await ScreenBrightness().setScreenBrightness(1.0);
    // } catch (_) {}
  }

  Future<void> _initCamera() async {
    try {
      // 🛡️ CRITICAL FIX: Dispose old controller if it exists
      // This prevents the "Session already active" crash on Oppo/Vivo.
      if (_controller != null) {
        await _controller!.dispose();
        _controller = null;
      }

      // 🛡️ CRITICAL FIX: Wait for 100ms (Optimized for performance)
      // This ensures the Android "Looper" is ready before the camera starts.
      await Future.delayed(const Duration(milliseconds: 100));

      if (_isDisposed || !mounted) return;

      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _showCameraError("No cameras found on this device.");
        return;
      }

      final front = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      _controller = controller;
      await controller.initialize();

      if (_isDisposed || !mounted) {
        await controller.dispose();
        return;
      }

      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      setState(() => _isInitialized = true);
    } on CameraException catch (e) {
      debugPrint("Camera init CameraException: $e");
      _showCameraError(
          "Camera error: ${e.description ?? 'Unknown error'}. Please check permissions.");
    } on PlatformException catch (e) {
      debugPrint("Camera init PlatformException: ${e.code} - ${e.message}");
      if (e.code == 'no_available_camera') {
        _showCameraError(
            "No cameras available on this device. Please ensure your camera is not disabled or in use by another app.");
      } else {
        _showCameraError(
            "Device camera error: ${e.message ?? 'Unknown'}. Please restart the app.");
      }
    } catch (e) {
      debugPrint("Camera init error: $e");
      _showCameraError("Could not start camera. Please try again.");
    }
  }

  void _showCameraError(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Camera Error"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (_isCapturing || !_isInitialized || controller == null) return;

    // Immediately lock capture state synchronously
    _isCapturing = true;

    try {
      // Flash simulation
      setState(() => _triggerFlash = true);
      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted) setState(() => _triggerFlash = false);

      if (!controller.value.isTakingPicture) {
        final image = await controller.takePicture();

        if (mounted) {
          setState(() {
            _capturedPath = image.path;
            _isCapturing = false;
          });
        }
      } else {
        _isCapturing = false;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _triggerFlash = false;
          _isCapturing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Capture failed: $e")),
        );
      }
    }
  }

  void _retake() {
    setState(() => _capturedPath = null);
  }

  void _send() {
    // 1️⃣ USER RULE: Capture exact time when SEND is pressed.
    final DateTime captureTime = DateTime.now();
    bool isFrontCamera =
        _controller?.description.lensDirection == CameraLensDirection.front;

    // Return BOTH the path and the precise time it was confirmed.
    Navigator.pop(context, <String, dynamic>{
      'path': _capturedPath,
      'captureTime': captureTime,
      'isFrontCamera': isFrontCamera,
    });
  }

  @override
  void dispose() {
    if (_isDisposed) return; // Already disposing
    _isDisposed = true;

    // 🔥 CRITICAL FIX: Nullify controller reference before disposing
    // This helps prevent race conditions where the UI or background tasks
    // try to access a controller that is in the middle of closing.
    final controller = _controller;
    _controller = null;

    if (controller != null) {
      // Disposing asynchronously to avoid blocking the main thread
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview or captured image
          if (_capturedPath != null)
            // 🔥 FIX: Check if it's front camera and visually flip the captured preview
            // so the user doesn't see the mirror effect before sending.
            _controller?.description.lensDirection == CameraLensDirection.front
                ? Transform.scale(
                    scaleX: -1,
                    child: Image.file(
                      File(_capturedPath!),
                      fit: BoxFit.contain,
                    ),
                  )
                : Image.file(
                    File(_capturedPath!),
                    fit: BoxFit.contain,
                  )
          else if (_isInitialized && _controller != null)
            Builder(builder: (context) {
              final ctrl = _controller!;
              return SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: ctrl.value.previewSize?.height ?? 100,
                    height: ctrl.value.previewSize?.width ??
                        (100 * ctrl.value.aspectRatio),
                    child: CameraPreview(ctrl),
                  ),
                ),
              );
            })
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

          // Flash overlay
          if (_triggerFlash) Container(color: Colors.white),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 28),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.isClockIn
                            ? const Color(0xFF075E54)
                            : const Color(0xFF5C2D2D),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        widget.isClockIn ? "📸 Clock In" : "📸 Clock Out",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48), // Balance
                  ],
                ),
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: _capturedPath == null
                    ? _buildCaptureButton()
                    : _buildPreviewButtons(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureButton() {
    return Center(
      child: GestureDetector(
        onTap: _capture,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isCapturing ? Colors.grey : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Retake
        GestureDetector(
          onTap: _retake,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
              border: Border.all(color: Colors.white54, width: 1.5),
            ),
            child: const Icon(Icons.refresh_rounded,
                color: Colors.white, size: 28),
          ),
        ),

        // Send (checkmark)
        GestureDetector(
          onTap: _send,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF075E54),
            ),
            child:
                const Icon(Icons.send_rounded, color: Colors.white, size: 28),
          ),
        ),
      ],
    );
  }
}
