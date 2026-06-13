import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../../core/app_export.dart';
import '../../../widgets/custom_icon_widget.dart';

/// Order preview section displaying final order details
class OrderPreviewWidget extends StatelessWidget {
  final Map<String, dynamic> orderData;

  const OrderPreviewWidget({
    super.key,
    required this.orderData,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.3),
          width: 2,
        ),
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
              children: [
                CustomIconWidget(
                  iconName: 'receipt_long',
                  color: theme.colorScheme.secondary,
                  size: 24,
                ),
                SizedBox(width: 2.w),
                Text(
                  'Order Preview',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
            SizedBox(height: 2.h),
            _buildDivider(context),
            SizedBox(height: 2.h),
            _buildSectionTitle(context, 'Customer Information'),
            SizedBox(height: 1.h),
            _buildInfoRow(
              context,
              'Name',
              orderData['customerName'] as String? ?? 'N/A',
            ),
            _buildInfoRow(
              context,
              'Phone',
              orderData['customerPhone'] as String? ?? 'N/A',
            ),
            if (orderData['customerAlternatePhone'] != null &&
                (orderData['customerAlternatePhone'] as String).isNotEmpty)
              _buildInfoRow(
                context,
                'Alternate Phone',
                orderData['customerAlternatePhone'] as String,
              ),
            _buildInfoRow(
              context,
              'Address',
              orderData['customerAddress'] as String? ?? 'N/A',
              isMultiline: true,
            ),
            SizedBox(height: 2.h),
            _buildDivider(context),
            SizedBox(height: 2.h),
            _buildSectionTitle(context, 'Product Details'),
            SizedBox(height: 1.h),
            _buildInfoRow(
              context,
              'Product',
              orderData['productName'] as String? ?? 'N/A',
            ),
            _buildInfoRow(
              context,
              'Brand',
              orderData['productBrand'] as String? ?? 'N/A',
            ),
            _buildInfoRow(
              context,
              'OS Code',
              orderData['osCode'] as String? ?? 'N/A',
            ),
            SizedBox(height: 2.h),
            _buildDivider(context),
            SizedBox(height: 2.h),
            _buildSectionTitle(context, 'Pricing Breakdown'),
            SizedBox(height: 1.h),
            _buildInfoRow(
              context,
              'MRP',
              '₹${orderData['mrp'] ?? 'N/A'}',
            ),
            _buildInfoRow(
              context,
              'Offer Price',
              '₹${orderData['offerPrice'] ?? 'N/A'}',
            ),
            _buildInfoRow(
              context,
              'Final Price (MOP)',
              '₹${orderData['finalPrice'] ?? 'N/A'}',
              isHighlighted: true,
            ),
            SizedBox(height: 2.h),
            _buildDivider(context),
            SizedBox(height: 2.h),
            _buildInfoRow(
              context,
              'Salesman ID',
              orderData['salesmanId'] as String? ?? 'N/A',
            ),
            _buildInfoRow(
              context,
              'Order Date',
              orderData['timestamp'] as String? ?? 'N/A',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);

    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value, {
    bool isHighlighted = false,
    bool isMultiline = false,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 0.5.h),
      child: Row(
        crossAxisAlignment:
            isMultiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 35.w,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: isHighlighted
                  ? theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.secondary,
                      fontWeight: FontWeight.w700,
                    )
                  : theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              maxLines: isMultiline ? null : 1,
              overflow: isMultiline ? null : TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 1,
      color: theme.colorScheme.outline.withValues(alpha: 0.3),
    );
  }
}
