class PublicProfile {
  final String userId;
  final String email;
  final String displayName;
  final String photoUrl;

  const PublicProfile({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.photoUrl,
  });

  factory PublicProfile.fromJson(Map<String, dynamic> json) {
    return PublicProfile(
      userId: (json['user_id'] ?? '') as String,
      email: (json['email'] ?? '') as String,
      displayName: (json['display_name'] ?? '') as String,
      photoUrl: (json['photo_url'] ?? '') as String,
    );
  }
}

