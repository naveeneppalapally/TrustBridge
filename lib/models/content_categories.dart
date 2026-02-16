import 'package:flutter/material.dart';

enum RiskLevel {
  high('High Risk', Colors.red),
  medium('Medium Risk', Colors.orange),
  low('Low Risk', Colors.blue);

  const RiskLevel(this.label, this.color);

  final String label;
  final Color color;
}

class ContentCategory {
  const ContentCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.riskLevel,
  });

  final String id;
  final String name;
  final String description;
  final IconData icon;
  final RiskLevel riskLevel;
}

class ContentCategories {
  const ContentCategories._();

  static const List<ContentCategory> highRisk = [
    ContentCategory(
      id: 'adult-content',
      name: 'Adult Content',
      description: 'Pornography and sexually explicit material.',
      icon: Icons.block,
      riskLevel: RiskLevel.high,
    ),
    ContentCategory(
      id: 'gambling',
      name: 'Gambling',
      description: 'Online betting, casinos, and lottery websites.',
      icon: Icons.casino,
      riskLevel: RiskLevel.high,
    ),
    ContentCategory(
      id: 'weapons',
      name: 'Weapons',
      description: 'Firearms, explosives, and dangerous weapon content.',
      icon: Icons.gpp_bad,
      riskLevel: RiskLevel.high,
    ),
    ContentCategory(
      id: 'drugs',
      name: 'Drugs and Alcohol',
      description: 'Illegal drugs, substance abuse, and drug marketplaces.',
      icon: Icons.medication,
      riskLevel: RiskLevel.high,
    ),
    ContentCategory(
      id: 'violence',
      name: 'Violence',
      description: 'Graphic violence, gore, and harmful media.',
      icon: Icons.warning_amber,
      riskLevel: RiskLevel.high,
    ),
  ];

  static const List<ContentCategory> mediumRisk = [
    ContentCategory(
      id: 'social-networks',
      name: 'Social Networks',
      description: 'Instagram, TikTok, Snapchat, and similar platforms.',
      icon: Icons.people,
      riskLevel: RiskLevel.medium,
    ),
    ContentCategory(
      id: 'dating',
      name: 'Dating Sites',
      description: 'Dating apps and adult matchmaking services.',
      icon: Icons.favorite,
      riskLevel: RiskLevel.medium,
    ),
    ContentCategory(
      id: 'chat',
      name: 'Chat and Messaging',
      description: 'Anonymous chats, random chat rooms, and live messaging.',
      icon: Icons.chat_bubble,
      riskLevel: RiskLevel.medium,
    ),
    ContentCategory(
      id: 'streaming',
      name: 'Video Streaming',
      description: 'Video platforms where mature content can appear.',
      icon: Icons.play_circle_outline,
      riskLevel: RiskLevel.medium,
    ),
  ];

  static const List<ContentCategory> lowRisk = [
    ContentCategory(
      id: 'games',
      name: 'Online Games',
      description: 'Browser games and game portals.',
      icon: Icons.sports_esports,
      riskLevel: RiskLevel.low,
    ),
    ContentCategory(
      id: 'shopping',
      name: 'Shopping',
      description: 'E-commerce sites and online marketplaces.',
      icon: Icons.shopping_cart,
      riskLevel: RiskLevel.low,
    ),
    ContentCategory(
      id: 'forums',
      name: 'Forums',
      description: 'Public discussion boards and communities.',
      icon: Icons.forum,
      riskLevel: RiskLevel.low,
    ),
    ContentCategory(
      id: 'news',
      name: 'News',
      description: 'News portals and current event websites.',
      icon: Icons.newspaper,
      riskLevel: RiskLevel.low,
    ),
  ];

  static List<ContentCategory> get allCategories => [
        ...highRisk,
        ...mediumRisk,
        ...lowRisk,
      ];

  static ContentCategory? findById(String id) {
    for (final category in allCategories) {
      if (category.id == id) {
        return category;
      }
    }
    return null;
  }
}
