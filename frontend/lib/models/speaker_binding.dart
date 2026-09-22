
class SpeakerBindingInfo {
  const SpeakerBindingInfo({
    required this.id,
    required this.speakerId,
    this.platform = 'dueros',
    this.createdAt,
  });

  final int id;
  final String speakerId;
  final String platform;
  final DateTime? createdAt;

  factory SpeakerBindingInfo.fromJson(Map<String, dynamic> json) {
    final created = json['created_at']?.toString();
    return SpeakerBindingInfo(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      speakerId: (json['speaker_id'] ?? '').toString(),
      platform: (json['platform'] ?? 'dueros').toString(),
      createdAt: created == null ? null : DateTime.tryParse(created),
    );
  }

  
  String get shortId {
    if (speakerId.length <= 16) return speakerId;
    return '...${speakerId.substring(speakerId.length - 6)}';
  }

  
  String get displayName {
    if (platform == 'dueros') return '小度音箱（编号 $shortId）';
    return '智能音箱（编号 $shortId）';
  }
}