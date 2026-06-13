import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../core/app_export.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/custom_icon_widget.dart';
import './widgets/customer_form_widget.dart';
import './widgets/edit_order_dialog_widget.dart';
import './widgets/order_preview_widget.dart';
import './widgets/product_summary_card_widget.dart';
import './widgets/progress_indicator_widget.dart';

/// Customer Billing Screen for capturing customer information and finalizing orders
class CustomerBillingScreen extends StatefulWidget {
  const CustomerBillingScreen({super.key});

  @override
  State<CustomerBillingScreen> createState() => _CustomerBillingScreenState();
}

class _CustomerBillingScreenState extends State<CustomerBillingScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _alternatePhoneController =
      TextEditingController();

  bool _isLoading = false;
  bool _showPreview = false;
  int _currentStep = 1;

  // Mock product data
  final Map<String, dynamic> _productData = {
    'osCode': 'SLF2412250001',
    'name': 'Premium Leather Sofa Set',
    'brand': 'Luxury Living',
    'mrp': '89,999',
    'offerPrice': '74,999',
    'mop': '69,999',
    'adjustedPrice': '69,999',
    'stockCount': '5',
  };

  final String _salesmanId = 'SM001';

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _alternatePhoneController.dispose();
    super.dispose();
  }

  // FIX: Helper method to navigate to dashboard cleanly
  void _navigateToDashboard() {
    Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
  }


  // Handle back navigation logic
  void _handleBackNavigation() async {
    // 1. If in preview mode, go back to edit form
    if (_showPreview) {
      setState(() {
        _showPreview = false;
        _currentStep = 1;
      });
      return;
    }

    // 2. Check for unsaved changes
    if (_nameController.text.isNotEmpty ||
        _addressController.text.isNotEmpty ||
        _phoneController.text.isNotEmpty ||
        _alternatePhoneController.text.isNotEmpty) {
      final shouldDiscard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text('Unsaved Changes'),
          content: const Text(
            'You have unsaved changes. Are you sure you want to go back?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Discard'),
            ),
          ],
        ),
      );

      if (shouldDiscard == true) {
        _navigateToDashboard();
      }
      return;
    }

    // 3. No changes, safe to go to dashboard
    _navigateToDashboard();
  }

  Future<void> _handleCreateOrder() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_showPreview) {
      setState(() {
        _showPreview = true;
        _currentStep = 2;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      await Future.delayed(const Duration(seconds: 2));

      // Duplicate check simulation
      if (_phoneController.text.trim() == '9876543210') {
        if (mounted) {
          _showErrorDialog(
            'Duplicate Customer',
            'A customer with this phone number already exists.',
          );
          setState(() => _isLoading = false);
          return;
        }
      }

      final orderId = 'ORD${DateTime.now().millisecondsSinceEpoch}';

      if (mounted) {
        setState(() => _isLoading = false);
        _showSuccessDialog(orderId);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorDialog('Order Failed', 'Please try again.');
      }
    }
  }

  void _showSuccessDialog(String orderId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            CustomIconWidget(
              iconName: 'check_circle',
              color: const Color(0xFF2E7D32),
              size: 28,
            ),
            SizedBox(width: 2.w),
            const Text('Order Created'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your order has been created successfully!'),
            SizedBox(height: 2.h),
            Container(
              padding: EdgeInsets.all(3.w),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .secondary
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Text(
                    'Order ID: ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Expanded(
                    child: Text(
                      orderId,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _resetForm();
            },
            child: const Text('Create New Order'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _navigateToDashboard(); // FIX: Go to dashboard properly
            },
            child: const Text('Go to Dashboard'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _handleEditOrder() {
    showDialog(
      context: context,
      builder: (context) => EditOrderDialogWidget(
        productData: _productData,
        customerControllers: {
          'name': _nameController,
          'address': _addressController,
          'phone': _phoneController,
          'alternatePhone': _alternatePhoneController,
        },
        onSave: (updatedData) {
          setState(() {
            final product =
                updatedData['productData'] as Map<String, dynamic>;
            final customer =
                updatedData['customerData'] as Map<String, dynamic>;

            _productData['adjustedPrice'] = product['adjustedPrice'];
            _nameController.text = customer['name'] ?? '';
            _addressController.text = customer['address'] ?? '';
            _phoneController.text = customer['phone'] ?? '';
            _alternatePhoneController.text = customer['alternatePhone'] ?? '';
          });
        },
      ),
    );
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _nameController.clear();
    _addressController.clear();
    _phoneController.clear();
    _alternatePhoneController.clear();
    setState(() {
      _showPreview = false;
      _currentStep = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // FIX: Intercept back button using PopScope
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: CustomAppBar(
          title: _showPreview ? 'Review Order' : 'New Order',
          // FIX: Handle AppBar back button manually
          onBackPressed: _handleBackNavigation,
        ),
        body: Column(
          children: [
            ProgressIndicatorWidget(
              currentStep: _currentStep,
              steps: const ['Customer Info', 'Review & Confirm'],
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(height: 2.h),
                    ProductSummaryCardWidget(
                      productData: _productData,
                      onEdit: _handleEditOrder,
                    ),
                    SizedBox(height: 2.h),
                    if (!_showPreview)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4.w),
                        child: CustomerFormWidget(
                          formKey: _formKey,
                          nameController: _nameController,
                          addressController: _addressController,
                          phoneController: _phoneController,
                          alternatePhoneController: _alternatePhoneController,
                        ),
                      )
                    else
                      OrderPreviewWidget(
                        orderData: {
                          ..._productData,
                          'customerName': _nameController.text.trim(),
                          'customerPhone': _phoneController.text.trim(),
                          'deliveryAddress': _addressController.text.trim(),
                          'productName': _productData['name'],
                          'finalPrice': _productData['adjustedPrice'],
                          'salesmanId': _salesmanId,
                          'timestamp': DateTime.now().toString(),
                        },
                      ),
                    SizedBox(height: 10.h),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: Container(
          padding: EdgeInsets.all(4.w),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withValues(alpha: 0.1),
                offset: const Offset(0, -4),
                blurRadius: 8,
              ),
            ],
          ),
          child: SafeArea(
            child: SizedBox(
              width: double.infinity,
              height: 6.h,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleCreateOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.onPrimary,
                          ),
                        ),
                      )
                    : Text(
                        _showPreview ? 'Confirm Order' : 'Preview Order',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
