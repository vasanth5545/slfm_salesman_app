import 'package:flutter/material.dart';
import 'package:slfm_salesman_app/services/activity_logger.dart';
import 'package:flutter/services.dart';
// mobile_scanner removed - not needed currently
import 'package:sizer/sizer.dart';

import '../../core/app_export.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/custom_bottom_bar.dart';
import '../../widgets/custom_icon_widget.dart';
import './widgets/missing_products_widget.dart';
import './widgets/scan_progress_widget.dart';
import './widgets/scanned_items_list_widget.dart';

class StockCheckingScreen extends StatefulWidget {
  const StockCheckingScreen({super.key});

  @override
  State<StockCheckingScreen> createState() => _StockCheckingScreenState();
}

class _StockCheckingScreenState extends State<StockCheckingScreen>
    with WidgetsBindingObserver {
  // Scanner disabled - mobile_scanner package removed
  bool _isFlashOn = false;
  bool _isScanningActive = true;

  final TextEditingController _manualCodeController = TextEditingController();

  // Mock database of products
  final List<Map<String, dynamic>> _productDatabase = [
    {
      "id": "QR001",
      "name": "Premium Leather Sofa Set",
      "category": "Living Room",
      "osCode": "BLR-18-12-2024-001",
      "brand": "Comfort Plus",
      "stock": 5,
      "scanned": false,
      "scanTime": null,
      "scanBy": null,
    },
    {
      "id": "QR002",
      "name": "Modern Dining Table 6-Seater",
      "category": "Dining",
      "osCode": "BLR-18-12-2024-002",
      "brand": "WoodCraft",
      "stock": 3,
      "scanned": false,
      "scanTime": null,
      "scanBy": null,
    },
    {
      "id": "QR003",
      "name": "Orthopedic Queen Mattress",
      "category": "Bedroom",
      "osCode": "BLR-18-12-2024-003",
      "brand": "SleepWell",
      "stock": 8,
      "scanned": false,
      "scanTime": null,
      "scanBy": null,
    },
    {
      "id": "QR004",
      "name": "Executive Office Chair",
      "category": "Office",
      "osCode": "BLR-18-12-2024-004",
      "brand": "ErgoOffice",
      "stock": 12,
      "scanned": false,
      "scanTime": null,
      "scanBy": null,
    },
    {
      "id": "QR005",
      "name": "Solid Wood Coffee Table",
      "category": "Living Room",
      "osCode": "BLR-18-12-2024-005",
      "brand": "Heritage",
      "stock": 4,
      "scanned": false,
      "scanTime": null,
      "scanBy": null,
    },
  ];

  // Scanned items list
  final List<Map<String, dynamic>> _scannedProducts = [];

  // Missing products list
  List<Map<String, dynamic>> _missingProducts = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _calculateMissingProducts();
  }

  void _calculateMissingProducts() {
    _missingProducts =
        _productDatabase.where((p) => p["scanned"] == false).toList();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _manualCodeController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (mounted) {
      setState(() {});
    }
  }

  // Barcode detection disabled - mobile_scanner removed

  void _processScannedCode(String code) {
    // Prevent duplicate processing
    if (_scannedProducts.any((p) => p["id"] == code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Item $code already scanned'),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    // Find product in database
    final productIndex = _productDatabase.indexWhere((p) => p["id"] == code);

    if (productIndex != -1) {
      setState(() {
        // Update product status
        _productDatabase[productIndex]["scanned"] = true;
        _productDatabase[productIndex]["scanTime"] = DateTime.now();
        _productDatabase[productIndex]["scanBy"] = "Salesman";

        // Add to scanned list
        _scannedProducts.insert(0, _productDatabase[productIndex]);

        // Recalculate missing products
        _calculateMissingProducts();
      });

      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scanned: ${_productDatabase[productIndex]["name"]}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );
    } else {
      // Unknown product
      HapticFeedback.heavyImpact();
      try { ActivityLogger.instance.logError('UI', 'Snackbar error shown'); } catch(_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unknown item code: $code'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _toggleFlash() {
    setState(() {
      _isFlashOn = !_isFlashOn;
    });
  }

  void _showManualEntryDialog() {
    setState(() {
      _isScanningActive = false;
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manual Entry'),
        content: TextField(
          controller: _manualCodeController,
          decoration: const InputDecoration(
            labelText: 'Enter QR Code / Product ID',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isScanningActive = true;
              });
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_manualCodeController.text.isNotEmpty) {
                _processScannedCode(_manualCodeController.text);
                _manualCodeController.clear();
                Navigator.pop(context);
                setState(() {
                  _isScanningActive = true;
                });
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    ).then((_) {
      // Ensure scanning resumes if dialog is dismissed
      if (mounted && !_isScanningActive) {
        setState(() {
          _isScanningActive = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalProducts = _productDatabase.length;
    final scannedCount = _scannedProducts.length;
    final remainingCount = totalProducts - scannedCount;
    final completionPercentage =
        totalProducts > 0 ? (scannedCount / totalProducts) * 100 : 0.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: CustomAppBar(
        title: 'Stock Checking',
        style: CustomAppBarStyle.standard,
        onBackPressed: () => Navigator.pop(context),
      ),
      body: Column(
        children: [
          // Camera Preview Area
          SizedBox(
            height: 35.h,
            child: Stack(
              children: [
                // Scanner placeholder - mobile_scanner removed
                Container(
                  color: Colors.black87,
                  child: const Center(
                    child: Text(
                      'Scanner disabled\nUse manual entry',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                  ),
                ),
                CustomPaint(
                  painter: _ScanningOverlayPainter(
                    scanAreaColor: Colors.white,
                    overlayColor: Colors.black.withValues(alpha: 0.5),
                  ),
                  child: Container(),
                ),
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: _buildCameraControls(theme),
                ),
              ],
            ),
          ),

          // Progress Indicator
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.shadowColor.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Progress Stats
                  ScanProgressWidget(
                    totalProducts: totalProducts,
                    scannedCount: scannedCount,
                    remainingCount: remainingCount,
                    completionPercentage: completionPercentage,
                  ),

                  const SizedBox(height: 16),

                  // Tabs for Scanned/Missing
                  Expanded(
                    child: DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          TabBar(
                            labelColor: theme.colorScheme.primary,
                            unselectedLabelColor:
                                theme.colorScheme.onSurfaceVariant,
                            indicatorColor: theme.colorScheme.primary,
                            tabs: [
                              Tab(text: 'Scanned ($scannedCount)'),
                              Tab(text: 'Missing ($remainingCount)'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _scannedProducts.isNotEmpty
                                    ? ScannedItemsListWidget(
                                        scannedProducts: _scannedProducts,
                                        scrollController: ScrollController(),
                                      )
                                    : _buildEmptyState(theme),
                                _missingProducts.isNotEmpty
                                    ? SingleChildScrollView(
                                        child: MissingProductsWidget(
                                          missingProducts: _missingProducts,
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          'All items scanned!',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomBar(
        currentRoute: '/stock-checking-screen',
        onTap: (route) {
          if (route != '/stock-checking-screen') {
            Navigator.pushReplacementNamed(context, route);
          }
        },
      ),
    );
  }

  Widget _buildCameraControls(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildControlButton(
          icon: _isFlashOn ? 'flash_on' : 'flash_off',
          onPressed: _toggleFlash,
          theme: theme,
        ),
        const SizedBox(width: 24),
        _buildControlButton(
          icon: 'edit',
          onPressed: _showManualEntryDialog,
          theme: theme,
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required String icon,
    required VoidCallback onPressed,
    required ThemeData theme,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: CustomIconWidget(
          iconName: icon,
          color: Colors.white,
          size: 24,
        ),
        onPressed: onPressed,
      ),
    );
  }

  /// Build empty state
  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        // FIX: Wrapped in FittedBox/SingleChildScrollView to prevent overflow in small spaces
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomIconWidget(
                iconName: 'qr_code_scanner',
                size: 48,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'No items scanned yet',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Start scanning QR codes to track inventory',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanningOverlayPainter extends CustomPainter {
  final Color scanAreaColor;
  final Color overlayColor;

  _ScanningOverlayPainter({
    required this.scanAreaColor,
    required this.overlayColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scanAreaSize = size.width * 0.6;
    final scanAreaRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: scanAreaSize,
      height: scanAreaSize,
    );

    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
          RRect.fromRectAndRadius(scanAreaRect, const Radius.circular(12)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      overlayPath,
      Paint()..color = overlayColor,
    );

    final borderPaint = Paint()
      ..color = scanAreaColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final cornerLength = 20.0;
    final left = scanAreaRect.left;
    final top = scanAreaRect.top;
    final right = scanAreaRect.right;
    final bottom = scanAreaRect.bottom;

    // Top-left
    canvas.drawLine(Offset(left, top), Offset(left + cornerLength, top), borderPaint);
    canvas.drawLine(Offset(left, top), Offset(left, top + cornerLength), borderPaint);

    // Top-right
    canvas.drawLine(Offset(right, top), Offset(right - cornerLength, top), borderPaint);
    canvas.drawLine(Offset(right, top), Offset(right, top + cornerLength), borderPaint);

    // Bottom-left
    canvas.drawLine(Offset(left, bottom), Offset(left + cornerLength, bottom), borderPaint);
    canvas.drawLine(Offset(left, bottom), Offset(left, bottom - cornerLength), borderPaint);

    // Bottom-right
    canvas.drawLine(Offset(right, bottom), Offset(right - cornerLength, bottom), borderPaint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - cornerLength), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
