/// Message types in the attendance chat
enum ChatMessageType {
  system, // System info messages (greetings, confirmations)
  dateHeader, // Center-aligned date headers (e.g., "Yesterday", "Today")
  clockIn, // Clock in with selfie
  clockOut, // Clock out with selfie
  leaveRequest, // Leave application message
  reEntry, // Re-entry after break
}

/// Upload/delivery status indicators (WhatsApp style)
enum UploadStatus {
  sending, // ⏳ Clock icon (uploading to server)
  sent, // ✓ Single grey tick
  delivered, // ✓✓ Double grey tick
  success, // ✓✓ Double blue tick (server confirmed)
  failed, // ❌ Red cross
}

/// Leave approval status
enum LeaveStatus {
  none,
  pending, // ⏳ Pending admin approval
  approved, // ✅ Approved
  rejected, // ❌ Rejected
}

class AttendanceChatMessage {
  final String id;
  final ChatMessageType type;
  final String text;
  final DateTime timestamp;
  final bool isSentByMe; // true = user message (right), false = system (left)

  // For clock in/out messages
  final String? imagePath; // Local file path of selfie
  final String? imageUrl; // Server URL of uploaded selfie
  final UploadStatus uploadStatus;

  // For leave request messages
  final String? leaveType; // "Full Day" or "Half Day"
  final DateTime? leaveStartDate;
  final DateTime? leaveEndDate;
  final String? leaveReason;
  final LeaveStatus leaveStatus;
  final int? leaveDays;

  // For attendance status
  final String? attendanceStatus; // "Present", "Half Day", "Late", etc.

  // Link to local DB record
  final String? attendanceUid;

  const AttendanceChatMessage({
    required this.id,
    required this.type,
    required this.text,
    required this.timestamp,
    this.isSentByMe = true,
    this.imagePath,
    this.imageUrl,
    this.uploadStatus = UploadStatus.success,
    this.leaveType,
    this.leaveStartDate,
    this.leaveEndDate,
    this.leaveReason,
    this.leaveStatus = LeaveStatus.none,
    this.leaveDays,
    this.attendanceStatus,
    this.attendanceUid,
  });

  AttendanceChatMessage copyWith({
    String? text,
    DateTime? timestamp,
    UploadStatus? uploadStatus,
    String? imageUrl,
    String? attendanceStatus,
    LeaveStatus? leaveStatus,
    String? imagePath,
    String? leaveType,
    String? leaveReason,
    String? attendanceUid,
  }) {
    return AttendanceChatMessage(
      id: id,
      type: type,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isSentByMe: isSentByMe,
      imagePath: imagePath ?? this.imagePath,
      imageUrl: imageUrl ?? this.imageUrl,
      uploadStatus: uploadStatus ?? this.uploadStatus,
      leaveType: leaveType ?? this.leaveType,
      leaveStartDate: leaveStartDate,
      leaveEndDate: leaveEndDate,
      leaveReason: leaveReason ?? this.leaveReason,
      leaveStatus: leaveStatus ?? this.leaveStatus,
      leaveDays: leaveDays,
      attendanceStatus: attendanceStatus ?? this.attendanceStatus,
      attendanceUid: attendanceUid ?? this.attendanceUid,
    );
  }
}
