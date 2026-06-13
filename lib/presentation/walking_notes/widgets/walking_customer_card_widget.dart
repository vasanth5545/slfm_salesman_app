import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';


class WalkingCustomerCardWidget extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isMyEntry;
  final VoidCallback? onEdit;
  final VoidCallback? onCall;
  final VoidCallback? onAddFeedback;

  const WalkingCustomerCardWidget({
    super.key,
    required this.item,
    required this.isMyEntry,
    this.onEdit,
    this.onCall,
    this.onAddFeedback,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool hasFeedback = item['feedback_text'] != null && item['feedback_text'].toString().trim().isNotEmpty;
    
    return Container(
      margin: EdgeInsets.only(bottom: 1.5.h),
      decoration: BoxDecoration(
        color: const Color(0xFF15222B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(3.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- HEADER ROW (Name + Date) ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: isMyEntry ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                        child: Icon(Icons.person, size: 18, color: isMyEntry ? Colors.green : Colors.orange),
                      ),
                      SizedBox(width: 3.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['customer_name'] ?? 'Unknown',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // Show Showroom Tag only if NOT my entry
                            if (!isMyEntry)
                              Container(
                                margin: EdgeInsets.only(top: 0.5.h),
                                padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 0.2.h),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  item['showroom_name'] ?? 'Branch',
                                  style: TextStyle(fontSize: 8.sp, color: Colors.orange.shade800, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // RIGHT SIDE: Date & Edit
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // DATE (Always Visible)
                    Text(
                      item['date'] ?? '',
                      style: TextStyle(fontSize: 9.sp, color: Colors.grey[500], fontWeight: FontWeight.w500),
                    ),
                    if (isMyEntry) ...[
                      SizedBox(height: 1.h),
                      InkWell(
                        onTap: onEdit,
                        child: Padding(
                          padding: EdgeInsets.all(1.w),
                          child: const Icon(Icons.edit, size: 20, color: Colors.blue),
                        ),
                      ),
                    ]
                  ],
                )
              ],
            ),
            
            SizedBox(height: 1.5.h),
            Divider(color: Colors.grey.withValues(alpha: 0.1), height: 1),
            SizedBox(height: 1.5.h),
            
            // --- PHONE ROW ---
            Row(
              children: [
                const Icon(Icons.phone, size: 16, color: Colors.grey),
                SizedBox(width: 2.w),
                Flexible(
                  child: InkWell(
                    onTap: onCall,
                    child: Text(
                      item['phone'] ?? '',
                      style: const TextStyle(
                        color: Colors.blue, 
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.blue,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 0.8.h),
            
            // --- NEEDS TEXT ---
            Text(
              "Looking for: ${item['product_interest']}",
              style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600, fontSize: 11.sp),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            
            // --- ADDED BY (If not my entry) ---
            if (!isMyEntry && item['salesman_name'] != null) ...[
                SizedBox(height: 0.8.h),
                Row(
                  children: [
                    Icon(Icons.badge_outlined, size: 14, color: Colors.grey[600]),
                    SizedBox(width: 1.w),
                    Flexible(
                      child: Text(
                        "Added by: ${item['salesman_name']}",
                        style: TextStyle(fontSize: 9.sp, color: Colors.grey[600]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
            ],

            // --- FEEDBACK SECTION ---
            if (!isMyEntry) ...[
              SizedBox(height: 1.5.h),
              
              if (hasFeedback)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(2.w),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3))
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, size: 14, color: Colors.green[700]),
                          SizedBox(width: 1.w),
                          Expanded(
                            child: Text(
                              "Feedback by ${item['feedback_by']}", 
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9.sp, color: Colors.green[800]),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: 1.w),
                          Flexible(
                            child: Text(
                              item['feedback_date'] ?? "", 
                              style: TextStyle(fontSize: 8.sp, color: Colors.green[600]),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 0.5.h),
                      Text(item['feedback_text'], style: TextStyle(fontSize: 10.sp, color: Colors.grey[300])),
                    ],
                  ),
                )
              else
                // BUTTON FIX: Removed fixed height, added padding
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onAddFeedback,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                      padding: EdgeInsets.symmetric(vertical: 1.5.h), // Better padding for touch targets
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_call, size: 18),
                        SizedBox(width: 2.w),
                        const Flexible(
                          child: Text(
                            "Call & Add Feedback",
                            overflow: TextOverflow.ellipsis, 
                            maxLines: 1,
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
