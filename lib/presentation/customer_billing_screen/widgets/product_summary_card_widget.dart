import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../../core/app_export.dart';
import '../../../widgets/custom_icon_widget.dart';

/// Product summary card showing selected product details with edit option
class ProductSummaryCardWidget extends StatelessWidget {
  final Map<String, dynamic> productData;
  final VoidCallback onEdit;

  const ProductSummaryCardWidget({
    super.key,
    required this.productData,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.08),
            offset: const Offset(0, 2),
            blurRadius: 8,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(4.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Selected Product',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: CustomIconWidget(
                    iconName: 'edit',
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  tooltip: 'Edit Product',
                ),
              ],
            ),
            SizedBox(height: 2.h),
            _buildProductDetail(
              context,
              'Product Name',
              productData['name'] as String? ?? 'N/A',
            ),
            SizedBox(height: 1.h),
            _buildProductDetail(
              context,
              'Brand',
              productData['brand'] as String? ?? 'N/A',
            ),
            SizedBox(height: 1.h),
            Row(
              children: [
                Expanded(
                  child: _buildProductDetail(
                    context,
                    'MRP',
                    '₹${productData['mrp'] ?? 'N/A'}',
                  ),
                ),
                SizedBox(width: 4.w),
                Expanded(
                  child: _buildProductDetail(
                    context,
                    'Offer Price',
                    '₹${productData['offerPrice'] ?? 'N/A'}',
                  ),
                ),
              ],
            ),
            SizedBox(height: 1.h),
            _buildProductDetail(
              context,
              'Final Price (MOP)',
              '₹${productData['adjustedPrice'] ?? productData['mop'] ?? 'N/A'}',
              isHighlighted: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductDetail(
    BuildContext context,
    String label,
    String value, {
    bool isHighlighted = false,
  }) {
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
        Text(
          value,
          style: isHighlighted
              ? theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.w700,
                )
              : theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
        ),
      ],
    );
  }
}
