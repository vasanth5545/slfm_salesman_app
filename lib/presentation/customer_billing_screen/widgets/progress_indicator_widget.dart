import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../../core/app_export.dart';
import '../../../widgets/custom_icon_widget.dart';

/// Progress indicator showing billing step completion
class ProgressIndicatorWidget extends StatelessWidget {
  final int currentStep;
  final List<String> steps;

  const ProgressIndicatorWidget({
    super.key,
    required this.currentStep,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
      color: theme.colorScheme.surface,
      child: Row(
        children: List.generate(
          steps.length,
          (index) => Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _buildStepItem(
                    context,
                    index,
                    steps[index],
                    index < currentStep,
                    index == currentStep,
                  ),
                ),
                if (index < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: index < currentStep
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepItem(
    BuildContext context,
    int index,
    String label,
    bool isCompleted,
    bool isActive,
  ) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          width: 10.w,
          height: 10.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted || isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.surface,
            border: Border.all(
              color: isCompleted || isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: Center(
            child: isCompleted
                ? CustomIconWidget(
                    iconName: 'check',
                    color: theme.colorScheme.onPrimary,
                    size: 16,
                  )
                : Text(
                    '${index + 1}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: isActive
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
        SizedBox(height: 1.h),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: isCompleted || isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
