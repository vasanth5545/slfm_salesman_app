import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sizer/sizer.dart';

import '../../../core/app_export.dart';
import '../../../widgets/custom_icon_widget.dart';

/// Dialog widget for editing product and customer details
class EditOrderDialogWidget extends StatefulWidget {
  final Map<String, dynamic> productData;
  final Map<String, TextEditingController> customerControllers;
  final Function(Map<String, dynamic>) onSave;

  const EditOrderDialogWidget({
    super.key,
    required this.productData,
    required this.customerControllers,
    required this.onSave,
  });

  @override
  State<EditOrderDialogWidget> createState() => _EditOrderDialogWidgetState();
}

class _EditOrderDialogWidgetState extends State<EditOrderDialogWidget> {
  late TextEditingController _adjustedPriceController;
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _phoneController;
  late TextEditingController _alternatePhoneController;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _adjustedPriceController = TextEditingController(
      text:
          widget.productData['adjustedPrice']?.toString().replaceAll(',', '') ??
          '',
    );
    _nameController = TextEditingController(
      text: widget.customerControllers['name']?.text ?? '',
    );
    _addressController = TextEditingController(
      text: widget.customerControllers['address']?.text ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.customerControllers['phone']?.text ?? '',
    );
    _alternatePhoneController = TextEditingController(
      text: widget.customerControllers['alternatePhone']?.text ?? '',
    );

    _adjustedPriceController.addListener(_onFieldChanged);
    _nameController.addListener(_onFieldChanged);
    _addressController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
    _alternatePhoneController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    setState(() {
      _hasChanges = true;
    });
  }

  @override
  void dispose() {
    _adjustedPriceController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _alternatePhoneController.dispose();
    super.dispose();
  }

  void _handleSave() {
    if (_formKey.currentState!.validate()) {
      final updatedData = {
        'productData': {
          ...widget.productData,
          'adjustedPrice': _adjustedPriceController.text.trim(),
        },
        'customerData': {
          'name': _nameController.text.trim(),
          'address': _addressController.text.trim(),
          'phone': _phoneController.text.trim(),
          'alternatePhone': _alternatePhoneController.text.trim(),
        },
      };
      widget.onSave(updatedData);
      Navigator.of(context).pop();
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;

    final shouldPop = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Text('Discard Changes?'),
            content: const Text(
              'You have unsaved changes. Do you want to discard them?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep Editing'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Discard'),
              ),
            ],
          ),
    );
    return shouldPop ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _onWillPop()) {
          if (!context.mounted) return;
          Navigator.of(context).pop();
        }
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: BoxConstraints(maxHeight: 80.h, maxWidth: 90.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(4.w),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        CustomIconWidget(
                          iconName: 'edit',
                          color: theme.colorScheme.primary,
                          size: 24,
                        ),
                        SizedBox(width: 2.w),
                        Text(
                          'Edit Order Details',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () async {
                        if (await _onWillPop()) {
                          if (!context.mounted) return;
                          Navigator.of(context).pop();
                        }
                      },
                      icon: CustomIconWidget(
                        iconName: 'close',
                        color: theme.colorScheme.onPrimaryContainer,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(4.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Product Details',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        _buildReadOnlyField(
                          context,
                          'Product Name',
                          widget.productData['name'] as String? ?? 'N/A',
                        ),
                        SizedBox(height: 1.5.h),
                        _buildReadOnlyField(
                          context,
                          'Brand',
                          widget.productData['brand'] as String? ?? 'N/A',
                        ),
                        SizedBox(height: 1.5.h),
                        Row(
                          children: [
                            Expanded(
                              child: _buildReadOnlyField(
                                context,
                                'MRP',
                                '₹${widget.productData['mrp'] ?? 'N/A'}',
                              ),
                            ),
                            SizedBox(width: 4.w),
                            Expanded(
                              child: _buildReadOnlyField(
                                context,
                                'Offer Price',
                                '₹${widget.productData['offerPrice'] ?? 'N/A'}',
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 1.5.h),
                        TextFormField(
                          controller: _adjustedPriceController,
                          decoration: InputDecoration(
                            labelText: 'Adjusted Price (MOP)',
                            hintText: 'Enter adjusted price',
                            prefixText: '₹',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 4.w,
                              vertical: 2.h,
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter adjusted price';
                            }
                            final price = int.tryParse(value);
                            if (price == null) {
                              return 'Please enter valid price';
                            }
                            final mop =
                                int.tryParse(
                                  widget.productData['mop']
                                          ?.toString()
                                          .replaceAll(',', '') ??
                                      '0',
                                ) ??
                                0;
                            if (price < mop) {
                              return 'Price cannot be less than MOP (₹$mop)';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 3.h),
                        Text(
                          'Customer Information',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        TextFormField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Customer Name',
                            hintText: 'Enter customer name',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 4.w,
                              vertical: 2.h,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter customer name';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 1.5.h),
                        TextFormField(
                          controller: _addressController,
                          decoration: InputDecoration(
                            labelText: 'Address',
                            hintText: 'Enter address',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 4.w,
                              vertical: 2.h,
                            ),
                          ),
                          maxLines: 3,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter address';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 1.5.h),
                        TextFormField(
                          controller: _phoneController,
                          decoration: InputDecoration(
                            labelText: 'Phone Number',
                            hintText: 'Enter phone number',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 4.w,
                              vertical: 2.h,
                            ),
                          ),
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter phone number';
                            }
                            if (value.trim().length != 10) {
                              return 'Phone number must be 10 digits';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 1.5.h),
                        TextFormField(
                          controller: _alternatePhoneController,
                          decoration: InputDecoration(
                            labelText: 'Alternate Phone Number (Optional)',
                            hintText: 'Enter alternate phone number',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 4.w,
                              vertical: 2.h,
                            ),
                          ),
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          validator: (value) {
                            if (value != null && value.trim().isNotEmpty) {
                              if (value.trim().length != 10) {
                                return 'Phone number must be 10 digits';
                              }
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.all(4.w),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          if (await _onWillPop()) {
                            if (!context.mounted) return;
                            Navigator.of(context).pop();
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 2.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    SizedBox(width: 4.w),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _handleSave,
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 2.h),
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Save Changes'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadOnlyField(BuildContext context, String label, String value) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: 0.5.h),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
