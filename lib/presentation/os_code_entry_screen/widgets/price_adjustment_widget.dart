import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sizer/sizer.dart';

import '../../../core/app_export.dart';
import '../../../widgets/custom_icon_widget.dart';

/// Price adjustment section with stepper controls and validation
class PriceAdjustmentWidget extends StatefulWidget {
  final double originalMop;
  final double minMargin;
  final Function(double) onPriceChanged;

  const PriceAdjustmentWidget({
    super.key,
    required this.originalMop,
    required this.minMargin,
    required this.onPriceChanged,
  });

  @override
  State<PriceAdjustmentWidget> createState() => _PriceAdjustmentWidgetState();
}

class _PriceAdjustmentWidgetState extends State<PriceAdjustmentWidget> {
  late TextEditingController _priceController;
  late double _currentPrice;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentPrice = widget.originalMop;
    _priceController = TextEditingController(
      text: _currentPrice.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  void _validateAndUpdatePrice(double newPrice) {
    setState(() {
      if (newPrice < widget.minMargin) {
        _errorMessage =
            'Price cannot be below minimum margin of ₹${widget.minMargin.toStringAsFixed(2)}';
        _currentPrice = widget.minMargin;
      } else {
        _errorMessage = null;
        _currentPrice = newPrice;
      }
      _priceController.text = _currentPrice.toStringAsFixed(2);
      widget.onPriceChanged(_currentPrice);
    });
  }

  void _incrementPrice() {
    HapticFeedback.lightImpact();
    _validateAndUpdatePrice(_currentPrice + 100);
  }

  void _decrementPrice() {
    HapticFeedback.lightImpact();
    _validateAndUpdatePrice(_currentPrice - 100);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CustomIconWidget(
                iconName: 'tune',
                color: theme.colorScheme.primary,
                size: 20,
              ),
              SizedBox(width: 2.w),
              Text(
                'Adjust MOP',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 2.h),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _priceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    prefixStyle: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outline,
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
                      ),
                    ),
                  ),
                  onChanged: (value) {
                    final price = double.tryParse(value);
                    if (price != null) {
                      _validateAndUpdatePrice(price);
                    }
                  },
                ),
              ),
              SizedBox(width: 2.w),
              Column(
                children: [
                  InkWell(
                    onTap: _incrementPrice,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: EdgeInsets.all(2.w),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: CustomIconWidget(
                        iconName: 'add',
                        color: theme.colorScheme.primary,
                        size: 24,
                      ),
                    ),
                  ),
                  SizedBox(height: 1.h),
                  InkWell(
                    onTap: _decrementPrice,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: EdgeInsets.all(2.w),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: CustomIconWidget(
                        iconName: 'remove',
                        color: theme.colorScheme.primary,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_errorMessage != null) ...[
            SizedBox(height: 1.h),
            Row(
              children: [
                CustomIconWidget(
                  iconName: 'error_outline',
                  color: theme.colorScheme.error,
                  size: 16,
                ),
                SizedBox(width: 1.w),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: 2.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 1.h),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Minimum Margin',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '₹${widget.minMargin.toStringAsFixed(2)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
