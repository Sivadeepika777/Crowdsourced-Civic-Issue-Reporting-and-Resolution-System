/// AI Civic Guardian - Data Models
///
/// Plain data classes mirroring the backend's Pydantic schemas exactly.
/// Keep the lists below in sync with main.py on the backend if you add
/// new categories or severity levels.

const List<String> kIssueCategories = [
  'Potholes',
  'Garbage Dump',
  'Water Leakage',
  'Sewage Overflow',
  'Broken Streetlight',
  'Illegal Dumping',
  'Traffic Signal Damage',
  'Road Damage',
  'Drainage Blockage',
  'Tree Fallen',
  'Public Toilet Issues',
  'Stray Animals',
  'Flooding',
  'Pollution',
  'Noise Pollution',
  'Encroachment',
  'Park Maintenance',
  'Electricity Problems',
  'Drinking Water Problems',
  'Road Accident Spot',
  'Public Property Damage',
  'Illegal Construction',
  'Fire Hazard',
  'Other Issues',
];

const List<String> kSeverityLevels = ['Low', 'Medium', 'High', 'Critical'];

const List<String> kTrackingStages = [
  'Submitted',
  'Verified',
  'Assigned',
  'In Progress',
  'Resolved',
  'Closed',
];

class AppUser {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String role;
  final int points;
  final DateTime createdAt;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    required this.role,
    required this.points,
    required this.createdAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      phone: json['phone'] as String?,
      role: json['role'] as String? ?? 'citizen',
      points: json['points'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class StatusHistoryEntry {
  final String status;
  final String? note;
  final DateTime timestamp;

  StatusHistoryEntry({required this.status, this.note, required this.timestamp});

  factory StatusHistoryEntry.fromJson(Map<String, dynamic> json) {
    return StatusHistoryEntry(
      status: json['status'] as String,
      note: json['note'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

class Complaint {
  final String id;
  final String title;
  final String description;
  final String category;
  final String severity;
  final String status;
  final double latitude;
  final double longitude;
  final String? address;
  final String? landmark;
  final bool isAnonymous;
  final String? contactNumber;
  final List<String> imageUrls;
  final String? reportedBy;
  final List<StatusHistoryEntry> statusHistory;
  final DateTime createdAt;
  final DateTime updatedAt;

  Complaint({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.severity,
    required this.status,
    required this.latitude,
    required this.longitude,
    this.address,
    this.landmark,
    required this.isAnonymous,
    this.contactNumber,
    required this.imageUrls,
    this.reportedBy,
    required this.statusHistory,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Complaint.fromJson(Map<String, dynamic> json) {
    return Complaint(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      category: json['category'] as String,
      severity: json['severity'] as String,
      status: json['status'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address'] as String?,
      landmark: json['landmark'] as String?,
      isAnonymous: json['is_anonymous'] as bool? ?? false,
      contactNumber: json['contact_number'] as String?,
      imageUrls: (json['image_urls'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
      reportedBy: json['reported_by'] as String?,
      statusHistory: (json['status_history'] as List<dynamic>? ?? [])
          .map((e) => StatusHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
