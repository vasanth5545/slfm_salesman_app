import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sizer/sizer.dart';

import '../../../core/app_export.dart';
import '../../../widgets/custom_icon_widget.dart';

/// Customer information form with validation
class CustomerFormWidget extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController addressController;
  final TextEditingController phoneController;
  final TextEditingController alternatePhoneController;

  const CustomerFormWidget({
    super.key,
    required this.formKey,
    required this.nameController,
    required this.addressController,
    required this.phoneController,
    required this.alternatePhoneController,
  });

  @override
  State<CustomerFormWidget> createState() => _CustomerFormWidgetState();
}

class _CustomerFormWidgetState extends State<CustomerFormWidget> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Customer Details',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 2.h),
          _buildTextField(
            context,
            controller: widget.nameController,
            label: 'Customer Name',
            hint: 'Enter full name',
            prefixIcon: 'person',
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Customer name is required';
              }
              if (value.trim().length < 3) {
                return 'Name must be at least 3 characters';
              }
              return null;
            },
          ),
          SizedBox(height: 2.h),
          _buildTextField(
            context,
            controller: widget.addressController,
            label: 'Address',
            hint: 'Enter complete address',
            prefixIcon: 'location_on',
            maxLines: 3,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Address is required';
              }
              return null;
            },
          ),
          SizedBox(height: 2.h),
          _buildTextField(
            context,
            controller: widget.phoneController,
            label: 'Primary Phone',
            hint: 'Enter 10-digit mobile number',
            prefixIcon: 'phone',
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Phone number is required';
              }
              if (value.trim().length != 10) {
                return 'Phone number must be 10 digits';
              }
              if (!RegExp(r'^[6-9]\d{9}$').hasMatch(value.trim())) {
                return 'Enter a valid Indian mobile number';
              }
              return null;
            },
          ),
          SizedBox(height: 2.h),
          _buildTextField(
            context,
            controller: widget.alternatePhoneController,
            label: 'Alternate Phone (Optional)',
            hint: 'Enter alternate contact number',
            prefixIcon: 'phone_android',
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
                if (!RegExp(r'^[6-9]\d{9}$').hasMatch(value.trim())) {
                  return 'Enter a valid Indian mobile number';
                }
                if (value.trim() == widget.phoneController.text.trim()) {
                  return 'Alternate phone must be different';
                }
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required String hint,
    required String prefixIcon,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
  }) {
    final theme = Theme.of(context);

    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Padding(
          padding: EdgeInsets.all(3.w),
          child: CustomIconWidget(
            iconName: prefixIcon,
            color: theme.colorScheme.primary,
            size: 20,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.colorScheme.outline,
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.colorScheme.outline,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.colorScheme.primary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.colorScheme.error,
            width: 1,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.colorScheme.error,
            width: 2,
          ),
        ),
        filled: true,
        fillColor: theme.colorScheme.surface,
      ),
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
    );
  }
}
