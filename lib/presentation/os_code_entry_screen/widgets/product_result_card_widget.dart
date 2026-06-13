import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../../core/app_export.dart';

/// Product result display card with expandable details
class ProductResultCardWidget extends StatefulWidget {
  final Map<String, dynamic> product;
  final VoidCallback onMoveToBilling;

  const ProductResultCardWidget({
    super.key,
    required this.product,
    required this.onMoveToBilling,
  });

  @override
  State<ProductResultCardWidget> createState() =>
      _ProductResultCardWidgetState();
}

class _ProductResultCardWidgetState extends State<ProductResultCardWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: EdgeInsets.symmetric(vertical: 1.h),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.1),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: EdgeInsets.all(4.w),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(2.w),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: CustomIconWidget(
                      iconName: 'chair',
                      color: theme.colorScheme.primary,
                      size: 32,
                    ),
                  ),
                  SizedBox(width: 3.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.product['name'] as String,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 0.5.h),
                        Text(
                          widget.product['brand'] as String,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CustomIconWidget(
                    iconName: _isExpanded ? 'expand_less' : 'expand_more',
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            Divider(
              height: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
            Padding(
              padding: EdgeInsets.all(4.w),
              child: Column(
                children: [
                  _buildPriceRow(
                    context,
                    'MRP',
                    widget.product['mrp'] as String,
                    theme.colorScheme.onSurfaceVariant,
                  ),
                  SizedBox(height: 1.h),
                  _buildPriceRow(
                    context,
                    'Offer Price',
                    widget.product['offerPrice'] as String,
                    AppTheme.successLight,
                  ),
                  SizedBox(height: 1.h),
                  _buildPriceRow(
                    context,
                    'MOP',
                    widget.product['mop'] as String,
                    theme.colorScheme.primary,
                  ),
                  SizedBox(height: 1.h),
                  _buildStockRow(context),
                  SizedBox(height: 2.h),
                  SizedBox(
                    width: double.infinity,
                    height: 6.h,
                    child: ElevatedButton(
                      onPressed: widget.onMoveToBilling,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CustomIconWidget(
                            iconName: 'receipt_long',
                            color: theme.colorScheme.onPrimary,
                            size: 20,
                          ),
                          SizedBox(width: 2.w),
                          Text(
                            'Move to Billing',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPriceRow(
      BuildContext context, String label, String value, Color valueColor) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: valueColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildStockRow(BuildContext context) {
    final theme = Theme.of(context);
    final stockCount = widget.product['stockCount'] as int;
    final isLowStock = stockCount < 5;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 1.h),
      decoration: BoxDecoration(
        color: isLowStock
            ? AppTheme.warningLight.withValues(alpha: 0.1)
            : AppTheme.successLight.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CustomIconWidget(
                iconName: isLowStock ? 'warning' : 'inventory',
                color:
                    isLowStock ? AppTheme.warningLight : AppTheme.successLight,
                size: 20,
              ),
              SizedBox(width: 2.w),
              Text(
                'Stock Available',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          Text(
            '$stockCount units',
            style: theme.textTheme.titleSmall?.copyWith(
              color: isLowStock ? AppTheme.warningLight : AppTheme.successLight,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
