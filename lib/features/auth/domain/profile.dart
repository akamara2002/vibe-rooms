/// A row of `public.profiles`.
class Profile {
  const Profile({
    required this.id,
    required this.displayName,
    required this.avatarEmoji,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    displayName: json['display_name'] as String,
    avatarEmoji: json['avatar_emoji'] as String,
  );

  final String id;
  final String displayName;
  final String avatarEmoji;

  Map<String, dynamic> toJson() => {
    'id': id,
    'display_name': displayName,
    'avatar_emoji': avatarEmoji,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Profile &&
          other.id == id &&
          other.displayName == displayName &&
          other.avatarEmoji == avatarEmoji;

  @override
  int get hashCode => Object.hash(id, displayName, avatarEmoji);

  @override
  String toString() => 'Profile($id, $displayName $avatarEmoji)';
}
