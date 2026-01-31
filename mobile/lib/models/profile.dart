class Profile {
  final String userId;
  final String displayName;
  final String bio;
  final DateTime dob;
  final String photoUrl;

  Profile({
    required this.userId,
    required this.displayName,
    required this.bio,
    required this.dob,
    required this.photoUrl,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      userId: (json['user_id'] ?? '') as String,
      displayName: (json['display_name'] ?? '') as String,
      bio: (json['bio'] ?? '') as String,
      dob: DateTime.parse((json['dob'] ?? '1970-01-01T00:00:00Z') as String),
      photoUrl: (json['photo_url'] ?? '') as String,
    );
  }

  Map<String, dynamic> toUpsertJson({
    String? displayName,
    String? bio,
    DateTime? dob,
    String? photoUrl,
  }) {
    return {
      if (displayName != null) 'display_name': displayName,
      if (bio != null) 'bio': bio,
      if (dob != null) 'dob': dob.toUtc().toIso8601String(),
      if (photoUrl != null) 'photo_url': photoUrl,
    };
  }
}

