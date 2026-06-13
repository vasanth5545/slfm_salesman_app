import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sizer/sizer.dart';

import '../../../core/app_export.dart';
import '../../../widgets/custom_icon_widget.dart';

class DamageFormWidget extends StatelessWidget {
  final TextEditingController osCodeController;
  final TextEditingController brandController;
  final TextEditingController modelController;
  final TextEditingController rateController;
  final TextEditingController descController;

  const DamageFormWidget({
    super.key,
    required this.osCodeController,
    required this.brandController,
    required this.modelController,
    required this.rateController,
    required this.descController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTextField(context, "OS Code", "qr_code", osCodeController),
        SizedBox(height: 2.h),
        Row(
          children: [
            Expanded(child: _buildTextField(context, "Brand", "branding_watermark", brandController)),
            SizedBox(width: 3.w),
            Expanded(child: _buildTextField(context, "Model", "category", modelController)),
          ],
        ),
        SizedBox(height: 2.h),
        _buildTextField(context, "Product Rate", "currency_rupee", rateController, isNumber: true),
        SizedBox(height: 2.h),
        _buildTextField(context, "Damage Description", "description", descController, maxLines: 3),
      ],
    );
  }

  Widget _buildTextField(
    BuildContext context, 
    String label, 
    String icon, 
    TextEditingController controller, 
    {bool isNumber = false, int maxLines = 1}
  ) {
    final theme = Theme.of(context);
    
    return TextFormField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      maxLines: maxLines,
      inputFormatters: isNumber ? [FilteringTextInputFormatter.digitsOnly] : [],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Padding(
          padding: const EdgeInsets.all(12),
          child: CustomIconWidget(
            iconName: icon,
            color: theme.colorScheme.onSurfaceVariant,
            size: 20,
          ),
        ),
        filled: true,
        fillColor: theme.colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }
}
