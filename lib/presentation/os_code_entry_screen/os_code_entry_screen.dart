import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sizer/sizer.dart';

import '../../core/app_export.dart';
import './widgets/os_code_input_widget.dart';
import './widgets/price_adjustment_widget.dart';
import './widgets/product_result_card_widget.dart';
import './widgets/recent_lookups_widget.dart';

/// OS Code Entry Screen for product lookup and price adjustment
class OsCodeEntryScreen extends StatefulWidget {
  const OsCodeEntryScreen({super.key});

  @override
  State<OsCodeEntryScreen> createState() => _OsCodeEntryScreenState();
}

class _OsCodeEntryScreenState extends State<OsCodeEntryScreen> {
  final TextEditingController _osCodeController = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _productResult;
  double? _adjustedMop;

  // Mock product database
  final List<Map<String, dynamic>> _productDatabase = [
    {
      "osCode": "BLR-18-12-2025-001",
      "name": "Premium Leather Sofa Set",
      "brand": "Royal Comfort",
      "mrp": "₹85,000.00",
      "offerPrice": "₹72,000.00",
      "mop": "₹68,000.00",
      "minMargin": 65000.0,
      "stockCount": 8,
      "category": "Sofa",
    },
    {
      "osCode": "BLR-15-12-2025-002",
      "name": "Wooden Dining Table 6-Seater",
      "brand": "Teak Masters",
      "mrp": "₹45,000.00",
      "offerPrice": "₹38,000.00",
      "mop": "₹36,000.00",
      "minMargin": 34000.0,
      "stockCount": 3,
      "category": "Dining",
    },
    {
      "osCode": "BLR-10-12-2025-003",
      "name": "King Size Bed with Storage",
      "brand": "Sleep Haven",
      "mrp": "₹65,000.00",
      "offerPrice": "₹55,000.00",
      "mop": "₹52,000.00",
      "minMargin": 50000.0,
      "stockCount": 12,
      "category": "Bedroom",
    },
    {
      "osCode": "BLR-08-12-2025-004",
      "name": "Executive Office Chair",
      "brand": "ErgoTech",
      "mrp": "₹18,000.00",
      "offerPrice": "₹15,000.00",
      "mop": "₹14,500.00",
      "minMargin": 13500.0,
      "stockCount": 25,
      "category": "Office",
    },
    {
      "osCode": "BLR-05-12-2025-005",
      "name": "Modular Wardrobe 4-Door",
      "brand": "Space Savers",
      "mrp": "₹55,000.00",
      "offerPrice": "₹48,000.00",
      "mop": "₹46,000.00",
      "minMargin": 44000.0,
      "stockCount": 6,
      "category": "Bedroom",
    },
  ];

  // Mock recent lookups
  final List<Map<String, dynamic>> _recentLookups = [
    {
      "osCode": "BLR-18-12-2025-001",
      "productName": "Premium Leather Sofa Set",
      "timestamp": "2 hours ago",
    },
    {
      "osCode": "BLR-15-12-2025-002",
      "productName": "Wooden Dining Table 6-Seater",
      "timestamp": "5 hours ago",
    },
    {
      "osCode": "BLR-10-12-2025-003",
      "productName": "King Size Bed with Storage",
      "timestamp": "Yesterday",
    },
  ];

  @override
  void dispose() {
    _osCodeController.dispose();
    super.dispose();
  }

  Future<void> _performLookup() async {
    if (_osCodeController.text.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
      _productResult = null;
      _adjustedMop = null;
    });

    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    final osCode = _osCodeController.text.toUpperCase();
    final product = _productDatabase.firstWhere(
      (p) => (p['osCode'] as String).toUpperCase() == osCode,
      orElse: () => {},
    );

    setState(() {
      _isLoading = false;
      if (product.isNotEmpty) {
        _productResult = product;
        _adjustedMop = _parseMopValue(product['mop'] as String);
      } else {
        _showErrorDialog(
            'Product Not Found', 'No product found with OS Code: $osCode');
      }
    });
  }

  double _parseMopValue(String mopString) {
    return double.parse(mopString.replaceAll('₹', '').replaceAll(',', ''));
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            CustomIconWidget(
              iconName: 'error_outline',
              color: Theme.of(context).colorScheme.error,
              size: 24,
            ),
            SizedBox(width: 2.w),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _handleRecentLookupSelection(Map<String, dynamic> lookup) {
    _osCodeController.text = lookup['osCode'] as String;
    _performLookup();
  }

  void _moveToBilling() {
    if (_productResult == null) {
      return;
    }

    HapticFeedback.mediumImpact();

    // Navigate to customer billing screen with product data
    Navigator.pushNamed(
      context,
      '/customer-billing-screen',
      arguments: {
        'product': _productResult,
        'adjustedMop':
            _adjustedMop ?? _parseMopValue(_productResult!['mop'] as String),
      },
    );
  }

  void _openBarcodeScanner() {
    // Navigate to barcode scanner (would be implemented separately)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            CustomIconWidget(
              iconName: 'qr_code_scanner',
              color: Colors.white,
              size: 20,
            ),
            SizedBox(width: 2.w),
            const Text('Barcode scanner feature coming soon'),
          ],
        ),
        backgroundColor: AppTheme.primaryLight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Product Lookup'),
        leading: IconButton(
          icon: CustomIconWidget(
            iconName: 'arrow_back',
            color: theme.colorScheme.onSurface,
            size: 24,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: CustomIconWidget(
              iconName: 'qr_code_scanner',
              color: theme.colorScheme.primary,
              size: 24,
            ),
            onPressed: _openBarcodeScanner,
            tooltip: 'Scan Barcode',
          ),
          SizedBox(width: 2.w),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(4.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OsCodeInputWidget(
                controller: _osCodeController,
                onLookup: _performLookup,
                isLoading: _isLoading,
              ),
              if (_productResult != null) ...[
                SizedBox(height: 3.h),
                ProductResultCardWidget(
                  product: _productResult!,
                  onMoveToBilling: _moveToBilling,
                ),
                SizedBox(height: 2.h),
                PriceAdjustmentWidget(
                  originalMop: _parseMopValue(_productResult!['mop'] as String),
                  minMargin: _productResult!['minMargin'] as double,
                  onPriceChanged: (newPrice) {
                    setState(() => _adjustedMop = newPrice);
                  },
                ),
              ],
              SizedBox(height: 3.h),
              RecentLookupsWidget(
                recentLookups: _recentLookups,
                onLookupSelected: _handleRecentLookupSelection,
              ),
              SizedBox(height: 2.h),
            ],
          ),
        ),
      ),
    );
  }
}
